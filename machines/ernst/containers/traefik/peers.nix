# The addresses, ports, names and numeric ids containers/traefik.nix's files
# share.
#
# ── WHY THIS IS A PLAIN FILE AND NOT A MODULE ───────────────────────────────
#
# It is data.  `import ./traefik/peers.nix` gives every sibling the same
# attrset with no option plumbing, no `config` read, and therefore no way to
# introduce the recursion an option default reading `config` would.  The same
# shape — and the same reason — as machines/ernst/containers/arr/ids.nix and
# machines/ernst/allocations.nix.
#
# ── THESE ARE RESTATED, AND THAT IS STILL NOT FINISHED ──────────────────────
#
# arr/ids.nix, containers/homepage.nix and service-modules/monitoring.nix each
# hold their own copy of these port numbers.  Lifting them into
# machines/ernst/allocations.nix while three other files keep their copies
# would create a second source of truth with nothing asserting the two agree,
# which is worse than either end state.  That consolidation wants its own
# change, where all four consumers move together and a check holds them equal.
rec {
  ############################################################################
  # Identity.
  ############################################################################
  # Guest-side MAC — 02:00:00:<vlan>:00:<seq>, RESERVED for this container by
  # M2b in machines/ernst/allocations.nix.  This is the
  # address the UDM-Pro sees and the one the DHCP reservation keys on; never
  # the host-side vb-traefik.
  traefikMac = "02:00:00:90:00:04";

  # Numeric ids, continuing the 3000-range family that containers/arr/ and
  # microvms/wg-qbittorrent.nix established.  nspawn passes uids and gids
  # through unmapped, so an id chosen in here is an id on zdata — and
  # /srv/state/traefik is on zdata.  Add a row to
  # machines/ernst/allocations.nix for any new one.
  #
  # NOT in group media, and it never should be.  A reverse proxy has no
  # business holding a handle to the library; it moves bytes between two
  # sockets.
  traefikUid = 3005;
  traefikGid = 3005;

  ############################################################################
  # Names and addresses.
  ############################################################################

  # The public zone, rented on Cloudflare.  ONE wildcard covers every service
  # name below, which is why adding a route later needs no certificate work at
  # all — only a Technitium record and a block in the dynamic config.
  baseDomain = "goclan.org";

  # ACME account contact.  Let's Encrypt uses it for expiry warnings, which are
  # the backstop for a renewal that silently stopped working.  No longer the
  # ONLY backstop: M6 scrapes the metrics entryPoint below and raises
  # CertificateExpiringSoon at 14 days, which is two failed renewals in.  Kept
  # anyway — an email from the CA arrives even when the monitoring container is
  # the thing that is down.  Already public: it is the author address on every
  # commit in this repo.
  acmeEmail = "lutz0go@gmail.com";

  # Backends, by the addresses their DHCP reservations pin.  These are PEER
  # addresses, and hard-coding them here is the deliberate opposite of the rule
  # each container follows for its OWN address.
  #
  # The reason the rule inverts: a container declaring its own address creates
  # a second source of truth that DIVERGES SILENTLY from the UDM-Pro's pool.  A
  # proxy naming a peer cannot diverge quietly — if a reservation moves, every
  # route to it returns 502 immediately and loudly.  Traefik has to learn the
  # address from somewhere, and there is no service discovery here to learn it
  # from.
  jellyfinAddr = "10.0.90.10";
  arrAddr = "10.0.90.13";

  # M6.  The monitoring container: Grafana's backend, and the one host on
  # VLAN 90 permitted to read this container's metrics endpoint.
  monitoringAddr = "10.0.90.14";

  # M7.  Authelia.  Two roles in one address: the identity provider this proxy
  # ASKS about every admin request (the forwardAuth middleware below), and the
  # login portal it SERVES at auth.<domain> like any other backend.
  autheliaAddr = "10.0.90.15";

  jellyfinPort = 8096;
  prowlarrPort = 9696;
  sonarrPort = 8989;
  radarrPort = 7878;
  grafanaPort = 3000;
  autheliaPort = 9091;

  # M12.  Three more backends in the SAME arr container, on arrAddr — no new
  # address, no new MAC, no DHCP reservation, no UDM-Pro rule.
  #
  # These three and only these three.  M12 also adds UmlautAdaptarr (5005 and
  # a proxy on 5006) and MediathekArr's Newznab indexer (5008), and neither
  # gets a route: their only client is Prowlarr, in the same netns, over
  # 127.0.0.1.  containers/arr/ keeps them off its firewall list for the
  # same reason, and 5006 in particular is an HTTP proxy that has no business
  # being reachable.
  bazarrPort = 6767;
  cleanuparrPort = 11011;
  mediathekarrPort = 5007; # the downloader's SABnzbd API and setup wizard
  jellyseerrPort = 5055; # M13 — the household's request UI

  # M26.  The service index, and a backend on `arrAddr` for a reason unlike
  # M12's: those three were services that happened to be installed in that
  # container, while this one is there BECAUSE that is where the *arr API keys
  # it renders are staged.  containers/homepage.nix argues it at length and
  # co-defines containers.arr the way containers/crowdsec.nix co-defines this
  # one — so `arr/` is not the whole of what listens on this address.
  #
  # 8082 collides by NUMBER with the metrics entryPoint below and by nothing
  # else: that listener is in THIS container's namespace, this one is in the
  # arr container's, and no socket is shared between them.
  homepagePort = 8082;

  # M8.  Tvheadend, in its OWN container (nspawn, vb-tvheadend, VLAN 90) — it
  # needed a second network leg to the FRITZ!Box, which the arr container has
  # no business having.  Only the web UI routes through here; Jellyfin pulls
  # the M3U/XMLTV and the streams directly at L2 (10.0.90.10 → .18:9981,
  # allowed by the tvheadend container's own firewall), and HTSP (9982) is
  # routed nowhere and opened to nobody.
  tvheadendAddr = "10.0.90.18";
  tvheadendPort = 9981;

  # M9.  TubeSync, the first occupant of the PODMAN tier, on its own address.
  # Not in the arr container: it is a podman workload whose network namespace
  # is built by hand (see containers/tubesync.nix), which has nothing to do
  # with how the arr container is put together.
  tubesyncAddr = "10.0.90.19";
  tubesyncPort = 4848;

  # ── M14 ───────────────────────────────────────────────────────────────────
  #
  # FOUR more ports on the arr container's ONE address, and one new address.
  # The split is the milestone's whole placement story in two lines: everything
  # that is just another NixOS unit went into the existing container and needed
  # no network work at all; the one thing that is an opaque image took the
  # podman tier and therefore its own netns, MAC and DHCP reservation.
  #
  # Ports verified against upstream on 2026-08-28 — and audiobookshelf's is the
  # one docs/history.md got wrong: nixpkgs' module defaults to 8000, while
  # 13378 is the Docker image's number and what every client expects.
  # containers/arr/ sets it explicitly for that reason.
  lidarrPort = 8686;
  kapowarrPort = 5656;
  questarrPort = 5000;
  audiobookshelfPort = 13378;

  # M17 — Bindery, in the arr container.  Verified by RUNNING the binary
  # (2026-08-29): BINDERY_PORT, default 8787, kept.
  binderyPort = 8787;

  # ── 2026-09-08: two more ports on the arr container's ONE address ─────────
  #
  # Same placement argument M14 made and for the same reason: both are plain
  # NixOS units with upstream modules, so they went into the existing container
  # and needed no network work at all — no new MAC, no DHCP reservation, no
  # UDM-Pro rule.  Only CWA (below) is an opaque image and therefore had to
  # take the podman tier.
  #
  #   komga      25600  set on the far end through `settings.server.port` —
  #                     the top-level `services.komga.port` is a renamed alias
  #                     at this pin and warns at eval.  25600 is Komga's own
  #                     upstream default and what every client's setup doc
  #                     assumes.
  #   navidrome   4533  the module default, and the Subsonic ecosystem's
  #                     conventional port.  Kept rather than moved.
  komgaPort = 25600;
  navidromePort = 4533;

  # Storyteller, the podman tier's SECOND occupant, on its own address.
  # 02:00:00:90:00:0c → 10.0.90.20, following the 8 + <seq> convention in
  # machines/ernst/networking.nix.
  storytellerAddr = "10.0.90.20";
  storytellerPort = 8001;

  # RomM — the ROM library manager on the podman tier (containers/romm.nix).
  # Its netns firewall accepts this address and no other on ${toString rommPort}.
  rommAddr = "10.0.90.22";
  rommPort = 8080;

  # Open WebUI — the local-AI web client (M19), in an NSPAWN container on
  # 02:00:00:90:00:0f → 10.0.90.23, following the 8 + <seq> convention in
  # machines/ernst/networking.nix.  Its container firewall accepts THIS proxy's
  # address and no other on ${toString openWebuiPort}, so a backend-bypass
  # attempt from elsewhere on VLAN 90 — including the qBittorrent microvm one
  # layer-2 hop away — times out rather than reaching the app.
  #
  # It is declared by service-modules/local-ai.nix rather than by a file in
  # this directory, because it is one role of a fleet service module and not a
  # machine-specific container.  The address and port are restated here for the
  # same reason every other backend's are: this file cannot import that one.
  openWebuiAddr = "10.0.90.23";
  openWebuiPort = 8080;

  # Immich (M22) — the household photo library, in an NSPAWN container on
  # 02:00:00:90:00:11 → 10.0.90.25, following the 8 + <seq> convention in
  # machines/ernst/networking.nix.  Its container firewall accepts THIS proxy's
  # address and no other on ${toString immichPort}.
  #
  # THAT RESTRICTION IS TIGHTER THAN IT LOOKS AND IS LOAD-BEARING FOR THE TV.
  # Kodi runs on the ernst host, on VLAN 50, and reaches this service through
  # `photos.goclan.org` — i.e. through here, under M5's existing `Allow
  # Traefik` policy — rather than over a direct VLAN-90 hop.  M8 took the other
  # route for Tvheadend's HTSP and paid for it with a bespoke UDM-Pro policy
  # (ledger L12) that is broader than the flow it permits.  See
  # containers/immich.nix's "THE KODI PATH".
  immichAddr = "10.0.90.25";
  immichPort = 2283;

  # Nextcloud (M23) — the household file-sync / CalDAV / CardDAV server, in an
  # NSPAWN container on 02:00:00:90:00:12 → 10.0.90.26.  Its container firewall
  # accepts THIS proxy's address and no other, on port 80.
  #
  # PORT 80 IS NOT A MISTAKE AND NOT A DOWNGRADE.  The container runs the
  # nixpkgs module's own nginx, which terminates plain HTTP; TLS is terminated
  # once, here, with the *.goclan.org wildcard this file already holds.  The
  # hop from 10.0.90.12 to 10.0.90.26 is one layer-2 frame on br0 inside VLAN
  # 90, which is the same trust boundary every other backend on this list sits
  # behind — jellyfin, komga and the arr suite are all plain HTTP too.
  nextcloudAddr = "10.0.90.26";
  nextcloudPort = 80;

  # Home Assistant (M24) — the household's home-automation hub, in an NSPAWN
  # container on 02:00:00:90:00:13 → 10.0.90.27.  Its container firewall accepts
  # THIS proxy's address and no other on ${toString homeassistantPort}.
  #
  # IT HAS A SECOND LEG THIS PROXY CANNOT SEE AND MUST NOT ROUTE TO.  The
  # container also holds an address on VLAN 20 (`iot0`), so that mDNS and SSDP
  # discovery of the household's wifi devices happens on the segment those
  # devices are on rather than across a firewall boundary.  Nothing here routes
  # to it: that leg exists for the hub to talk OUT, and its firewall admits only
  # multicast discovery in.  See containers/home-assistant.nix.
  #
  # THE BACKEND IS A LONG-LIVED WEBSOCKET, which is the one operational thing to
  # know about this route.  The companion app authenticates once at /auth/token
  # and then holds /api/websocket open for the life of the session; the browser
  # UI does the same.  So the `websecure` readTimeout (3600s) and the `wan`
  # readTimeout (1800s) are what bound how long a client goes before a
  # reconnect.  A reconnect is not a failure — Home Assistant's clients handle
  # it — but lowering either value makes this route flap, and that is worth
  # knowing before someone tunes a timeout for an unrelated backend.
  homeassistantAddr = "10.0.90.27";
  homeassistantPort = 8123;

  # Miniflux (M27) — the feed reader, in an NSPAWN container on
  # 02:00:00:90:00:14 → 10.0.90.28.  Its container firewall accepts THIS
  # proxy's address, the service index's and the monitoring container's, and
  # nothing else.
  #
  # NOT AN appApiHosts NAME ANY MORE.  It shipped as one and moved to
  # `protectedHosts` when off-LAN access was wanted; its router therefore
  # carries the `authelia` middleware, which the guard below enforces.
  minifluxAddr = "10.0.90.28";
  minifluxPort = 8080;

  # Mail (M31) — 02:00:00:90:00:17 → 10.0.90.31.
  #
  # THIS PROXY ROUTES EXACTLY ONE THING TO IT, and not the mail server.
  # SMTP, IMAP and ManageSieve reach that container through four UDM-Pro
  # DNATs (ledger L19/L20) and a LAN rule (L22); none of them is HTTP and
  # `:25` has no SNI, so no TCP router could carry them even if this file had
  # one.  What IS routed is the MTA-STS policy file — a fixed HTTPS URL by
  # RFC 8461 — served by a four-line nginx vhost in that container so the
  # policy and the MX it names cannot drift apart.
  mailAddr = "10.0.90.31";
  mtaStsPort = 8080;

  # Karakeep (M27) — bookmarks and page archives, in an NSPAWN container on
  # 02:00:00:90:00:15 → 10.0.90.29.
  #
  # IT HAS A SECOND LEG THIS PROXY CANNOT SEE AND MUST NOT ROUTE TO, the way
  # Home Assistant does: a point-to-point /128 veth (`ai0`, fdca:fe92::) to the
  # host's inference server, on no VLAN at all.  That leg exists for the
  # container to talk OUT and carries nothing inbound.  See
  # containers/karakeep.nix and `roles.ollama…exposeOn` in clan.nix.
  karakeepAddr = "10.0.90.29";
  karakeepPort = 3000;

  # Music Assistant (M30) — the player controller over Navidrome's library, in
  # an NSPAWN container on 02:00:00:90:00:16 → 10.0.90.30.
  #
  # 8095 IS THE API AND UI PORT, AND THERE IS A SECOND LISTENER THIS PROXY MUST
  # NOT ROUTE TO.  8097 is Music Assistant's STREAM server, deliberately split
  # from the API, and its client is a SPEAKER fetching a URL — not a browser.
  # Putting it behind this proxy would mean putting forward-auth in front of a
  # Yamaha receiver.  It stays on the L2 path, admitted by source address in
  # that container's own firewall.
  #
  # IT ALSO HAS A SECOND LEG THIS PROXY CANNOT SEE, like Home Assistant's: iot1
  # on VLAN 20, for mDNS discovery of the one speaker in the house.  Nothing
  # inbound from this proxy goes anywhere near it.
  massAddr = "10.0.90.30";
  massPort = 8095;

  # Paperless-ngx — the household document archive (M32).
  #
  # IT ALSO HAS A SECOND LEG THIS PROXY CANNOT SEE, like Home Assistant's and
  # Music Assistant's, but for the opposite direction: `doc0`
  # (fdca:fe95::1/::2) exists so mneme, a HOST service, can reach the document
  # API for M32b's `document_search`.  Nothing inbound from this proxy goes
  # anywhere near it, and nothing on that leg can reach back out.
  #
  # Port 28981 is the module's own default and is granian, not nginx — unlike
  # Nextcloud there is no web server in front of the application inside the
  # container.  TLS is still terminated once, here.
  paperlessAddr = "10.0.90.32";
  paperlessPort = 28981;

  # Calibre-Web-Automated — the podman tier's FOURTH occupant, and the only
  # one of this round's three additions that needed an address of its own.
  #
  # WHY PODMAN AND NOT THE arr CONTAINER: CWA is not in nixpkgs.  nixpkgs has
  # `calibre-web` 0.6.26, which is the UPSTREAM project, not the
  # crocodilestick/Calibre-Web-Automated fork — a different codebase with the
  # ingest pipeline, the Kobo endpoint and the KOReader sync this deployment is
  # for.  So it is an opaque image, which is exactly the line invariant #1 and
  # containers/romm.nix draw for the podman tier.
  #
  # 02:00:00:90:00:0d / 10.0.90.21 — REUSED, not new.  This pair was M16's
  # cloudflared container and was marked FREE AGAIN by M18 when the tunnel was
  # deleted.  The allocation table in machines/ernst/allocations.nix is updated
  # to say so; a DHCP reservation for the old MAC must be re-pointed rather
  # than added alongside, or the address gets handed out twice.
  cwaAddr = "10.0.90.21";
  cwaPort = 8083;

  # slskd's web UI, in the MICROVM guest — the first backend here that is not
  # an nspawn container or a podman netns.
  #
  # ADDED AFTER THE FACT, and the omission is worth recording.  M14 routed
  # Soularr to slskd's API across VLAN 90 at layer 2 and stopped there, which
  # left the human web UI as the ONLY admin surface in this fleet not behind
  # Traefik — reachable solely by pointing a browser at 10.0.90.11:5030 from a
  # management VLAN, i.e. dependent on a per-guest UDM-Pro exception.
  #
  # That exception is what failed on 2026-08-28: from a LAN client, the guest
  # answered :22 and :8080 but timed out on :5030, so the page half-loaded and
  # its websocket died in a retry loop.  Routing it here removes the
  # dependency entirely — the browser talks to Traefik under the one permanent
  # `Allow Traefik` policy, and VLAN 90 needs no consumer-facing hole.
  #
  # The guest's nftables gained a matching pair of rules for THIS address only
  # (input on 5030, and the established reply) — deliberately not a seat in its
  # @api_clients set, which would also hand Traefik qBittorrent's API.
  slskdAddr = "10.0.90.11";
  slskdPort = 5030;

  # SOULARR HAS NO ROUTE AND NO PORT.  It is a one-shot timer, not a server,
  # and its bundled Flask web UI is deliberately not packaged — see
  # machines/ernst/containers/pkgs/soularr.nix.  Listed here as an absence so
  # nobody adds a router for symmetry with the rest of the milestone.

  # M6.  Traefik's own Prometheus metrics, on a SEPARATE entryPoint from the
  # one that serves traffic.  Its own port rather than a route on :443 because
  # a route would be reachable by anything the consumer-zone ZBF rule already
  # permits to reach :443 — i.e. every client VLAN — and would then need a
  # middleware to take that back.  A separate listener is restricted once, in
  # the container firewall, and cannot be re-exposed by adding a router.
  #
  # This endpoint is the ONLY source of certificate-expiry data: this process
  # owns acme.json, so nothing else can answer "when does the wildcard
  # actually expire" without parsing a file it should not be reading.  The
  # CertificateExpiringSoon alert in service-modules/monitoring.nix is what
  # closes the gap this file's ACME block names — "there is no monitoring on
  # this until M6".
  metricsPort = 8082;
}
