# machines/ernst/containers/music-assistant.nix
#
# Music Assistant — the household's music player, over the library Navidrome
# already indexes (M30 in docs/roadmap.md).  An nspawn container with TWO legs
# on br0, serving `music.goclan.org` through Traefik behind forward-auth.
#
# ── WHAT THIS IS, AND WHAT IT IS NOT ────────────────────────────────────────
#
#   Navidrome is a LIBRARY SERVER.  It indexes Lidarr's tree, serves the
#   Subsonic API, and every client — Tempo, Symfonium, play:Sub — does the
#   playing itself, on the phone, to whatever that phone is plugged into.
#   Nothing in this house can say "play this album in the living room".
#
#   Music Assistant is the missing half: a player controller.  It holds the
#   queue, resolves a track to a stream, transcodes if the target needs it, and
#   drives the speakers directly.  It does NOT index music — it reads
#   Navidrome over the Subsonic API and treats it as its library.
#
#   SO THIS ADDS NOTHING TO THE MUSIC PIPELINE AND DOES NOT REPLACE ANY OF IT.
#   Lidarr + slskd + Soularr still acquire (M14), Navidrome still indexes and
#   still serves every mobile client on its own hostname (`appApiHosts`, on the
#   WAN).  This container is a consumer of Navidrome, in exactly the sense that
#   containers/karakeep.nix is a consumer of llama-swap.
#
# ── WHY THE nspawn TIER ─────────────────────────────────────────────────────
#
#   `services.music-assistant` is a first-class NixOS module, so architecture
#   invariant #1 puts it here.  The podman tier exists for upstreams that ship
#   only an OCI image (storyteller, cwa, romm, tubesync), and this is not one —
#   despite Music Assistant's own documentation recommending its Docker image
#   and its HAOS add-on.  containers/miniflux.nix and containers/karakeep.nix
#   both made this call at M27 and this file takes the same side.
#
# ── THE LIBRARY: `opensubsonic`, NOT `filesystem_local` ─────────────────────
#
#   Music Assistant would happily read /srv/media/music directly — the
#   `filesystem_local` provider needs no dependencies at all, and it is the
#   obvious-looking answer since the files are on this very host.  It is
#   deliberately NOT done, for two reasons that both matter:
#
#     1. IT WOULD PUT A SECOND INDEX ON THE SAME FILES.  Navidrome's database
#        is not a cache of the library — containers/arr.nix says so at length:
#        it holds play counts, ratings, starred tracks and playlists that exist
#        nowhere else.  A second scanner means two libraries that disagree
#        about what is in them, and the one the phones use is the one that
#        would drift.
#     2. IT WOULD NEED THE MEDIA MOUNT.  `filesystem_local` means binding
#        /srv/media/music into this container and joining gid 3000, which is a
#        handle on 47 TB for a service whose entire job is to fetch bytes over
#        HTTP.  Reading through Navidrome keeps this container with NO bind
#        mount onto the media tree at all — the same trade
#        containers/immich.nix and containers/nextcloud.nix make.
#
#   `subsonic_scrobble` is the return path and is why this arrangement is
#   better than a second index rather than merely cheaper: a play started in
#   Music Assistant is scrobbled back to Navidrome, so the history and the star
#   ratings stay in the one database the mobile clients read.  It declares
#   `depends_on: opensubsonic` and takes no extra dependency.
#
#   THE PROVIDER IS CONFIGURED IN THE UI, NOT HERE.  Music Assistant keeps
#   provider configuration in its own database under ${stateRoot}; there is no
#   declarative option for a URL and a password, and there will not be one.
#   The Navidrome account it authenticates with is a manual step — see
#   docs/roadmap.md M30.
#
# ── TWO LEGS, AND THE SECOND ONE IS THE WHOLE POINT ─────────────────────────
#
#   eth0  VLAN 90 (Services)  — Traefik reaches the web UI here, Home
#                               Assistant reaches the WebSocket API here, and
#                               Navidrome is one L2 hop away on .13.
#   iot1  VLAN 20 (IoT)       — the segment the household's speakers are on.
#                               This leg exists for DISCOVERY, and it is not
#                               optional.
#
#   THE ONE PLAYER IN THIS HOUSE IS A YAMAHA MusicCast RECEIVER AT 10.0.20.31,
#   read out of Home Assistant's own config entries rather than assumed
#   (`yamaha_musiccast`, `.storage/core.config_entries`).  No Chromecast, no
#   Sonos, no DLNA renderer, no Snapcast.
#
#   And Music Assistant's `musiccast` provider is DISCOVERY-ONLY.  Its manifest
#   declares `"mdns_discovery": ["_http._tcp.local."]` and provider.py has
#   exactly one entry point, `on_mdns_service_state_change`; there is no
#   add-by-address config flow to fall back on.  (`check_yamaha_ssdp` runs
#   afterwards and is a UNICAST HTTP GET of the device description, not
#   multicast — which is why this file opens 5353/udp and, unlike
#   containers/home-assistant.nix, does NOT open 1900/udp.)
#
#   mDNS is link-local by definition, and this repo has refused to relay it
#   across a firewall boundary twice in writing — M8's session prompt and note
#   3 of machines/ernst/networking.nix.  containers/home-assistant.nix answered
#   that with a second veth onto the segment its devices are on; this file
#   answers it the same way, for the same reason, one VLAN later.
#
#   Unicast to VLAN 20 needs no leg at all: the UDM-Pro has LAN, IoT, HA, DNS,
#   Servers and Matter in one `Internal` zone with `Internal -> Internal: Allow
#   All`.  What is not routable is the discovery, and that is all this leg is
#   for.
#
# ── THE VETH IS `iot1`, AND THAT IS THE M29 OUTAGE NOT REPEATED ─────────────
#
#   `extraVeths.<name>` becomes nspawn's `--network-veth-extra=<name>`, which
#   names BOTH ends, so the name lands in the HOST's one flat interface
#   namespace.  M19 named Open WebUI's leg `ai0`, M27 gave karakeep the same
#   name, and Open WebUI silently had no second interface for five days.
#
#   `iot0` is taken, by containers/home-assistant.nix.  Hence `iot1`.  The
#   assertion at the top of machines/ernst/networking.nix is what checks this
#   rather than the comment — it groups every container's `extraVeths` and
#   fails evaluation on a collision.
#
# ── THE STREAM SERVER IS A SECOND LISTENER, ON A SECOND PORT ────────────────
#
#   Music Assistant runs TWO HTTP servers, and conflating them is how the
#   firewall ends up wrong:
#
#     8095  the API and the web UI.  A WebSocket-driven SPA; the Home
#           Assistant integration speaks the same WebSocket.
#     8097  the STREAM server, deliberately separate from the API
#           (controllers/streams/README.md).  This is the URL a PLAYER fetches
#           — so its client is the Yamaha receiver, not a browser and not
#           Traefik.
#
#   Both are Python constants (`DEFAULT_PORT`), settable only in Music
#   Assistant's own settings database.  Change either in the UI and the rules
#   below stop matching, silently.
#
# ── AND THE RECEIVER TALKS BACK ON AN EPHEMERAL UDP PORT ────────────────────
#
#   aiomusiccast does not poll.  It opens a UDP socket on ("0.0.0.0", 0) — an
#   EPHEMERAL port, chosen by the kernel — and hands the number to the receiver
#   in an `X-AppPort` header; the receiver then pushes status events there,
#   roughly every second while playing (pyamaha.py:186-199).
#
#   There is no fixed port to open, and conntrack does not help: the events are
#   unsolicited from the kernel's point of view, since the HTTP request that
#   registered the port was a different socket on a different protocol.  So the
#   rule below is narrow in SOURCE (the one receiver) and wide in PORT (the
#   local ephemeral range).  That asymmetry is stated rather than hidden.
#
#   WITHOUT IT the failure is not "no player": the receiver is discovered, it
#   plays, and the UI simply never updates — volume, position and track
#   changes made at the receiver are invisible.  Which reads as a Music
#   Assistant bug.
#
# ── forward-auth, UNLIKE Home Assistant AND UNLIKE Navidrome ────────────────
#
#   `music.goclan.org` is in `protectedHosts` (containers/ingress-policy.nix),
#   and that is worth saying explicitly because the two services it sits
#   between are both exemptions.
#
#   The test that file states is whether every client can render a login page
#   and follow a 302.  Here every client can: the only one is a browser.
#   Navidrome's exemption is the Subsonic protocol, which carries its token in
#   a query parameter; Home Assistant's is the companion app holding a bearer
#   token over a WebSocket with no browser anywhere in it.  Neither argument
#   transfers.
#
#   THIS UI IS ALSO WEBSOCKET-DRIVEN, AND THAT IS NOT THE SAME PROBLEM.  Home
#   Assistant's exemption turns on a NATIVE app opening the upgrade with no
#   cookie jar; here the upgrade is issued by the same browser that just
#   authenticated to Authelia, so it carries the session cookie and
#   forward-auth authorises it like any other request.
#
#   LAN-ONLY.  The router names `websecure` and nothing else: it is NOT in
#   `wanExposed`, there is no public A record, and there is no ledger row —
#   Navidrome is already on the WAN and is what a phone off the property should
#   be talking to.  Music Assistant drives speakers that are, by construction,
#   in the house.
#
# ── IT HAS ITS OWN ACCOUNTS, AND THAT WAS CHECKED RATHER THAN ASSUMED ───────
#
#   The reflex assumption about a self-hosted media controller is that it has no
#   authentication at all and the reverse proxy is the entire boundary.  That is
#   FALSE at 2.8.7 and the difference matters for what this file has to do, so it
#   was read out of the source rather than guessed:
#
#     * a users table with roles (`UserRole.ADMIN`) and a per-user
#       `player_filter`, so a household account can be scoped to some speakers;
#     * `auth_middleware` on every route, with a short bypass list —
#       /info, /login, /setup, /auth/, /assets/, /favicon.ico, /manifest.json,
#       /index.html and / — and `require_authentication()` in the handlers;
#     * the WebSocket at /ws tracks an authenticated user per connection and
#       refuses admin commands to a non-ADMIN role;
#     * `LoginRateLimiter`, an ESCALATING PER-USERNAME backoff over a 30-minute
#       window: 3-5 failures 30 s, 6-9 60 s, 10-14 120 s, 15+ 300 s.
#
#   So the posture here is belt-and-braces rather than proxy-only, and the
#   backoff is Nextcloud's per-ACCOUNT shape, not Home Assistant's per-SOURCE
#   `ip_ban`.  Do not read either as describing this one.
#
#   THE FIRST-RUN WINDOW CLOSES ITSELF, which is the one real difference from
#   Komga, Navidrome and CWA.  `/setup` creates the first admin and is
#   unauthenticated by construction — but `_handle_setup` returns 400 "Setup
#   already completed" once `auth.has_users`, so the window is not open
#   indefinitely waiting for somebody to notice.  It is still a deploy step and
#   not a matter of taste: until that account exists, anybody who can reach this
#   vhost can create it.  On the LAN, behind forward-auth, that is a much
#   narrower window than the one docs/roadmap.md warns about for the WAN names —
#   which is exactly why this service is not one of them.
#
# ── THE HOME ASSISTANT INTEGRATION IS ALREADY OFFERABLE ─────────────────────
#
#   Nothing is added to containers/home-assistant.nix for this.
#   `music_assistant` is a packaged component in this channel
#   (component-packages.nix -> music-assistant-client), and since PR #229 that
#   file's `extraComponents` ends with `++ buildableComponents` — every
#   packaged integration, not a curated dozen.  So the hub can already offer
#   it.
#
#   IT WILL NOT AUTO-DISCOVER, and that is correct rather than broken.  Music
#   Assistant advertises `_mass._tcp.local.`, but the hub's own firewall
#   accepts 5353/udp on `iot0` ONLY — VLAN 20, where the devices are — so
#   nothing on VLAN 90 is heard in either direction.  Opening mDNS between the
#   two containers to save one text field would put both services' multicast on
#   the Services VLAN for no capability.  The config flow takes the URL by
#   hand; see docs/roadmap.md M30.
#
# ── THE CONTAINER IS CALLED `mass`, NOT `music-assistant` ───────────────────
#
#   The same constraint containers/home-assistant.nix hit: nspawn's
#   --network-bridge names the host side of the veth `vb-<container>`, and a
#   Linux interface name caps at 15 characters (IFNAMSIZ - 1).
#   `vb-music-assistant` is 18 and the link cannot be created at all — a
#   failure at container START, not at evaluation, so a clean `nix build`
#   proves nothing.
#
#   `mass` is upstream's own abbreviation (the service advertises `_mass._tcp`
#   and its config lives under a `mass` namespace), so this is not an invented
#   nickname.  `vb-mass` is 7.
#
#   So: the FILE is music-assistant.nix, the SERVICE is
#   music-assistant.service inside, and the MACHINE is `mass` —
#   `machinectl`, `nixos-container run mass`, `systemctl restart container@mass`.
#
# ── DynamicUser IS TURNED OFF, AND THE STATE DIRECTORY IS WHY ───────────────
#
#   Upstream runs this under `DynamicUser = true` with
#   `StateDirectory = "music-assistant"`.  That combination MIGRATES the state
#   directory — systemd renames /var/lib/music-assistant to
#   /var/lib/private/music-assistant on first start — and here that path is a
#   BIND MOUNT.  containers/crowdsec.nix measured exactly this, quoting
#   systemd's own log line, and service-modules/local-ai.nix hit it with
#   ollama before that.  Same call, same reason, third time.
#
#   The deeper version of the same argument is in machines/ernst/networking.nix
#   under the uid table: ids pass through the nspawn boundary UNMAPPED onto
#   zdata, so a systemd-ALLOCATED uid owning files on the pool is precisely
#   what that table exists to prevent.  Keeping state and keeping a per-boot
#   identity are mutually exclusive, and M29b already wrote that down for
#   mneme.
#
#   So: uid/gid 3040, and the six protections `DynamicUser` had been implying
#   are restated below — arr.nix's prowlarr and jellyseerr blocks are the
#   working examples.
#
# ── WHAT IS DELIBERATELY NOT DONE ───────────────────────────────────────────
#
#   NO PROMETHEUS JOB.  Music Assistant exposes no metrics endpoint of any
#   kind — SN3, stated rather than omitted.  What DOES cover it is the
#   container-unit collector: `exporters.containers` walks `machinectl list` on
#   a one-minute timer, so `music-assistant.service` failing inside here raises
#   `ContainerSystemdUnitFailed` with no per-container configuration at all.
#   That mechanism exists because soularr.service failed 1,412 times in the arr
#   container without alerting (PR #139).
#
#   NO SPOTIFY, NO TIDAL, NO QOBUZ, NO YouTube MUSIC.  `providers` below is the
#   list of optional dependency sets to install, and each one is a package
#   closure for a service this household does not subscribe to.  ytmusic would
#   additionally pull in `deno` and require `@pkey` in the syscall filter.
#   Adding one is one word here plus a UI setup; adding all of them is a
#   rebuild for nothing.
#
#   NO SNAPCAST, NO AIRPLAY, NO CHROMECAST — same reasoning, measured rather
#   than assumed: there is no such device in Home Assistant's registry.  Note
#   that `airplay` in particular would want an inbound UDP range of
#   32768-65535 (upstream's own `openFirewall`), which is not a thing to carry
#   speculatively.
#
#   NO SECOND DATASET.  A SQLite database and a tree of small JSON blobs is
#   `zdata/state`'s write profile exactly — 128K recordsize, the default —
#   which is the call containers/home-assistant.nix, containers/miniflux.nix
#   and containers/karakeep.nix all made before this one.
#   docs/guides/ernst-zdata-datasets.md splits by write profile, not by
#   service.
{ config, pkgs, lib, ... }:

let
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

  # Home Assistant (M24).  Its `music_assistant` integration holds a WebSocket
  # open against 8095 for the life of the session — the same shape the
  # companion app holds against the hub itself.
  hassAddr = "10.0.90.27";

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
  # in containers/arr.nix, and nothing in this file's firewall block concerns
  # it.  A reader looking for the Navidrome wiring should look there.

  # The Yamaha MusicCast receiver, on the IoT VLAN.  Read out of Home
  # Assistant's config entries, not guessed.  It is the one PLAYER in the
  # house, and the only source that needs the two rules on the iot1 leg.
  musiccastAddr = "10.0.20.31";

  # 8095 — the API and web UI.  8097 — the stream server the PLAYER fetches.
  # Both are Python constants in the application, not NixOS options; see the
  # header.
  massPort   = 8095;
  streamPort = 8097;

  # The local ephemeral range, which is what aiomusiccast's event socket binds
  # into.  Matches ernst's `net.ipv4.ip_local_port_range` default — restate it
  # here rather than reading the sysctl, because the rule has to be a literal
  # in the iptables invocation either way and a silent mismatch would look like
  # a flaky receiver.
  ephemeralLow  = 32768;
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
in
{
  ##############################################################################
  # Host side — the state directory and the two veths.
  ##############################################################################

  # ── NO tmpfiles RULES, AND containers/immich.nix IS WHY ───────────────────
  #
  # That file records the measured failure: activating a new configuration does
  # not re-run systemd-tmpfiles-setup.service in time for a container the same
  # activation starts, and immich died five times into its start limit.  The
  # one host-side directory this container binds belongs to the ordered unit
  # below, and is not also a tmpfiles rule.
  systemd.services.mass-dirs = {
    description = "Verify /srv/state is mounted and create Music Assistant's directory";
    wantedBy   = [ "multi-user.target" ];
    after      = [ "srv-state.mount" ];
    requires   = [ "srv-state.mount" ];
    before     = [ "container@mass.service" ];
    requiredBy = [ "container@mass.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.util-linux pkgs.coreutils ];

    # BLOCKING (`requires` + `requiredBy`) rather than advisory, and the
    # consequence here is milder than Home Assistant's but the same shape: a
    # Music Assistant that starts without its state is a NEW one on zroot, with
    # no library provider, no players and no queue, which will be rolled back
    # on the next boot while reporting success throughout.  The Navidrome
    # credential would have to be entered again every time.
    script = ''
      set -eu

      # findmnt, not `mountpoint`: this has to check WHAT is mounted.
      #
      # THE TARGET IS THE PARENT, NOT ${stateRoot}.  `findmnt --target` on a
      # path that does not exist yet returns nothing — it does not walk up to
      # the nearest existing ancestor — so checking ${stateRoot} would fail on
      # every first run.  immich-dirs refused its own first deploy that way on
      # 2026-09-11.
      ssrc=$(findmnt --noheadings --output SOURCE --target /srv/state || true)
      if [ "$ssrc" != "zdata/state" ]; then
        echo "mass-dirs: /srv/state is not zdata/state (found '$ssrc')." >&2
        echo "  Refusing to create Music Assistant's state directory, because" >&2
        echo "  it would land on zroot and be rolled back on the next boot —" >&2
        echo "  taking the Navidrome credential and every player with it." >&2
        echo "  See docs/guides/ernst-zdata-datasets.md." >&2
        exit 1
      fi

      # NUMERIC ids on purpose: `music-assistant` is a CONTAINER user and the
      # host has no matching passwd entry.  Same shape traefik.nix uses for
      # uid 3005.
      #
      # 0700 is asked for and 0700 is what systemd's StateDirectory wants too,
      # so unlike Nextcloud's and Immich's directories there is no mode
      # tug-of-war here to lose.
      install -d -o ${toString massUid} -g ${toString massGid} -m 0700 ${stateRoot}
    '';
  };

  # Leg 1 — the host side of eth0, a VLAN-90 port on br0.
  #
  # `KeepMaster`, not `Bridge`: nspawn's --network-bridge creates this veth AND
  # enslaves it, so networkd must be told to keep its hands off the master.
  # machines/ernst/networking.nix has the long form of why a bridge port carries
  # no address of its own.
  systemd.network.networks."60-vb-mass" = {
    matchConfig.Name = "vb-mass";
    networkConfig = {
      KeepMaster          = true;
      LinkLocalAddressing = "no";
      IPv6AcceptRA        = false;
    };
    bridgeVLANs = [ { VLAN = 90; PVID = 90; EgressUntagged = 90; } ];
    linkConfig.RequiredForOnline = "enslaved";
  };

  # Leg 2 — the host side of iot1, a VLAN-20 port on br0.
  #
  # `Bridge = "br0"`, NOT `KeepMaster`, and the difference is not cosmetic:
  # --network-veth-extra creates the pair and enslaves NOTHING, so here
  # networkd owns the enslavement and nothing competes for it.  This is
  # machines/ernst/networking.nix's Pattern A, the same shape
  # containers/home-assistant.nix uses for iot0 and containers/tvheadend.nix
  # for fritz0.
  #
  # NOTE THE NAME.  --network-veth-extra names BOTH ends identically, so this
  # matches the plain `iot1` and not `vb-iot1`.
  systemd.network.networks."60-${iotVeth}" = {
    matchConfig.Name = iotVeth;
    networkConfig = {
      Bridge              = "br0";
      LinkLocalAddressing = "no";
      IPv6AcceptRA        = false;
    };
    bridgeVLANs = [ { VLAN = 20; PVID = 20; EgressUntagged = 20; } ];
    # A bridge port's terminal state is "enslaved"; it never becomes routable.
    linkConfig.RequiredForOnline = "enslaved";
  };

  # Same VLAN race, same idempotent backstop, same "-" prefix as every other
  # nspawn container on br0: networkd applies [BridgeVLAN] only once it observes
  # the link's master, and nspawn sets that master out of band.  With
  # DefaultPVID = "none" on br0 a miss is fail-CLOSED — the port is dead rather
  # than silently joining VLAN 50.
  #
  # `bridge vlan show dev vb-mass` and `bridge vlan show dev iot1` are the
  # checks.
  systemd.services."container@mass".serviceConfig.ExecStartPost = [
    "-${pkgs.iproute2}/bin/bridge vlan add dev vb-mass vid 90 pvid untagged"
    "-${pkgs.iproute2}/bin/bridge vlan add dev ${iotVeth} vid 20 pvid untagged"
  ];

  # Avahi must not discover the IoT segment through this veth.  The host side
  # holds no address, so avahi has nothing to bind and would skip it anyway —
  # but containers/home-assistant.nix and containers/tvheadend.nix both state
  # the exclusion rather than relying on that accident, and during M8's Phase 0
  # the accident did not hold: a briefly-addressed interface had ernst's mDNS on
  # a foreign segment within seconds.  modules/networking/mdns.nix runs the
  # reflector with no interface pinning, which is what makes this worth stating.
  services.avahi.denyInterfaces = [ iotVeth ];

  ##############################################################################
  # The container.
  ##############################################################################
  containers.mass = {
    autoStart = true;
    ephemeral = false;

    # Leg 1 — eth0 on br0 / VLAN 90.  MAC from the allocation table in
    # machines/ernst/networking.nix; the DHCP reservation 10.0.90.30 on the
    # UDM-Pro keys on it (manual step).  Sequence 16, and the last octet is
    # 8 + seq as everywhere else on this bridge.
    privateNetwork  = true;
    hostBridge      = "br0";
    localMacAddress = "02:00:00:90:00:16";

    # Leg 2 — iot1 on br0 / VLAN 20.
    #
    # NO ADDRESS AND NO MAC HERE.  `extraVeths` has no MAC option at all, and
    # `localAddress` would be applied by container-init before networkd starts
    # and then fight it over the same interface — containers/tvheadend.nix
    # records that.  Both are set by the container's own networkd, below.
    extraVeths.${iotVeth} = { };

    bindMounts = {
      # The state tree, bound at the module's OWN default so `configDir`, the
      # `--config` argument and the StateDirectory all agree with nothing
      # overridden.
      "${configDir}" = {
        hostPath   = stateRoot;
        isReadOnly = false;
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
        LLMNR        = "no";
      };

      # eth0 — VLAN 90.  The same block as every sibling container: DHCP
      # against the UDM-Pro reservation, resolver declared rather than
      # inherited.
      systemd.network.networks."10-eth0" = {
        matchConfig.Name = "eth0";
        networkConfig = {
          DHCP         = "ipv4";
          DNS          = "10.0.5.3";
          Domains      = "~. skynet.lan";
          IPv6AcceptRA = false;
          # SN2: v4 only.  M18 measured that IPv6AcceptRA alone blocks an RA
          # but NOT link-local assignment; this is the line that actually makes
          # `ip -6 addr show dev eth0` empty.
          LinkLocalAddressing = "no";
        };
        dhcpV4Config = {
          UseDNS     = false;
          UseDomains = false;
        };
        linkConfig.RequiredForOnline = "routable";
      };

      # iot1 — VLAN 20, the discovery leg.
      systemd.network.networks."20-${iotVeth}" = {
        matchConfig.Name = iotVeth;
        networkConfig = {
          DHCP                = "ipv4";
          IPv6AcceptRA        = false;
          LinkLocalAddressing = "no";
        };

        # ── UseGateway = false IS LOAD-BEARING ────────────────────────────
        #
        # Both legs take DHCP and both DHCP servers hand out a default route.
        # Without this the container ends up with TWO `default via` entries and
        # its path off-segment is decided by whichever lease was applied last —
        # a coin toss on every boot, and one that changes which VLAN this
        # container's outbound traffic (provider metadata, MusicBrainz, cover
        # art) is seen leaving on.  containers/home-assistant.nix states the
        # same thing for iot0.
        #
        # UseRoutes = false for the same reason one level down: a classless
        # static route option on VLAN 20 would install routes here that belong
        # to the other leg's routing decision.  VLAN 20 is ON-LINK for this
        # interface, and on-link is the whole job.
        #
        # DNS stays on eth0's Technitium, so UseDNS/UseDomains are off for the
        # same non-negotiable reason they are off there: an IoT VLAN's DHCP
        # server is not this container's resolver.
        dhcpV4Config = {
          UseDNS     = false;
          UseDomains = false;
          UseGateway = false;
          UseRoutes  = false;
        };

        # THE MAC IS PINNED HERE because `extraVeths` has no option for it and
        # the UDM-Pro reservation has to key on a value this repo chose rather
        # than on whatever nspawn derives from the machine name.  Second entry
        # in the VLAN 20 allocation table in machines/ernst/networking.nix.
        linkConfig = {
          MACAddress = "02:00:00:20:00:02";
          # NOT "routable".  A DHCP problem on the IoT VLAN must leave a
          # RUNNING container with one failed unit and a working web UI — the
          # library and the browser player do not need this leg — not a
          # host-side restart loop because a lease did not arrive.
          RequiredForOnline = "no";
        };
      };

      # Same 20 s cap as every sibling: a DHCP failure must leave a RUNNING
      # container with one failed unit, not a host-side restart loop.
      systemd.network.wait-online.timeout = 20;

      # ── The container firewall — the only enforcement point for br0-local
      #    traffic, since those frames are one L2 hop and the UDM-Pro never
      #    sees them.
      #
      #   8095/tcp  from Traefik (.12), from Home Assistant (.27) and from the
      #             service index (.13).
      #
      #             THE SECOND SOURCE IS THE HUB, not a human.  The
      #             `music_assistant` integration opens a WebSocket to
      #             /ws and holds it, which is what puts Music Assistant's
      #             players and queues into Home Assistant as entities and what
      #             makes them usable from Assist.  It does NOT go through
      #             Traefik: forward-auth is on that path, and the integration
      #             has no cookie jar — which is the same reason the hub itself
      #             is an `appApiHosts` name.  A direct L2 hop avoids the
      #             question entirely.
      #
      #             THE THIRD IS THE SERVICE INDEX, for a `siteMonitor` and
      #             nothing more.  It reaches `/`, which is on the application's
      #             own auth bypass list, so this line buys an up/down dot and
      #             grants no control — see `dashboardAddr` in the let block.
      #
      #   8097/tcp  from the Yamaha receiver ONLY.  This is the stream URL a
      #             PLAYER fetches, so its client is a speaker.
      #
      #             NO `-i` HERE, DELIBERATELY, unlike the rule below.  Which
      #             leg this arrives on depends on which address Music
      #             Assistant published in the URL — and it picks
      #             `ip_addresses[0]` from its own interfaces, which is
      #             non-deterministic on a multi-homed host (upstream's own test
      #             patch in nixpkgs works around exactly that indexing).  A
      #             source-matched rule with no interface is correct for both
      #             answers: same-segment via iot1, or routed to VLAN 90 via the
      #             UDM-Pro.  The published address can be pinned in the UI and
      #             SHOULD be — see docs/roadmap.md M30 — but the firewall must
      #             not depend on somebody having done it.
      #
      #   5353/udp  mDNS, ON iot1 ONLY.  The reason the leg exists.
      #
      #             `-i iot1` rather than `-s <addr>/32`, and that difference is
      #             deliberate: the source is a multicast group (224.0.0.251)
      #             and every device on the segment, so there is no address to
      #             name.  The INTERFACE is the restriction — nothing on VLAN 90
      #             gains a port from this line.
      #
      #             NO 1900/udp, unlike containers/home-assistant.nix.  The
      #             `musiccast` provider discovers over mDNS and then confirms
      #             with a UNICAST HTTP GET of the device description
      #             (`check_yamaha_ssdp`), so nothing here listens for SSDP
      #             NOTIFY.  Add it only alongside a provider that needs it —
      #             `dlna` would.
      #
      #   ephemeral udp  from the Yamaha receiver ONLY, on iot1.  Its status
      #             events.  See the header: aiomusiccast binds ("0.0.0.0", 0)
      #             and advertises the port in `X-AppPort`, so there is no fixed
      #             number to open.  Narrow in source, wide in port, and that
      #             asymmetry is the honest shape of this requirement.
      #
      # THE DISCOVERY AND EVENT RULES ARE WHAT MAKE THE SECOND LEG REAL.  Both
      # protocols work by this side LISTENING, so without an inbound accept the
      # provider sends queries and hears nothing — and the leg is decorative
      # while looking correct.  That failure is silent: discovery finds no
      # speakers, which is indistinguishable from a household with none.
      #
      # extraCommands, not extraInputRules: the latter is declared
      # unconditionally but consumed only under networking.nftables, so here it
      # would produce no rule and no warning.  containers/traefik.nix is the
      # only nftables container on this machine.
      networking.firewall.allowedTCPPorts = [ ];
      networking.firewall.extraCommands = ''
        iptables -A nixos-fw -p tcp -s ${traefikAddr}/32   --dport ${toString massPort} -j nixos-fw-accept
        iptables -A nixos-fw -p tcp -s ${hassAddr}/32      --dport ${toString massPort} -j nixos-fw-accept
        iptables -A nixos-fw -p tcp -s ${dashboardAddr}/32 --dport ${toString massPort} -j nixos-fw-accept
        iptables -A nixos-fw -p tcp -s ${musiccastAddr}/32 --dport ${toString streamPort} -j nixos-fw-accept
        iptables -A nixos-fw -i ${iotVeth} -p udp --dport 5353 -j nixos-fw-accept
        iptables -A nixos-fw -i ${iotVeth} -p udp -s ${musiccastAddr}/32 --dport ${toString ephemeralLow}:${toString ephemeralHigh} -j nixos-fw-accept
      '';

      ##########################################################################
      # The service.
      ##########################################################################
      services.music-assistant = {
        enable = true;

        # ── `providers` IS A DEPENDENCY LIST, NOT A CONFIGURATION ───────────
        #
        # It selects which optional Python closures get installed; the provider
        # itself is still added and configured in Music Assistant's UI, and its
        # settings live in the database under ${configDir}.  So a name here is
        # necessary and not sufficient — and a name MISSING here presents as a
        # provider that appears in the list and then fails to set up.
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

          # THE PLAYER.  The Yamaha receiver at ${musiccastAddr}, which is the
          # only playback target in this house that is not a browser tab.
          # Pulls in aiomusiccast.  DISCOVERY-ONLY — there is no add-by-address
          # flow, which is the entire reason this container has a second leg.
          "musiccast"
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
      # that no build error reports.  arr.nix's prowlarr and jellyseerr blocks
      # are the working examples of this same restoration.
      #
      # Everything else the module sets survives untouched: an empty
      # CapabilityBoundingSet, DevicePolicy=closed, ProcSubset=pid,
      # ProtectProc=invisible, the Protect* family, RestrictNamespaces,
      # RestrictRealtime, SystemCallFilter and UMask=0077.
      systemd.services.music-assistant.serviceConfig = {
        DynamicUser = lib.mkForce false;
        User        = "music-assistant";
        Group       = "music-assistant";

        NoNewPrivileges = true;
        PrivateTmp      = true;
        ProtectSystem   = "strict";
        RemoveIPC       = true;

        # StateDirectory= already grants this; naming it keeps the set of
        # writable paths readable in one place, as seerr's block does.
        ReadWritePaths = [ configDir ];

        # 0700, matching what mass-dirs installs on the host.  Without this
        # systemd's default 0755 and the host-side install(1) take turns
        # winning, one per deploy — the M3 defect, and the same tug-of-war
        # arr.nix records for sonarr and prowlarr.
        StateDirectoryMode = "0700";
      };

      # The numeric id is the interface across the nspawn boundary — the host
      # has no `music-assistant` passwd entry, so mass-dirs above installs the
      # directory by number and this is what makes the two agree.
      users.groups.music-assistant = { gid = massGid; };
      users.users.music-assistant = {
        isSystemUser = true;
        uid          = massUid;
        group        = "music-assistant";
        home         = configDir;

        # NOT in any media group, and that is the point of reading the library
        # over HTTP: this account has no handle on /srv/media at all.  The
        # jellyseerr block in arr.nix makes the same argument — a service that
        # only speaks REST has no business holding a file descriptor on 47 TB.
      };

      # `curl` is the test plan's instrument for proving this backend is
      # reachable from Traefik and from nowhere else, and for the one-line
      # check that Navidrome answers the Subsonic ping from in here.
      environment.systemPackages = with pkgs; [ curl ];
      documentation.enable       = false;
      documentation.nixos.enable = false;
    };
  };
}
