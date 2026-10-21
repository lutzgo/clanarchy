# machines/ernst/containers/tvheadend.nix
#
# Tvheadend as a SAT>IP client against the FRITZ!Box 6591's four DVB-C tuners,
# publishing an M3U playlist and an XMLTV guide that Jellyfin consumes as a
# Live TV tuner + EPG source (M8 — see docs/history.md).
#
# ── THE PACKAGE IS HAND-ROLLED ──────────────────────────────────────────────
#
#   nixpkgs REMOVED both pkgs.tvheadend and services.tvheadend (PR #332259 —
#   unmaintained, stuck on FFmpeg 4); verified gone from the stable pin and
#   from nixos-unstable on 2026-08-27.  Rather than moving tiers (podman + the
#   linuxserver image) this follows M13's Janitorr precedent: built from source
#   in pkgs/tvheadend.nix with `--disable-libav`, so the FFmpeg coupling that
#   killed the nixpkgs package does not exist here at all.  Transcoding is
#   Jellyfin's job on the iGPU; Tvheadend only remuxes.  The unit below is
#   hand-written because there is no module to configure.
#
# ── THE FRITZ!BOX IS DIRECTLY ATTACHED — no VLAN, no UDM-Pro, no ZBF rule ───
#
#   A FRITZ LAN port is cabled STRAIGHT INTO enp12s0, ernst's second NIC.  The
#   whole flow — RTSP control and the unicast RTP return — stays on a two-port
#   bridge (br-fritz) that never touches the UDM-Pro, so the RTP return path is
#   ONE iptables line in this container, and the FRITZ's DHCP server and IPv6
#   RAs cannot reach any skynet VLAN.  Ledger rows L6 and L7 are retired as
#   never-created.
#
#   FRITZ!Box 6591 Cable (Vodafone), MAC 2c:91:ab:73:3f:35, in bridge mode for
#   the house uplink (the UDM-Pro holds the public IP).  Its LAN side
#   nonetheless serves all of 192.168.178.0/24: DHCP on, UI and SAT>IP at
#   192.168.178.1.  Provider CPE — we do not administer it, and its firmware
#   can change under us on Vodafone's schedule.
#
#   NOT ALL ITS LAN PORTS ARE EQUAL.  One (the guest port) is IPv4-silent: no
#   ARP, no DHCPv4, IPv6 RAs only, all services blocked.  That port is what
#   made the first cabling attempt look dead.  IF THIS LINK EVER GOES IPv4-DARK
#   AFTER SOMEBODY RE-PLUGS CABLES, CHECK WHICH LAN PORT THE CABLE IS IN before
#   debugging anything here.
#
#   The FRITZ side also sends IPv6 RAs carrying a DEFAULT ROUTE (observed: a
#   6to4 prefix plus an fd93: ULA).  ernst must never accept them — SN2 — which
#   is why every interface in this file pins `IPv6AcceptRA = false`.  During
#   Phase 0 the host briefly picked up a v6 default route via the FRITZ from a
#   manually-upped enp12s0; the networkd units below make that impossible by
#   construction.
#
# ── PHASE 0 EVIDENCE (measured 2026-08-27, from ernst over this very link) ──
#
#   satipdesc.xml     <satip:X_SATIPCAP>DVBC-4</satip:X_SATIPCAP> — four DVB-C
#                     frontends, present despite the Vodafone-branded firmware
#                     (modelNumber 6591lgi).  No branding lock.
#   Stream test       ZDF HD (freq=450, 256qam, sr 6900): 12 s of RTP →
#                     13.7 MB MPEG-TS (~9.1 Mbit/s); ffprobe: h264 1280x720
#                     @50fps + 2× ac3 + an EPG data stream.  EIT rides the mux,
#                     so the OTA grabber needs no external XMLTV source.
#   Mux sweep         all 8 probed frequencies lock, quality 13–14, level
#                     114–131.  330 MHz (Das Erste) locks noticeably SLOWER
#                     than the rest — expect its first tune to take seconds.
#   RTP transport     interleaved-TCP is NOT available: SETUP with RTP/AVP/TCP
#                     returns "461 Unsupported Transport".  UDP unicast RTP is
#                     the mode, hence the firewall rule below.  (It is also why
#                     ffprobe's RTSP client appeared to hang during Phase 0 —
#                     it stalls silently when RTP never arrives.)
#   Channel list      the box publishes its OWN M3U with tuning parameters at
#                     http://192.168.178.1/dvb/m3u/channellist.m3u (213
#                     channels).  Useful for cross-checking mux config.
#
# ── TUNER CEILING — 4, and every consumer counts ────────────────────────────
#
#   SAT>IP maps ONE RTSP session to ONE frontend: two clients on the same mux
#   still burn two tuners, unlike a local DVB card where one frontend feeds any
#   number of demuxed services.  The pool is shared with EPG grabbing (the OTA
#   EIT grabber periodically tunes muxes), anything the FRITZ!Box does with its
#   own tuners (FRITZ!App TV), and every concurrent stream and DVR recording.
#
#   THERE IS NO "MAX INPUT STREAMS" SETTING TO SET.  The ceiling is not a limit
#   applied to a network — it is the NUMBER OF FRONTENDS Tvheadend creates,
#   which comes from the SAT>IP device's "Tuner configuration" (`tunercfgu`).
#   That is left at **"Auto"**, which reads X_SATIPCAP from satipdesc.xml —
#   `DVBC-4` here — and creates exactly four DVB-C frontends.  Verified on the
#   running instance 2026-08-27: four tuners under "GoFRITZ - 192.168.178.1",
#   `tunercfgu: "Auto"` on disk.  Auto beats pinning `DVBC-4` by hand: if
#   Vodafone's firmware ever changes the tuner count, Auto follows and a
#   hand-pinned value silently would not.
#
#   Contention is resolved by SUBSCRIPTION WEIGHT, not by a cap: the EPG
#   grabber subscribes at weight 4 and live viewing at 100, so a live tune
#   PREEMPTS an EPG grab rather than failing — which is why the initial EPG
#   scan happily saturates all four tuners and is not a problem.  A fifth
#   concurrent tune fails cleanly at the RTSP layer (the box refuses the SETUP;
#   Tvheadend reports "no free adapter").
#
#   The same auto-detection got the transport right without being told:
#   `tcp_mode: false` on disk, matching the measured 461 above.
#
# ── TVHEADEND SHARES TUNERS, JELLYFIN RECORDS ───────────────────────────────
#
#   Tvheadend is a tuner-sharing + EPG daemon; Jellyfin's DVR schedules and
#   records.  Recordings therefore land in a library Jellyfin already indexes
#   BY CONSTRUCTION, so the recordings→library bridge — unsolved upstream — is
#   never built.  MediathekArr (M12) already covers öffentlich-rechtliche
#   catch-up, so the DVR's remaining job is modest.  The cost, stated: DVR
#   state lives in Jellyfin's database and its scheduler is materially weaker
#   (no priorities, no timeshift).
#
#   CONSEQUENCE FOR THIS FILE: uid 3026 has its OWN group and NO media access —
#   Tvheadend writes nothing outside /srv/state/tvheadend.  Moving recording
#   here would mean media group membership, a recordings subdirectory under
#   /srv/media, and that bridge tool: a new argument, not a config flip.  The
#   Jellyfin-side recordings directory is declared in jellyfin.nix.
#
# ── AUTHENTICATION: NONE HERE, AUTHELIA OWNS IT (--noacl) ───────────────────
#
#   TVHEADEND'S OWN HTTP AUTH CANNOT COEXIST WITH AUTHELIA FORWARD-AUTH,
#   because the two contend for the same header.  Measured through the real
#   chain on 2026-08-27:
#
#     no Authorization header          -> 302  (Authelia redirect, normal)
#     ANY Authorization header         -> 401  (from AUTHELIA, not Tvheadend)
#
#   Tvheadend challenges with **Digest only** — no Basic at all
#   (`WWW-Authenticate: Digest realm="tvheadend", qop=auth, …`, verified
#   against the built binary).  The browser answers in `Authorization`,
#   Traefik's forwardAuth hands that request to Authelia, which treats the
#   header as ITS OWN credential, fails to find `tvhadmin`, and returns 401
#   before the request reaches this container.  The browser re-prompts for
#   ever.  The symptom is a login box that reappears after every attempt —
#   which looks exactly like a wrong password and is not one.
#
#   So the choice was never "which credential" but "which layer
#   authenticates".  Authelia, per lgo 2026-08-27.  Consequences:
#
#     - Anyone who clears Authelia reaches Tvheadend AS ADMIN.  Today that is
#       `lgo` and `go`, both already in Authelia's `admins` group, so no
#       privilege is actually widened.
#     - 9981 is NOT a public port.  The container firewall below admits exactly
#       two sources — Traefik (10.0.90.12, behind two-factor) and Jellyfin
#       (10.0.90.10).  That firewall is now the ONLY thing between the LAN and
#       an unauthenticated admin UI, so DO NOT WIDEN IT without revisiting this.
#     - Jellyfin needs no credential in its M3U/XMLTV URLs.
#
#   THE TWO COHERENT ALTERNATIVES, if this ever needs revisiting: drop the
#   `authelia` middleware from the tvheadend router and let digest auth be the
#   gate (loses 2FA and the portal); or keep both and give Traefik's address an
#   anonymous full-rights ACCESS ENTRY inside Tvheadend so no Authorization
#   header is ever needed (defence in depth, but that entry is hand-made UI
#   state a lost state dir takes with it).  Neither is better by inspection.
#
# ── CHANNEL LOGOS (picons) — DECLARATIVE DATA, RUNTIME SETTING ─────────────
#
#   The logos are a pinned package (pkgs/picons.nix), bind-mounted read-only at
#   the stable path /picons.  The two settings that make Tvheadend USE them are
#   runtime state in /srv/state/tvheadend/config and cannot be declared here —
#   same as the access entries and the tuner configuration.
#
#   Configuration -> General -> Base, with "Expert" view level showing:
#
#     Channel icon path         file:///picons/%C.png
#     Channel icon name scheme  Service name picons
#
#   IT IS THE *CHANNEL ICON* PATH, NOT THE *PICON* PATH, and getting that wrong
#   is the single easiest way to end up with no logos and no error.  Tvheadend
#   has both and they drive different schemes:
#
#     chiconpath + chiconscheme  name-based.  %C is the channel name run
#                                through svcnamepicons(), which is what
#                                pkgs/picons.nix renames to.
#     piconpath  + piconscheme   service-REFERENCE based (`1_0_1_…`), keyed to
#                                a satellite bouquet's service refs.  This is
#                                DVB-C off a FRITZ!Box, so those refs match
#                                nothing in any published pack.
#
#   Most guides on the internet describe the second and call it "picons", which
#   is why this note exists.  `chiconscheme` = 2 (CHICON_SVCNAME,
#   src/tvheadend.h:106) is the value that matters.
#
#   COVERAGE, measured against the 198 channels this instance carries
#   (2026-09-11): 104/117 TV (88%), 49/81 radio (60%), 153/198 overall.  Radio
#   is the weak half and structurally will be — the pack is built for satellite
#   TV bouquets.
#
#   Kodi gets these for free: pvr.hts pulls channel icons over HTSP, so there
#   is nothing to configure on the TV side.
#
# ── STORAGE ─────────────────────────────────────────────────────────────────
#
#   /srv/state/tvheadend (zdata) → /var/lib/tvheadend in the container, the
#   same remap-to-upstream-default trick jellyfin.nix uses.  Everything
#   Tvheadend persists — network/mux/service tree, channel map, access
#   control, EPG database — lives there.  uid/gid 3026 on both sides (nspawn
#   maps 1:1; allocated in machines/ernst/allocations.nix).
{
  config,
  lib,
  pkgs,
  ...
}: let
  # Built from source; see pkgs/tvheadend.nix for why nixpkgs cannot supply
  # this and what must never be dropped from its configure flags.
  tvheadend = pkgs.callPackage ./pkgs/tvheadend.nix {};

  # Channel logos, renamed to the scheme THIS Tvheadend generates.  See
  # pkgs/picons.nix — the rename is not cosmetic, it is worth 27 channels, and
  # the package's header carries the measurement.
  picons = pkgs.callPackage ./pkgs/picons.nix {};

  tvheadendUid = 3026; # allocated in machines/ernst/allocations.nix
  tvheadendGid = 3026;

  # VLAN-90 peers allowed to reach the HTTP port (M3U, XMLTV, stream URLs,
  # web UI).  Same one-hop-on-br0 caveat as everywhere else: their frames
  # never reach the UDM-Pro, so this container's firewall is the only
  # enforcement point that exists for them.
  traefikAddr = "10.0.90.12"; # web UI via tvheadend.goclan.org (authelia)
  jellyfinAddr = "10.0.90.10"; # M3U tuner + XMLTV guide + stream pulls
  httpPort = 9981;
  htspPort = 9982; # see the firewall block — opened to exactly one address

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
  fritzAddr = "192.168.178.1";
  containerFritzAddr = "192.168.178.2/24";
in {
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
      LinkLocalAddressing = "no";
      IPv6AcceptRA = false;
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
      Bridge = "br-fritz";
      LinkLocalAddressing = "no";
      IPv6AcceptRA = false;
    };
    # A bridge port's terminal state is "enslaved"; and this one must also
    # never block boot (the FRITZ end can be powered off or unplugged).
    linkConfig.RequiredForOnline = "no";
  };

  # Avahi must not discover this segment.  With no host address here it has
  # nothing to bind, but the exclusion is stated rather than left to that
  # accident — during Phase 0, a manually-addressed enp12s0 had avahi
  # broadcasting ernst's mDNS onto the FRITZ segment within seconds.
  services.avahi.denyInterfaces = ["br-fritz" "enp12s0" "fritz0"];

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

  ##############################################################################
  # The container.
  ##############################################################################
  #
  # modules/containers/nspawn.nix generates the dirs unit, the VLAN-90 leg and
  # its backstop, the `fritz0` leg on br-fritz, the container preamble, the
  # in-container networking and the firewall.
  #
  # The br-fritz BRIDGE ITSELF stays above, and that split is the point: a
  # bridge, which physical port is enslaved to it, and which interfaces avahi
  # must not touch are facts about this house's wiring. Only the container's
  # own end of it is a container concern.
  clanarchy.containers.tvheadend = {
    enable = true;
    mac = "02:00:00:90:00:0a";

    # NO uid/gid PIN: the in-container user block declares it in full.

    stateVersion = "26.05";

    # AN ORDERED UNIT RATHER THAN A tmpfiles RULE, same fix as jellyfin: this
    # path is bound into the container, and a tmpfiles rule for a bound path
    # races the container's own start.
    stateDirs = [
      {
        path = "/srv/state/tvheadend";
        owner = tvheadendUid;
        group = tvheadendGid;
      }
    ];

    # The FRITZ segment. Static, no gateway, no DNS: the only thing this leg
    # exists for is 192.168.178.1, which is on-link. The FRITZ advertises a
    # default route over RA (measured — see the file header), and the module's
    # `IPv6AcceptRA = false` is what keeps this container from acquiring a
    # second, wrong path to the internet.
    bridgeLegs = [
      {
        veth = "fritz0";
        bridge = "br-fritz";
        address = containerFritzAddr;
      }
    ];

    allowFrom = [
      {
        peer = traefikAddr;
        port = httpPort;
      } # the web UI via tvheadend.goclan.org
      {
        peer = jellyfinAddr;
        port = httpPort;
      } # M3U tuner, XMLTV guide, streams
      {
        peer = kodiHostAddr;
        port = htspPort;
      } # Kodi's native protocol
      {
        peer = kodiHostAddr;
        port = httpPort;
      } # and its guide/stream fetches
      # SAT>IP: the tuner streams RTP back on ephemeral ports, so this one
      # names no port at all. Scoped to the FRITZ's own address, on a segment
      # nothing else sits on.
      {
        peer = fritzAddr;
        port = null;
        proto = "udp";
      }
    ];

    bindMounts = {
      # Tvheadend state, remapped to the upstream default path so the unit
      # below needs no --config gymnastics beyond naming it.
      "/var/lib/tvheadend" = {
        hostPath = "/srv/state/tvheadend";
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
        hostPath = "${picons}/picons";
        isReadOnly = true;
      };
    };

    config = {
      config,
      pkgs,
      lib,
      ...
    }: {
      # The container's firewall — the only enforcement point for br0-local
      # traffic (one L2 hop; the UDM-Pro never sees it).
      #
      #   9981/tcp   Traefik (web UI, behind authelia), Jellyfin (M3U + XMLTV +
      #              the stream URLs inside the playlist), and — since
      #              2026-09-11 — the ernst HOST, for Kodi's channel icons.
      #
      #              ── WHY KODI NEEDS THE *HTTP* PORT, WHICH IS NOT OBVIOUS ──
      #
      #              It already has HTSP on 9982, and one might reasonably
      #              assume channel icons ride that connection. They do not.
      #              For HTSP version >= 15 `htsp_image()` (src/htsp_server.c)
      #              sends a RELATIVE path — literally `imagecache/42` — and
      #              the CLIENT builds the absolute URL from its own
      #              connection settings. So pvr.hts turns that into
      #              `http://10.0.90.18:9981/imagecache/42` and fetches it
      #              over plain HTTP, out of band from HTSP entirely.
      #
      #              ── WHAT HAPPENED WHEN IT COULD NOT ───────────────────
      #
      #              M22's picon work gave all 198 channels an icon. Before
      #              that they had none, so Kodi never made these requests and
      #              the missing rule was invisible. Afterwards, every icon
      #              fetch hit this firewall and timed out after 30 s, on four
      #              threads, in a loop — and KODI'S UI WEDGED. Measured
      #              2026-09-11: a single kodi.bin spinning at 11% CPU for 23
      #              hours, its log solid with
      #
      #                CCurlFile::Open - <http://10.0.90.18:9981/imagecache/18>
      #                  Failed with code 0: Timeout was reached(28)
      #
      #              It could not even be exited from the menu. The TV was
      #              unusable, and nothing in `systemctl --failed` said so.
      #
      #              ── THE COST, STATED RATHER THAN BURIED ───────────────
      #
      #              9981 IS THE UNAUTHENTICATED ADMIN UI. `--noacl` is set
      #              (see AUTHENTICATION above), so whoever reaches this port
      #              is an admin. This rule hands that to every account on the
      #              ernst host — including `go`, which AUTOLOGINS on the
      #              television with no password.
      #
      #              What makes it defensible is that it is not a new class of
      #              access: the same /32 already has 9982, and this file
      #              already records that HTSP here is "ANONYMOUS AND
      #              FULL-RIGHTS, exactly like the 9981 admin UI". So the
      #              marginal grant is a web UI on top of an equivalent binary
      #              protocol, to one address that already had it.
      #
      #              IF THAT TRADE IS EVER REFUSED, the alternative is not to
      #              re-close this line — it is to give Tvheadend real access
      #              entries (an anonymous full-rights entry per permitted
      #              address, the escape route the AUTHENTICATION section
      #              already sketches) so that neither port is open to
      #              anonymous admin in the first place.
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
      ##########################################################################
      # The service.  Hand-written — nixpkgs removed services.tvheadend.
      ##########################################################################
      users.users.tvheadend = {
        isSystemUser = true;
        group = "tvheadend";
        uid = tvheadendUid;
        home = "/var/lib/tvheadend";
      };
      users.groups.tvheadend = {gid = tvheadendGid;};

      systemd.services.tvheadend = {
        description = "Tvheadend (SAT>IP client against the FRITZ!Box 6591)";
        wantedBy = ["multi-user.target"];
        wants = ["network-online.target"];
        after = ["network-online.target"];

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
          User = "tvheadend";
          Group = "tvheadend";
          Restart = "on-failure";
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
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ReadWritePaths = ["/var/lib/tvheadend"];
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectClock = true;
          ProtectHostname = true;
          ProtectControlGroups = true;
          ProtectKernelTunables = true;
          ProtectProc = "invisible";
          RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6" "AF_NETLINK"];
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          RemoveIPC = true;
          LockPersonality = true;
          CapabilityBoundingSet = "";
          SystemCallFilter = ["@system-service" "~@privileged" "@chown"];
          UMask = "0077";
        };
      };
    };
  };
}
