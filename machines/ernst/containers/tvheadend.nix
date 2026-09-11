# machines/ernst/containers/tvheadend.nix
#
# Tvheadend as a SAT>IP client against the FRITZ!Box 6591's four DVB-C
# tuners, publishing an M3U playlist and an XMLTV guide that Jellyfin
# consumes as a Live TV tuner + EPG source (M8 in docs/roadmap.md).
#
# ── TWO DEPARTURES FROM THE M8 PROMPT, both argued here ─────────────────────
#
# 1. THE PACKAGE IS HAND-ROLLED.  The prompt said "tvheadend is in nixpkgs; no
#    image escape hatch is needed".  nixpkgs REMOVED both pkgs.tvheadend and
#    services.tvheadend (PR #332259 — unmaintained, stuck on FFmpeg 4);
#    verified gone from stable pin and nixos-unstable on 2026-08-27.  Rather
#    than moving tiers (podman + linuxserver image), this follows M13's
#    Janitorr precedent: build from source, in pkgs/tvheadend.nix, with
#    --disable-libav so the FFmpeg coupling that killed the nixpkgs package
#    does not exist here at all.  Transcoding is Jellyfin's job on the iGPU;
#    Tvheadend only remuxes.  The unit below is hand-written since there is no
#    module to configure.
#
# 2. THE FRITZ!BOX IS DIRECTLY ATTACHED — no VLAN, no UDM-Pro, no ZBF rule.
#    The prompt's 0.2 assumed the FRITZ!Box lands on a UniFi VLAN and budgeted
#    an ACL (TCP 49000 + 554) plus the ephemeral-UDP return problem (ledger
#    row L7).  What actually happened (2026-08-27): a FRITZ LAN port is
#    cabled STRAIGHT INTO enp12s0, ernst's second NIC, previously unused.
#    The whole flow — RTSP control and the unicast RTP return — stays on a
#    two-port bridge (br-fritz) that never touches the UDM-Pro, so:
#      - L6 and L7 are RETIRED AS NEVER-CREATED (see the roadmap ledger);
#      - the RTP return path is ONE iptables line in this container;
#      - the FRITZ's DHCP server and IPv6 RAs cannot reach any skynet VLAN.
#    The prompt itself blessed the degenerate case ("if the FRITZ!Box ends up
#    on the same VLAN as Tvheadend, there is no ACL at all"); a dedicated
#    point-to-point segment is that, minus the shared-VLAN exposure.
#
# ── PHASE 0 EVIDENCE (measured 2026-08-27, from ernst over this very link) ──
#
#   satipdesc.xml     <satip:X_SATIPCAP>DVBC-4</satip:X_SATIPCAP> — four
#                     DVB-C frontends, present despite the Vodafone-branded
#                     firmware (modelNumber 6591lgi).  No branding lock.
#   Stream test       ZDF HD (freq=450, 256qam, sr 6900): 12 s of RTP →
#                     13.7 MB MPEG-TS (~9.1 Mbit/s), ffprobe: h264 1280x720
#                     @50fps + 2× ac3 + an EPG data stream.  EIT rides the
#                     mux, so the over-the-air grabber needs no external
#                     XMLTV source.
#   Mux sweep         all 8 probed frequencies lock, quality 13–14, level
#                     114–131.  330 MHz (Das Erste) locks noticeably SLOWER
#                     than the rest — expect its first tune to take seconds.
#   RTP transport     interleaved-TCP is NOT available: SETUP with
#                     RTP/AVP/TCP returns "461 Unsupported Transport".
#                     UDP unicast RTP is the mode, hence the firewall rule
#                     below.  (This is also why ffprobe's RTSP client
#                     appeared to hang during Phase 0 — it stalls silently
#                     when RTP never arrives.)
#   Channel list      the box publishes its OWN M3U with tuning parameters:
#                     http://192.168.178.1/dvb/m3u/channellist.m3u
#                     (213 channels).  Useful for cross-checking mux config.
#
# ── THE FRITZ!BOX, as peer (provider CPE — we do not administer it) ─────────
#
#   FRITZ!Box 6591 Cable (Vodafone), MAC 2c:91:ab:73:3f:35, in Vodafone
#   bridge/Kabelmodem mode for the house uplink (the UDM-Pro holds the public
#   IP).  Its LAN side nonetheless serves the full 192.168.178.0/24 network:
#   DHCP on, UI and SAT>IP at 192.168.178.1.  Its firmware can change under
#   us on Vodafone's schedule.
#
#   NOT ALL ITS LAN PORTS ARE EQUAL — one port (the guest port) is
#   IPv4-silent: no ARP, no DHCPv4, IPv6 RAs only, all services blocked.
#   That port is what made the first cabling attempt look dead.  If this link
#   ever goes IPv4-dark after someone re-plugs cables at the FRITZ end,
#   CHECK WHICH LAN PORT THE CABLE IS IN before debugging anything here.
#
#   The FRITZ side also sends IPv6 RAs carrying a DEFAULT ROUTE (observed:
#   6to4 prefix + fd93: ULA).  Ernst must never accept them — SN2 in the
#   roadmap decided IPv6 off — which is why every interface in this file
#   pins IPv6AcceptRA = false.  During Phase 0 the host briefly picked up a
#   v6 default route via the FRITZ from a manually-upped enp12s0; the
#   networkd units below make that impossible by construction.
#
# ── TUNER CEILING — 4, and every consumer counts ────────────────────────────
#
#   SAT>IP maps ONE RTSP session to ONE frontend: two clients on the same mux
#   still burn two tuners (unlike a local DVB card, where one frontend feeds
#   any number of demuxed services).  The pool is shared with:
#     - EPG grabbing (the OTA EIT grabber periodically tunes muxes),
#     - anything the FRITZ!Box itself does with its tuners (FRITZ!App TV),
#     - every concurrent live stream and every DVR recording.
#   THERE IS NO "MAX INPUT STREAMS" SETTING TO SET, and the M8 prompt's
#   instruction to set one was based on a wrong model of the SAT>IP client.
#   The ceiling is not a limit applied to a network — it is the NUMBER OF
#   FRONTENDS Tvheadend creates, which comes from the SAT>IP device's "Tuner
#   configuration" (`tunercfgu`).  That is left at **"Auto"**, which reads
#   X_SATIPCAP from satipdesc.xml — `DVBC-4` here — and creates exactly four
#   DVB-C frontends.  Verified on the running instance 2026-08-27: four
#   tuners under "GoFRITZ - 192.168.178.1", and `tunercfgu: "Auto"` on disk.
#   Auto is preferable to pinning `DVBC-4` by hand: if Vodafone's firmware
#   ever changes the tuner count, Auto follows it and a hand-pinned value
#   silently would not.
#
#   Contention is resolved by SUBSCRIPTION WEIGHT, not by a cap: the EPG
#   grabber subscribes at weight 4 and live viewing at 100, so a live tune
#   PREEMPTS an EPG grab rather than failing.  That is why the initial EPG
#   scan happily saturates all four tuners and is not a problem.  Headroom
#   decision: live viewing wins; recordings are shape (ii) (Jellyfin DVR) and
#   a failed recording shows up in Jellyfin's activity log.  A fifth
#   concurrent tune fails cleanly at the RTSP layer (the box refuses the
#   SETUP; Tvheadend reports "no free adapter").
#
#   The same auto-detection got the transport right without being told:
#   `tcp_mode: false` on disk, matching Phase 0's measured 461 rejection of
#   interleaved TCP.
#
# ── SHAPE (ii): TVHEADEND SHARES TUNERS, JELLYFIN RECORDS ───────────────────
#
#   The roadmap's M8 amendment asks this file to argue shape (i) (Tvheadend
#   records + a bespoke bridge tool) vs shape (ii) (Tvheadend is a
#   tuner-sharing + EPG daemon; Jellyfin's DVR schedules and records).  This
#   ships (ii), per the amendment's own instruction ("shape (ii) may collapse
#   most of M8 — TEST IT BEFORE BUILDING (i)"):
#     - recordings land in a library Jellyfin already indexes, BY
#       CONSTRUCTION — the expensive half of (i) (the recordings→library
#       bridge, unsolved upstream) is never built;
#     - MediathekArr (M12) already covers öffentlich-rechtliche catch-up, so
#       the DVR's remaining job — live sport, private broadcasters,
#       Depublizierung — is modest and does not need Tvheadend's conflict
#       resolution;
#     - the cost, stated: DVR state lives in Jellyfin's database, and its
#       scheduler is materially weaker (no priorities, no timeshift).
#   CONSEQUENCE FOR THIS FILE: uid 3026 has its OWN group and NO media
#   access — Tvheadend writes nothing outside /srv/state/tvheadend.  If (ii)
#   proves too weak in use, escalating to (i) means: media group membership
#   here, a recordings subdirectory under /srv/media, and the bridge tool the
#   roadmap budgets — a new argument, not a config flip.
#   The Jellyfin-side recordings directory (/srv/media/library/recordings,
#   bound RW into the jellyfin container) is declared in jellyfin.nix.
#
# ── AUTHENTICATION: NONE HERE, AUTHELIA OWNS IT (--noacl) ───────────────────
#
#   THE M8 PROMPT ASKED FOR A TVHEADEND SUPERUSER AND A SEPARATE
#   STREAMING-ONLY USER FOR JELLYFIN.  Both are gone, and the first deploy is
#   why: Tvheadend's own HTTP auth CANNOT COEXIST with Authelia forward-auth,
#   because the two contend for the same header.
#
#   Measured through the real chain on 2026-08-27:
#
#     no Authorization header          -> 302  (Authelia redirect, normal)
#     ANY Authorization header         -> 401  (from AUTHELIA, not Tvheadend)
#
#   Tvheadend challenges with **Digest only** — it offers no Basic at all
#   (`WWW-Authenticate: Digest realm="tvheadend", qop=auth, …`, verified
#   against the built binary).  The browser answers in the `Authorization`
#   header; Traefik's forwardAuth hands that request to Authelia, which
#   treats the header as ITS OWN credential, fails to find `tvhadmin` in its
#   user database, and returns 401 before the request ever reaches this
#   container.  The browser re-prompts, forever.  The observable symptom is a
#   login box that reappears after every attempt — which looks exactly like a
#   wrong password and is not one.
#
#   So the choice was never "which credential" but "which layer authenticates".
#   lgo chose Authelia, 2026-08-27.  Consequences, stated plainly:
#
#     - Anyone who clears Authelia reaches Tvheadend AS ADMIN.  Today that is
#       `lgo` and `go`, both already in Authelia's `admins` group, so no
#       privilege is actually widened.
#     - 9981 is NOT a public port.  The container firewall below admits
#       exactly two sources — Traefik (10.0.90.12, behind two-factor) and
#       Jellyfin (10.0.90.10) — and nothing else on VLAN 90, let alone off it.
#       That firewall is now the ONLY thing standing between the LAN and an
#       unauthenticated admin UI, so DO NOT WIDEN IT without revisiting this
#       decision.
#     - Jellyfin needs no credential in its M3U/XMLTV URLs, which is the
#       second half of what the prompt's "streaming-only user" was for.
#
#   IF THIS EVER NEEDS REVISITING, the two coherent alternatives are: drop the
#   `authelia` middleware from the tvheadend router in containers/traefik.nix
#   and let Tvheadend's digest auth be the gate (loses 2FA and the portal); or
#   keep both and give Traefik's address an anonymous full-rights ACCESS ENTRY
#   inside Tvheadend so no Authorization header is ever needed (defence in
#   depth, but that entry is hand-made UI state that a lost state dir takes
#   with it).  Neither is better by inspection — they trade different things.
#
# ── CHANNEL LOGOS (picons) — DECLARATIVE DATA, RUNTIME SETTING ─────────────
#
#   The logos themselves are a pinned package (pkgs/picons.nix), bind-mounted
#   read-only at the stable path /picons.  The two settings that make
#   Tvheadend USE them are runtime state in /srv/state/tvheadend/config and
#   cannot be declared here — the same situation as the access entries above
#   and the tuner configuration.
#
#   Configuration -> General -> Base, with "Expert" view level showing:
#
#     Channel icon path         file:///picons/%C.png
#     Channel icon name scheme  Service name picons
#
#   IT IS THE *CHANNEL ICON* PATH, NOT THE *PICON* PATH, and getting that
#   wrong is the single easiest way to end up with no logos and no error.
#   Tvheadend has both, and they drive different schemes:
#
#     chiconpath + chiconscheme  name-based.  %C is substituted with the
#                                channel name run through svcnamepicons(),
#                                which is what pkgs/picons.nix renames to.
#     piconpath  + piconscheme   service-REFERENCE based (`1_0_1_…`), keyed to
#                                a satellite bouquet's service refs.  This is
#                                DVB-C off a FRITZ!Box, so those refs do not
#                                match anything in any published pack.
#
#   Most guides on the internet describe the second and call it "picons",
#   which is why this note exists.  `chiconscheme` = 2 (CHICON_SVCNAME,
#   src/tvheadend.h:106) is the value that matters.
#
#   COVERAGE, measured against the 198 channels this instance carries
#   (2026-09-11): 104/117 TV (88%), 49/81 radio (60%), 153/198 overall.
#   Radio is the weak half and structurally will be — the pack is built for
#   satellite TV bouquets.
#
#   Kodi gets these for free: pvr.hts pulls channel icons over HTSP from this
#   server, so there is nothing to configure on the TV side.
#
# ── STORAGE ─────────────────────────────────────────────────────────────────
#
#   /srv/state/tvheadend (zdata) → /var/lib/tvheadend in the container, the
#   same remap-to-upstream-default trick jellyfin.nix uses.  Everything
#   Tvheadend persists — network/mux/service tree, channel map, access
#   control, EPG database — lives there.  uid/gid 3026 on both sides (nspawn
#   maps 1:1; the number is allocated in machines/ernst/networking.nix).
{ config, lib, pkgs, ... }:
let
  # Built from source; see pkgs/tvheadend.nix for why nixpkgs cannot supply
  # this and what must never be dropped from its configure flags.
  tvheadend = pkgs.callPackage ./pkgs/tvheadend.nix { };

  # Channel logos, renamed to the scheme THIS Tvheadend generates.  See
  # pkgs/picons.nix — the rename is not cosmetic, it is worth 27 channels, and
  # the package's header carries the measurement.
  picons = pkgs.callPackage ./pkgs/picons.nix { };

  tvheadendUid = 3026;   # allocated in machines/ernst/networking.nix
  tvheadendGid = 3026;

  # VLAN-90 peers allowed to reach the HTTP port (M3U, XMLTV, stream URLs,
  # web UI).  Same one-hop-on-br0 caveat as everywhere else: their frames
  # never reach the UDM-Pro, so this container's firewall is the only
  # enforcement point that exists for them.
  traefikAddr  = "10.0.90.12";   # web UI via tvheadend.goclan.org (authelia)
  jellyfinAddr = "10.0.90.10";   # M3U tuner + XMLTV guide + stream pulls
  httpPort     = 9981;
  htspPort     = 9982;           # see the firewall block — opened to exactly one address

  # The ernst HOST, and the only thing permitted to speak HTSP.
  #
  # NOT a VLAN-90 peer, which is why it is separated from the two above: Kodi
  # runs on the host, whose only address is on VLAN 50, so this traffic is
  # ROUTED through the UDM-Pro rather than taking the one-L2-hop br0 path the
  # other two do.
  #
  # THAT SECOND ENFORCEMENT POINT HAD TO BE OPENED SEPARATELY, and this file
  # could not do it. When this rule first deployed the flow still failed:
  # measured 2026-09-10, SYNs left the host on br0 toward 10.0.90.18:9982 and
  # retransmitted six times with no SYN-ACK and no RST while the accept rule
  # below stayed at ZERO packets — the UDM-Pro was dropping them before the
  # container ever saw them, under the `Internal → Services: Block All` zone
  # default. (Reaching 10.0.90.12:443 from the host does NOT generalise: that
  # one flow has its own M5 policy. Assuming otherwise cost a round here.)
  #
  # Resolved by ZBF policy `Allow Kodi to Tvheadend HTSP`, added by lgo on
  # 2026-09-10 — roadmap ledger row L12. Verified after: 9982 connects and
  # the accept rule below moves off zero.
  #
  # BOTH HALVES ARE LOAD-BEARING, in opposite directions. Without the router
  # policy nothing arrives; without this rule the container refuses what does.
  # And since that policy is written broadly — whole `Servers` network to any
  # Services host on 9982 — the /32 here is the only thing that keeps HTSP to
  # Kodi. See the firewall block for why that matters more than it looks.
  kodiHostAddr = "10.0.50.10";

  # The FRITZ!Box on the dedicated segment.  Static on both sides: the
  # container takes .2 (outside the FRITZ's default DHCP pool, .20–.200), and
  # deliberately does NOT DHCP from the box — a lease would arrive with the
  # FRITZ as default gateway and resolver, both of which must never be used.
  fritzAddr     = "192.168.178.1";
  containerFritzAddr = "192.168.178.2/24";
in
{
  ##############################################################################
  # Host side 1 — the FRITZ segment: enp12s0 ⇄ br-fritz ⇄ container fritz0.
  #
  # A dedicated two-port bridge.  The host itself holds NO address on it —
  # debugging goes through the container (`nixos-container run tvheadend`,
  # where curl against 192.168.178.1 works), not through a host leg that
  # would put ernst itself on the FRITZ's L2 segment.
  ##############################################################################
  systemd.network.netdevs."60-br-fritz" = {
    netdevConfig = {
      Name = "br-fritz";
      Kind = "bridge";
    };
    # No VLANFiltering: one segment, two ports, nothing to filter.  br0's
    # DefaultPVID="none" fail-closed machinery is solving a problem this
    # bridge does not have.
  };

  systemd.network.networks."60-br-fritz" = {
    matchConfig.Name = "br-fritz";
    networkConfig = {
      # No address, no link-local, no RA — the host does not speak here.
      LinkLocalAddressing     = "no";
      IPv6AcceptRA            = false;
      ConfigureWithoutCarrier = true;
    };
    linkConfig.RequiredForOnline = "no";
  };

  # enp12s0 — the physical leg to the FRITZ!Box.  networkd owns the
  # enslavement (Bridge=), like the microvm tap pattern A: nothing else
  # competes for this link, so there is no KeepMaster race to work around.
  # machines/ernst/networking.nix's header note about enp12s0 being unplugged
  # is updated to point here.
  systemd.network.networks."60-enp12s0" = {
    matchConfig.Name = "enp12s0";
    networkConfig = {
      Bridge              = "br-fritz";
      LinkLocalAddressing = "no";
      IPv6AcceptRA        = false;
    };
    # A bridge port's terminal state is "enslaved"; and this one must also
    # never block boot (the FRITZ end can be powered off or unplugged).
    linkConfig.RequiredForOnline = "no";
  };

  # Host side of the container's fritz0 veth (nspawn --network-veth-extra
  # names both ends identically; see extraVeths below).  networkd enslaves it
  # to br-fritz on appearance.
  systemd.network.networks."60-fritz0" = {
    matchConfig.Name = "fritz0";
    networkConfig = {
      Bridge              = "br-fritz";
      LinkLocalAddressing = "no";
      IPv6AcceptRA        = false;
    };
    linkConfig.RequiredForOnline = "no";
  };

  # Avahi must not discover this segment.  With no host address here it has
  # nothing to bind, but the exclusion is stated rather than left to that
  # accident — during Phase 0, a manually-addressed enp12s0 had avahi
  # broadcasting ernst's mDNS onto the FRITZ segment within seconds.
  services.avahi.denyInterfaces = [ "br-fritz" "enp12s0" "fritz0" ];

  ##############################################################################
  # Host side 2 — the Services-VLAN veth and the state dir.
  #
  # THERE IS NO CREDENTIAL HERE, AND THAT IS A DECISION — see "AUTHENTICATION"
  # in the file header.  An earlier revision of this file generated a
  # Tvheadend superuser as a clan var and staged it into the state dir; it
  # was removed once the first deploy proved Tvheadend's own HTTP auth cannot
  # coexist with Authelia forward-auth.  If that var is still in
  # vars/per-machine/ernst/tvheadend-superuser/ it is orphaned, and the file
  # staged at /srv/state/tvheadend/superuser by that revision is inert — both
  # can be deleted.
  ##############################################################################

  # State dir on zdata.  Numeric ids: the tvheadend user exists only inside
  # the container; nspawn maps 1:1 (same as jellyfin's 964).
  systemd.tmpfiles.rules = [
    "d /srv/state/tvheadend 0700 ${toString tvheadendUid} ${toString tvheadendGid} -"
  ];

  # Host side of the VLAN-90 veth — identical rationale to vb-jellyfin /
  # vb-arr, see jellyfin.nix's "Host-side wiring" for the long form.
  systemd.network.networks."60-vb-tvheadend" = {
    matchConfig.Name = "vb-tvheadend";
    networkConfig = {
      KeepMaster          = true;
      LinkLocalAddressing = "no";
      IPv6AcceptRA        = false;
    };
    bridgeVLANs = [ { VLAN = 90; PVID = 90; EgressUntagged = 90; } ];
    linkConfig.RequiredForOnline = "enslaved";
  };

  # Same VLAN race, same idempotent backstop, same "-" prefix as every other
  # nspawn container on br0.  `bridge vlan show dev vb-tvheadend` is the check.
  systemd.services."container@tvheadend".serviceConfig.ExecStartPost = [
    "-${pkgs.iproute2}/bin/bridge vlan add dev vb-tvheadend vid 90 pvid untagged"
  ];

  ##############################################################################
  # The container.
  ##############################################################################
  containers.tvheadend = {
    autoStart = true;
    ephemeral = false;

    # Leg 1 — eth0 on br0 / VLAN 90.  MAC from the allocation table in
    # machines/ernst/networking.nix; DHCP reservation 10.0.90.18 on the
    # UDM-Pro keys on it (manual step).
    privateNetwork  = true;
    hostBridge      = "br0";
    localMacAddress = "02:00:00:90:00:0a";

    # Leg 2 — fritz0 on br-fritz, to the FRITZ!Box.  Same mechanism as the
    # monitoring container's mon0: nspawn --network-veth-extra names both
    # ends fritz0.  All addressing is done by the container's own networkd
    # (below), not here — localAddress would be applied by container-init
    # before networkd starts and then fight it over the same interface.
    extraVeths.fritz0 = { };

    bindMounts = {
      # Tvheadend state, remapped to the upstream default path so the unit
      # below needs no --config gymnastics beyond naming it.
      "/var/lib/tvheadend" = {
        hostPath   = "/srv/state/tvheadend";
        isReadOnly = false;
      };

      # ── Channel logos, at a STABLE PATH, and that is the whole point ──────
      #
      # A bind mount rather than referencing the store path directly, even
      # though /nix/store is already visible in this container and the direct
      # reference would work today.
      #
      # THE REASON IS THAT THE CONSUMER IS RUNTIME STATE.  Tvheadend's
      # "Channel icon path" lives in /srv/state/tvheadend/config — it is a UI
      # setting, exactly like the access entries and the tuner config this
      # file already discusses, and nothing here can declare it.  Point that
      # setting at a store path and it is correct until the next time the
      # package changes, at which point the path stops existing and every logo
      # silently disappears — with the stale value still sitting in the config
      # file looking perfectly reasonable.
      #
      # /picons never moves.  Updating the pack is then a deploy and nothing
      # else: the mount source changes, the setting does not.
      #
      # Read-only: Tvheadend reads these and has no business writing them.
      "/picons" = {
        hostPath   = "${picons}/picons";
        isReadOnly = true;
      };
    };

    config = { config, pkgs, lib, ... }: {
      system.stateVersion = "26.05";

      ##########################################################################
      # Networking — two legs, one netns.
      ##########################################################################
      networking.useHostResolvConf = false;
      networking.useNetworkd = true;
      services.resolved.enable = true;

      # eth0 — VLAN 90.  Same block as every sibling container: DHCP against
      # the UDM-Pro reservation, resolver declared rather than inherited.
      systemd.network.networks."10-eth0" = {
        matchConfig.Name = "eth0";
        networkConfig = {
          DHCP         = "ipv4";
          DNS          = "10.0.5.3";
          Domains      = "~. skynet.lan";
          IPv6AcceptRA = false;
        };
        dhcpV4Config = {
          UseDNS     = false;
          UseDomains = false;
        };
        linkConfig.RequiredForOnline = "routable";
      };

      # fritz0 — the FRITZ segment.  Static, no gateway, no DNS, no RA: the
      # only thing this leg is for is 192.168.178.1, which is on-link.  The
      # FRITZ advertises a default route over RA (measured — see the file
      # header); IPv6AcceptRA=false is what keeps this container from
      # acquiring a second, wrong path to the internet.
      systemd.network.networks."20-fritz0" = {
        matchConfig.Name = "fritz0";
        networkConfig = {
          Address             = containerFritzAddr;
          IPv6AcceptRA        = false;
          LinkLocalAddressing = "no";
        };
        # The FRITZ end being down must not hold up the container's boot.
        linkConfig.RequiredForOnline = "no";
      };

      # Same 20 s cap as jellyfin.nix, same reasoning: a DHCP failure on eth0
      # must leave a RUNNING container with one failed unit, not a host-side
      # restart loop.
      systemd.network.wait-online.timeout = 20;

      # The container's firewall — the only enforcement point for br0-local
      # traffic (one L2 hop; the UDM-Pro never sees it).
      #
      #   9981/tcp   ONLY from Traefik (web UI, behind authelia) and Jellyfin
      #              (M3U + XMLTV + the stream URLs inside the playlist).
      #   9982/tcp   HTSP — ONLY from the ernst host (10.0.50.10).
      #
      #              This line used to open to NOBODY, on the grounds that the
      #              protocol's clients (Kodi's pvr.hts) did not exist in this
      #              fleet, and said that if one appeared this was the line to
      #              widen — deliberately, then.  One appeared: the htpc role's
      #              Kodi now ships pvr-hts (modules/roles/htpc.nix), so this is
      #              that deliberate widening, made by lgo on 2026-09-10.
      #
      #              THIS RULE IS THE GATE.  It is not a second line of defence
      #              behind Tvheadend's own auth, because THERE IS NO SUCH AUTH
      #              HERE.  An earlier revision of this comment claimed HTSP
      #              "authenticates on its own — it takes a Tvheadend user and
      #              password", and used that to argue the widening was safe.
      #              That claim was FALSE as this instance is configured, and it
      #              was written before anyone checked.  Measured 2026-09-10:
      #              /srv/state/tvheadend has NO accesscontrol and NO passwd
      #              directory — zero access entries, which in Tvheadend means
      #              everyone gets full rights — and `curl` to
      #              10.0.90.18:9981/api/serverinfo from an allowed source
      #              answers with no credentials at all.
      #
      #              So HTSP here is ANONYMOUS AND FULL-RIGHTS, exactly like the
      #              9981 admin UI the note above refuses to widen.  What makes
      #              this line defensible is not the protocol, it is the /32:
      #              one source address, one port, one client.  Widen the source
      #              and there is nothing else in the way.
      #
      #              THE UDM-Pro RULE IS BROADER THAN THIS ONE.  `Allow Kodi to
      #              Tvheadend HTSP` (added 2026-09-10) permits the whole
      #              `Servers` network to any Services-zone host on 9982, so the
      #              /32 below — not the router — is what actually restricts
      #              this to Kodi.  Do not relax it on the assumption that the
      #              router is also filtering; for this flow it is not.
      #
      #              If a second HTSP client ever appears, give Tvheadend a real
      #              access entry FIRST.  Adding a second address here without
      #              one hands full rights to another machine.
      #   udp from the FRITZ!Box — the RTP/RTCP return path.  Interleaved-TCP
      #              is rejected by this box (461, measured), so media arrives
      #              as unicast UDP on client-chosen ephemeral ports; a static
      #              port list cannot express that, the source address can.
      #              Scoped to fritz0's peer, which is the only host on that
      #              two-port bridge.
      #
      # extraCommands, not extraInputRules — the latter is consumed only under
      # networking.nftables and silently produces nothing here (the arr
      # container's header carries the long form of that warning).
      networking.firewall.allowedTCPPorts = [ ];
      networking.firewall.extraCommands = ''
        iptables -A nixos-fw -p tcp -s ${traefikAddr}/32  --dport ${toString httpPort} -j nixos-fw-accept
        iptables -A nixos-fw -p tcp -s ${jellyfinAddr}/32 --dport ${toString httpPort} -j nixos-fw-accept
        iptables -A nixos-fw -p tcp -s ${kodiHostAddr}/32 --dport ${toString htspPort} -j nixos-fw-accept
        iptables -A nixos-fw -p udp -s ${fritzAddr}/32 -j nixos-fw-accept
      '';

      ##########################################################################
      # The service.  Hand-written — nixpkgs removed services.tvheadend.
      ##########################################################################
      users.users.tvheadend = {
        isSystemUser = true;
        group        = "tvheadend";
        uid          = tvheadendUid;
        home         = "/var/lib/tvheadend";
      };
      users.groups.tvheadend = { gid = tvheadendGid; };

      systemd.services.tvheadend = {
        description = "Tvheadend (SAT>IP client against the FRITZ!Box 6591)";
        wantedBy = [ "multi-user.target" ];
        wants    = [ "network-online.target" ];
        after    = [ "network-online.target" ];

        serviceConfig = {
          # --satip_xml pins discovery to the static description URL.  SSDP
          # would actually work here (fritz0 shares the FRITZ's L2 segment),
          # but the static URL is declarative, survives an upstream SSDP
          # quirk, and matches what the M8 prompt asks for.
          ExecStart = lib.concatStringsSep " " [
            "${tvheadend}/bin/tvheadend"
            "--config /var/lib/tvheadend"
            "--http_port ${toString httpPort}"
            "--htsp_port ${toString htspPort}"
            "--satip_xml http://${fritzAddr}:49000/satipdesc.xml"
            "--nobackup"
            # --noacl: Tvheadend performs NO authentication of its own.
            # Authelia is the auth boundary.  This is load-bearing, not a
            # convenience — see "AUTHENTICATION" in the file header for the
            # measurement that forced it and what guards the port instead.
            "--noacl"
          ];
          User  = "tvheadend";
          Group = "tvheadend";
          Restart    = "on-failure";
          RestartSec = "5s";

          # Hardening.  Written for this unit rather than inherited from a
          # module that no longer exists.  The notable absences:
          #   PrivateDevices=true IS set — SAT>IP needs no /dev/dvb; the
          #     tuners are on the far end of an RTSP session.
          #   MemoryDenyWriteExecute is NOT set — pcre2's sljit wants W^X
          #     exec pages for regex JIT; it degrades to the interpreter
          #     when refused, but a hardening flag whose observable effect
          #     is "EPG regexes got slower" is the kind that never gets
          #     re-evaluated.  Left off, stated here.
          #
          # ── @chown IS ADDED BACK, AND THE FIRST DEPLOY IS WHY ─────────
          #
          #   `@system-service ~@privileged` alone makes this service
          #   CRASH-LOOP AT STARTUP: SIGSYS, status=31/SYS, core dumped,
          #   nothing in Tvheadend's own log because it never gets far
          #   enough to open one.  Measured on ernst 2026-08-27, and the
          #   only visible symptom through the front door was Traefik
          #   answering 502 Bad Gateway.
          #
          #   The syscall is `chown`, which is a member of BOTH
          #   @system-service (via @chown) and @privileged — so subtracting
          #   @privileged takes it away.  Tvheadend calls it on its lock
          #   file at startup, as `chown(path, -1, -1)`: a NO-OP that
          #   changes neither owner nor group and needs no capability at
          #   all.  seccomp filters on the syscall NUMBER, not on
          #   arguments, so a call that could not possibly do anything
          #   privileged still gets the process killed.
          #
          #   Adding it back costs nothing real here: the unit runs as an
          #   unprivileged uid with CapabilityBoundingSet="" and
          #   NoNewPrivileges, and without CAP_CHOWN the kernel refuses any
          #   chown that would actually change an owner.  The syscall is
          #   permitted; the operation is still impossible.
          #
          #   ORDER MATTERS AND IT IS LOAD-BEARING.  systemd applies these
          #   lines in sequence — allow @system-service, subtract
          #   @privileged, then add @chown back — so @chown must come
          #   AFTER the ~@privileged line.  Verified empirically under a
          #   real seccomp filter rather than read off the manual:
          #   `systemd-run --user` with these three lines starts and serves
          #   HTTP, with only the first two it dies on SIGSYS.
          #
          #   GENERAL LESSON, worth propagating the way M13's
          #   RuntimeDirectoryUser finding was: `systemd-analyze security`
          #   scores this unit BETTER with the crashing filter, because it
          #   rates directives, not whether the process survives them.  Run
          #   the service, not just the analyzer.
          NoNewPrivileges        = true;
          ProtectSystem          = "strict";
          ReadWritePaths         = [ "/var/lib/tvheadend" ];
          ProtectHome            = true;
          PrivateTmp             = true;
          PrivateDevices         = true;
          ProtectClock           = true;
          ProtectHostname        = true;
          ProtectControlGroups   = true;
          ProtectKernelTunables  = true;
          ProtectProc            = "invisible";
          RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK" ];
          RestrictRealtime       = true;
          RestrictSUIDSGID       = true;
          RemoveIPC              = true;
          LockPersonality        = true;
          CapabilityBoundingSet  = "";
          SystemCallFilter       = [ "@system-service" "~@privileged" "@chown" ];
          UMask                  = "0077";
        };
      };
    };
  };
}
