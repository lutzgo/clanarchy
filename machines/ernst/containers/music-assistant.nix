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
#   THE PROVIDER IS CONFIGURED OUTSIDE THIS FILE.  Music Assistant keeps
#   provider configuration in its own database under ${stateRoot}; there is no
#   declarative option for a URL and a password, and there will not be one.
#   The Navidrome account it authenticates with is a manual step — see
#   docs/roadmap.md M30.
#
#   "OUTSIDE THIS FILE" IS NOT THE SAME AS "IN THE BROWSER", and the difference
#   bit twice: `musiccast` and `subsonic_scrobble` declare no config entries, so
#   their setup dialogs have no fields and the SAVE button can never enable.
#   They have to be written into the settings database directly.  See the note
#   at `providers` below for the exact shape and the procedure.
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
#   THE PLAYERS IN THIS HOUSE ARE TWO YAMAHA MusicCast SPEAKERS ON VLAN 20 —
#   `Küche` at 10.0.20.31 and `Renate` at 10.0.20.32.  No Chromecast, no Sonos,
#   no DLNA renderer, no Snapcast.
#
#   THIS FILE SHIPPED SAYING THERE WAS ONE, and the correction is worth keeping
#   because of where the wrong number came from.  M30 read Home Assistant's
#   `core.config_entries`, found one `yamaha_musiccast` entry, and treated it as
#   an inventory of the segment.  It is an inventory of what the HUB has been
#   configured with.  Browsing `_http._tcp.local.` from the leg itself found
#   both in seconds — see the note at `musiccastAddrs`.
#
# ── AND THE SECOND LEG DOES NOTHING UNTIL ONE SETTING IS CHANGED ────────────
#
#   READ THIS BEFORE DEBUGGING ANY "no players found" REPORT.  Music Assistant's
#   zeroconf binds to the DEFAULT INTERFACE ONLY unless told otherwise, and the
#   option's own description says so:
#
#     "By default, Music Assistant will only listen on the default interface.
#      If you have multiple network interfaces and you want to discover players
#      on all interfaces, you can change this setting to 'All interfaces'."
#         — CONF_ENTRY_ZEROCONF_INTERFACES, constants.py:669
#
#   The default interface here is eth0, on VLAN 90, where there are no speakers.
#   So `iot1` is CARRIED, ADDRESSED, FIREWALLED AND DECORATIVE until
#   Settings -> Core -> Discovery -> "Mdns/Zeroconf discovery interface(s)" is
#   set to **All interfaces** (`core.discovery.values.zeroconf_interfaces =
#   "all"`, advanced-only, `requires_reload`).
#
#   MEASURED BOTH WAYS on 2026-09-27: with the default, the provider loaded and
#   discovered nothing for twenty minutes while both speakers were announcing —
#   confirmed by browsing `_http._tcp.local.` from the hass container's own
#   VLAN-20 leg, which saw both immediately.  With "all", both appeared within a
#   minute of the reload.
#
#   THIS IS THE SILENT FAILURE THIS FILE ALREADY WARNED ABOUT, arriving from a
#   direction the warning did not anticipate.  The note on the firewall rules
#   says an absent accept leaves the leg "decorative while looking correct", and
#   that discovery finding nothing is "indistinguishable from a household with
#   no discoverable devices".  Both were true here with every rule correct: the
#   application simply was not listening on the interface.  It is NOT declarable
#   — it lives in Music Assistant's own settings database like every provider —
#   so it is a deploy step, and it is the FIRST one to check.
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
#           — so its client is a Yamaha speaker, not a browser and not
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
# ── NO forward-auth, AND IT SHIPPED WITH IT ────────────────────────────────
#
#   `music.goclan.org` is in `appApiHosts` (containers/ingress-policy.nix).  It
#   was in `protectedHosts` for one day, and the move is the direction that
#   file's header warns about — so the reason is recorded here too rather than
#   only there.
#
#   THE ARGUMENT FOR THE STRICT DOOR RESTED ON A FALSE PREMISE, and it was this
#   file's premise: that the only client of the hostname is a browser, because
#   Home Assistant reached the container DIRECTLY on 10.0.90.30:8095 and never
#   came through the proxy at all.  The integration does not work that way.
#   From the deployed code, `config_flow.py`:
#
#       login_url = f"{self.url}/login?{params}"
#       return self.async_external_step(step_id="auth", url=login_url)
#
#   `self.url` is the ONE url typed into the config flow, and both halves use
#   it: the browser is redirected to `{url}/login`, and the hub's own
#   server-side calls — `GET {url}/info`, `POST {url}/auth/login` for the
#   long-lived token, and the persistent `{url}/ws` — go to the same address.
#   There is no separate field for an internal one.
#
#   So this hostname has a non-browser client, and `/ws` is an HTTP UPGRADE
#   with no cookie jar: the exact thing that exempts `ha` itself.
#
#   MEASURED, NOT REASONED BACKWARDS.  Pointed at the direct address, the
#   BROWSER half broke instead — it was sent to
#   `http://10.0.90.30:8095/login?…`, which no human's machine may reach, and
#   the external step hung on a blank page.  With the middleware attached there
#   is no single URL that satisfies both halves.
#
#   LAN-ONLY, and that is what keeps the exemption proportionate: this is the
#   ONLY name in `appApiHosts` that is NOT also in `wanExposed`.  Every other
#   entry in that list is a deliberate unauthenticated surface facing the
#   internet; this one faces the living room, has no public A record and takes
#   no ledger row.  The compensations below are defending the house against the
#   house.
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
  # in containers/arr.nix, and nothing in this file's firewall block concerns
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
      #   8095/tcp  from Traefik (.12) and from the service index (.13).
      #
      #             EVERY HUMAN AND THE HUB ALIKE ARRIVE ON .12.  Home Assistant
      #             had a rule of its own here and lost it — see the note where
      #             `hassAddr` used to be: its config flow drives the browser and
      #             its own server-side calls from one url, so it cannot be
      #             pointed at this address, and the accept was a rule nothing
      #             used.
      #
      #             THE SECOND IS THE SERVICE INDEX, for a `siteMonitor` and
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
        iptables -A nixos-fw -p tcp -s ${traefikAddr}/32 --dport ${toString massPort} -j nixos-fw-accept
        iptables -A nixos-fw -p tcp -s ${dashboardAddr}/32 --dport ${toString massPort} -j nixos-fw-accept
      '' + lib.concatMapStrings (addr: ''
        iptables -A nixos-fw -p tcp -s ${addr}/32 --dport ${toString streamPort} -j nixos-fw-accept
      '') musiccastAddrs + ''
        iptables -A nixos-fw -i ${iotVeth} -p udp --dport 5353 -j nixos-fw-accept
      '' + lib.concatMapStrings (addr: ''
        iptables -A nixos-fw -i ${iotVeth} -p udp -s ${addr}/32 --dport ${toString ephemeralLow}:${toString ephemeralHigh} -j nixos-fw-accept
      '') musiccastAddrs + ''
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
