# machines/ernst/containers/traefik.nix
#
# Traefik v3 in an nspawn container: one reverse proxy on its own L2 identity,
# so every consumer VLAN collapses to a single permanent firewall rule pointing
# at THIS address instead of one rule per backend.
#
# nspawn per invariant #1: Traefik terminates TLS for in-house services and
# never fetches attacker-supplied URLs, so it is trusted tier.  (The workload
# that DOES render hostile pages is FlareSolverr — see containers/arr/.)
#
# History: docs/history.md M2b (the veth), M16 (the Cloudflare Tunnel, now
# deleted), M18 (the WAN forward that replaced it), M7 (Authelia).
#
# ── Networking: veth on br0, Services VLAN 90 ────────────────────────────────
#
#   The skeleton is modules/containers/nspawn.nix; its header owns the
#   rationale (KeepMaster over Bridge=, the VLAN-race backstop, the 20 s
#   wait-online cap).
#
#   MAC 02:00:00:90:00:04 ↔ DHCP reservation 10.0.90.12, in
#   machines/ernst/allocations.nix.  The reservation lives on the UDM-Pro, not
#   here, because the UDM-Pro owns the pool and a second copy diverges
#   silently.  It must be INSIDE the pool (10.0.90.6–.254): UniFi accepts an
#   address from the reserved .2–.5 range and then hands out a pool lease
#   anyway.
#
#   10.0.90.12 is the point of the milestone — the single address any client
#   VLAN may reach.  Jellyfin's .10 and arr's .13 are reachable from nowhere
#   else; see BACKEND BYPASS.
#
#   The RESOLVER is declared here (Technitium 10.0.5.3) because a
#   DHCP-supplied resolver that quietly changes does not fail loudly.  The ACME
#   resolvers are deliberately NOT Technitium — see SPLIT HORIZON.
#
# ── TWO ENTRYPOINTS, AND WHY THAT IS THE WHOLE SECURITY ARGUMENT ─────────────
#
#     websecure  :443 on 10.0.90.12   LAN only.  Every pre-M18 router names
#                                     this and only this.
#     wan        :8443 on 10.0.90.12  the UDM-Pro's DNAT target, and nothing
#                                     else.
#
#   A router is internet-reachable if and only if it names `wan`.  So creating
#   a route does NOT expose it: exposure is one greppable entry in `wanExposed`
#   below.  This reproduces the tunnel's fail-closed-by-construction property,
#   which a plain WAN :443 → `websecure` forward would have destroyed — every
#   router would become reachable, gated on middleware correctness alone, and a
#   middleware one edit from wrong fails OPEN.
#
#   MEASURED, scratch Traefik 3.7.10, 2026-09-03 — the milestone rests on this
#   entirely, so it was tested before the config was written:
#
#     - a `websecure`-only router requested on `wan` is UNMATCHED: 404, no
#       backend contact.  Control: the same request for a router that DOES name
#       `wan` returned 502 from the absent backend, which proves routing
#       happens at all and the 404 is a real miss;
#     - unknown SNI and no-SNI on `wan` also 404;
#     - the TLS handshake COMPLETES first, with `CN=TRAEFIK DEFAULT CERT`.  So
#       a scanner of the public IP learns a Traefik is here: an existence
#       disclosure, not an exposure.  This is the one place this is weaker than
#       the tunnel;
#     - the certificate store is GLOBAL and entrypoint-independent — a cert
#       attached to no entrypoint was served on both, selected by SNI alone.
#       That is why `wan` below carries NO certResolver: a second resolver
#       request for the same main+sans risks duplicate issuance against Let's
#       Encrypt's 5-per-week limit, and the failure mode of omitting it is loud
#       and free (a browser warning naming TRAEFIK DEFAULT CERT).
#
#   THE FAIL-OPEN PATH, DEFENDED IN CODE.  A router omitting `entryPoints` is
#   instantiated on EVERY entrypoint — measured on the same instance, one
#   appeared as both `websecure-forgot-entrypoints@file` and
#   `wan-forgot-entrypoints@file` and proxied on `wan`.  The split alone is
#   therefore not fail-closed; `withWan` below THROWS AT EVALUATION if a router
#   omits `entryPoints`, or if the set naming `wan` is anything but what
#   `wanExposed` generates.  Forgetting is a build error.
#
#   DNS IS THE SECOND, INDEPENDENT GATE.  Every other name exists only inside
#   Technitium, so from outside they NXDOMAIN.  Neither gate is sufficient
#   alone: DNS does not gate a request to the bare public IP.
#
#   `wanExposed` is authoritative and the registrar must agree with it by hand
#   — nothing makes them agree automatically, which is the point of two
#   independent gates.  A NAME IN `wanExposed` WITH NO PUBLIC A RECORD IS
#   INERT: that is how audiobookshelf stayed unreachable for a day after a
#   correct deploy.  If an exposed service is unreachable from outside,
#   `dig +short <name>.goclan.org @1.1.1.1` is the FIRST command.
#
#   "DNS-only" IS LOAD-BEARING: these records must not be Cloudflare-proxied.
#   A proxied record makes every request arrive from a Cloudflare address, and
#   CrowdSec — which reads Traefik's access log and bans at the packet layer —
#   would see one source for the whole internet.  Its bans would be useless at
#   best and self-inflicted outages at worst.
#
#   NO AAAA RECORDS, EVER, while SN2 holds.
#
# ── IPv4-ONLY BY CONSTRUCTION (standing note SN2) ────────────────────────────
#
#   The hazard: if the UDM-Pro ever permits inbound v6 and this container ever
#   acquires a global address, a v6 listener bypasses the DNAT and therefore
#   the `wan` entrypoint — and the firewall bouncer sets
#   `nftables.ipv6.enabled = false`, so there is no `ip6 crowdsec` table.  Over
#   v6 the routers would be reachable AND unbannable at once.
#
#   THE BIND IS NOT THE DEFENCE.  Every entryPoint is written `0.0.0.0:`
#   rather than `:` and it makes no difference: Go treats `0.0.0.0` as
#   unspecified and opens AF_INET6 with IPV6_V6ONLY=0 for any wildcard listen.
#   Measured on the deployed config 2026-09-07 — all four entryPoints plus
#   CrowdSec's metrics port were accepting v6 on link-local.  `disable_ipv6`
#   does not help either: the socket family is available whenever the module is
#   loaded, regardless of addressing.
#
#   What actually holds the line, in the order it is relied on:
#
#     1. NO IPv6 ADDRESS EXISTS IN THIS NETNS — `LinkLocalAddressing = "no"`.
#        The sockets stay dual-stack; they have nothing to be reached on.
#        THE PROOF IS `ip -6 addr show dev eth0` RETURNING NOTHING — not
#        `ss -f inet6`, and not a bare `ip -6 addr show`, because `lo` keeps
#        `::1/128 scope host` and is supposed to.
#     2. No v6 forward on the UDM-Pro.  Outside Nix, an explicit "do not" in
#        M18's manual steps, NOT audited.
#     3. No GUA anywhere on VLAN 90.  Measured 2026-08-25 and 2026-09-03:
#        link-local only, no v6 default route, `accept_ra = 0` on br0.
#
#   (3) is a state, not a defence, which is why M6 alerts on it
#   (`UnexpectedIPv6GlobalAddress`) — that alert is the tripwire for (1) and
#   (2) being all that is left.
#
# ── TLS: ACME DNS-01, wildcard, split horizon ────────────────────────────────
#
#   One wildcard for *.goclan.org over DNS-01, specifically so that no inbound
#   port is needed to prove domain control.  HTTP-01 never runs.
#
#   THEREFORE :80 IS NOT FORWARDED FROM THE WAN, and "open 80 for Let's
#   Encrypt" is the single most likely wrong edit to the UDM-Pro.  The `web`
#   entryPoint exists only to 308 a bare hostname typed on the LAN.
#
#   SPLIT HORIZON.  The CERTIFICATE is public — every name in it hits the
#   Certificate Transparency logs at issuance, so `*.goclan.org` is
#   world-readable forever.  The SERVICES are not: jellyfin.goclan.org and the
#   arr names exist only in Technitium, and Cloudflare's zone holds nothing for
#   them but the transient _acme-challenge TXT.  CT discloses that a wildcard
#   exists — not one service name, and not an address.
#
#   THE ACME RESOLVERS ARE PUBLIC ONES, AND THAT IS LOAD-BEARING.  lego
#   verifies its own TXT propagated before asking Let's Encrypt to validate.
#   Through this container's normal resolver that check asks Technitium, which
#   is authoritative for goclan.org inside the LAN and knows nothing about
#   _acme-challenge — an authoritative NXDOMAIN, forever.  The failure is a
#   renewal that hangs at "waiting for DNS record propagation", i.e. a
#   certificate that expires with the proxy still running.  1.1.1.1 and 9.9.9.9
#   ask the PUBLIC view, which is the view Let's Encrypt uses.
#
#   THE STORE IS ON zdata — /srv/state/traefik, because zroot rolls back
#   (invariant #7) and acme.json cannot be regenerated cheaply against a
#   5-per-week duplicate limit.  Traefik creates it 0600; the directory is 0700
#   uid 3005.  The Cloudflare token is a prompted clan var — see the generator
#   at the bottom and the staging oneshot.
#
# ── BACKEND BYPASS HARDENING: backend-side source restriction ────────────────
#
#   ONE mechanism, (a): each backend's own firewall, in its own netns, accepts
#   its web port ONLY from 10.0.90.12.  Those rules live beside the ports they
#   restrict, in containers/jellyfin.nix and containers/arr/.
#
#   WHY NOT (b), a UDM-Pro intra-zone ZBF rule — not a preference, (b) CANNOT
#   do the job: .10, .11, .12 and .13 are ports on the same VLAN on the same
#   bridge, so traffic between them is switched at layer 2 and the frames never
#   reach the UDM-Pro.  containers/arr/ relies on that property in the other
#   direction.  A gateway cannot filter traffic it never sees.
#   DO NOT ADD (b) AS WELL: two sources of truth for one property is how you
#   get a rule nobody dares delete because nobody can prove what it does.
#
#   The adjacency is real, not theoretical.  10.0.90.11 is the qBittorrent
#   microvm — the one workload on ernst that talks to the open internet on its
#   own behalf — one L2 hop from Sonarr's, Radarr's and Prowlarr's web UIs.
#   Source-restricting those ports is the largest thing this buys beyond TLS.
#
#   WHAT (a) DOES NOT COVER:
#
#     - code execution IN THIS CONTAINER.  Traefik is inside the allow-list by
#       construction.  This is the cost of collapsing every rule to one address;
#     - the backends' OUTBOUND reach — that is invariant #1's tiering;
#     - spoofed sources.  br0 does no source validation, so a VLAN 90 host can
#       forge .12.  It gets no replies, so this blocks exploitation-by-response
#       but not a blind one-shot write to an unauthenticated API;
#     - the host itself, which is on VLAN 50 and reaches VLAN 90 through the
#       UDM-Pro — the one path (b) would have covered.
#
#   DEBUGGING CONSEQUENCE: `curl http://10.0.90.10:8096` from a laptop or from
#   ernst FAILS, and that is correct.  Reach a backend with
#   `nixos-container run jellyfin -- curl -sS localhost:8096/health` instead —
#   `lo` is always trusted.
#
# ── JELLYFIN KEEPS NATIVE AUTH, FOREVER ──────────────────────────────────────
#
#   NEVER put Authelia, or any forward-auth middleware, in front of the
#   Jellyfin route.  TV apps, the mobile clients, Chromecast senders and every
#   DLNA-ish device authenticate with Jellyfin's own token API and cannot
#   perform an interactive OIDC redirect; forward-auth turns the first request
#   into a 302 to a page the client has no browser to render, so the app fails
#   with an opaque network error.
#
#   The arr routes are the opposite case and are what forward-auth exists for.
#   The distinction is NOT "admin versus household" — it is "can the client
#   render a login page and follow a 302".
#
# ── Storage, and the second occupant ─────────────────────────────────────────
#
#   /srv/state/traefik (zdata/state) → /var/lib/traefik.  Nothing else
#   persists; both configs are generated into the store on every deploy.
#
#   containers/crowdsec.nix puts the CrowdSec agent, its local API and the
#   firewall bouncer in THIS netns — the only place that sees the pre-DNAT
#   source of a WAN request — with its decisions database bound separately from
#   /srv/state/crowdsec.  That file CO-DEFINES `containers.traefik.config`:
#   read its header before assuming this file is the whole of what runs here.
{
  config,
  lib,
  pkgs,
  ...
}: let
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

  ############################################################################
  # ── M18: THE `wan` ENTRYPOINT.  THE COMPLETE EXTERNAL SURFACE ─────────────
  #
  # Read the TWO ENTRYPOINTS block in the file header before touching anything
  # below.  These four bindings and the guard under them are the whole of what
  # replaced the Cloudflare Tunnel's ingress list.
  ############################################################################

  # The entryPoint name.  A router is internet-reachable if and only if it
  # names this, so `grep -n 'wan' machines/ernst/containers/traefik.nix` is the
  # complete audit — which is the property M16's ingress list had and a
  # middleware never can.
  wanEntryPoint = "wan";

  # NOT 443.  The UDM-Pro DNATs WAN :443 → 10.0.90.12:8443, so `websecure`
  # keeps :443 for the LAN and stays byte-for-byte the listener every internal
  # client already talks to.  A shared port would mean one listener serving two
  # trust levels, which is precisely the thing this milestone exists to avoid.
  wanPort = 8443;

  # THE COMPLETE EXTERNAL SURFACE, AS EXISTING ROUTER NAMES.
  #
  # Each entry names a router defined below.  `withWan` copies it onto the
  # `wan` entrypoint as `<name>-wan`, INHERITING its rule, its service and its
  # middlewares — see there for why inheritance rather than a second
  # declaration.
  #
  # ADDING A NAME HERE IS GROWING THE INTERNET-FACING SURFACE OF THE HOUSE.
  # It needs: a public A record at the registrar, a ledger row, and — for
  # anything that is not Jellyseerr or the portal — an answer to why the
  # unauthenticated attack surface should stop being Authelia.
  #
  # `authelia` IS LOAD-BEARING, not padding.  Forward-auth is a REDIRECT
  # protocol: an unauthenticated request to jellyseerr answers 302 to
  # https://auth.goclan.org/?rd=…, so if the portal does not resolve and route
  # externally, no external login can ever complete.
  #
  # TWO SHAPES OF NAME ON THIS LIST, and the distinction is the whole posture:
  #
  #   protectedHosts  (jellyseerr, authelia, openwebui) — the wan twin inherits
  #     the `authelia` middleware, so the chain is
  #     wan-ratelimit → wan-inflight → authelia → app, i.e. admins-only
  #     forward-auth with mandatory 2FA.  No `wanLoginPaths` entry for these:
  #     that list is appApiHosts-only, because a forward-auth name already has
  #     Authelia's PER-IDENTITY regulation in front of its login, which beats a
  #     per-source rate limit — an entry here would rate-limit the portal.
  #
  #   appApiHosts  (audiobookshelf, jellyfin, komga, navidrome, cwa, immich) —
  #     answered by the APPLICATION, with Authelia never consulted, because
  #     their native clients cannot follow a forward-auth redirect.  The
  #     argument is in ingress-policy.nix, once, rather than restated per name.
  #     The app's own accounts are then the entire boundary against the
  #     internet and THERE IS NO SECOND FACTOR; `wan-ratelimit`/`wan-inflight`
  #     are the only limits in front of the login form, and CrowdSec banning on
  #     401s in the access log is the main thing standing between these and
  #     credential stuffing.
  #
  # THE PRECONDITION THIS FILE CANNOT ENFORCE, for any appApiHosts name: THE
  # ADMIN ACCOUNT MUST ALREADY EXIST AND ITS PASSWORD MUST BE STRONG.  A
  # first-run wizard is unauthenticated by construction and hands the root
  # account to whoever loads it first; on the LAN that window was survivable,
  # on the WAN it is not.  immich is the one that closes it BY MECHANISM rather
  # than by being quick — `IMMICH_ALLOW_SETUP` is false in containers/immich.nix
  # and M22 creates the A record last, deliberately.
  #
  # IMMICH HAS ONE PROPERTY NONE OF THE OTHERS HAS: part of its vhost is
  # UNAUTHENTICATED ON PURPOSE.  A shared album link is answered to an
  # anonymous caller from anywhere until revoked — that is the feature, and the
  # reason an album can be sent to someone with no account here.  Expiry and a
  # per-link password are the controls; both are runtime state this repo cannot
  # set.  So "the application's own accounts are the boundary" is weaker here
  # than for the other five.
  #
  # THE FAIL-CLOSED NEGATIVE CONTROL IS `sonarr`, NOT `jellyfin`.  jellyfin was
  # M18's control until it was exposed deliberately; any router not in this
  # list works, and sonarr is strictly better because it carries the `authelia`
  # middleware, so a leak there would be caught twice.  The checklist in
  # docs/guides/ernst-app-api-ingress.md uses it.
  #
  # THE OLD "NEVER EXPOSE JELLYFIN" NOTE WAS CLOUDFLARE'S TERMS OF SERVICE,
  # NOT A SECURITY RULE.  It forbade proxying video through the tunnel; M18
  # deleted the tunnel and the constraint went with it.  Said here because the
  # prohibition outlived its reason in two files.
  #
  # `openwebui` WIDENS TWO SETTINGS in service-modules/local-ai.nix, both
  # bounded by the forward-auth above rather than by themselves:
  # `ENABLE_OAUTH_SIGNUP` creates an account for anyone who clears Authelia —
  # the set who could already log in; `ENABLE_LOGIN_FORM` is the break-glass
  # password form, which on the wan path sits BEHIND forward-auth, so it is a
  # second door only for someone already through the first.  monitoring.nix
  # makes the same call for Grafana: if Authelia is down, every admin UI in the
  # house is down.  What no middleware changes is the impact — this vhost holds
  # the household's conversation history and can drive the GPU and outbound
  # search, so exposing it raises what an Authelia compromise is worth.
  #
  # Reversals and dates: docs/history.md (M16 the original two names, M18, M19
  # `chat`, M22 immich).
  wanExposed = [
    "jellyseerr"
    "authelia"
    "audiobookshelf"
    "jellyfin"
    "komga"
    "navidrome"
    "cwa"
    "openwebui"
    "immich"

    # Nextcloud (M23).  Off-LAN reach is most of the reason to run it: a phone
    # that only syncs on the home wifi is a phone that syncs when the photos
    # are already safe.  Same three separate acts as every other name here —
    # this entry, a public A record, and the ledger row in docs/ledger.md.
    "nextcloud"

    # Home Assistant (M24).  Off-LAN reach is the requirement rather than a
    # side effect, and in a sharper form than Nextcloud's: the companion app is
    # not only a client, it is a SENSOR.  Presence detection, zone triggers and
    # background location all work by the phone POSTing to this hostname while
    # it is away from the house — which is precisely when it is off the LAN.  A
    # hub reachable only on the home wifi cannot know anyone has left it.
    #
    # Same three separate acts as every other name here: this entry, a public A
    # record, and the ledger row (L15) in docs/ledger.md.
    "homeassistant"

    # The service index (M26).  Off-LAN reach is the modest half of the case
    # and the honest one: an index of the house's services is most useful from
    # a phone that is not in the house, which is where you are when you cannot
    # remember what the ebook server is called.
    #
    # IT IS THE FIRST NAME ADDED TO THIS LIST SINCE M19'S `openwebui` THAT IS
    # NOT AN EXEMPTION, and that is the thing to read rather than the count.
    # L13, L14 and L15 each put an appApiHosts name on the internet with
    # Authelia never consulted, because each had a native client that cannot
    # follow a 302.  This name is in `protectedHosts`, so `mkWan` copies the
    # `authelia` middleware onto the wan twin and the public path is
    # rate-limit → forward-auth → 2FA before the application sees a byte.
    # Chat's posture (ledger row L10), not Home Assistant's.
    #
    # NO `wanLoginPaths` ENTRY, and its absence is correct rather than an
    # oversight: that mechanism exists to give appApiHosts names a credential-
    # endpoint rate limit in place of the per-identity regulation they never
    # get.  This name goes through Authelia, which already has it — 3 attempts
    # in 5 minutes, 15 minute ban, per user rather than per path.  There is
    # also no login endpoint on this backend to point a matcher at.
    #
    # Same three separate acts as every other name here: this entry, a public A
    # record, and the ledger row (L16) in docs/ledger.md.
    "homepage"

    # Karakeep (M27), and the interesting part is what is NOT here beside it.
    #
    # ITS OWN MILESTONE'S OTHER SERVICE WAS DELIBERATELY LAN-ONLY AND IS NOT
    # ANY MORE — see `miniflux` below.  The asymmetry was argued at length
    # here ("reading feeds can wait for the LAN") and it lasted one day: lgo
    # went to another LAN and wanted his feeds.  The claim is corrected rather
    # than deleted, because the reasoning was sound and the PREMISE was wrong,
    # and those fail differently.
    #
    # `wanLoginPaths` DOES carry an entry for this one, unlike `homepage`'s and
    # now unlike `miniflux`'s, because this is an `appApiHosts` name: Authelia
    # never sees the request, so the per-identity regulation that makes a
    # login-path rate limit redundant behind forward-auth does not apply.
    #
    # Same three separate acts as every other name here: this entry, a public A
    # record, and the ledger row (L17) in docs/ledger.md.
    "karakeep"

    # Miniflux (M27, exposed afterwards).  UNLIKE EVERY OTHER NAME ADDED TO
    # THIS LIST SINCE M19'S `chat` EXCEPT `homepage`, IT IS NOT AN EXEMPTION:
    # it sits in `protectedHosts`, so `mkWan` copies the `authelia` middleware
    # onto the wan twin and the public path is rate-limit → forward-auth → 2FA
    # before Miniflux sees a byte.
    #
    # IT WAS MOVED OUT OF `appApiHosts` TO GET HERE, which is the part worth
    # reading: the cheap way to give a service off-LAN reach is to add it to
    # this list as it stands, and for this one that would have put an
    # unauthenticated vhost on the internet to save an edit.  The clients that
    # justified the exemption — native RSS readers over Fever and Google
    # Reader — do not exist in this house, so the exemption cost something and
    # bought nothing.
    #
    # Same three separate acts as every other name here: this entry, a public A
    # record, and the ledger row (L18) in docs/ledger.md.
    "miniflux"

    # Paperless-ngx (M32).  Off-LAN reach is the requirement rather than a side
    # effect, and the reason is the same one that makes the whole thing worth
    # building: a scan is most useful at the moment somebody is standing at a
    # counter being asked for a document they left at home.  A document archive
    # reachable only on the home wifi is an archive you have to go home to
    # read, which is the filing cabinet it replaces.
    #
    # `wanLoginPaths` DOES carry an entry for this one, like `karakeep`'s and
    # unlike `cloud`'s, because this is an `appApiHosts` name AND because its
    # login surface is addressable — see the entry below for the argument.
    #
    # Same three separate acts as every other name here: this entry, a public A
    # record, and the ledger row (L21) in docs/ledger.md.
    "paperless"

    # M31's MTA-STS policy.  THIS ONE HAS TO BE PUBLIC OR IT DOES NOTHING:
    # the readers are remote MTAs deciding whether to require TLS to us, and
    # they are by definition outside the house.  A LAN-only MTA-STS policy is
    # a file nobody fetches.
    #
    # It is also the least sensitive name on this list by a distance — the
    # response body is four lines naming the MX, which is already a public DNS
    # record.  Ledger row L23.
    "mtasts"
  ];

  # ── THE LOGIN PATHS, PER SERVICE, AND WHAT THIS DOES NOT COVER ────────────
  #
  # Router name -> the Traefik path matcher for that service's credential-
  # accepting endpoints.  `withWan` generates a SECOND wan router per entry,
  # `<name>-wan-login`, identical to the ordinary wan router except that it
  # carries `wan-login-ratelimit` instead of `wan-ratelimit` and outranks it on
  # priority.  Everything else about the vhost keeps the browsing limit.
  #
  # Only services in `appApiHosts` appear here, and that is the point: the
  # forward-auth names already have Authelia's per-user regulation in front of
  # their login, which is strictly better than a rate limit because it counts
  # per identity rather than per source address.
  #
  # ── WHERE THIS GENUINELY DOES NOT HELP, STATED RATHER THAN IMPLIED ────────
  #
  #   Two of these protocols carry the credential on EVERY request instead of
  #   exchanging it once for a token:
  #
  #     Subsonic (navidrome /rest/**)  — user + token/salt in the query string
  #                                      of every call, by protocol definition.
  #     Komga (/api/**, /opds/**)      — HTTP Basic on every call.
  #
  #   For those, "the login path" is not a distinct path, and rate-limiting the
  #   API would break streaming and page-turning for legitimate clients.  So
  #   the entries below cover the BROWSER login forms only, and brute force
  #   against the API is left to CrowdSec's 401 scenario
  #   (containers/crowdsec.nix), which keys on response status and not on path
  #   and is therefore the control that actually covers this case.
  #
  #   Writing that down because a `wan-login-ratelimit` in the config reads
  #   like full coverage, and it is not.  The honest claim is: it closes the
  #   form-login path cheaply, and CrowdSec is what closes the rest.
  #
  # PATH MATCHING IS CASE-SENSITIVE in Traefik while several of these
  # applications route case-insensitively.  The matchers below use the casing
  # the official clients actually send, which is what matters for the limit to
  # bite on a real attack tool replaying a real client's requests.
  wanLoginPaths = {
    # Jellyfin's token exchange.  Every app — TV, mobile, Chromecast sender —
    # POSTs here once and then carries an access token.
    jellyfin = "PathPrefix(`/Users/AuthenticateByName`)";

    # Audiobookshelf's form login.  Its apps POST here and then hold a bearer
    # token, so this is the whole credential surface for the mobile clients.
    audiobookshelf = "PathPrefix(`/login`)";

    # Komga's cookie-session login, used by the web UI and by Komelia's
    # initial handshake.  NOT /api/** — see the caveat above.
    komga = "PathPrefix(`/api/v1/login`)";

    # Navidrome's native web-UI login.  NOT /rest/** — see the caveat above.
    # Navidrome additionally ships its own limiter (5 attempts / 2 min,
    # observed in its startup log at 0.63.2), so this is the second of two.
    navidrome = "PathPrefix(`/auth/login`)";

    # CWA has three credential endpoints and they are genuinely distinct
    # paths, so all three are covered: the web form, KOReader's progress-sync
    # auth, and the Kobo device-token handshake.
    cwa = "(PathPrefix(`/login`) || PathPrefix(`/kosync/users/auth`) || PathPrefix(`/kobo_auth`))";

    # Immich's login and its API-key-issuing endpoint.  The app and the web UI
    # both POST to /api/auth/login and then carry a bearer token, so this is
    # the whole form-credential surface for every client that has one.
    #
    # `/api/auth/change-password` is included for a different reason than rate
    # limiting a login: it is the endpoint an attacker with a stolen session
    # would use to take the account, and it is cheap to make slow.
    #
    # WHAT THIS DOES NOT COVER, stated for the same reason the Navidrome and
    # Komga entries state theirs: a SHARED ALBUM LINK is not a credential
    # endpoint at all, so nothing here limits guessing at share URLs.  Those
    # are 128-bit random keys, which is the actual control; CrowdSec's 401
    # scenario is what sees a campaign of wrong ones.
    immich = "(PathPrefix(`/api/auth/login`) || PathPrefix(`/api/auth/change-password`))";

    # Home Assistant's two credential endpoints (M24).  `/auth/login_flow` is
    # the multi-step login the browser and the companion app both walk —
    # username/password, then the TOTP step — and `/auth/token` is where the
    # resulting authorization code becomes an access token.
    #
    # THIS ONE IS A CLEAN CASE, unlike the three caveats above, and it is worth
    # saying why: Home Assistant's credential path and its DATA path are
    # genuinely different URLs.  Everything else the app does rides
    # `/api/websocket`, which is opened once and then stays open, so a limit
    # here cannot touch it.  That is exactly the property Nextcloud's
    # `/remote.php/dav/**` lacks, and why this entry exists while that one
    # deliberately does not.
    #
    # `/api/websocket` MUST NOT BE MATCHED.  One request per ten seconds is
    # fine for a login and fatal for a reconnect storm after a network blip,
    # which is when every client in the house tries at once.
    #
    # `/auth/token` is also the REFRESH endpoint — the app trades its refresh
    # token for a new access token roughly every half hour.  A burst of 5 at
    # 1/10s covers a household of phones comfortably; it would not cover a
    # household of hundreds, which this is not.
    homeassistant = "(PathPrefix(`/auth/login_flow`) || PathPrefix(`/auth/token`))";

    # Karakeep's NextAuth credential endpoints (M27), and this entry is BELT
    # AND BRACES rather than the main control — which is worth saying, because
    # it is the reverse of every other entry in this map.
    #
    # containers/karakeep.nix sets `DISABLE_PASSWORD_AUTH`, so on the stated
    # behaviour there is no password to guess here at all and the real login
    # happens at Authelia, which has per-identity regulation.  THAT IS AN
    # ASSUMPTION ABOUT AN UPSTREAM FLAG AND IT IS NOT VERIFIED: if
    # `DISABLE_PASSWORD_AUTH` turns out to hide the form rather than to remove
    # the NextAuth credentials provider, the endpoint below still accepts POSTs
    # and this vhost is on the internet.  Limiting it costs nothing, because
    # nobody legitimate ever posts there.
    #
    # `/api/auth/callback/custom` MUST NOT BE MATCHED — that is the OAuth
    # RETURN from Authelia, i.e. the successful path, and it is a different
    # prefix from `/api/auth/callback/credentials` on purpose.
    #
    # NOTHING HERE COVERS API-KEY GUESSING against /api/v1/**, and it must not:
    # that is every request the browser extensions and the Floccus adapter
    # make, so a limit there would break unattended bookmark sync.  Same shape
    # as the Komga and Subsonic caveat above; CrowdSec's status-based 401
    # scenario is what actually covers it.
    karakeep = "(PathPrefix(`/api/auth/callback/credentials`) || PathPrefix(`/api/auth/signin`))";

    # ── MINIFLUX IS STILL ABSENT FROM THIS MAP, FOR A NEW REASON (M27) ─────
    #
    # It used to be absent because it was not on the WAN at all, and this note
    # told whoever exposed it to add a matcher here as the second edit.  THAT
    # ADVICE IS NOW WRONG and is replaced rather than followed: the name went
    # public by moving to `protectedHosts`, not by staying an exemption, so
    # Authelia is in front of it and already regulates the credential path per
    # IDENTITY — 3 attempts in 5 minutes, 15 minute ban — which is strictly
    # better than a per-source rate limit on a path.
    #
    # That is `homepage`'s situation exactly, and the rule generalises: an
    # entry here belongs to `appApiHosts` names and to nothing else.

    # ── NEXTCLOUD IS DELIBERATELY ABSENT FROM THIS MAP (M23) ────────────────
    #
    # It is in `appApiHosts` and it is in `wanExposed`, so by the pattern above
    # it should be here too.  It is not, because both candidate matchers are
    # wrong, in opposite directions:
    #
    #   /remote.php/dav/**  is not a login path.  It is EVERY request the
    #                       desktop sync client, DAVx5 and vdirsyncer make —
    #                       the credential rides along on all of them, which is
    #                       the Komga/Subsonic caveat above in its sharpest
    #                       form.  One request per ten seconds would not slow an
    #                       attacker down noticeably and WOULD stop sync.
    #   /login/v2/**        is Login Flow v2, which the desktop client POLLS
    #                       while the user completes the browser half of adding
    #                       an account.  A strict limit there breaks enrolment
    #                       itself — the one operation a household member
    #                       performs exactly once and cannot debug.
    #
    # So the honest coverage statement for this vhost is the one the caveat
    # above already makes for Navidrome and Komga, minus the cheap half: this
    # name is protected by `wan-ratelimit` + `wan-inflight`, by CrowdSec's
    # status-based 401 scenario, and by NEXTCLOUD'S OWN brute-force throttle,
    # which is on by default and is per-account rather than per-source.
    #
    # THAT LAST CONTROL IS THE REAL ONE AND IT HAS A PREREQUISITE: it keys on
    # the client address, so it is worth nothing unless
    # `settings.trusted_proxies` in containers/nextcloud.nix names this proxy.
    # If that line is ever removed, one attacker locks out the household and
    # this comment is where to look.
    #
    # Revisit if CrowdSec's metrics show enough 401s on this vhost to argue for
    # a matcher narrower than either of the two above.

    # ── PAPERLESS IS PRESENT, AND THE CONTRAST WITH NEXTCLOUD IS THE POINT ──
    #
    # Both names are in `appApiHosts` and both are in `wanExposed`, so the two
    # entries look like they should go the same way.  They do not, and the test
    # that separates them is NOT "does it have an app" — it is **is the
    # credential endpoint a DISTINCT path, or is it every request?**
    #
    #   /api/token/        is where Paperless Mobile exchanges a username and
    #                      password for a DRF token.  It is hit ONCE per device
    #                      per enrolment, and never again — the token rides in
    #                      an `Authorization` header on the ordinary API paths
    #                      afterwards, which this matcher does not touch.  One
    #                      request per ten seconds is invisible to a phone
    #                      being set up and ruinous to a password guesser.
    #   /accounts/login    is django-allauth's browser form, including the POST.
    #                      Same shape: a human logs in, a human does not log in
    #                      sixty times a minute.
    #
    # That is exactly what Nextcloud lacks: its equivalent of the first is
    # every sync request, and its equivalent of the second is a poll loop.
    # So the asymmetry between these two neighbouring entries is a property of
    # the protocols, not an inconsistency to tidy — do not "fix" it by removing
    # this entry or by adding one for `nextcloud`.
    #
    # NOTE `/accounts/login` IS A PREFIX WITHOUT A TRAILING SLASH on purpose:
    # allauth serves the form at /accounts/login/ and the OIDC leg under
    # /accounts/oidc/..., so a trailing slash here would still catch the form
    # while a broader `/accounts` would also rate-limit the OIDC callback — one
    # redirect per login, but shared with every other household member behind
    # the same public address.
    paperless = "(PathPrefix(`/api/token/`) || PathPrefix(`/accounts/login`))";
  };

  ############################################################################
  # ── THE INGRESS POLICY, AND THE GUARD THAT ENFORCES IT ────────────────────
  #
  # `appApiHosts`, `protectedHosts`, `householdHosts` and `portalHost` are
  # defined ONCE in ./ingress-policy.nix and consumed by both this file and
  # containers/authelia.nix.  Read that file before changing a middleware on
  # any router below — it carries the whole argument for which names may be
  # answered by the application instead of by Authelia.
  ############################################################################
  ingressPolicy = import ./ingress-policy.nix {inherit baseDomain;};

  # Extract the Host(`x`) literal from a router's rule, so the guard can check
  # a router against the policy without a second hand-maintained mapping from
  # router name to hostname.  Deriving it is the point: a hand-maintained map
  # is exactly the kind of list that goes stale, and the RomM 403 in
  # ingress-policy.nix's header is what that looks like in production.
  #
  # Every rule in this file is a bare Host(`…`) or a Host(`…`) && something.
  # A rule this cannot parse returns null and is REPORTED by the guard rather
  # than skipped — a router the policy cannot see is the failure mode this
  # whole mechanism exists to prevent.
  hostOfRule = rule: let
    m = builtins.match ".*Host\\(`([^`]+)`\\).*" rule;
  in
    if m == null
    then null
    else builtins.head m;
  ############################################################################

  # ── THE GUARD AND THE GENERATOR, IN ONE FUNCTION ──────────────────────────
  #
  # MEASURED on a scratch Traefik 3.7.10 (see the header): a router that OMITS
  # `entryPoints` is instantiated on EVERY entrypoint — it appeared as both
  # `websecure-forgot-entrypoints@file` and `wan-forgot-entrypoints@file` and
  # proxied on `wan`.  So the entrypoint split alone is NOT fail-closed: the
  # default for a forgotten line is exposure.  This closes it at EVALUATION
  # time, which is the only place a mistake can be caught before it is serving.
  #
  # THE WAN ROUTERS INHERIT FROM THEIR LAN TWINS, and that is not a shortcut —
  # it removes a whole class of bug.  An earlier draft of this file declared
  # each external router from scratch, derived its service name from the host
  # label, and therefore pointed `auth.goclan.org` at a service called `auth`
  # that does not exist (the service is `authelia`).  It evaluated fine.  It
  # would have 404'd the portal on the external path only — i.e. it would have
  # broken external logins and nothing else, which is exactly the failure that
  # survives a LAN test.  Copying the twin makes the rule, the service and the
  # forward-auth middleware identical BY CONSTRUCTION rather than by
  # inspection, so the external and internal paths cannot disagree.
  #
  # THREE CHECKS, and each one is a mistake somebody will make:
  #
  #   (a) every router NAMES its entryPoints — the measured fail-open above;
  #   (b) every name in `wanExposed` is a router that exists — a typo here
  #       would otherwise silently expose nothing and read as if it had;
  #   (c) NO router names `wan` by hand — so `entryPoints = [ "websecure"
  #       "wan" ]` bolted onto some future admin UI fails the build rather
  #       than the review.
  #
  # `throw` and not `assertions`: a throw fires wherever the config is
  # evaluated, including `nix flake check` and the CI eval, and it cannot be
  # demoted to a warning.
  withWan = lanRouters: let
    names = lib.attrNames lanRouters;
    missing = lib.filter (n: !(lanRouters.${n} ? entryPoints)) names;
    unknown = lib.filter (n: !(lanRouters ? ${n})) wanExposed;
    stray = lib.filter (n: lib.elem wanEntryPoint lanRouters.${n}.entryPoints) names;

    # ── CHECKS (d)–(f): THE INGRESS POLICY, ENFORCED ─────────────────────
    #
    # See ./ingress-policy.nix for why this is a mechanism rather than a
    # fourth comment.  The short version: the same decision used to be
    # written in three files and enforced in none, and it cost a production
    # 403 on RomM.
    #
    # These run over the LAN routers, BEFORE `mkWan` copies any of them —
    # so a policy violation is caught whether or not the name is exposed.
    # A wrong middleware on a LAN-only router is still wrong; it just has a
    # smaller blast radius until someone adds it to `wanExposed`.
    hostOf = n: hostOfRule lanRouters.${n}.rule;
    hasAuth = n: lib.elem "authelia" (lanRouters.${n}.middlewares or []);

    # (d) a rule this cannot parse is a router the policy cannot see.
    unparsable = lib.filter (n: hostOf n == null) names;

    # (e) an appApi host that carries forward-auth.  This is the regression
    #     the whole file exists to prevent: it breaks every native client of
    #     that service, and it breaks them with an opaque network error
    #     rather than a login prompt, so it does not look like an auth
    #     change when it is reported.
    wronglyProtected =
      lib.filter
      (n: hostOf n != null && lib.elem (hostOf n) ingressPolicy.appApiHosts && hasAuth n)
      names;

    # (f) a routed hostname that is in NONE of the policy lists.  Left
    #     unchecked this is the RomM failure exactly — the router exists,
    #     Authelia has never heard of the name, and the user gets a 403
    #     after a successful login.  Catching it here turns a support
    #     ticket into a build error that names the file to edit.
    unclassified =
      lib.filter
      (n: let
        host = hostOf n;
      in
        host
        != null
        && !(lib.elem host ingressPolicy.appApiHosts)
        && !(lib.elem host ingressPolicy.protectedHosts)
        && !(lib.elem host ingressPolicy.householdHosts)
        && host != ingressPolicy.portalHost)
      names;

    # (g) the mirror of (e): a host the policy says is protected, whose
    #     router forgot the middleware.  Authelia's default_policy = "deny"
    #     does NOT save this case — the middleware is what sends the request
    #     to Authelia at all, so a missing one means the request goes
    #     straight to the backend unauthenticated.  This is the fail-OPEN
    #     direction and is the more dangerous of the two.
    wronglyOpen =
      lib.filter
      (n: let
        host = hostOf n;
      in
        host
        != null
        && (lib.elem host ingressPolicy.protectedHosts
          || lib.elem host ingressPolicy.householdHosts)
        && !(hasAuth n))
      names;

    # ── The order of the middlewares is deliberate ────────────────────────
    #
    # Rate limit and concurrency cap FIRST, then whatever the LAN twin
    # carries (forward-auth, for everything but the portal).  A flood is shed
    # here rather than being turned into one Authelia authz call per request:
    # Authelia is a single container in the login path of every admin UI in
    # the house, and letting the internet drive it at line rate would hand an
    # attacker a lever on the household's own access.
    mkWan = n: {
      name = "${n}-wan";
      value =
        lanRouters.${n}
        // {
          entryPoints = [wanEntryPoint];
          middlewares =
            ["wan-ratelimit" "wan-inflight"]
            ++ (lanRouters.${n}.middlewares or []);
        };
    };

    # ── The login routers, generated the same way and for the same reason ─
    #
    # Generated HERE rather than declared by hand next to their twins,
    # because a hand-declared router naming `wan` is exactly what check (c)
    # forbids — and it forbids it for a good reason.  Generating them keeps
    # the rule, the service and the forward-auth state inherited from the
    # LAN twin, so the login path and the ordinary path cannot disagree
    # about which backend they reach or whether they are authenticated.
    #
    # PRIORITY IS EXPLICIT.  Traefik's default priority is the rule's
    # length, and `Host(x) && PathPrefix(y)` is longer than `Host(x)`, so
    # these would win anyway today — but that is an accident of string
    # length, not a guarantee, and it silently inverts the day someone
    # lengthens a Host rule.  An explicit high priority makes it a property.
    #
    # Only generated for names that are BOTH exposed and listed in
    # `wanLoginPaths`; an entry for an unexposed service is inert rather
    # than an error, since the point of the list is the wan surface.
    mkWanLogin = n: {
      name = "${n}-wan-login";
      value =
        lanRouters.${n}
        // {
          entryPoints = [wanEntryPoint];
          rule = "${lanRouters.${n}.rule} && ${wanLoginPaths.${n}}";
          priority = 1000;
          middlewares =
            ["wan-login-ratelimit" "wan-inflight"]
            ++ (lanRouters.${n}.middlewares or []);
        };
    };

    wanLoginNames = lib.filter (n: wanLoginPaths ? ${n}) wanExposed;

    # A `wanLoginPaths` entry whose router does not exist is a typo that
    # would otherwise silently protect nothing — same failure shape as check
    # (b), so it gets the same treatment.
    unknownLogin = lib.filter (n: !(lanRouters ? ${n})) (lib.attrNames wanLoginPaths);
  in
    if missing != []
    then
      throw ''
        traefik.nix: these routers do not name their entryPoints, and Traefik
        binds such a router to EVERY entrypoint — including `wan`, which is
        the internet:
          ${lib.concatStringsSep ", " missing}
        Add `entryPoints = [ "websecure" ];` to each.  See the TWO
        ENTRYPOINTS block in this file's header.
      ''
    else if unknown != []
    then
      throw ''
        traefik.nix: `wanExposed` names routers that do not exist:
          ${lib.concatStringsSep ", " unknown}
        It takes ROUTER names (e.g. `authelia`), not host labels (`auth`).
      ''
    else if stray != []
    then
      throw ''
        traefik.nix: these routers put themselves on the `wan` entrypoint by
        hand:
          ${lib.concatStringsSep ", " stray}
        `wan` is the internet, and exposure is an edit to `wanExposed` plus a
        public A record plus a ledger row — never an entryPoints list on an
        existing router.  See the TWO ENTRYPOINTS block in this file's
        header.
      ''
    else if unparsable != []
    then
      throw ''
        traefik.nix: the ingress-policy guard cannot find a Host(`…`) literal
        in the rule of these routers, so it cannot tell whether they are
        allowed to carry forward-auth:
          ${lib.concatStringsSep ", " unparsable}
        Every router here must match on a literal hostname.  If you genuinely
        need a different matcher, extend `hostOfRule` — do NOT skip the
        check, which is the one thing that keeps this file and
        containers/authelia.nix from disagreeing.
      ''
    else if wronglyProtected != []
    then
      throw ''
        traefik.nix: these routers carry the `authelia` forward-auth
        middleware, but their hostnames are in `appApiHosts`:
          ${lib.concatStringsSep ", " wronglyProtected}
        THIS BREAKS EVERY NATIVE CLIENT OF THAT SERVICE.  forward-auth is a
        redirect protocol; an app with a bearer token has no browser to
        follow a 302 to the portal, so it fails with an opaque network error
        that reads as a broken server rather than a login prompt.
        If you are ADDING auth deliberately, the hostname must move out of
        `appApiHosts` in ./ingress-policy.nix — and read the block there
        first, because each entry is in that list for a measured reason.
      ''
    else if wronglyOpen != []
    then
      throw ''
        traefik.nix: these routers are missing the `authelia` middleware, but
        their hostnames are declared protected in ./ingress-policy.nix:
          ${lib.concatStringsSep ", " wronglyOpen}
        THIS IS THE FAIL-OPEN DIRECTION.  Authelia's default_policy = "deny"
        does not save it: the middleware is what sends the request to
        Authelia at all, so without it the request reaches the backend
        unauthenticated and Authelia is never consulted.
        Add `middlewares = [ "authelia" ];`, or move the hostname into
        `appApiHosts` with an argument for why a native client needs it.
      ''
    else if unclassified != []
    then
      throw ''
        traefik.nix: these routers serve hostnames that appear in NO list in
        ./ingress-policy.nix:
          ${lib.concatStringsSep ", " unclassified}
        Every routed hostname must be classified, because Authelia derives
        its access_control rules from the same file.  A name routed here and
        absent there returns 403 to a user who has just logged in
        successfully — which reads as an Authelia fault and is a missing line
        in a list.  That is not hypothetical; it is what happened to RomM.
        Add the hostname to `appApiHosts`, `protectedHosts` or
        `householdHosts`.
      ''
    else if unknownLogin != []
    then
      throw ''
        traefik.nix: `wanLoginPaths` names routers that do not exist:
          ${lib.concatStringsSep ", " unknownLogin}
        An entry here that matches nothing produces no login rate limit and
        reads in review as though it does.  It takes ROUTER names.
      ''
    else
      lanRouters
      // lib.listToAttrs (map mkWan wanExposed)
      // lib.listToAttrs (map mkWanLogin wanLoginNames);

  # ── WHERE THE `mgmt-only` ipAllowList WENT ────────────────────────────────
  #
  # M5 shipped an interim IP allow-list here — 10.0.10.0/24 (LAN),
  # 10.0.50.0/24 (Servers), 10.0.70.0/24 (travel/wg) — on the *arr routes, and
  # M6 added Grafana to it.  That was ledger row L5, and M7 RETIRED IT: it is
  # deleted, not stacked underneath the forward-auth middleware.
  #
  # The argument for removing rather than keeping it, and the cost that comes
  # with that (the login portal is now visible from the IoT VLAN), are written
  # out in machines/ernst/containers/authelia.nix under "THE ipAllowList IS
  # REMOVED, NOT STACKED".  The short version: an allow-list under an identity
  # provider means valid credentials plus a correct TOTP code still fail from
  # anywhere nobody pre-declared, which is most of what the identity provider
  # was added for.
  #
  # DO NOT REINTRODUCE IT as "defence in depth" without reading that block.
  # The depth is still there and it did not come from this list: every backend
  # refuses its own web port from anything but this container's address, so the
  # only path to the *arr is through here — and the only way through here is
  # now through Authelia.

  ############################################################################
  # Secrets staging.
  ############################################################################

  # The Cloudflare token, staged out of sops into a host tmpfs directory and
  # bound read-only into the container at the SAME path.
  #
  # NOT a bind of /run/secrets itself: that path is a symlink to a
  # per-generation directory which is REPLACED on every deploy, so an nspawn
  # bind established at container start would keep exposing a deleted
  # generation until the container is restarted.  microvms/wg-qbittorrent.nix
  # hit this first and its header explains it at length.  A directory we own
  # has a stable identity and is rewritten in place.
  secretsDir = "/run/traefik-secrets";
  envFile = "${secretsDir}/cloudflare.env";

  gen = config.clan.core.vars.generators.traefik-acme;

  # The module's default dataDir.  Named here because the ACME storage path in
  # the static config has to agree with the bind mount, and one binding is
  # cheaper to keep in step than two string literals.
  dataDir = "/var/lib/traefik";
in {
  ##############################################################################
  # Host-side wiring.
  ##############################################################################

  # Stage the Cloudflare token where the container can see it.
  #
  # 0400 root:root.  systemd reads EnvironmentFile= as PID 1, before it drops
  # to User=traefik, so the traefik uid never needs to read this file and must
  # not be able to.  That is the whole difference from the wg-qbittorrent
  # staging unit, whose WebUI hash HAD to be group-readable because the process
  # that consumes it runs unprivileged — and which shipped broken once because
  # the directory was not group-traversable.  No such trap here: nothing but
  # PID 1 opens it.
  #
  # GENERATE BEFORE YOU DEPLOY.  clan-core cannot know a sops secret's path
  # until the secret exists; until then `files.<n>.path` evaluates to the
  # literal "/no-such-path" and THAT is what gets baked into the script below.
  # A deploy that runs before `clan vars generate ernst` produces a system
  # whose staging unit can never succeed however often it is restarted — it has
  # to be rebuilt.  The failure is at least loud and fail-closed: this unit
  # fails, `container@traefik` never starts, and there is no proxy rather than
  # a proxy with no certificate.
  #
  # ROTATING THE TOKEN needs a restart, not just a deploy.  If this unit's text
  # is unchanged, systemd will not re-run it when the underlying sops file
  # changes, so the staged copy stays stale.  After `clan vars generate ernst`:
  #     systemctl restart traefik-secrets container@traefik
  systemd.services.traefik-secrets = {
    description = "Stage the Cloudflare ACME token for container@traefik";
    after = ["local-fs.target"];
    before = ["container@traefik.service"];
    requiredBy = ["container@traefik.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.coreutils}/bin/install -d -m 0700 -o root -g root ${secretsDir}
      ${pkgs.coreutils}/bin/install -m 0400 -o root -g root \
        ${gen.files."cloudflare.env".path} ${envFile}
    '';
  };

  # There is deliberately NO `networking.firewall.allowedTCPPorts` on the HOST.
  # 443 is opened inside the container's own netns; on the host it is not a
  # port at all.  Reachability from the consumer VLANs is the UDM-Pro's job —
  # and after this milestone it is ONE rule per zone, pointing at 10.0.90.12,
  # which is the entire reduction M5 exists to deliver.
  #
  # The host-side veth network and the VLAN-race backstop are generated by
  # modules/containers/nspawn.nix, whose header owns both arguments.
  # `bridge vlan show dev vb-traefik` remains the check — do not trust silence
  # from either mechanism.

  ##############################################################################
  # Vars generator: the Cloudflare DNS-01 credential.
  #
  # A SCOPED API TOKEN, not the Global API Key.  Both work with lego's
  # cloudflare provider, and the difference is the blast radius of this
  # container being compromised:
  #
  #   Global API Key  → full control of every zone and every setting on the
  #                     Cloudflare ACCOUNT, and it cannot be rotated without
  #                     breaking everything else that uses it.
  #   Scoped token    → Zone:DNS:Edit on goclan.org and nothing else, revocable
  #                     on its own.
  #
  # The token needs exactly two permissions, both on the goclan.org zone:
  #     Zone / DNS  / Edit
  #     Zone / Zone / Read
  # Zone:Read is not optional — lego looks the zone id up by name before it can
  # write the challenge record, and a token with only DNS:Edit fails at that
  # lookup with an error that names neither permission.
  #
  # The file is emitted in KEY=value form rather than as a bare token because
  # services.traefik consumes it through systemd's EnvironmentFile=.
  ##############################################################################
  clan.core.vars.generators.traefik-acme = {
    files."cloudflare.env".secret = true;

    prompts."cloudflare-dns-api-token" = {
      description = "Cloudflare API token, scoped Zone:DNS:Edit + Zone:Zone:Read on ${baseDomain}";
      type = "hidden";
    };

    runtimeInputs = [pkgs.coreutils pkgs.gnugrep];

    script = ''
      set -euo pipefail

      token=$(tr -d '[:space:]' < "$prompts/cloudflare-dns-api-token")

      # Validate before writing.  Every one of these fails LATE otherwise — the
      # container starts, the routes serve, and the only symptom is that no
      # certificate ever appears and the browser shows Traefik's self-signed
      # default.  A human is watching exactly once, at prompt time.
      fail=0
      err() { echo "  ✗ $*" >&2; fail=1; }

      if [ -z "$token" ]; then
        err "empty token"
      fi

      # A Global API Key is 37 lowercase hex characters.  A scoped token is 40
      # characters of [A-Za-z0-9_-].  Catching the former is worth a rule of its
      # own: it AUTHENTICATES FINE, so the mistake is invisible at every point
      # where it could be caught later — the certificate issues, everything
      # works, and the account is one container compromise from being lost.
      if printf '%s' "$token" | grep -qE '^[0-9a-f]{37}$'; then
        err "that is a Global API Key (37 hex chars), not a scoped token."
        err "  Create one at: Cloudflare → My Profile → API Tokens → Create Token"
        err "  Permissions:   Zone/DNS/Edit + Zone/Zone/Read, on ${baseDomain}"
      elif ! printf '%s' "$token" | grep -qE '^[A-Za-z0-9_-]{30,}$'; then
        err "does not look like a Cloudflare API token (expected 40 chars of [A-Za-z0-9_-])"
      fi

      [ "$fail" -eq 0 ] || exit 1

      # The consumer is systemd's EnvironmentFile=, which wants KEY=value.
      # No quoting: systemd would keep the quotes as part of the value.
      printf 'CF_DNS_API_TOKEN=%s\n' "$token" > "$out/cloudflare.env"
    '';
  };

  ##############################################################################
  # The container itself.
  ##############################################################################

  ##############################################################################
  # The container.
  ##############################################################################
  #
  # modules/containers/nspawn.nix generates the dirs unit, the host-side veth
  # network, the VLAN backstop, the container preamble and the in-container
  # networking. It does NOT generate this container's firewall — see
  # `manageFirewall` below.
  #
  # `traefik-secrets` STAYS HAND-WRITTEN: it installs the Cloudflare token as
  # a whole file rather than composing an env file out of keys.
  #
  # containers/crowdsec.nix CO-DEFINES this container, adding its own daemon
  # inside Traefik's netns — the only place that sees the pre-DNAT source of a
  # WAN request. `containers.<n>.config` merges like any other option, and
  # `clanarchy.containers.<n>.config` is passed through to it unchanged, so
  # that arrangement is unaffected by this move.
  clanarchy.containers.traefik = {
    enable = true;
    mac = traefikMac;

    # NO uid/gid PIN: the module allocates traefik dynamically and the
    # in-container block handles it — see its own note.

    stateVersion = "26.05";

    # ── THE FIREWALL IS THIS CONTAINER'S OWN, AND THAT IS NOT A SHORTCUT ─────
    #
    # Two reasons, either of which is sufficient. First, "which peers" is the
    # wrong question for the ingress: 80, 443 and the WAN port answer the
    # whole internet, which is the entire point of the machine. Second, this
    # is the one container here running `networking.nftables`, where the
    # `extraCommands` the module emits is declared but never consumed — no
    # rule, no warning, no firewall. Its rules use `extraInputRules`, below.
    manageFirewall = false;

    # AN ORDERED UNIT RATHER THAN A tmpfiles RULE: bound into the container,
    # so a tmpfiles rule for it races the container's own start. The guard
    # matters more here than anywhere — acme.json on a filesystem that rolls
    # back means re-issuing every certificate on every boot, and Let's
    # Encrypt rate-limits that.
    #
    # NUMERIC ids on purpose: `traefik` is a container user and the host has
    # no matching passwd entry.
    stateDirs = [
      {
        path = "/srv/state/traefik";
        owner = traefikUid;
        group = traefikGid;
      }
    ];

    bindMounts = {
      # The certificate store, at the module's own default dataDir so
      # services.traefik needs no path override.
      "${dataDir}" = {
        hostPath = "/srv/state/traefik";
        isReadOnly = false;
      };
      # The staged Cloudflare token, read-only, at the identical path.
      "${secretsDir}" = {
        hostPath = secretsDir;
        isReadOnly = true;
      };
    };

    config = {
      config,
      pkgs,
      lib,
      ...
    }: {
      # Matches the host.  Certificate expiry, renewal attempts and every
      # access-log line are rendered in local time, and a container that
      # silently defaults to UTC makes "when did the cert actually renew" a
      # two-hour question.  Same call as containers/arr/.
      time.timeZone = "Europe/Berlin";

      ##########################################################################
      # Networking.  The container owns its netns, so it owns all of this.
      ##########################################################################

      # services.resolved asserts !networking.useHostResolvConf, and with a
      # private netns the host's resolv.conf is a stale snapshot of someone
      # else's resolver anyway.  virtualisation/container-config.nix sets it
      # `mkDefault true`, so a plain `false` wins without mkForce.

      ##########################################################################
      # THE FIREWALL IS nftables HERE, AND M18 IS WHY — argue before reverting.
      #
      # Every other container in this fleet uses the iptables firewall with
      # `extraCommands`.  This one moved, for one reason: the CrowdSec firewall
      # bouncer (machines/ernst/containers/crowdsec.nix) has to enforce bans in
      # THIS netns, and the two backends give materially different guarantees.
      #
      #   iptables mode.  The bouncer inserts `-I INPUT … -j DROP` above the
      #     `-j nixos-fw` jump.  A firewall RELOAD re-inserts nixos-fw at the
      #     top — and `PartOf=` does not propagate reload, only restart — so
      #     after a reload nixos-fw ACCEPTs :443 before the drop is ever
      #     reached, and every ban is silently inert.  A ban that is not
      #     observed in the ruleset is not a ban (SN3), and this is the version
      #     of that failure that leaves no trace at all.
      #   nftables mode.  The drop lives in its OWN base chain in its OWN
      #     table.  Both chains are traversed at the input hook and only `drop`
      #     is terminal, so nixos-fw accepting :443 does not prevent the drop.
      #     Ordering stops being a property anyone has to get right.
      #
      # It also makes the drop rule DECLARATIVE: with the bouncer in nftables
      # mode the NixOS module emits `networking.nftables.tables.crowdsec` — the
      # set and the `ip saddr @crowdsec-blacklists drop` chain are in the Nix
      # config, greppable, and re-created by nftables.service, while the
      # bouncer only manages set membership.  Measured in a throwaway VM on
      # 2026-09-03 before any of this was written; the transcript and the four
      # upstream defects it found are in crowdsec.nix's header.
      #
      # THE COST, stated: `networking.firewall.extraCommands` is REJECTED under
      # nftables, so the M6 metrics rule below had to move to
      # `extraInputRules`.  The comment that used to sit there said
      # extraInputRules "would produce no rule and no warning" — true then,
      # false now, and this is the edit that makes it false.
      ##########################################################################
      networking.nftables.enable = true;

      # 443 is the service.  80 exists ONLY to redirect to it (see the
      # entryPoint below) and is opened for that reason alone — a household
      # that types a bare hostname gets a redirect instead of a connection
      # refused, and nothing is ever served over it.  If you want to remove the
      # redirect, remove BOTH this port and the entryPoint; leaving the port
      # open with no listener is worse than either.
      #
      # 8443 IS THE WAN ENTRYPOINT and is the only listener the internet can
      # reach — see TWO ENTRYPOINTS in the file header.  It is open to the
      # whole Services VLAN here rather than to the gateway alone, deliberately
      # and with the reason written down: the UDM-Pro DNATs to this address
      # from the WAN, so the source it arrives from is whatever external client
      # sent it and there is no stable inside source to filter on.  What gates
      # this port is the ROUTER SET, not an address list.
      #
      # 80 IS NOT FORWARDED FROM THE WAN.  ACME is DNS-01, so HTTP-01 never
      # runs — see the TLS block in the header, which exists so nobody opens it
      # "for Let's Encrypt".
      #
      # No 8080: the Traefik dashboard/API is not enabled.  See the static
      # config below.
      #
      # 8082 (metrics) is NOT in this list on purpose — it is opened below for
      # one source address only.  Everything on VLAN 90 could otherwise read
      # every route name, backend address and TLS setting in the house off an
      # unauthenticated endpoint, which is most of what the dashboard was
      # switched off to avoid.
      networking.firewall.allowedTCPPorts = [80 443 wanPort];

      # M6: the metrics endpoint, source-restricted to the monitoring
      # container.  Same mechanism and the same reasoning as the backend
      # hardening this file imposes on jellyfin and the arr — see BACKEND
      # BYPASS HARDENING above — just pointing the other way: there, this
      # container is the permitted source; here, it is the protected one.
      #
      # `extraInputRules` now that the firewall is nftables — see the block
      # above.  It lands in nixos-fw's input chain ahead of the terminal
      # refuse, which is the same placement the old iptables append had.
      networking.firewall.extraInputRules = ''
        ip saddr ${monitoringAddr} tcp dport ${toString metricsPort} accept
      '';

      # SN2's enforcement is NOT here.  It is `LinkLocalAddressing = "no"` on
      # the 10-eth0 network unit below — see the comment there.
      #
      # THERE WAS A `boot.kernel.sysctl` disable_ipv6 BLOCK IN THIS SPOT AND IT
      # IS DELIBERATELY GONE: two attempts, both deployed, both measured, both
      # dead (`all` alone, then `all`+`default`+`eth0` — eth0 kept
      # fe80::ff:fe90:4/64 either way).  Two independent reasons, each fatal
      # alone: systemd-sysctl runs before eth0 exists in this netns, so the
      # per-interface key is silently skipped; and networkd writes
      # `disable_ipv6 = 0` on every link it configures.  networkd owns the link.
      #
      # THE SOCKETS ARE DUAL-STACK AND STAY DUAL-STACK whatever is done here —
      # Go returns AF_INET6 with IPV6_V6ONLY=0 for any wildcard listen, so the
      # address written in an entryPoint makes no difference.  The mechanism is
      # that NO IPv6 ADDRESS EXISTS IN THIS NETNS: the sockets have nothing to
      # be reached on, and no delegated prefix can be accepted.
      #
      # THE PROOF, EXACTLY, because two different wrong commands have already
      # been written down as one:
      #
      #   ip -6 addr show dev eth0   ->  nothing        <- THIS is the check
      #   ip -6 route show           ->  nothing        <- and this
      #   ip -6 addr show            ->  ::1/128 on lo  <- EXPECTED, not a failure
      #   ss -ltnH -f inet6          ->  five listeners <- EXPECTED, not a failure
      #
      # The bare `ip -6 addr show` form was accurate only while the deleted
      # sysctls existed, because `all = 1` covered `lo` and took `::1` with it.
      # Loopback is unreachable from outside this netns; `::1` coming back is
      # correct.

      ##########################################################################
      # Users.  Numeric ids are the interface across the nspawn boundary.
      ##########################################################################

      # The upstream module declares users.users.traefik without a uid (it lets
      # NixOS allocate one dynamically from the system range) and
      # users.groups.traefik without a gid.  Both are plain definitions with no
      # uid/gid attribute, so adding one here is a MERGE and needs no mkForce —
      # unlike containers/arr/, where the servarr modules DO set uid from
      # config.ids.uids.* and the override has to fight them.
      #
      # isSystemUser is already true upstream and stays true; it is restated
      # because NixOS infers "effectively a system user" from uid < 1000, and
      # 3005 is not, so the inference stops working the moment the uid is
      # pinned.  containers/arr/ hit exactly this and the error names
      # neither the uid nor the cause.
      users.users.traefik = {
        isSystemUser = true;
        uid = traefikUid;
      };
      users.groups.traefik = {gid = traefikGid;};

      ##########################################################################
      # Traefik.
      ##########################################################################
      services.traefik = {
        enable = true;

        # dataDir left at its default — /var/lib/traefik is the bind mount.
        environmentFiles = [envFile];

        ########################################################################
        # STATIC configuration — entryPoints, the ACME resolver, logging.
        # Changing anything here needs a Traefik restart; the dynamic half
        # below is re-read live.
        #
        # NOTE ON envsubst: because environmentFiles is non-empty, the module
        # renders this file through envsubst at ExecStartPre, into
        # /run/traefik/config.toml.  Nothing below may contain a literal `$` —
        # it would be substituted (probably to the empty string) with no error.
        ########################################################################
        staticConfigOptions = {
          # Neither of these should reach the internet from a box whose whole
          # point is that it does not need to.
          global.checkNewVersion = false;
          global.sendAnonymousUsage = false;

          # To the journal.  `journalctl -u traefik` inside the container is
          # where the ACME exchange and every routing decision are visible, and
          # it is the instrument the PR test plan uses.
          log.level = "INFO";

          # ── M18: JSON, because CrowdSec reads this ─────────────────────────
          #
          # The access log was `common` (CLF) from M5 until M18.  It is now
          # JSON, and the change was checked before it was made rather than
          # after: `grep -rn accessLog` across this repo returns ONE definition
          # and two comments about timezone rendering, so nothing else parses
          # this stream and there is no second consumer to break.
          #
          # WHY JSON.  crowdsecurity/traefik-logs has two parsing paths and the
          # JSON one is strictly better: the CLF path is a grok pattern that
          # has to re-derive fields from a text line, while the JSON path reads
          # `ClientHost` — the field Q2 is about — directly, plus `RouterName`,
          # `DownstreamStatus` and the User-Agent header, with a nil guard on
          # each.  A grok that stops matching after a Traefik bump is a silently
          # blind detector, which is SN3's failure exactly.
          #
          # STILL ON stdout, so still in this container's journal: destination
          # unchanged, format changed.  That is deliberately the smaller edit —
          # a file would have needed a path, an owner, a rotation unit and a
          # readable-by-crowdsec permission triangle, and every one of those is
          # a way for the detector to read nothing while looking healthy.
          #
          # HEADERS ARE DROPPED except User-Agent, which is Traefik's default
          # and is restated because it is now load-bearing in two directions:
          # crowdsecurity/traefik-logs reads `request_User-Agent` (the
          # http-bad-user-agent scenario is nothing without it), and a request
          # header set that grew a `Cookie` would put session credentials into
          # a log a second daemon reads.
          accessLog = {
            format = "json";
            fields.headers.defaultMode = "drop";
            fields.headers.names."User-Agent" = "keep";
          };

          # M6: Prometheus metrics, on the dedicated `metrics` entryPoint
          # below.  Entrypoint labels are on — that is what makes
          # traefik_entrypoint_* per-listener — and router/service labels are
          # OFF: they multiply the series count by the number of routes for
          # data nothing here alerts on or graphs, and every route added later
          # would silently widen the TSDB.
          #
          # addServicesLabels stays off for a second reason: the backend
          # addresses are the one thing in this config worth not publishing to
          # an endpoint, even a restricted one.
          metrics.prometheus = {
            entryPoint = "metrics";
            addEntryPointsLabels = true;
            addRoutersLabels = false;
            addServicesLabels = false;
          };

          # THE API AND DASHBOARD ARE OFF, deliberately and by omission: there
          # is no `api` block here at all.  Enabling it would put an
          # unauthenticated read of every route, service and TLS setting behind
          # the one address every VLAN is now allowed to reach.  If it is ever
          # wanted, it belongs behind M7's forward-auth, not behind the
          # ipAllowList — an admin API is not a management-network problem.
          #
          # EVERY ADDRESS BELOW IS `0.0.0.0:` AND NOT `:` — see IPv4-ONLY BY
          # CONSTRUCTION in the file header.  A bare `:443` binds the v6
          # wildcard too, and a v6 listener is a path that bypasses the
          # UDM-Pro's DNAT and therefore bypasses the `wan` entrypoint.
          entryPoints = {
            # :80 does nothing but redirect, and is INTERNAL ONLY — it is not
            # forwarded from the WAN and must not be.  `permanent = true` is a
            # 308, so clients and TV apps cache it and stop asking.
            web = {
              address = "0.0.0.0:80";
              http.redirections.entryPoint = {
                to = "websecure";
                scheme = "https";
                permanent = true;
              };
            };

            # ── M18: THE INTERNET.  Nothing else on this box listens to it ───
            #
            # The UDM-Pro DNATs WAN :443 here.  A router reaches this listener
            # if and only if it names `wan`, and `wanExposed` in the let block
            # above is the complete list — see TWO ENTRYPOINTS in the header
            # for the measurement that this is actually true, and for the one
            # way it can be made false (a router that omits `entryPoints`),
            # which `withWan` turns into a build failure.
            #
            # NO `http.tls.certResolver` AND NO `domains`, deliberately.  The
            # certificate store is global and entrypoint-independent —
            # measured — so this listener serves the same wildcard
            # `websecure`'s resolver already obtained.  Declaring a second
            # request for the same main+sans would put a duplicate issuance
            # against Let's Encrypt's 5-per-week limit in the path of a
            # milestone that cannot be tested before deploying; NOT declaring
            # it fails loudly and for free, as a browser warning naming
            # TRAEFIK DEFAULT CERT.  `http.tls = { }` still turns TLS on.
            ${wanEntryPoint} = {
              address = "0.0.0.0:${toString wanPort}";
              http.tls = {};

              # See THE 60-SECOND CEILING on `websecure` below.  30 minutes
              # here rather than an hour, and the difference is the threat
              # model rather than the file sizes: this listener is the
              # internet, and readTimeout is the only thing bounding a client
              # that opens a request and dribbles a body at one byte per
              # second.  What makes raising it acceptable at all is that such
              # a client must hold a slot to do it, and `wan-inflight` caps
              # the slots at 40 — so the cost of the attack is bounded by a
              # control that already exists, not by this number.
              #
              # It is raised rather than left alone because the phones are
              # the case that matters: an FP5 backing up a video over mobile
              # upstream is the client most likely to need more than a minute,
              # and Immich's mobile upload is a single POST with no resume.
              transport.respondingTimeouts.readTimeout = "1800s";
            };

            websecure = {
              address = "0.0.0.0:443";

              # ── THE 60-SECOND CEILING ON EVERY UPLOAD, AND IT WAS INVISIBLE ─
              #
              # Traefik v3 defaults `respondingTimeouts.readTimeout` to 60s,
              # and it bounds "the maximum duration for reading the ENTIRE
              # REQUEST, INCLUDING THE BODY" — not the headers, not idle time.
              # Any POST taking longer than a minute to transfer is killed
              # mid-body however healthy both ends are, logged as 499 because
              # the client is what gets cut off.
              #
              # NOT CONFIGURING IT IS NOT THE SAME AS NOT HAVING ONE, which is
              # the trap this file fell into: `respondingTimeouts` appeared
              # nowhere, and that was once read as "no timeout is set" when
              # unset means the default.
              #
              # MEASURED 2026-09-14, which turned it from a theory into a
              # number.  A 1.1 GB video died with
              #
              #   DownstreamStatus 499   Duration 59999986474 ns   (= 60.000 s)
              #   RequestContentSize 897340887                     (856 MB sent)
              #
              # The eight other errors in that run share the same END instant
              # but have durations of 39 s, 3.4 s and 125 ms — immich-go's
              # --on-errors=stop cancelling what was in flight.  One root cause
              # wearing nine hats.
              #
              # AN HOUR, AND WHY IT IS NOT UNBOUNDED.  The staged corpus holds
              # 14 files over 2 GB and a 5 GB maximum; at the ~14 MB/s a single
              # stream gets alongside seven others, 5 GB needs ~6 minutes.
              # `0` would disable the timeout entirely and is the wrong shape
              # of fix — a wedged connection should eventually die, and "no
              # limit" is how the next person inherits a hang with no number to
              # reason about.
              #
              # THIS IS NOT AN IMPORT SETTING.  It is in front of every upload
              # this proxy carries — Immich from both phones, CWA, Jellyfin.
              # The import merely made a pre-existing ceiling visible.
              transport.respondingTimeouts.readTimeout = "3600s";

              # THE WILDCARD IS REQUESTED HERE, ONCE, at the entryPoint — not
              # per router.  This is the difference between one certificate and
              # one certificate per hostname:
              #
              #   Without an explicit `domains` block, Traefik asks the resolver
              #   for a cert covering each router's Host() rule individually.
              #   That still works over DNS-01, but it is four certificates
              #   instead of one, four renewals to fail independently, and four
              #   entries against Let's Encrypt's 50-certs-per-domain-per-week
              #   limit.  It also puts every service NAME into the public CT
              #   logs, which is exactly the disclosure the wildcard avoids.
              #
              # main + sans covers the apex and everything one level below it.
              # A wildcard does NOT match multiple labels: a future
              # foo.bar.goclan.org would need its own entry.
              http.tls = {
                certResolver = "cloudflare";
                domains = [
                  {
                    main = baseDomain;
                    sans = ["*.${baseDomain}"];
                  }
                ];
              };
            };

            # M6.  Plain HTTP, no TLS, no certResolver: this listener is
            # reachable from exactly one address on the same bridge (see the
            # firewall rule above), the hop never leaves the host, and asking
            # the ACME resolver for a certificate here would put a fourth
            # name in the wildcard's place for no reader.
            metrics.address = "0.0.0.0:${toString metricsPort}";
          };

          certificatesResolvers.cloudflare.acme = {
            email = acmeEmail;
            storage = "${dataDir}/acme.json";

            # STAGING, for when something here changes.  Let's Encrypt's
            # production endpoint allows 5 duplicate certificates per week; a
            # wrong provider config that retries can burn that in an afternoon
            # and leave the household without a working proxy for six days.
            # Uncomment to point at staging (its certs are untrusted — the
            # browser warning is expected and is the signal it worked), verify
            # issuance in the log, then re-comment AND delete acme.json before
            # switching back, because the two CAs share the one store:
            #
            #   caServer = "https://acme-staging-v02.api.letsencrypt.org/directory";

            dnsChallenge = {
              provider = "cloudflare";

              # PUBLIC resolvers.  `resolvers` is what lego uses to find the
              # challenge name's AUTHORITY (Traefik's own help text: "Use
              # following DNS servers to resolve the FQDN authority"); it then
              # checks the TXT against the authoritative nameservers it found.
              #
              # Kept explicit rather than inheriting the container's resolver.
              # As deployed that inheritance would happen to work — Technitium
              # hosts one small zone per SERVICE name (jellyfin.goclan.org and
              # friends) and is not authoritative for goclan.org itself, so it
              # would recurse for _acme-challenge and get the right answer.
              # That is a property of how the zones were laid out on 2026-08-23,
              # not of the design: hosting the whole goclan.org zone internally
              # would make Technitium authoritative, and it would then answer an
              # authoritative NXDOMAIN for _acme-challenge forever.  Pinning
              # public resolvers makes the correct behaviour independent of that
              # choice.  (An earlier revision of this comment asserted the
              # Technitium-authoritative case as fact.  It was a prediction, and
              # it did not fire — the thing that did is below.)
              resolvers = ["1.1.1.1:53" "9.9.9.9:53"];

              # ── THE 30-MINUTE NEGATIVE CACHE.  MEASURED ON ernst 2026-08-23 ──
              #
              # Without this delay, issuance fails on a race lego loses to
              # itself, and then keeps losing:
              #
              #   1. lego writes the TXT record at Cloudflare.
              #   2. ~1 s later it asks 9.9.9.9 for the authority of
              #      _acme-challenge.goclan.org.  Cloudflare's edge has not
              #      published yet, and Cloudflare answers a nonexistent name
              #      with NXDOMAIN — not NODATA.
              #   3. goclan.org's SOA minimum is 1800.  9.9.9.9 therefore caches
              #      that NXDOMAIN for THIRTY MINUTES.
              #   4. lego polls every 2 s for 120 s, hits its own poisoned cache
              #      every time, and times out.  Traefik retries, still inside
              #      the 30-minute window, and fails identically.
              #
              # The observed error names the mechanism exactly, which is the only
              # reason it was cheap to find:
              #   "recursive nameservers: NS 9.9.9.9:53 returned NXDOMAIN for
              #    _acme-challenge.goclan.org"
              # while the record was demonstrably live at the authoritative
              # servers the whole time:
              #   dig +short @jamie.ns.cloudflare.com TXT _acme-challenge.goclan.org
              #
              # 60 s, against a Cloudflare edge that publishes in about five.
              # The point is not the margin — it is that the FIRST query happens
              # after the record exists, so the negative cache is never created
              # and there is nothing to wait out.  The 120 s propagation check
              # still runs afterwards; this only moves when it starts.
              #
              # DO NOT "fix" this with propagation.disableChecks instead.  That
              # hands the record to Let's Encrypt unverified, and a premature
              # hand-off burns failed-validation rate limit with no local signal
              # at all.  The check is worth keeping; it just must not run before
              # the thing it checks for exists.
              #
              # IF IT STILL FAILS with NXDOMAIN after this: a poisoned entry is
              # already cached from an earlier attempt.  Nothing in the config
              # can clear it — wait out the 30 minutes, or verify with
              # `dig @9.9.9.9 TXT _acme-challenge.goclan.org` (NOERROR means the
              # cache is clean) before restarting the container.
              propagation.delayBeforeChecks = "60s";
            };
          };
        };

        ########################################################################
        # DYNAMIC configuration — routers, services, middlewares.
        ########################################################################
        dynamicConfigOptions = {
          http.middlewares = {
            # ── M7: Authelia forward-auth ──────────────────────────────────
            #
            # Every request to a protected router is paused here while Traefik
            # asks Authelia whether to continue.  A 2xx lets it through; a 401
            # is turned into the redirect to the portal.
            #
            # trustForwardHeader = FALSE, and this is the setting to get right.
            # It does NOT control whether Authelia is told what the user asked
            # for — Traefik always writes X-Forwarded-Method / -Proto / -Host /
            # -Uri onto the auth request from the ACTUAL request.  What it
            # controls is whether an X-Forwarded-* header that arrived FROM THE
            # CLIENT is passed through instead.  Nothing sits in front of this
            # proxy, so any such header was written by the client, and trusting
            # it would let anyone claim they were asking for a different host
            # than the one they are actually being proxied to.
            #
            # (Authelia's own Traefik documentation shows `true`.  That is
            # written for deployments behind a CDN or an upstream load
            # balancer, where the real client details only exist in those
            # headers.  This is not one, and `false` is the safe end of the
            # same switch.  It is the same argument the deleted ipAllowList
            # rested on: peer address, not headers.)
            #
            # authResponseHeaders copies the authenticated identity onto the
            # request that finally reaches the backend.  Nothing behind here
            # consumes them today — the *arr have no header auth and Grafana
            # uses OIDC rather than auth proxy — but they are what a future
            # `auth.proxy` mode would read, and they are free.
            #
            # A NOTE ON WHAT THIS DOES NOT DO: it authenticates the REQUEST,
            # not the API key.  Sonarr's and Radarr's own API keys still work
            # for anything that can reach their ports, which after M5 is this
            # container and nothing else.  Forward-auth is the outer boundary;
            # mechanism (a) is still the inner one.
            authelia.forwardAuth = {
              address = "http://${autheliaAddr}:${toString autheliaPort}/api/authz/forward-auth";
              trustForwardHeader = false;
              authResponseHeaders = [
                "Remote-User"
                "Remote-Name"
                "Remote-Email"
                "Remote-Groups"
              ];
            };

            # ── M18: the two limits, and they are on the wan routers ONLY ────
            #
            # Attached by `withWan` above and by nothing else, so the
            # household's internal requests through `websecure` are not
            # metered.  That is the entire reason the external routers are
            # separate routers rather than a second entryPoint on the existing
            # ones.
            #
            # BOTH OF THESE KEY ON THE PEER ADDRESS, and so does every CrowdSec
            # decision.  `sourceCriterion` is left at its default — Traefik's
            # ipStrategy with depth 0, i.e. the address the connection actually
            # came from, NOT an X-Forwarded-For hop.  That is the same call
            # `trustForwardHeader = false` makes above and for the same reason:
            # nothing sits in front of this proxy, so any XFF header was
            # written by the client.
            #
            # WHICH MAKES THEM WORTH EXACTLY AS MUCH AS Q2's ANSWER.  If the
            # UDM-Pro SNATs the forward instead of preserving the source, every
            # external request arrives from 10.0.90.1 and these become a single
            # global cap that one client can exhaust for everyone — and a
            # CrowdSec ban on the gateway address would take the whole house
            # off Jellyseerr.  crowdsec.nix therefore ships in SIMULATION until
            # Q2 is confirmed from the access log; read its header before
            # flipping it.
            #
            # THE NUMBERS ARE A FIRST CUT and are stated as such.  Jellyseerr
            # is a poster wall: one page view is dozens of image GETs, and the
            # measured internal traffic through this proxy is ~2200 requests an
            # hour across every service.  50/s average with a 100 burst is
            # comfortably above one human browsing and far below a scanner.
            # The trigger to change them is a household member being limited,
            # or a flood that passes — not tidiness.
            wan-ratelimit.rateLimit = {
              average = 50;
              burst = 100;
              period = "1s";
            };

            # Concurrency, which the rate limit does not cover: 50/s of
            # requests that each take 30 s is not a rate problem, it is 1500
            # open connections to Jellyseerr's single-threaded Node process.
            wan-inflight.inFlightReq.amount = 40;

            # ── 2026-09-08: THE LOGIN LIMIT.  A DIFFERENT NUMBER, DELIBERATELY ─
            #
            # `wan-ratelimit` above is sized for BROWSING — 50/s, because a
            # Jellyseerr poster wall is dozens of image GETs per page view and
            # a Jellyfin client polls.  That number is useless against
            # credential stuffing: 50 password guesses per second is 4.3
            # million a day.
            #
            # Authentication has the opposite shape.  A human logs in once and
            # then does not log in again for weeks; an app stores its token.
            # So the login paths get their own routers (below) carrying this
            # instead, and the two limits stop having to be one compromise
            # number.
            #
            # THIS IS THE COMPENSATION FOR `appApiHosts` BEING UNAUTHENTICATED
            # AT THE PROXY.  Those names are answered by the application, so
            # Authelia's per-user regulation — three failures in five minutes
            # then a fifteen-minute ban — does not apply to any of them.  This
            # is the nearest equivalent that works without a browser, and it
            # is the reason the login routers exist at all.
            #
            # 1 per 10 s average, burst 5.  Sized so a human fat-fingering a
            # password twice never notices, and a script gets ~6 attempts in
            # the first minute and 6/min thereafter.  That is slow enough that
            # CrowdSec's 401 scenario (containers/crowdsec.nix) reaches its
            # threshold and bans at the packet layer long before a wordlist
            # goes anywhere.  The two controls are meant to compose: this one
            # slows, CrowdSec stops.
            #
            # period is 10s with average 1 rather than average 0.1/1s, because
            # Traefik's rateLimit takes an integer average — a fractional rate
            # is expressed by lengthening the period.
            wan-login-ratelimit.rateLimit = {
              average = 1;
              burst = 5;
              period = "10s";
            };
          };

          # ── M18: THE GUARD.  Do not remove it to "fix" a build error ───────
          #
          # EVERY ROUTER BELOW IS LAN-ONLY AND UNTOUCHED BY M18.  `withWan`
          # checks them (see the let block) and then ADDS the external routers
          # by copying the ones `wanExposed` names onto the `wan` entrypoint —
          # so `jellyseerr-wan` and `authelia-wan` do not appear in this block
          # at all, and cannot disagree with their twins about rule, service or
          # forward-auth.
          #
          # It throws at evaluation if a router omits `entryPoints` (Traefik
          # would bind such a router to the internet), if `wanExposed` names a
          # router that does not exist, or if any router puts itself on `wan`
          # by hand.  The argument and the measurement are in the TWO
          # ENTRYPOINTS block at the top of this file.
          #
          # If this throws: the fix is an `entryPoints` line on the new router,
          # or an entry in `wanExposed` plus a public A record plus a ledger
          # row.  It is never to delete the wrapper.
          http.routers = withWan {
            # ── Jellyfin: the household route ──────────────────────────────
            #
            # NO MIDDLEWARE, and never a forward-auth one.  See "JELLYFIN KEEPS
            # NATIVE AUTH, FOREVER" in the file header.
            jellyfin = {
              rule = "Host(`jellyfin.${baseDomain}`)";
              entryPoints = ["websecure"];
              service = "jellyfin";
            };

            # ── Authelia: the portal itself (M7) ───────────────────────────
            #
            # NO MIDDLEWARE, necessarily.  This is the route the forward-auth
            # redirect POINTS AT, so putting the middleware on it would send
            # an unauthenticated user to a page that redirects them to itself.
            #
            # It is also the route Grafana's OIDC flow uses server-side: the
            # authorization redirect, the token exchange and the userinfo call
            # all land here.  That is why authelia.nix's access-control block
            # needs no bypass rules — none of those requests is ever forwarded
            # for authorization in the first place.
            #
            # Reachable from every zone the `Allow Traefik` ZBF rule permits,
            # which after L5's retirement includes IoT.  What is exposed there
            # is a login form with a two_factor policy and regulation behind
            # it; see authelia.nix.
            #
            # M18: THIS ROUTER IS UNCHANGED AND IS STILL LAN-ONLY.  The portal
            # reaches the internet through `auth-wan`, generated from
            # `wanExposed` — a separate router on the `wan` entrypoint carrying
            # the rate limits.  It is on the external set for the reason M16
            # recorded as a corrected premise: forward-auth is a redirect
            # protocol, so no external login can complete unless the portal
            # resolves and routes from outside.  What the internet meets there
            # is this login form, per-user regulation (3 failures / 5 min → 15
            # min ban) and mandatory 2FA — which was the design intent.
            authelia = {
              rule = "Host(`auth.${baseDomain}`)";
              entryPoints = ["websecure"];
              service = "authelia";
            };

            # ── The arr stack: admin routes, behind Authelia ───────────────
            #
            # THREE HOSTNAMES, NOT THREE PATH PREFIXES.  containers/arr/
            # anticipated this ("M5 can route three paths to one address
            # perfectly well") and subdomains are the better of the two:
            # Sonarr, Radarr and Prowlarr all need a matching `UrlBase` set in
            # their own settings before they will work under a path prefix, and
            # a missing UrlBase presents as a UI that loads a blank page with
            # 404s on every asset.  Distinct hostnames need no UrlBase at all,
            # so there is nothing to keep in step between this file and three
            # web UIs.
            prowlarr = {
              rule = "Host(`prowlarr.${baseDomain}`)";
              entryPoints = ["websecure"];
              middlewares = ["authelia"];
              service = "prowlarr";
            };
            sonarr = {
              rule = "Host(`sonarr.${baseDomain}`)";
              entryPoints = ["websecure"];
              middlewares = ["authelia"];
              service = "sonarr";
            };
            radarr = {
              rule = "Host(`radarr.${baseDomain}`)";
              entryPoints = ["websecure"];
              middlewares = ["authelia"];
              service = "radarr";
            };

            # ── M12's three, same treatment ────────────────────────────────
            #
            # Ordinary routers on names the M5 wildcard certificate already
            # covers, riding the permanent `Allow Traefik` ZBF rule.  NOT
            # shims, so they get no interim-rule ledger row — the roadmap says
            # as much for M13's and M15's routes and the reasoning is the
            # same: this is architecture invariant #3 working as designed.
            #
            # `authelia`, not `mgmt-only`.  M7 deleted mgmt-only (ledger row
            # L5) and these are admin-facing browser UIs, which is exactly the
            # case forward-auth is for.
            #
            # ADDING A NAME HERE IS HALF THE JOB.  authelia.nix's
            # access_control is deny-by-default, so a route carrying this
            # middleware with no matching domain in `protectedHosts` fails
            # CLOSED.  All three are added there in the same commit.
            #
            # No UrlBase needed on any of them, for the reason the three above
            # give: distinct hostnames rather than path prefixes.
            bazarr = {
              rule = "Host(`bazarr.${baseDomain}`)";
              entryPoints = ["websecure"];
              middlewares = ["authelia"];
              service = "bazarr";
            };
            cleanuparr = {
              rule = "Host(`cleanuparr.${baseDomain}`)";
              entryPoints = ["websecure"];
              middlewares = ["authelia"];
              service = "cleanuparr";
            };
            # MediathekArr's DOWNLOADER, which is also its setup wizard — the
            # page a human opens to configure the thing.  The indexer half on
            # 5008 is deliberately not routed.
            mediathekarr = {
              rule = "Host(`mediathekarr.${baseDomain}`)";
              entryPoints = ["websecure"];
              middlewares = ["authelia"];
              service = "mediathekarr";
            };

            # ── Tvheadend (M8): admin route, behind Authelia ───────────────
            #
            # Same treatment as the *arr routers: an admin-facing browser UI
            # with no TV/mobile client that a forward-auth redirect could
            # break — the household never opens this page; they watch Live TV
            # through Jellyfin, whose own router above stays middleware-free.
            # The name is in authelia.nix's protectedHosts in the same
            # commit (deny-by-default: middleware without the name fails
            # CLOSED as a 403).
            tvheadend = {
              rule = "Host(`tvheadend.${baseDomain}`)";
              entryPoints = ["websecure"];
              middlewares = ["authelia"];
              service = "tvheadend";
            };

            # ── TubeSync (M9): admin route, behind Authelia ────────────────
            #
            # Browser-only and admin-facing, so the *arr treatment applies and
            # the Jellyfin carve-out does not — there is no TV or mobile
            # client here that a forward-auth redirect could break.
            #
            # containers/tubesync.nix explains why its own HTTP_USER/HTTP_PASS
            # basic auth is NOT used as a second layer: it would answer in the
            # `Authorization` header, which Authelia consumes as its own
            # credential and rejects.  M8 paid for that lesson with Tvheadend.
            tubesync = {
              rule = "Host(`tubesync.${baseDomain}`)";
              entryPoints = ["websecure"];
              middlewares = ["authelia"];
              service = "tubesync";
            };

            # ── M14's five, and one of them is NOT like the others ─────────
            #
            # Four operator tools behind `authelia`, in the usual shape:
            # lidarr, kapowarr, questarr and storyteller.  Nothing new to say
            # about those — they are admin-facing browser UIs on names the M5
            # wildcard already covers, riding the permanent `Allow Traefik` ZBF
            # rule, so none of them is a shim and none gets a ledger row.
            #
            # AUDIOBOOKSHELF IS THE EXCEPTION, and it is the THIRD permanent
            # bypass in this fleet.  See its router below.
            lidarr = {
              rule = "Host(`lidarr.${baseDomain}`)";
              entryPoints = ["websecure"];
              middlewares = ["authelia"];
              service = "lidarr";
            };
            kapowarr = {
              rule = "Host(`kapowarr.${baseDomain}`)";
              entryPoints = ["websecure"];
              middlewares = ["authelia"];
              service = "kapowarr";
            };
            questarr = {
              rule = "Host(`questarr.${baseDomain}`)";
              entryPoints = ["websecure"];
              middlewares = ["authelia"];
              service = "questarr";
            };
            # ── Bindery (M17): admin route, behind Authelia ────────────────
            #
            # The *arr treatment: an operator-facing browser UI with no TV or
            # mobile client a forward-auth redirect could break — the
            # household asks for books the same way it asks for films, and
            # READS them in Audiobookshelf/Storyteller, never here.  The name
            # is in authelia.nix's protectedHosts in the same commit
            # (deny-by-default: middleware without the name fails CLOSED).
            bindery = {
              rule = "Host(`bindery.${baseDomain}`)";
              entryPoints = ["websecure"];
              middlewares = ["authelia"];
              service = "bindery";
            };
            # ── Audiobookshelf (M14): NO MIDDLEWARE.  A permanent bypass ────
            #
            # In `appApiHosts` (./ingress-policy.nix), which owns the
            # client-compatibility argument: the apps speak the REST API with
            # a bearer token and have no browser to follow a 302.
            #
            # THE THIRD PERMANENT BYPASS IN THE FLEET, alongside Jellyfin's
            # native auth and the qBittorrent WebUI — a `—` row in
            # docs/ledger.md, so it is not mistaken for something to "fix"
            # later by adding the middleware back.
            #
            # Audiobookshelf's own accounts are then the ENTIRE boundary, with
            # two non-theoretical consequences:
            #
            #   1. ITS FIRST-RUN WIZARD IS UNAUTHENTICATED BY CONSTRUCTION.
            #      With no root account yet, the setup page creates one for
            #      whoever loads it first, reachable from every consumer VLAN
            #      the moment the Technitium record resolves.  THE ADMIN
            #      ACCOUNT MUST BE CREATED IMMEDIATELY after the first deploy.
            #   2. THERE IS NO SECOND FACTOR ON THIS NAME.  Authelia's
            #      per-user regulation and 2FA do not apply.
            #
            # DO NOT MERGE THIS REASONING WITH JELLYSEERR'S EXEMPTION, which
            # rests on its posture being a Jellyfin-account login — dropping
            # forward-auth there swaps one login for another.  This one is the
            # client-compatibility clause.
            audiobookshelf = {
              rule = "Host(`audiobookshelf.${baseDomain}`)";
              entryPoints = ["websecure"];
              service = "audiobookshelf";
            };

            # ── Komga: app-API tier, no forward-auth ──────────────────────
            #
            # In `appApiHosts`: Komelia, Mihon's Komga source and every OPDS
            # reader authenticate with HTTP Basic or an API key against
            # /api/** and /opds/**, with no browser.
            #
            # THE KIDS' LIBRARIES ARE NOT BYPASSED BY THIS, which is the one
            # question exposing Komga raises.  Komga enforces per-user library
            # grants, age restrictions and label filtering INSIDE the
            # application on every API and OPDS path, keyed on the
            # authenticated principal rather than on which vhost the request
            # arrived through; there is no "internal" path that skips them.  A
            # public vhost changes WHO CAN REACH THE LOGIN, not what an account
            # may see past it.  Verify by logging in as a restricted account
            # through the external name and confirming the library list is
            # short — it is in the PR test plan because it must not be assumed.
            #
            # NO SEPARATE ADMIN SURFACE TO KEEP OFF THIS VHOST: Komga's
            # administration is a role on an ordinary account on the same
            # origin, with no port or path prefix to split.  "Keep admin
            # surfaces off the public vhost" is the policy elsewhere here and
            # cannot be honoured; the compensation is a strong admin credential
            # and no first-run window (Komga creates no account until one is
            # posted).
            komga = {
              rule = "Host(`komga.${baseDomain}`)";
              entryPoints = ["websecure"];
              service = "komga";
            };

            # ── Navidrome: app-API tier, no forward-auth ──────────────────
            #
            # The Subsonic API at /rest/** puts the credential in the query
            # string of every request — that is the protocol, not a Navidrome
            # choice — and Tempo, Symfonium and play:Sub speak only that.
            # Forward-auth cannot be expressed in it at all.
            #
            # SERVER-SENT EVENTS, A PROPERTY TO PRESERVE: Navidrome pushes scan
            # progress and now-playing over SSE on /api/events.  Traefik does
            # not buffer responses unless a `buffering` middleware is attached,
            # and none is attached here or inherited by the wan routers.
            # Adding one later — here or to the wan chain — breaks the stream
            # and presents as "the UI stops updating", not as an error.
            navidrome = {
              rule = "Host(`navidrome.${baseDomain}`)";
              entryPoints = ["websecure"];
              service = "navidrome";
            };

            # ── CWA: app-API tier, no forward-auth on this router ─────────
            #
            # THREE app protocols, none able to follow a redirect: OPDS (basic
            # auth), the Kobo sync endpoint (a device token in the URL path; a
            # Kobo has no browser at all), and /kosync (KOReader, custom
            # header auth).
            #
            # THE WEB UI GETS A DIFFERENT ANSWER.  CWA speaks OIDC natively, so
            # the browser surface is wired to Authelia's OIDC provider INSIDE
            # the application rather than to forward-auth at the proxy — see
            # containers/cwa.nix.  Real 2FA-backed auth for the web UI without
            # a middleware the e-reader would choke on, which a proxy-level
            # bypass alone cannot reach.
            cwa = {
              rule = "Host(`cwa.${baseDomain}`)";
              entryPoints = ["websecure"];
              service = "cwa";
            };

            # ── Storyteller: NO forward-auth, and NOT on `wan` ────────────
            #
            # The middleware came off 2026-09-27: the Reader app POSTs to
            # /api/v2/token to get a credential, and forward-auth answered that
            # very call with a 303 to auth.goclan.org — measured.  A client
            # with no browser cannot follow it, so the app could never obtain a
            # credential at all.  Same clause as audiobookshelf, komga,
            # navidrome and cwa; the reasoning is in ingress-policy.nix.
            #
            # `websecure` ONLY, and deliberately absent from `wanExposed`.
            # This name answers the LAN and the VPN, never the public
            # internet, which is what makes dropping forward-auth a smaller
            # decision here than for the WAN names.
            storyteller = {
              rule = "Host(`storyteller.${baseDomain}`)";
              entryPoints = ["websecure"];
              service = "storyteller";
            };

            # ── RomM: admin route, behind Authelia ────────────────────────
            #
            # NOT one of the client-compatibility carve-outs.  RomM has its own
            # login and an in-browser EmulatorJS player, but every consumer is
            # a browser — the Deck reads its games from a Syncthing replica on
            # local disk, not through this route — so there is no native client
            # whose token handling a forward-auth redirect could break.  That
            # is exactly the argument Jellyfin and Audiobookshelf won and this
            # one does not get to.
            romm = {
              rule = "Host(`romm.${baseDomain}`)";
              entryPoints = ["websecure"];
              middlewares = ["authelia"];
              service = "romm";
            };

            # Open WebUI (M19) — the local-AI chat client.
            #
            # THIS ROUTER NAMES `websecure` ONLY AND IS EXPOSED ANYWAY.  Not a
            # conflict — exposure is never an entryPoints edit here, it is an
            # entry in `wanExposed`, which makes `mkWan` generate a SECOND
            # router (`openwebui-wan`).  Adding "wan" here by hand throws at
            # evaluation.  The posture argument is on `wanExposed` above.
            #
            # `authelia` like every other admin surface.  It ALSO speaks OIDC
            # to the same provider (containers/authelia.nix): the middleware
            # decides whether the request arrives, OIDC decides whose it is.
            # Both matter on an internet-facing path.
            openwebui = {
              rule = "Host(`chat.${baseDomain}`)";
              entryPoints = ["websecure"];
              middlewares = ["authelia"];
              service = "openwebui";
            };

            # ── Immich (M22): app-API tier, no forward-auth ────────────────
            #
            # In `appApiHosts`, and the third client class is the one worth
            # reading twice:
            #
            #   the mobile app on two phones — bearer tokens, no browser;
            #   the Kodi add-on on the TV — `x-api-key` over http.client;
            #   A SHARED ALBUM LINK — answered to an ANONYMOUS caller, by
            #   design, which is how someone with no account here sees an
            #   album at all.
            #
            # UPLOADS COME THROUGH THIS ROUTER, which is the operational thing
            # to know: phone auto-backup and the darktable push both POST whole
            # files, and a 4K video off a phone is not a small request.
            # A PROPERTY TO PRESERVE — Traefik does not buffer request bodies
            # unless a `buffering` middleware is attached, and none is attached
            # here or inherited by the wan router.  Adding one later would make
            # big uploads fail as "the phone stopped backing up" rather than as
            # an error anyone sees.
            immich = {
              rule = "Host(`photos.${baseDomain}`)";
              entryPoints = ["websecure"];
              service = "immich";
            };

            # ── Nextcloud (M23) — NO forward-auth, and the reason is in ────
            #    containers/ingress-policy.nix under `(h "cloud")`.
            #
            # Short form: the desktop sync client, DAVx5 and vdirsyncer all
            # authenticate with app passwords over /remote.php/dav/** and none
            # of them can render a login page or follow a 302.  The BROWSER
            # path is not left open by that — it goes through Authelia's OIDC
            # provider, registered by containers/nextcloud.nix's provisioning
            # unit.  CWA's arrangement, not Grafana's.
            #
            # TWO PROPERTIES OF THIS ROUTER TO PRESERVE, both the same class of
            # invisible-if-broken as the Immich note above:
            #
            #   NO `buffering` MIDDLEWARE, here or on the wan chain this router
            #   inherits.  Nextcloud is a file-sync server; buffering whole
            #   request bodies would make large uploads fail in a way that
            #   presents as "sync is stuck" rather than as an error.
            #
            #   THE readTimeout ON `websecure` (3600s) AND `wan` (1800s) IS
            #   WHAT LETS BIG UPLOADS FINISH.  Those were raised on 2026-09-14
            #   after a 1.1 GB Immich upload died at exactly 60.000 s against
            #   the default; the same ceiling bounds a PUT to this backend,
            #   because it covers the entire request including the body.
            nextcloud = {
              rule = "Host(`cloud.${baseDomain}`)";
              entryPoints = ["websecure"];
              service = "nextcloud";
            };

            # ── Paperless-ngx (M32) — NO forward-auth, and the reason is in ──
            #    containers/ingress-policy.nix under `(h "docs")`.
            #
            # Short form: the Paperless Mobile app on both phones POSTs to
            # /api/token/ once and then sends `Authorization: Token …` on every
            # request.  No browser, so a 302 to the portal arrives as an opaque
            # network error.  The browser path IS handed to Authelia's OIDC
            # provider, which makes this CWA's and Nextcloud's arrangement
            # rather than Home Assistant's.
            #
            # ONE PROPERTY OF THIS ROUTER TO PRESERVE, the same class of
            # invisible-if-broken as the Immich and Nextcloud notes above: NO
            # `buffering` MIDDLEWARE, here or on the wan chain this router
            # inherits.  A phone uploading a multi-page colour scan is a large
            # POST, and buffering the whole body would make it fail as
            # "the upload button does nothing" rather than as an error anyone
            # sees.  The `readTimeout` on `websecure` (3600s) and `wan` (1800s)
            # bounds it and is already generous.
            paperless = {
              rule = "Host(`docs.${baseDomain}`)";
              entryPoints = ["websecure"];
              service = "paperless";
            };

            # ── Home Assistant (M24) — NO forward-auth, and the reason is in ─
            #    containers/ingress-policy.nix under `(h "ha")`.
            #
            # Short form: the companion app exchanges credentials once at
            # /auth/token and then holds an authenticated WebSocket open at
            # /api/websocket for the life of the session.  It has no browser,
            # so a 302 to the portal reaches it as an opaque network error.  It
            # is also the endpoint the app PUSHES location to, in the
            # background, with no user present to log in to anything.
            #
            # UNLIKE Nextcloud AND CWA, THE BROWSER PATH IS NOT HANDED TO
            # AUTHELIA'S OIDC PROVIDER EITHER, and that is worth stating rather
            # than leaving as a gap.  Home Assistant's OIDC support at this
            # version is community-supplied rather than core, and the local
            # account is the recovery path for a house whose lights are on this
            # server.  What defends it instead is named and configured in
            # containers/home-assistant.nix: HA's own `ip_ban_enabled`
            # (per-source, written to ip_bans.yaml) and native TOTP MFA, plus
            # `wan-login-ratelimit` below.  Revisit when core OIDC lands.
            #
            # ONE PROPERTY OF THIS ROUTER TO PRESERVE, the same class of
            # invisible-if-broken as the Immich and Nextcloud notes above: NO
            # `buffering` MIDDLEWARE, here or on the wan chain this router
            # inherits.  A buffering middleware consumes the response before
            # forwarding it, which would break the WebSocket upgrade and
            # present as "the app never connects" rather than as an error.
            homeassistant = {
              rule = "Host(`ha.${baseDomain}`)";
              entryPoints = ["websecure"];
              service = "homeassistant";
            };

            # ── Miniflux (M27) — the feed reader ──────────────────────────
            #
            # `authelia` MIDDLEWARE, AND IT DID NOT SHIP THAT WAY.  This name
            # was in `appApiHosts` with no middleware, on an argument about
            # Miniflux's Fever and Google Reader APIs — protocols that are real
            # and that nobody in this house uses.  It moved to `protectedHosts`
            # when off-LAN access was wanted, because forward-auth in front is
            # a better answer than an unauthenticated vhost on the internet.
            # containers/ingress-policy.nix carries the full argument and the
            # cost.
            #
            # THE GUARD BELOW ENFORCES THE PAIRING: a `protectedHosts` name
            # MISSING this middleware throws at evaluation, which is the
            # fail-open direction and the one worth catching.
            #
            # IT ALSO KEEPS ITS OIDC CLIENT, so this is now GRAFANA's
            # arrangement — forward-auth decides whether the request arrives,
            # OIDC decides whose it is — and no longer CWA's.  Do not read the
            # two as interchangeable for this name.
            #
            # NO `wanLoginPaths` ENTRY, and its absence is correct rather than
            # an oversight: that mechanism substitutes a credential-endpoint
            # rate limit for the per-identity regulation `appApiHosts` names
            # never get.  This name goes through Authelia, which already has it
            # — 3 attempts in 5 minutes, per user rather than per path.  Same
            # reasoning as `homepage`.
            miniflux = {
              rule = "Host(`miniflux.${baseDomain}`)";
              entryPoints = ["websecure"];
              middlewares = ["authelia"];
              service = "miniflux";
            };

            # ── MTA-STS (M31) — one static file, for remote mail servers ──
            #
            # NO `authelia` MIDDLEWARE, and this is the least arguable
            # exemption on the proxy.  Every other `appApiHosts` entry is a
            # judgement about whether some client could follow a 302; here the
            # clients are GMAIL'S AND OUTLOOK'S MTAs fetching a policy file
            # before they will talk TLS to us, and an MTA has no browser, no
            # session and no human.  A login page would simply mean the policy
            # is unreadable and the feature off.
            #
            # IT PUBLISHES NOTHING PRIVATE.  The file's entire content is the
            # MX hostname, which is already a public DNS record — this is the
            # one exemption where there is no secret behind the door at all.
            #
            # THE BACKEND IS THE MAIL CONTAINER, which is otherwise not on this
            # proxy at all (containers/mail.nix, convention 1).  That is
            # deliberate: the policy names this server's own MX, so the two
            # live together and cannot drift.
            mtasts = {
              rule = "Host(`mta-sts.${baseDomain}`)";
              entryPoints = ["websecure"];
              service = "mtasts";
            };

            # ── Karakeep (M27) — bookmarks and page archives ──────────────
            #
            # NO `authelia` MIDDLEWARE, same list and same guard.  What makes
            # this entry different from every other exemption on this proxy is
            # that the clients which cannot follow a 302 are ones THIS
            # REPOSITORY INSTALLS — the Karakeep extension and the Floccus
            # adapter, declared for lgo in service-modules/software.nix and
            # modules/users/lgo/browsers.nix.  Moving this name to
            # `protectedHosts` would break an unattended sync between two
            # laptops, which presents as bookmarks quietly failing to
            # propagate rather than as an error anybody sees.
            #
            # ON THE INTERNET (`wanExposed` + ledger row L17), with a
            # `wanLoginPaths` entry above.
            karakeep = {
              rule = "Host(`karakeep.${baseDomain}`)";
              entryPoints = ["websecure"];
              service = "karakeep";
            };

            # ── Music Assistant (M30) — the player controller ──────────────
            #
            # NO `authelia` MIDDLEWARE, AND IT SHIPPED WITH ONE.  The original
            # router carried forward-auth on the argument that this hostname's
            # only client is a browser — and that the hub's WebSocket did not
            # count, because it reached the container directly on 10.0.90.30:8095
            # and never came through here.  The second half is wrong, which makes
            # the first half wrong too.
            #
            # `homeassistant/components/music_assistant/config_flow.py` builds
            # `login_url = f"{self.url}/login?…"` and hands it to
            # `async_external_step`, so the ONE url typed into the config flow is
            # used for BOTH the browser redirect AND the hub's own server-side
            # `GET /info`, `POST /auth/login` and persistent `/ws`.  There is no
            # separate internal-address field, and `/ws` is an HTTP UPGRADE with
            # no cookie jar — the same thing that exempts `homeassistant` itself.
            #
            # MEASURED: pointed at the direct address the BROWSER half broke
            # instead, hanging on a blank page, because no human's machine may
            # reach 10.0.90.30. Neither URL satisfies both halves with the
            # middleware attached. containers/ingress-policy.nix carries the full
            # argument and the compensations — which are real here and were read
            # out of the application rather than assumed: its own accounts with
            # roles, `require_authentication()` on the handlers, a `/ws` that
            # tracks an authenticated user and refuses admin commands to a
            # non-ADMIN role, and an escalating per-username login backoff.
            #
            # STILL LAN-ONLY, and that is what keeps this proportionate: it is the
            # ONLY name in `appApiHosts` that is not also in `wanExposed`. No
            # public record, no ledger row, no `wanLoginPaths` entry — that
            # mechanism protects a credential path facing the internet, and this
            # one faces the living room.
            mass = {
              rule = "Host(`music.${baseDomain}`)";
              entryPoints = ["websecure"];
              service = "mass";
            };

            # slskd's web UI — in the microvm guest, not a container.  Behind
            # `authelia` like every other admin surface; its own login exists
            # but is a single shared operator account, not per-user.
            #
            # NOTE ON WEBSOCKETS: this UI is SignalR-driven and holds a
            # persistent connection.  Traefik proxies websockets natively with
            # no extra configuration, which is part of why routing it here is
            # better than the direct path it replaces — that path died on the
            # websocket while ordinary GETs still succeeded.
            slskd = {
              rule = "Host(`slskd.${baseDomain}`)";
              entryPoints = ["websecure"];
              middlewares = ["authelia"];
              service = "slskd";
            };

            # ── Jellyseerr: the HOUSEHOLD route — posture set by M16 ───────
            #
            # Reachable FROM THE INTERNET, and the requirement is that the
            # unauthenticated attack surface on the external path is AUTHELIA,
            # not Jellyseerr's Node application.
            #
            # `jellyseerr-wan` (copied by `withWan`) carries this same
            # `authelia` middleware plus the two external limits, so the AUTH
            # POSTURE IS IDENTICAL on both paths and all that differs is that
            # the household is not rate-limited in its own house.
            #
            # TWO ALTERNATIVES REJECTED, AND STILL REJECTED.  Splitting on
            # ENTRYPOINT is fine — that is which socket the packet arrived on
            # and cannot be mis-classified.  Splitting on CLIENT IDENTITY is
            # what must not happen:
            #
            #   - a second internal-only router keyed on ClientIP with no
            #     middleware FAILS OPEN: anything the matcher mis-classifies is
            #     served unauthenticated.  This shape fails CLOSED — a
            #     mis-classified internal request meets a login form, which is
            #     an inconvenience, not an exposure;
            #   - an Authelia `networks` bypass for RFC1918 sources trusts
            #     X-Forwarded-For arithmetic on the exact boundary this exists
            #     to harden.
            #
            # The cost is that household members hold an Authelia account
            # (group `household` in authelia.nix) alongside their Jellyfin one.
            # Remember-me runs a month, so the friction is periodic.
            #
            # "WHO REQUESTED THIS" IS NOT FLATTENED: forward-auth sits IN FRONT
            # of Jellyseerr, and its own Jellyfin-account login and per-user
            # request attribution continue underneath — exactly as Grafana
            # keeps its local admin under the same middleware.
            #
            # The name is in authelia.nix's access_control via its OWN rule
            # (household + admins), NOT via `protectedHosts`: that list feeds
            # the admins-only rule, and this is the one protected name in the
            # fleet a non-admin must be able to reach.
            jellyseerr = {
              rule = "Host(`jellyseerr.${baseDomain}`)";
              entryPoints = ["websecure"];
              middlewares = ["authelia"];
              service = "jellyseerr";
            };

            # ── Grafana (M6): admin route, behind Authelia ─────────────────
            #
            # Same treatment as the arr — browser only, admin facing — and it
            # was the fourth member of ledger row L5 until M7 retired it.
            #
            # Grafana keeps its OWN login underneath the forward-auth, which
            # is the account that still works when the identity provider is
            # the thing that is broken.  M7 is what made that account
            # REACHABLE again: with this route behind the middleware the local
            # form cannot be got at through this proxy at all, so the
            # break-glass path goes around it entirely, over M6's mon0 veth.
            # It is written out beside services.grafana in
            # service-modules/monitoring.nix — read it before you need it.
            #
            # Nothing special is needed for Grafana's live-tail websockets:
            # Traefik proxies an Upgrade request transparently, and the
            # entryPoint sets no forwardedHeaders that could interfere.
            grafana = {
              rule = "Host(`grafana.${baseDomain}`)";
              entryPoints = ["websecure"];
              middlewares = ["authelia"];
              service = "grafana";
            };

            # ── The service index (M26): admin route, behind Authelia ──────
            #
            # An ordinary protected router, and the only thing worth a note is
            # what it points AT: the arr container's address on a port that
            # containers/arr/ does not mention, because the service is
            # declared in containers/homepage.nix instead.  A reader chasing
            # `homepageAddr` through arr/ will not find it; that file's
            # header and this comment are the two places that say where to
            # look.
            #
            # `authelia`, and this name is in `protectedHosts` in the same
            # commit — a route carrying the middleware with no matching domain
            # in authelia.nix's deny-by-default access_control returns 403 to a
            # user who has just logged in successfully, which is the RomM
            # failure.  The guard below catches the reverse direction too.
            homepage = {
              rule = "Host(`home.${baseDomain}`)";
              entryPoints = ["websecure"];
              middlewares = ["authelia"];
              service = "homepage";
            };
          };

          # Backends are plain HTTP over VLAN 90 — the hop from here to them is
          # a single layer-2 forward inside br0 on this host and never touches a
          # wire.  Terminating TLS again at each backend would mean four more
          # certificates for a link that cannot be observed without already
          # being on ernst.
          #
          # There is deliberately no `passHostHeader = false` anywhere: Traefik
          # forwards the original Host by default, which is what lets Jellyfin
          # generate correct absolute URLs.
          # ── A shorter idle timeout on the pool to Authelia (M7) ───────────
          #
          # LOG HYGIENE, not behaviour.  After M7, authelia-main's journal
          # filled with `status_code=408` "Request timeout occurred" errors
          # from this container's address — one per idle connection, every one
          # of those requests having been served.
          #
          # Authelia's `server.timeouts.read` defaults to 6 s and Traefik holds
          # an idle keep-alive connection for `idleConnTimeout`, default 90 s.
          # Whoever's timer is shorter closes it, and fasthttp logs the close
          # against the LAST request it saw on that connection — which is why
          # the line names a path that completed normally minutes earlier.
          # Making Traefik hang up first (5 s < 6 s) means the connection is
          # always closed by its owner.  The cost is one TCP handshake per
          # burst on a layer-2 hop that never leaves this host.
          #
          # WHY NOT raise Authelia's read timeout: that weakens a real
          # server-side protection (a slow-header client holding a connection)
          # to silence a log line, and it would have to exceed Traefik's 90 s
          # to work at all.  The pool is the thing misbehaving; fix the pool.
          #
          # CONFIRMED ON ernst 2026-08-24: zero 408s after the restart, and not
          # for want of traffic — both accounts registered WebAuthn credentials
          # through this proxy within the half hour, which is exactly the
          # browse-then-idle pattern that produced them.
          #
          # Re-check if a nixpkgs bump moves either default:
          #   nixos-container run authelia -- \
          #     journalctl -u authelia-main --since "30 min ago" | grep -c 408
          # Expect 0.  If it is ever not 0, say so HERE rather than leaving a
          # confirmed-once story to be inherited as permanent truth.
          http.serversTransports.shortIdle.forwardingTimeouts.idleConnTimeout = "5s";

          http.services = {
            jellyfin.loadBalancer.servers = [{url = "http://${jellyfinAddr}:${toString jellyfinPort}/";}];
            prowlarr.loadBalancer.servers = [{url = "http://${arrAddr}:${toString prowlarrPort}/";}];
            sonarr.loadBalancer.servers = [{url = "http://${arrAddr}:${toString sonarrPort}/";}];
            radarr.loadBalancer.servers = [{url = "http://${arrAddr}:${toString radarrPort}/";}];

            # M12 — same container, same address, three more ports.
            bazarr.loadBalancer.servers = [{url = "http://${arrAddr}:${toString bazarrPort}/";}];
            cleanuparr.loadBalancer.servers = [{url = "http://${arrAddr}:${toString cleanuparrPort}/";}];
            mediathekarr.loadBalancer.servers = [{url = "http://${arrAddr}:${toString mediathekarrPort}/";}];

            # M13 — same container, same address, one more port.
            jellyseerr.loadBalancer.servers = [{url = "http://${arrAddr}:${toString jellyseerrPort}/";}];

            # M26 — the same address again, from containers/homepage.nix.
            homepage.loadBalancer.servers = [{url = "http://${arrAddr}:${toString homepagePort}/";}];

            # M8 — its own container on .18.
            tvheadend.loadBalancer.servers = [{url = "http://${tvheadendAddr}:${toString tvheadendPort}/";}];

            # M9 — its own address, in a podman netns on VLAN 90.
            tubesync.loadBalancer.servers = [{url = "http://${tubesyncAddr}:${toString tubesyncPort}/";}];

            # M14 — four more ports on the arr container's address …
            lidarr.loadBalancer.servers = [{url = "http://${arrAddr}:${toString lidarrPort}/";}];
            kapowarr.loadBalancer.servers = [{url = "http://${arrAddr}:${toString kapowarrPort}/";}];
            questarr.loadBalancer.servers = [{url = "http://${arrAddr}:${toString questarrPort}/";}];
            audiobookshelf.loadBalancer.servers = [{url = "http://${arrAddr}:${toString audiobookshelfPort}/";}];

            # 2026-09-08.  Two more on the arr container's existing address,
            # and one on the podman tier.
            komga.loadBalancer.servers = [{url = "http://${arrAddr}:${toString komgaPort}/";}];
            navidrome.loadBalancer.servers = [{url = "http://${arrAddr}:${toString navidromePort}/";}];
            cwa.loadBalancer.servers = [{url = "http://${cwaAddr}:${toString cwaPort}/";}];

            # M17 — a fifth port on the arr container's address.
            bindery.loadBalancer.servers = [{url = "http://${arrAddr}:${toString binderyPort}/";}];

            # … and one more podman netns of its own, the tier's second.
            storyteller.loadBalancer.servers = [{url = "http://${storytellerAddr}:${toString storytellerPort}/";}];
            romm.loadBalancer.servers = [{url = "http://${rommAddr}:${toString rommPort}/";}];
            openwebui.loadBalancer.servers = [{url = "http://${openWebuiAddr}:${toString openWebuiPort}/";}];

            # M22 — its own nspawn container on .25.
            immich.loadBalancer.servers = [{url = "http://${immichAddr}:${toString immichPort}/";}];

            # M23 — its own nspawn container on .26, answering on plain 80
            # from the module's own nginx.
            nextcloud.loadBalancer.servers = [{url = "http://${nextcloudAddr}:${toString nextcloudPort}/";}];
            paperless.loadBalancer.servers = [{url = "http://${paperlessAddr}:${toString paperlessPort}/";}];

            # M24 — its own nspawn container on .27.  Plain HTTP, and a
            # WebSocket rides the same backend; Traefik proxies the upgrade with
            # no configuration as long as nothing buffers.
            homeassistant.loadBalancer.servers = [{url = "http://${homeassistantAddr}:${toString homeassistantPort}/";}];

            # M27 — two nspawn containers on .28 and .29.  Plain HTTP on both;
            # neither terminates TLS, because the wildcard is terminated once,
            # here.
            miniflux.loadBalancer.servers = [{url = "http://${minifluxAddr}:${toString minifluxPort}/";}];
            karakeep.loadBalancer.servers = [{url = "http://${karakeepAddr}:${toString karakeepPort}/";}];

            # M31 — nginx inside the MAIL container, serving one static file.
            # The only backend on this proxy that is not a web application;
            # see the router above for why it lives there.
            mtasts.loadBalancer.servers = [{url = "http://${mailAddr}:${toString mtaStsPort}/";}];

            # M30 — its own nspawn container on .30, answering plain HTTP on
            # the API port.  A WebSocket rides the same backend and Traefik
            # proxies the upgrade with no configuration.  The stream server on
            # 8097 is NOT here and must not be — see the note at `massAddr`.
            mass.loadBalancer.servers = [{url = "http://${massAddr}:${toString massPort}/";}];

            # … and one in the microvm guest, the first non-container backend.
            slskd.loadBalancer.servers = [{url = "http://${slskdAddr}:${toString slskdPort}/";}];
            grafana.loadBalancer.servers = [{url = "http://${monitoringAddr}:${toString grafanaPort}/";}];

            # M7.  The same address the forwardAuth middleware above calls,
            # reached over the same plain-HTTP layer-2 hop — one backend, two
            # paths to it.  The portal is a browser-facing route; the
            # middleware's is a server-to-server call on a different path
            # (/api/authz/forward-auth) of the same listener.
            authelia.loadBalancer = {
              servers = [{url = "http://${autheliaAddr}:${toString autheliaPort}/";}];
              serversTransport = "shortIdle";
            };
          };
        };
      };

      # Additional hardening on top of the upstream module.
      #
      # Upstream already sets NoNewPrivileges, CapabilityBoundingSet =
      # cap_net_bind_service (the one capability a proxy binding :443 as an
      # unprivileged user actually needs), PrivateTmp, PrivateDevices,
      # ProtectHome, ProtectSystem = "full" and ReadWritePaths = [ dataDir ].
      # What is added here is the set it omits and that is SAFE INSIDE NSPAWN.
      #
      # THE OMISSIONS ARE THE INTERESTING PART, and they are not oversights.
      # containers/jellyfin.nix records that upstream deliberately disables
      # ProtectKernelTunables / ProtectKernelModules / ProtectControlGroups /
      # RestrictNamespaces / PrivateTmp under `!config.boot.isContainer`,
      # because they conflict with nspawn's own mount-namespace setup and
      # either error at activation or silently no-op.  The traefik module has
      # no such conditional — it is not container-aware — so setting them here
      # would be doing by hand exactly what the jellyfin module refuses to do
      # by machine.  They are left out for that reason, not because they were
      # not considered.
      #
      # PrivateUsers is omitted for a different reason: a user namespace and
      # AmbientCapabilities = cap_net_bind_service interact badly, and the
      # failure is a proxy that cannot bind 443 at all.
      #
      # REJECTED, with reasons:
      #   MemoryDenyWriteExecute = true
      #     Go's runtime does not need W|X pages, so this one would probably
      #     hold — but "probably" on the single service every other service is
      #     now behind, in a milestone that cannot be tested before deploying,
      #     is not a trade worth making.  Revisit with a measurement.
      #   IPAddressAllow / IPAddressDeny
      #     The allow-list would have to include Let's Encrypt, Cloudflare's
      #     API, two public resolvers and every client VLAN — i.e. most of the
      #     internet plus the LAN.  Inbound restriction is the container
      #     firewall's and the UDM-Pro's job.
      systemd.services.traefik.serviceConfig = {
        ProtectClock = true;
        ProtectHostname = true;
        ProtectProc = "invisible";
        RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RemoveIPC = true;
        LockPersonality = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = ["@system-service" "~@privileged" "~@debug" "~@mount"];
        UMask = "0077";
      };

      # `curl` and `dig` are the test plan's instruments: curl proves each
      # backend is reachable from HERE (and, from anywhere else, that it is
      # not), and dig is what checks the split-horizon answer differs from the
      # public one.  `openssl` reads the SANs off the issued certificate.
      environment.systemPackages = with pkgs; [curl dnsutils openssl];
      documentation.enable = false;
      documentation.nixos.enable = false;
    };
  };
}
