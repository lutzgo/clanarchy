# machines/ernst/containers/music-assistant.nix
#
# Music Assistant — the household's music player, over the library Navidrome
# already indexes (M30 — see docs/history.md).  An nspawn container with TWO
# legs on br0, serving `music.goclan.org` through Traefik.
#
# ── WHAT THIS IS, AND WHAT IT IS NOT ────────────────────────────────────────
#
#   Navidrome is a LIBRARY SERVER: it indexes Lidarr's tree, serves the
#   Subsonic API, and every client does the playing itself, on the phone.
#   Nothing in this house could say "play this album in the living room".
#
#   Music Assistant is the missing half — a player controller.  It holds the
#   queue, resolves a track to a stream, transcodes if the target needs it, and
#   drives the speakers.  It does NOT index music: it reads Navidrome over the
#   Subsonic API and treats it as its library.
#
#   SO IT ADDS NOTHING TO THE MUSIC PIPELINE AND REPLACES NONE OF IT.  Lidarr +
#   slskd + Soularr still acquire, Navidrome still indexes and still serves
#   every mobile client on its own hostname.  This is a consumer of Navidrome
#   in exactly the sense containers/karakeep.nix is a consumer of llama-swap.
#
#   nspawn tier because `services.music-assistant` is a first-class NixOS
#   module (invariant #1), despite upstream recommending its Docker image.
#
# ── THE LIBRARY: `opensubsonic`, NOT `filesystem_local` ─────────────────────
#
#   Music Assistant would happily read /srv/media/music directly, and
#   `filesystem_local` needs no dependencies at all.  Deliberately not done:
#
#     1. IT WOULD PUT A SECOND INDEX ON THE SAME FILES.  Navidrome's database
#        is not a cache — it holds play counts, ratings, starred tracks and
#        playlists that exist nowhere else.  Two scanners means two libraries
#        that disagree, and the one the phones use is the one that would drift.
#     2. IT WOULD NEED THE MEDIA MOUNT — binding /srv/media/music in and
#        joining gid 3000, a handle on 47 TB for a service whose entire job is
#        to fetch bytes over HTTP.  Reading through Navidrome keeps this
#        container with NO bind mount onto the media tree at all.
#
#   `subsonic_scrobble` is the return path, and it is why this is better than a
#   second index rather than merely cheaper: a play started here is scrobbled
#   back to Navidrome, so history and star ratings stay in the one database the
#   mobile clients read.  It declares `depends_on: opensubsonic`.
#
#   THE PROVIDER IS CONFIGURED OUTSIDE THIS FILE.  Provider configuration lives
#   in Music Assistant's own database under ${stateRoot}; there is no
#   declarative option for a URL and a password and there will not be one.
#
#   "OUTSIDE THIS FILE" IS NOT THE SAME AS "IN THE BROWSER", and the difference
#   bit twice: `musiccast` and `subsonic_scrobble` declare no config entries, so
#   their setup dialogs have no fields and SAVE can never enable.  They must be
#   written into the settings database directly — see the note at `providers`
#   for the shape and the procedure.
#
# ── TWO LEGS, AND THE SECOND ONE IS THE WHOLE POINT ─────────────────────────
#
#   eth0  VLAN 90 (Services)  — Traefik reaches the web UI, Home Assistant
#                               reaches the WebSocket API, Navidrome is one L2
#                               hop away on .13.
#   iot1  VLAN 20 (IoT)       — the segment the speakers are on.  This leg
#                               exists for DISCOVERY and is not optional.
#
#   THE PLAYERS ARE TWO YAMAHA MusicCast SPEAKERS ON VLAN 20 — `Küche` at
#   10.0.20.31 and `Renate` at 10.0.20.32.  No Chromecast, no Sonos, no DLNA
#   renderer, no Snapcast.  M30 shipped saying there was ONE, having read Home
#   Assistant's `core.config_entries` as an inventory of the segment when it is
#   an inventory of what the HUB has been configured with.  Browsing
#   `_http._tcp.local.` from the leg itself found both in seconds.
#
#   mDNS is link-local by definition, and this repo has twice refused in
#   writing to relay it across a firewall boundary.  containers/home-assistant.nix
#   answered that with a second veth onto the segment its devices are on; this
#   file does the same, one VLAN later.  Unicast to VLAN 20 needs no leg — the
#   UDM-Pro has one `Internal` zone with Allow All.  What is not routable is
#   the discovery, and that is all this leg is for.
#
#   `iot0` is taken by containers/home-assistant.nix, hence `iot1`.  nspawn's
#   `--network-veth-extra` names BOTH ends, so the name lands in the host's one
#   flat interface namespace; the assertion in modules/containers/assertions.nix
#   is what catches a collision, not this comment.
#
# ── AND THE SECOND LEG DOES NOTHING UNTIL ONE SETTING IS CHANGED ────────────
#
#   READ THIS BEFORE DEBUGGING ANY "no players found" REPORT.  Music
#   Assistant's zeroconf binds to the DEFAULT INTERFACE ONLY unless told
#   otherwise (CONF_ENTRY_ZEROCONF_INTERFACES, constants.py:669).  The default
#   here is eth0, on VLAN 90, where there are no speakers.  So `iot1` is
#   carried, addressed, firewalled and DECORATIVE until Settings -> Core ->
#   Discovery -> "Mdns/Zeroconf discovery interface(s)" is set to **All
#   interfaces** (`core.discovery.values.zeroconf_interfaces = "all"`,
#   advanced-only, `requires_reload`).
#
#   MEASURED BOTH WAYS 2026-09-27: with the default, the provider loaded and
#   discovered nothing for twenty minutes while both speakers were announcing —
#   confirmed by browsing `_http._tcp.local.` from the hass container's own
#   VLAN-20 leg, which saw both immediately.  With "all", both appeared within
#   a minute of the reload.
#
#   It is NOT declarable — it lives in the settings database like every
#   provider — so it is a deploy step, and the FIRST one to check.  The failure
#   is indistinguishable from a household with no discoverable devices, with
#   every firewall rule correct.
#
#   And the `musiccast` provider is DISCOVERY-ONLY: its manifest declares
#   `"mdns_discovery": ["_http._tcp.local."]` and provider.py has exactly one
#   entry point, `on_mdns_service_state_change`.  There is no add-by-address
#   flow to fall back on.  (`check_yamaha_ssdp` runs afterwards and is a
#   UNICAST HTTP GET of the device description, not multicast — which is why
#   this file opens 5353/udp and, unlike containers/home-assistant.nix, does
#   NOT open 1900/udp.)
#
# ── THE STREAM SERVER IS A SECOND LISTENER, ON A SECOND PORT ────────────────
#
#     8095  the API and the web UI.  A WebSocket-driven SPA; the Home
#           Assistant integration speaks the same WebSocket.
#     8097  the STREAM server, deliberately separate from the API
#           (controllers/streams/README.md).  Its client is a Yamaha speaker,
#           not a browser and not Traefik.
#
#   Both are Python constants (`DEFAULT_PORT`), settable only in the settings
#   database.  Change either in the UI and the rules below stop matching,
#   silently.
#
# ── AND THE RECEIVER TALKS BACK ON AN EPHEMERAL UDP PORT ────────────────────
#
#   aiomusiccast does not poll.  It opens a UDP socket on ("0.0.0.0", 0) — an
#   EPHEMERAL port chosen by the kernel — and hands the number to the receiver
#   in an `X-AppPort` header; the receiver pushes status events there roughly
#   every second while playing (pyamaha.py:186-199).
#
#   There is no fixed port to open, and conntrack does not help: the events are
#   unsolicited from the kernel's point of view, because the HTTP request that
#   registered the port was a different socket on a different protocol.  So the
#   rule below is narrow in SOURCE (the one receiver) and wide in PORT (the
#   local ephemeral range).  That asymmetry is stated rather than hidden.
#
#   WITHOUT IT the failure is not "no player": the receiver is discovered, it
#   plays, and the UI simply never updates — volume, position and track changes
#   made at the receiver are invisible.  Which reads as a Music Assistant bug.
#
# ── NO forward-auth, AND NO SECOND FACTOR ──────────────────────────────────
#
#   `music.goclan.org` is in `appApiHosts`; containers/ingress-policy.nix owns
#   the argument (Home Assistant's integration uses ONE url for both the
#   browser redirect and its own server-side `/ws`, so there is no single URL
#   that satisfies both halves with the middleware attached) and the
#   compensation list.  Do not re-derive it here.
#
#   LAN-ONLY, which is what keeps the exemption proportionate: this is the ONLY
#   name in `appApiHosts` that is NOT also in `wanExposed` — no public A
#   record, no ledger row.  The compensations are defending the house against
#   the house.
#
#   THE FIRST-RUN WINDOW CLOSES ITSELF, which is the one real difference from
#   Komga, Navidrome and CWA: `/setup` creates the first admin and is
#   unauthenticated by construction, but `_handle_setup` returns 400 "Setup
#   already completed" once `auth.has_users`.  It is still a deploy step —
#   until that account exists, anybody who can reach this vhost can create it.
#
# ── THE CONTAINER IS CALLED `mass`, NOT `music-assistant` ───────────────────
#
#   `vb-music-assistant` is 18 characters and IFNAMSIZ caps at 15, so the link
#   cannot be created at all — a failure at container START, not at evaluation,
#   so a clean `nix build` proves nothing.  `mass` is upstream's own
#   abbreviation (it advertises `_mass._tcp` and its config lives under a
#   `mass` namespace), not an invented nickname.
#
#   So: the FILE is music-assistant.nix, the SERVICE is
#   music-assistant.service inside, and the MACHINE is `mass` —
#   `machinectl`, `nixos-container run mass`, `systemctl restart container@mass`.
#
# ── DynamicUser IS TURNED OFF, AND THE STATE DIRECTORY IS WHY ───────────────
#
#   Upstream's `DynamicUser = true` + `StateDirectory = "music-assistant"`
#   MIGRATES the state directory to /var/lib/private/, and here that path is a
#   BIND MOUNT.  containers/crowdsec.nix measured exactly this and
#   service-modules/local-ai.nix hit it with ollama before that.
#
#   The deeper reason is that ids pass through the nspawn boundary UNMAPPED
#   onto zdata, so a systemd-ALLOCATED uid owning files on the pool is
#   precisely what the allocation registry exists to prevent.  Keeping state
#   and keeping a per-boot identity are mutually exclusive.  So: uid/gid 3040,
#   with the six protections `DynamicUser` had been implying restated below.
#
# ── WHAT IS DELIBERATELY NOT DONE ───────────────────────────────────────────
#
#   NO PROMETHEUS JOB.  Music Assistant exposes no metrics endpoint of any
#   kind — SN3, stated rather than omitted.  What covers it is the
#   container-unit collector: `exporters.containers` walks `machinectl list` on
#   a one-minute timer, so `music-assistant.service` failing in here raises
#   `ContainerSystemdUnitFailed` with no per-container configuration.
#
#   NO SPOTIFY, TIDAL, QOBUZ OR YouTube MUSIC.  `providers` below installs
#   dependency CLOSURES, and each would be one for a service this household
#   does not subscribe to; ytmusic would additionally pull in `deno` and need
#   `@pkey` in the syscall filter.
#
#   NO SNAPCAST, AIRPLAY OR CHROMECAST — measured, not assumed: there is no
#   such device in Home Assistant's registry.  `airplay` would additionally
#   want inbound UDP 32768-65535 (upstream's own `openFirewall`).
#
#   DECLINED IN THE 2026-09-27 CATALOGUE SWEEP, so the next person gets the
#   answers rather than the search:
#
#     genius_lyrics      `lyricsgenius` is NOT in nixpkgs — a derivation plus
#                        an API token for a SUPPLEMENTARY source, when `lrclib`
#                        is already enabled and carries synced lyrics.
#     airplay_receiver   NOT FREE, and invisibly so: the nixpkgs module reacts
#                        to this name by enabling AVAHI WITH PUBLISHING inside
#                        this container, on BOTH legs, where publishing is off
#                        and the host denies avahi on iot1.  Would also need
#                        inbound rules for shairport-sync or be decorative.
#                        ALPHA; its own PR if ever wanted.
#     lastfm_scrobble    Packaged, declined on merit: a SECOND scrobble
#                        destination behind a commercial account, when
#                        `listenbrainz_scrobble` does the same job for
#                        MetaBrainz with openly licensed data.
#     tunein             Wants an account for streams `radiobrowser` reaches
#                        without one.
#     spotify_connect    ALPHA, needs Premium.  No Spotify in this fleet.
#     plex_connect, vban_receiver, ariacast_receiver
#                        ALPHA; declined by lgo by name.
#
#   PROVIDERS WITH NO REQUIREMENTS NEED NO ENTRY IN `providers` AT ALL: the
#   option installs dependency closures, so a provider whose manifest lists no
#   requirements — `somafm`, `radioparadise`, `podcastfeed`,
#   `itunes_podcasts`, `internet_archive`, `orf_radiothek` — already imports
#   and can be enabled in the settings database alone.  None is today; any of
#   them is a UI step and no deploy.
#
#   NO SECOND DATASET.  A SQLite database and a tree of small JSON blobs is
#   `zdata/state`'s write profile exactly (128K recordsize, the default) — the
#   call home-assistant.nix, miniflux.nix and karakeep.nix all made before
#   this one.  docs/guides/ernst-zdata-datasets.md splits by write profile,
#   not by service.
#
# ── THE HOME ASSISTANT INTEGRATION IS ALREADY OFFERABLE ─────────────────────
#
#   Nothing is added to containers/home-assistant.nix for this.
#   `music_assistant` is packaged in this channel and that file's
#   `extraComponents` ends with `++ buildableComponents` since PR #229, so the
#   hub can already offer it.
#
#   IT WILL NOT AUTO-DISCOVER, and that is correct rather than broken.  Music
#   Assistant advertises `_mass._tcp.local.`, but the hub's firewall accepts
#   5353/udp on `iot0` ONLY — VLAN 20, where the devices are — so nothing on
#   VLAN 90 is heard either way.  Opening mDNS between the two containers to
#   save one text field would put both services' multicast on the Services VLAN
#   for no capability.  The config flow takes the URL by hand.
{
  config,
  pkgs,
  lib,
  ...
}: let
  ##############################################################################
  # Identity.
  ##############################################################################
  # uid/gid 3040 — the next free number in ernst's 3000 block, which M29b left
  # at 3040 when mneme took 3039.  Checked against nixpkgs' own ids.nix first,
  # as docs/guides/adding-a-module.md requires: there is NO static
  # `music-assistant` uid upstream, so nothing here is restating a number
  # somebody else owns (which is an option conflict, not a no-op — that is what
  # bit M27 with `hass` = 286 and `postgres` = 71).
  #
  # It is a real number rather than DynamicUser for the reason in the header:
  # this uid owns files on zdata, and ids cross the nspawn boundary unmapped.
  massUid = 3040;
  massGid = 3040;

  ##############################################################################
  # Addresses and ports.
  ##############################################################################

  # Traefik.  The only client of the web UI, and the only address allowed to
  # reach 8095 besides the hub below.
  traefikAddr = "10.0.90.12";

  # NO BINDING FOR HOME ASSISTANT, AND ITS ABSENCE IS THE POINT.  This file
  # shipped with an accept for 10.0.90.27 on 8095, so that the hub's
  # `music_assistant` integration could hold its WebSocket open on a direct L2
  # hop and skip the proxy — which was the stated reason this hostname did not
  # need a forward-auth exemption.
  #
  # THE INTEGRATION CANNOT USE IT.  Its config flow drives the browser and its
  # own server-side calls from ONE url (see the header), so the hub arrives
  # through Traefik on .12 like every other client, and an accept for .27 would
  # be a rule nothing uses carrying a comment that asserts the opposite of what
  # this file now says.  M26's first deploy-day defect removed a firewall rule
  # rather than adding one; this is the same move.
  #
  # Re-add it only alongside a way for the hub to be pointed at the direct
  # address, which this release of the integration does not have.

  # The service index (M26), which runs INSIDE containers.arr and therefore
  # shares Navidrome's address.  It gets 8095 for a `siteMonitor` — an up/down
  # dot, no widget, the same treatment Komga and Navidrome have there.
  #
  # THIS GRANTS LESS THAN IT LOOKS LIKE, and that is why it is here rather than
  # declined: `/` is on `auth_middleware`'s bypass list (see the accounts
  # section of the header), so a status probe needs no credential — and
  # everything past it does.  The dashboard gets to learn that the service
  # answers, not to control the music.  Contrast the hub's own tile, which
  # carries a long-lived ACCESS TOKEN because /api/states is authenticated.
  dashboardAddr = "10.0.90.13";

  # NOTHING IS DECLARED HERE FOR NAVIDROME, and its absence is worth a line.
  # The library lives at 10.0.90.13:4533 inside containers.arr, and this
  # container reaches it OUTBOUND — so the accept it needs is on the far end,
  # in containers/arr/, and nothing in this file's firewall block concerns
  # it.  A reader looking for the Navidrome wiring should look there.

  # ── THE MusicCast SPEAKERS, AND THERE ARE TWO ──────────────────────────────
  #
  # THIS FILE SHIPPED SAYING THERE WAS ONE, and the mistake is instructive about
  # where the fact came from.  M30 read Home Assistant's `core.config_entries`,
  # found a single `yamaha_musiccast` entry at 10.0.20.31, and wrote "the one
  # speaker in the house" — which is a statement about what the HUB has been
  # configured with, not about what is on the segment.
  #
  # Browsing `_http._tcp.local.` from the VLAN-20 leg found both, within seconds:
  #
  #     Küche._http._tcp.local.   10.0.20.31   (the one the hub knows)
  #     Renate._http._tcp.local.  10.0.20.32   (nobody had told this repo)
  #
  # Music Assistant discovered both as soon as it was looking on the right
  # interface, so the second one was never a question of discovery — only of
  # whether the two source-matched rules below would let it play.
  #
  # NAMED INDIVIDUALLY RATHER THAN AS A SUBNET, and that is a deliberate trade.
  # `-s 10.0.20.0/24` would cover every future speaker with no edit, and it would
  # also hand the whole IoT segment an ephemeral UDP range into this container —
  # a much wider grant than mDNS, which is multicast and has no source to name.
  # Adding a speaker is one line here; that is the right amount of friction for
  # something that opens a port to a device.
  # ── BOTH SPEAKERS ARE ON WI-FI, AND THE WIRED ATTEMPT IS RECORDED ─────────
  #
  # `Renate` (YSP-5600) is cabled to the switch and CANNOT USE THE CABLE.  The
  # attempt is written down rather than deleted, because the obvious next move
  # for a future reader — "just plug it in and switch it to wired" — is the one
  # that was already tried and failed.
  #
  #   The device switched itself to wired mode after a restart and then had no
  #   link at all.  Its own information screen:
  #
  #       Status        Trennen             (disconnected)
  #       Verbindung    Kabelgebunden       (wired)
  #       IP-Adresse    0.0.0.0             (and netmask, gateway, both DNS)
  #
  #   A device with link but no lease reports CONNECTED with 0.0.0.0, so this is
  #   a carrier problem, not DHCP.  Confirmed from this container: a full ARP
  #   sweep of VLAN 20 plus scans of 10.0.10.0/24, 10.0.30.0/24, 10.0.5.0/24 and
  #   an ARP sweep of VLAN 50 found NEITHER of its MACs anywhere.
  #
  #   THE LIKELY CAUSE IS THE SWITCH PORT, not the speaker.  The UDM-Pro's last
  #   record for the wired MAC is 192.168.2.10 on 2026-01-03 — an address from
  #   the pre-renumber flat network — so that port has not had a working lease
  #   since the VLAN cutover and was probably never re-profiled onto IoT.
  #
  # lgo reconnected it to Wi-Fi and abandoned the cable, so .32 is permanent
  # again and the wired address .33 is retired here.  ONE LINE PER SPEAKER, and
  # no line for an address nothing holds: an accept for .33 would now be a rule
  # with no client, which is what M26's first deploy-day defect removed rather
  # than added.
  #
  # IF THE CABLE IS EVER REVISITED: fix the switch port's network profile first
  # (it must be IoT/VLAN 20, where these rules and the DHCP reservation live),
  # confirm the speaker reports `Verbindung: Kabelgebunden` with a real address,
  # and only then add its wired address here.  The wired MAC is
  # 00:A0:DE:86:BE:4A and already has a UDM-Pro reservation for 10.0.20.33.
  #
  # ── AND THE TWO INTERFACES CARRY DIFFERENT VENDORS' MACs ──────────────────
  #
  #     wired_lan:    00A0DE86BE4A    Yamaha OUI (00:a0:de)
  #     wireless_lan: F83331DC4499    TI OUI     (f8:33:31)
  #
  # Only the wired NIC is a Yamaha.  The radio is a Texas Instruments module, so
  # the address in use below appears in the UDM-Pro as an unnamed "Texas
  # Instruments" client rather than as a speaker — which is worth knowing before
  # anyone auditing VLAN 20 concludes there is a stranger on the segment.
  musiccastAddrs = [
    "10.0.20.31" # Küche  — WX-021, Wi-Fi (has a wired port; no cable run)
    "10.0.20.32" # Renate — YSP-5600, Wi-Fi; its cable does not link, see above
  ];

  # 8095 — the API and web UI.  8097 — the stream server the PLAYER fetches.
  # Both are Python constants in the application, not NixOS options; see the
  # header.
  massPort = 8095;
  streamPort = 8097;

  # The local ephemeral range, which is what aiomusiccast's event socket binds
  # into.  Matches ernst's `net.ipv4.ip_local_port_range` default — restate it
  # here rather than reading the sysctl, because the rule has to be a literal
  # in the iptables invocation either way and a silent mismatch would look like
  # a flaky receiver.
  ephemeralLow = 32768;
  ephemeralHigh = 60999;

  ##############################################################################
  # The second leg.
  ##############################################################################

  # NOT `iot0` — containers/home-assistant.nix has that, and the name is
  # host-global.  See the header, and the assertion in
  # machines/ernst/networking.nix that turns a collision into an eval failure.
  iotVeth = "iot1";

  ##############################################################################
  # State.
  ##############################################################################

  # On zdata/state with no dataset of its own — see the header.
  stateRoot = "/srv/state/music-assistant";

  # The module's own default, and the value its `extraOptions` and
  # `StateDirectory` both already agree on.  Binding at the default means
  # nothing is overridden and nothing can disagree — the trick
  # containers/home-assistant.nix uses for /var/lib/hass.
  configDir = "/var/lib/music-assistant";
in {
  # ── The container, declared rather than assembled ─────────────────────────
  #
  # Generated by modules/containers/nspawn.nix: the dirs unit with its mount
  # guard, both host-side networkd files, both VLAN backstops, the container
  # preamble, the in-container networking for both legs, and the firewall.
  clanarchy.containers.mass = {
    enable = true;

    # Sequence 16 in machines/ernst/allocations.nix, which asserts the match.
    mac = "02:00:00:90:00:16";

    uid = massUid;
    gid = massGid;
    user = "music-assistant";

    stateDirs = [
      {
        path = stateRoot;
        owner = massUid;
        group = massGid;
        mode = "0700";
      }
    ];

    bindMounts.${configDir} = {
      hostPath = stateRoot;
      isReadOnly = false;
    };

    # ── THE SECOND LEG, AND WHY IT IS NOT A RELAY ─────────────────────────
    #
    # The `musiccast` provider is mDNS-discovery-only and the one speaker is a
    # Yamaha receiver on the IoT VLAN. mDNS is link-local, and this repo
    # refuses to relay it across a firewall boundary, so this container gets a
    # port on that segment instead.
    #
    # `iot1` and not `iot0`: the name is a HOST-GLOBAL allocation and
    # containers/home-assistant.nix already holds `iot0`. The assertion in
    # modules/containers/assertions.nix is what checks that, not this comment.
    vlanLegs = [
      {
        veth = iotVeth;
        vlan = 20;
        mac = "02:00:00:20:00:02";
      }
    ];

    allowFrom =
      [
        # The web UI, through Traefik, and the service index's tile.
        {
          peer = traefikAddr;
          port = massPort;
        }
        {
          peer = dashboardAddr;
          port = massPort;
        }
        # mDNS discovery, confined to the IoT leg — so enabling it for the
        # speakers does not also open it on the services VLAN. No `-s`: the
        # query goes to a multicast group and every device on the segment
        # answers, so there is no single address to name.
        {
          interface = iotVeth;
          proto = "udp";
          port = 5353;
        }
      ]
      # ONE RULE PER SPEAKER, not one for the segment.
      #
      # THE STREAM SERVER IS A SECOND LISTENER ON A SECOND PORT, and keeping the
      # two apart is how the firewall stays honest: a speaker pulls audio from
      # here, and that is not the web UI.
      ++ map (a: {
        peer = a;
        port = streamPort;
      })
      musiccastAddrs
      # Each receiver answers from an ephemeral port.
      ++ map (a: {
        interface = iotVeth;
        proto = "udp";
        peer = a;
        port = "${toString ephemeralLow}:${toString ephemeralHigh}";
      })
      musiccastAddrs;

    config = {
      config,
      pkgs,
      lib,
      ...
    }: {
      # ── resolved MUST NOT HOLD :5353 ─────────────────────────────────────
      #
      # Music Assistant runs its own python-zeroconf, exactly as Home Assistant
      # does, so this container has the same two-mDNS-sockets hazard
      # containers/home-assistant.nix measured on its first deploy:
      #
      #     ss -lunp | grep 5353
      #       0.0.0.0:5353   <the application>
      #       0.0.0.0:5353   systemd-resolve
      #
      # Multicast responses reach every socket joined to 224.0.0.251, so the
      # application gets those regardless — but a UNICAST mDNS response (what a
      # QU query asks for) is load-balanced between the two sockets by
      # SO_REUSEPORT.  The symptom would be a receiver that is discovered most
      # of the time, which reads as a flaky speaker rather than as a second
      # listener.  On a discovery-ONLY provider that is the whole failure mode.
      #
      # LLMNR goes too, for containers/tvheadend.nix's reason rather than this
      # one: it would otherwise answer name queries on the household IoT
      # segment, which is the opposite of the posture the avahi `denyInterfaces`
      # line on the host takes.
      #
      # Nothing is lost: this container resolves through Technitium on eth0,
      # declared explicitly below.
      services.resolved.settings.Resolve = {
        MulticastDNS = "no";
        LLMNR = "no";
      };

      services.music-assistant = {
        enable = true;

        # ── `providers` IS A DEPENDENCY LIST, NOT A CONFIGURATION ───────────
        #
        # It selects which optional Python closures get installed; the provider
        # itself is still added and configured in Music Assistant's UI, and its
        # settings live in the database under ${configDir}.  So a name here is
        # necessary and not sufficient — and a name MISSING here presents as a
        # provider that appears in the list and then fails to set up.
        #
        # ── TWO OF THE THREE CANNOT BE ADDED IN THE BROWSER AT ALL ─────────
        #
        # The header says provider configuration is a UI step.  For
        # `opensubsonic` that is true — it has a form, because it needs a URL
        # and a credential.  For the other two it is FALSE, and the failure is
        # a dead button rather than an error:
        #
        #     musiccast/__init__.py         get_config_entries -> ()
        #     subsonic_scrobble/__init__.py get_config_entries -> ()
        #
        # A provider with no config entries renders a setup dialog with NO
        # FIELDS, and Music Assistant's frontend keeps SAVE disabled because
        # nothing has changed — so there is no way to press it.  Measured on
        # both, 2026-09-27.  Neither is broken; there is simply nothing for the
        # form to collect, and the UI has no case for that.
        #
        # ADD THEM IN THE SETTINGS DATABASE INSTEAD, with the service stopped:
        #
        #     systemctl -M mass stop music-assistant
        #     cp -a ${configDir}/settings.json ${configDir}/settings.json.bak
        #     jq '.providers.<domain> = {values:{}, type:"<type>",
        #           domain:"<domain>", instance_id:"<domain>", enabled:true,
        #           name:"<Name>", default_name:null, last_error:null}' …
        #     install -o ${toString massUid} -g ${toString massGid} -m 0600 …
        #     systemctl -M mass start music-assistant
        #
        # `instance_id` EQUALS THE DOMAIN for both, because each manifest sets
        # `multi_instance: false`; a multi-instance provider gets
        # `<domain>--<shortuuid>` instead, which is why the OpenSubsonic entry
        # in that file looks different.  The shape is upstream's own — it is
        # what `create_builtin_provider_config` writes (controllers/config.py)
        # — so this is filling in a record the application would have written,
        # not inventing one.
        #
        # ── AND THE APPLICATION ENABLES A DEFAULT SET BEHIND THIS OPTION ────
        #
        # Measured on the first start, 2026-09-27.  Music Assistant writes a
        # `default_providers_setup` into its own settings and turns on a handful
        # of player providers whether or not anything here installed their
        # dependencies.  On this deploy that was `sendspin`, `airplay`,
        # `chromecast` and `dlna`, and all four failed on every start:
        #
        #     ERROR [music_assistant.controllers.config] Failed to load provider
        #     module for chromecast: Configure chromecast in
        #     `services.music-assistant.providers` to install the required
        #     dependencies.
        #
        # THE ERROR NAMES THIS OPTION AND THE FIX IS NOT TO EDIT IT.  That
        # message is nixpkgs' own, from `dont-install-deps.patch`, which replaces
        # upstream's pip-install-at-runtime with a RuntimeError; taken at face
        # value it invites adding four dependency closures for devices this
        # household does not own.  The correct fix is to DISABLE them in the UI,
        # because the defect is that they are enabled, not that they are missing.
        #
        # IT IS NOISE RATHER THAN AN OUTAGE, and it does not reach the alerting
        # path: these are application log lines, not a failed systemd unit, so
        # `ContainerSystemdUnitFailed` stays quiet and correctly so.  It is
        # recorded because the error message is actively misleading about which
        # way to fix it.
        #
        # OBSERVED AGAIN 2026-10-14, as `dlna` rather than `chromecast`:
        #
        #     ModuleNotFoundError: No module named 'async_upnp_client'
        #     RuntimeError: Configure dlna in `services.music-assistant.providers`
        #
        # Checked against this list before acting, which is the point of the
        # paragraph above: `dlna` is absent here deliberately, so the provider
        # is enabled in the UI and its requirements were never installed.
        # Operator decision the same day: DLNA is not wanted, so the list stays
        # as it is and the toggle comes off in the UI.  Do not "fix" this by
        # adding a line.
        providers = [
          # THE LIBRARY.  Navidrome speaks OpenSubsonic, and this is the
          # provider that reads it — see the header for why this rather than
          # `filesystem_local`.  Pulls in py-opensonic.
          "opensubsonic"

          # THE RETURN PATH.  Scrobbles plays back to Navidrome so history and
          # ratings stay in the database the phones read.  `depends_on:
          # opensubsonic` in its manifest, and no requirements of its own — so
          # this line costs nothing but makes the arrangement above symmetric
          # instead of read-only.
          "subsonic_scrobble"

          # THE PLAYERS.  The two Yamaha MusicCast speakers on VLAN 20, which
          # are the only playback targets in this house that are not browser tabs.
          # Pulls in aiomusiccast.  DISCOVERY-ONLY — there is no add-by-address
          # flow, which is the entire reason this container has a second leg.
          "musiccast"

          # LIVE RADIO.  The radio-browser.info community database, which is
          # what puts WDR 2 Rheinland, WDR 5 and the rest of the ARD stations
          # in reach without hand-maintaining stream URLs that the broadcaster
          # re-points without warning.  Pulls in `radios`, and nixpkgs has
          # exactly the 0.3.2 the manifest pins — no skew to check, unlike
          # py-opensonic.
          #
          # NO ACCOUNT AND NO CREDENTIAL, which is why this is the radio answer
          # here and `tunein` is not: TuneIn wants a login, and a second set of
          # household credentials to buy the same public streams is a poor
          # trade.
          "radiobrowser"

          # ── AUDIOBOOKS AND PODCASTS, from the server that already has them ─
          #
          # lgo asked (2026-09-27) which player supports Storyteller on
          # HASS/MASS.  The answer is NEITHER, and it is structural rather
          # than a gap: Storyteller emits an EPUB3 with media overlays — a
          # BOOK — and Music Assistant plays audio streams.  Its synced output
          # is read in the Storyteller Reader app and nowhere else in this
          # fleet.  This provider is the thing that actually answers the
          # question behind it: it puts the AUDIOBOOKS on the MusicCast
          # speakers, which is the part of "listening" that MA can do.
          #
          # Audiobookshelf is already deployed (arr container, port 13378) and
          # already holds the household's audiobooks, so this is a second
          # reader of an existing library rather than a new one — the same
          # shape as `opensubsonic` over Navidrome above, and chosen for the
          # same reason.  Chapters, resume position and BIDIRECTIONAL progress
          # sync come with it, so finishing a chapter in the ABS phone app and
          # picking it up on a speaker is one library, not two.
          #
          # NO SKEW, checked the way this file checks everything: the provider
          # manifest in the deployed MA 2.8.7 pins `aioaudiobookshelf==0.1.20`
          # and nixpkgs at this flake's pin has exactly 0.1.20.  Stage is
          # `stable`, not alpha — unlike the four receivers declined below.
          #
          # IT NEEDS AN API KEY, NOT A PASSWORD, and that is a hard version
          # boundary rather than a preference: ABS on ernst is 2.36.0, and ABS
          # requires key auth from 2.26 onwards.  The key is minted in ABS
          # (Settings → Users → API Keys) and entered in MA's browser UI, so
          # this line does the one thing the option is for — installing the
          # dependency closure — and nothing else, exactly like the two
          # plugins below.
          "audiobookshelf"

          # ── TWO PLUGINS, AND UNLIKE THE THREE ABOVE THEY HAVE FORMS ───────
          #
          # Both can be added in the browser, because both declare real config
          # entries — ListenBrainz two, Home Assistant thirteen.  So this option
          # is doing the ONE thing it is for and nothing else: installing the
          # dependency closure.  Enabling and configuring them is lgo's, in the
          # UI, because both need a token only he can mint.
          #
          # LISTENBRAINZ, NOT LAST.FM, and that was a choice rather than a
          # default: `lastfm_scrobble` is packaged too (pylast 7.0.2) and was
          # declined — it is a second scrobble destination behind a commercial
          # account, where ListenBrainz is MetaBrainz, the same project behind
          # the `musicbrainz` metadata provider this container already uses, and
          # its data is openly licensed.  Plays already reach Navidrome through
          # `subsonic_scrobble`; this is the one that leaves the house, so who
          # receives it is worth a sentence.
          "listenbrainz_scrobble"

          # THE HOME ASSISTANT PLUGIN IS THE REVERSE DIRECTION FROM THE
          # INTEGRATION, and conflating the two is easy.  The hub's
          # `music_assistant` integration makes MA's players appear in Home
          # Assistant.  THIS makes Home Assistant's own media players and
          # entities visible to MA.  Different daemon, different direction,
          # different credential — and this one is a plugin in MA's settings,
          # not something containers/home-assistant.nix declares.
          #
          # It needs no firewall rule: MA dials OUT to the hub on 10.0.90.27,
          # and that container already admits .30 on 8123 for the service index
          # and Traefik… no, it does not — outbound from here is unrestricted
          # and the ACCEPT it needs is on the hub's side, which already carries
          # a rule for Traefik and the dashboard only.  Expect to add `.30` to
          # containers/home-assistant.nix's 8123 list when this is configured;
          # it is NOT added here, because an accept for a plugin nobody has
          # enabled yet is a rule with no client.
          "hass"

          # ── NOT A SONOS.  THIS IS musiccast's UNDECLARED DEPENDENCY ────────
          #
          # There is no Sonos in this house and this does NOT enable the Sonos
          # provider — `providers` installs dependency closures; enabling is
          # separate state in Music Assistant's own database, and `sonos` sits
          # in upstream's `DEFAULT_PROVIDERS` behind `require_mdns = True`, so
          # nothing turns it on until a Sonos is actually seen on the segment.
          #
          # IT IS HERE BECAUSE musiccast CANNOT IMPORT WITHOUT IT, and the
          # manifest does not say so.  `providers/musiccast/manifest.json`
          # declares exactly one requirement, `aiomusiccast==0.15.0`, and that
          # is what the nixpkgs `providers` option installs.  The real import
          # graph is longer:
          #
          #   musiccast/provider.py:25
          #     from music_assistant.providers.sonos.helpers
          #                                    import get_primary_ip_address
          #   -> imports the sonos PACKAGE, so sonos/__init__.py runs
          #   sonos/__init__.py:17   from .provider import SonosPlayerProvider
          #   sonos/provider.py:14   from aiosonos.api.models import …
          #   -> ModuleNotFoundError: aiosonos
          #
          # A cross-provider import is invisible to the manifest, therefore
          # invisible to the option, therefore invisible to the build.  One
          # helper function — resolving a zeroconf record to an IPv4 address —
          # drags in a second player stack's entire dependency set.
          #
          # AND THE ERROR BLAMES THE WRONG THING.  nixpkgs'
          # `dont-install-deps.patch` turns any ImportError in a provider into
          #
          #     RuntimeError: Configure musiccast in
          #     `services.music-assistant.providers` to install the required
          #     dependencies.
          #
          # which names `musiccast` — already present and correct — and says
          # nothing about `sonos`.  Taken at face value it is unactionable; the
          # traceback above it is the only thing that identifies the real
          # missing module.  See the "default set" note above for the other
          # direction of the same misdirection.
          #
          # FOUND BY RUNNING IT.  The pre-deploy check verified the DECLARED
          # requirement — `import aiomusiccast` succeeds — which is a weaker
          # statement than "the provider imports" and did not catch this.  If a
          # future provider is added here, import the provider MODULE rather
          # than its manifest's requirements:
          #
          #     nixos-container run mass -- sh -c \
          #       'PYTHONPATH=$(systemctl show music-assistant -p Environment \
          #          | tr " " "\n" | grep ^PYTHONPATH= | cut -d= -f2-) \
          #        python3 -c "import music_assistant.providers.<name>"'
          "sonos"
        ];

        # FALSE, and it is not the default by accident — upstream's own default
        # is already false.  Stated because it is the option somebody will
        # reach for when a speaker does not appear: it would open 8097 on EVERY
        # interface in this netns, which is the whole Services VLAN, for a
        # service whose stream URLs are unauthenticated by protocol.  The five
        # explicit rules above are the answer instead.
        openFirewall = false;
      };

      # ── DynamicUser OFF, AND THE SIX PROTECTIONS IT IMPLIED, RESTATED ─────
      #
      # Why it is off is in the header: StateDirectory + DynamicUser MIGRATES
      # /var/lib/music-assistant, and here that is a bind mount.
      #
      # THE HARDENING MUST BE PUT BACK BY HAND.  `DynamicUser = true` silently
      # implies NoNewPrivileges, PrivateTmp, ProtectSystem=strict, ProtectHome,
      # RemoveIPC and RestrictSUIDSGID.  The upstream module sets ProtectHome
      # and RestrictSUIDSGID itself, so the four below are exactly what turning
      # it off would otherwise have dropped — a silent widening of the sandbox
      # that no build error reports.  arr/'s prowlarr and jellyseerr blocks
      # are the working examples of this same restoration.
      #
      # Everything else the module sets survives untouched: an empty
      # CapabilityBoundingSet, DevicePolicy=closed, ProcSubset=pid,
      # ProtectProc=invisible, the Protect* family, RestrictNamespaces,
      # RestrictRealtime, SystemCallFilter and UMask=0077.
      systemd.services.music-assistant.serviceConfig = {
        DynamicUser = lib.mkForce false;
        User = "music-assistant";
        Group = "music-assistant";

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        RemoveIPC = true;

        # StateDirectory= already grants this; naming it keeps the set of
        # writable paths readable in one place, as seerr's block does.
        ReadWritePaths = [configDir];

        # 0700, matching what mass-dirs installs on the host.  Without this
        # systemd's default 0755 and the host-side install(1) take turns
        # winning, one per deploy — the M3 defect, and the same tug-of-war
        # arr/ records for sonarr and prowlarr.
        StateDirectoryMode = "0700";
      };

      # The numeric id is the interface across the nspawn boundary — the host
      # has no `music-assistant` passwd entry, so mass-dirs above installs the
      # directory by number and this is what makes the two agree.
      users.groups.music-assistant = {gid = massGid;};
      users.users.music-assistant = {
        isSystemUser = true;
        uid = massUid;
        group = "music-assistant";
        home = configDir;

        # NOT in any media group, and that is the point of reading the library
        # over HTTP: this account has no handle on /srv/media at all.  The
        # jellyseerr block in arr/ makes the same argument — a service that
        # only speaks REST has no business holding a file descriptor on 47 TB.
      };

      # `curl` is the test plan's instrument for proving this backend is
      # reachable from Traefik and from nowhere else, and for the one-line
      # check that Navidrome answers the Subsonic ping from in here.
      environment.systemPackages = with pkgs; [curl];
      documentation.enable = false;
      documentation.nixos.enable = false;
    };
  };
}
