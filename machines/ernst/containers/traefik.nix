# machines/ernst/containers/traefik.nix
#
# Traefik v3, in a declarative systemd-nspawn NixOS container.  One reverse
# proxy on its own L2 identity, so every consumer VLAN collapses to a single
# permanent firewall rule pointing at THIS address instead of one rule per
# backend.  That reduction is the milestone; TLS is how it is made usable.
#
# Why nspawn: architecture invariant #1.  Traefik terminates TLS for trusted
# in-house services and never fetches attacker-supplied URLs on anyone's
# behalf, so it is a trusted-tier workload sharing the host kernel.  (The
# thing that DOES render hostile pages is FlareSolverr, and the argument for
# where it lives is in containers/arr.nix.)
#
# ── Networking: veth on br0, Services VLAN 90 ────────────────────────────────
#
#   Copied from containers/jellyfin.nix ("Networking — v2"), which is the
#   WORKING version of this pattern, and followed again by containers/arr.nix:
#   KeepMaster rather than Bridge=, the ExecStartPost that settles the VLAN
#   race, and the 20 s wait-online cap that stops a DHCP failure from
#   restart-looping the container.  Read jellyfin.nix's header for the full
#   rationale — including why this is a veth and not a macvlan or a tap — it is
#   not repeated here.
#
#   MAC 02:00:00:90:00:04 was RESERVED for this container by M2b, in the
#   allocation table in machines/ernst/networking.nix, against DHCP reservation
#   10.0.90.12.  M4 deliberately skipped to .13 so that .12 stayed free for it.
#
#   10.0.90.12 IS THE POINT OF THE MILESTONE.  It is the single address every
#   consumer-zone ZBF rule now targets, and the only address on VLAN 90 that
#   any client VLAN is permitted to reach.  Jellyfin's .10 and the arr's .13
#   stop being reachable from anywhere but here — see BACKEND BYPASS below.
#
#   Addressing is DHCP with a reservation on the UDM-Pro keyed on the pinned
#   MAC, NOT a static address in this file: the UDM-Pro owns the subnet and the
#   pool, and a second copy here diverges silently.  The reservation must be
#   INSIDE the DHCP pool (10.0.90.6–.254) — UniFi accepts an address from the
#   .2–.5 range the cutover runbook set aside and then hands out an ordinary
#   pool lease instead.  M2b lost a round to exactly that.
#
#   The RESOLVER is the opposite call and IS declared here (Technitium,
#   10.0.5.3), because a DHCP-supplied resolver that quietly changes does not
#   fail loudly.  Note the ACME resolvers below are deliberately NOT Technitium
#   — see SPLIT HORIZON.
#
# ── TWO ENTRYPOINTS, AND WHY THAT IS THE WHOLE SECURITY ARGUMENT ─────────────
#
#   M18 replaced the Cloudflare Tunnel with a UDM-Pro port forward.  The tunnel
#   is gone and machines/ernst/containers/cloudflared.nix is deleted, so THIS
#   COMMENT IS NOW THE ONLY PLACE THE ARGUMENT LIVES.  Read it before adding a
#   router, and read docs/roadmap.md M16 for the tunnel-versus-forward history.
#
#   WHAT M16 BOUGHT, PRECISELY.  Not "hides the home IP" — the address was
#   already public and M3 recorded it.  Not DDoS absorption.  What it bought is
#   FAIL-CLOSED-BY-CONSTRUCTION: the tunnel's ingress list named two hostnames,
#   so every OTHER router in this file was not refused from outside, it WAS NOT
#   THERE.  M16 rejected the plain port forward on exactly that ground — with
#   WAN :443 landing on `websecure`, every router here becomes
#   internet-reachable, gated on nothing but middleware correctness, and a
#   middleware one edit from wrong FAILS OPEN.
#
#   HOW THAT PROPERTY IS REPRODUCED HERE.  A SECOND ENTRYPOINT.
#
#     websecure  :443 on 10.0.90.12   LAN only.  Every router that existed
#                                     before M18 names this and only this, and
#                                     none of them was touched.
#     wan        :8443 on 10.0.90.12  the UDM-Pro's DNAT target, and NOTHING
#                                     else.  A router is internet-reachable if
#                                     and only if it names `wan`.
#
#   Creating a Traefik route therefore does NOT expose it.  The default is
#   invisible from outside, and exposure is an explicit, greppable act — one
#   entry in `wanExposed` below — exactly as adding a hostname to the tunnel's
#   ingress list was.
#
#   MEASURED, NOT ASSUMED (scratch Traefik 3.7.10, 2026-09-03).  The premise
#   was tested before this config was written, because the milestone rests on
#   it entirely:
#
#     - a `websecure`-only router requested on the `wan` entrypoint is
#       UNMATCHED: 404, no backend contact.  The control — the same request for
#       a router that DOES name `wan` — returned 502 from the (absent) backend,
#       which is what proves routing happens at all and the 404 is a real miss;
#     - unknown SNI and no-SNI on `wan` also 404;
#     - the TLS handshake COMPLETES first, with `CN=TRAEFIK DEFAULT CERT`.  So
#       this is 404-from-Traefik-with-a-cert, NOT "unrouted".  Stated plainly
#       because it is the one place this is weaker than the tunnel: anyone
#       scanning the public IP learns a Traefik is here.  That is an existence
#       disclosure, not an exposure — no router, no backend, no name;
#     - the certificate store is GLOBAL and entrypoint-independent: a
#       certificate attached to no entrypoint was served on both, selected by
#       SNI alone.  That is why the `wan` entrypoint below carries NO
#       certResolver — it serves the wildcard `websecure`'s resolver already
#       put in acme.json.  Declaring a second resolver request for the same
#       main+sans would risk a duplicate issuance against Let's Encrypt's
#       5-per-week limit, and the failure mode of NOT declaring it is loud and
#       free (a browser warning naming TRAEFIK DEFAULT CERT).
#
#   THE FAIL-OPEN PATH, WHICH IS REAL AND IS DEFENDED IN CODE.  A router that
#   OMITS `entryPoints` is instantiated by Traefik on EVERY entrypoint.
#   Measured on the same scratch instance: a router with no `entryPoints` line
#   appeared as BOTH `websecure-forgot-entrypoints@file` AND
#   `wan-forgot-entrypoints@file`, and proxied on `wan`.  That is M16's
#   objection reborn inside the entrypoint design, so the entrypoint split
#   ALONE is not fail-closed — it is fail-closed plus `withWan`
#   below, which THROWS AT EVALUATION if any router omits `entryPoints`, or if
#   the set of routers naming `wan` is anything but the ones `wanExposed`
#   generates.  Forgetting is a build error, not a silent exposure.  That is
#   the mechanism; the comment is only the reason.
#
#   DNS IS THE SECOND, INDEPENDENT GATE, and it is unchanged.  Only
#   `jellyseerr` and `auth` have public A records at the registrar; every other
#   name exists solely inside Technitium, so from outside they NXDOMAIN.  Two
#   gates, both explicit, neither sufficient alone — DNS does not gate a
#   request to the bare public IP, which is what the entrypoint is for.
#
#   THE COSTS OF DROPPING THE TUNNEL, stated plainly, since cloudflared.nix's
#   header used to carry the mirror image of this list:
#
#     - THE HOME IP APPEARS IN PUBLIC DNS.  Two A records now point at it.
#     - NO VOLUMETRIC DDoS ABSORPTION.  The line is the line.  `rateLimit` and
#       `inFlightReq` on the wan routers are application-layer limits and do
#       not pretend otherwise; CrowdSec drops at the packet layer, which helps
#       against a scanner and not against a flood.
#     - SN2 CAN NO LONGER BE DEFERRED.  The tunnel was outbound-only, which is
#       why SN2 could record IPv6 as un-audited and un-relied-upon.  Opening
#       WAN ingress ends that exemption — see IPv4-ONLY BY CONSTRUCTION below.
#
#   AND WHAT IS RECOVERED, which is why the trade was taken: TLS no longer
#   terminates at a third party that could read every Jellyfin credential
#   typed into the Jellyseerr login form, and there is one fewer availability
#   dependency between the household and its own house.
#
# ── IPv4-ONLY BY CONSTRUCTION (standing note SN2) ────────────────────────────
#
#   Every entryPoint below binds `0.0.0.0:` and not `:`.  A bare `:443` binds
#   the v6 wildcard too, and SN2's hazard is precisely that: if the UDM-Pro's
#   v6 ruleset ever permits inbound and this container ever acquires a global
#   address, a v6 listener is a second path to every router that bypasses the
#   UDM-Pro DNAT — and therefore bypasses the `wan` entrypoint entirely.
#
#   Measured on ernst 2026-09-03: link-local only on br0 and in all seven
#   containers, no GUA anywhere on VLAN 90, no v6 default route, and
#   `accept_ra = 0` on br0.  So this costs nothing today.  It is written down
#   because "nothing has a GUA" is the state, not the defence — the bind is the
#   defence, and it is one word per entryPoint.
#
# ── TLS: ACME DNS-01, wildcard, split horizon ────────────────────────────────
#
#   ONE wildcard certificate for *.goclan.org, issued over the DNS-01
#   challenge.  DNS-01 specifically so that no inbound port is needed to PROVE
#   DOMAIN CONTROL: the challenge is a TXT record lego writes and deletes at
#   Cloudflare, and HTTP-01 never runs.
#
#   THAT IS WHY :80 IS NOT FORWARDED FROM THE WAN, and it is worth being
#   explicit because "open 80 for Let's Encrypt" is the single most likely
#   wrong edit to the UDM-Pro after this milestone.  Nothing external depends
#   on :80: the `web` entryPoint below exists only to 308 a bare hostname typed
#   on the LAN over to :443, and no external name is ever handed out as
#   `http://`.  The ledger carries a row saying so.
#
#   SPLIT HORIZON — READ THIS BEFORE ASSUMING ANYTHING IS PUBLIC.
#
#     The CERTIFICATE is public.  Every name in it is published to the
#     Certificate Transparency logs the moment it is issued, so
#     "*.goclan.org" is world-readable and always will be.
#
#     The SERVICES are not.  jellyfin.goclan.org and the arr names exist ONLY
#     as records inside Technitium (10.0.5.3).  There are no public A or AAAA
#     records for them, and Cloudflare's zone holds nothing for these names but
#     the transient _acme-challenge TXT that lego adds and removes.
#
#     A public certificate is what makes people assume the service behind it is
#     reachable.  It is not.  The only thing CT discloses is that a wildcard
#     exists — not a single service name, and not an address.
#
#   THE ACME RESOLVERS ARE PUBLIC ONES, AND THAT IS LOAD-BEARING.  lego
#   verifies its own TXT record has propagated before telling Let's Encrypt to
#   validate.  If that check went through this container's normal resolver it
#   would ask Technitium — which is authoritative for the goclan.org names
#   inside the LAN and knows nothing about _acme-challenge — and the answer
#   would be an authoritative NXDOMAIN, forever.  The failure is a renewal that
#   hangs at "waiting for DNS record propagation" and then times out, i.e. a
#   certificate that expires with the proxy still running.  Pinning 1.1.1.1 and
#   9.9.9.9 makes the check ask the PUBLIC view, which is the view Let's
#   Encrypt will use.
#
#   THE STORE IS ON zdata.  /srv/state/traefik, bound to the module's default
#   dataDir, because zroot rolls back (invariant #7) and acme.json is the one
#   piece of state here that cannot be regenerated cheaply — Let's Encrypt
#   rate-limits duplicate certificates to 5 per week.  Traefik creates
#   acme.json 0600 itself; the directory is 0700 and owned by uid 3005.
#
#   THE CLOUDFLARE TOKEN is a clan var, prompted, never in the store and never
#   in this file.  See the generator at the bottom, and the staging oneshot
#   that is the only reason the container can see it at all.
#
# ── BACKEND BYPASS HARDENING: backend-side source restriction ────────────────
#
#   ONE mechanism, as the milestone requires, and it is (a): each backend's own
#   firewall, in its own netns, accepts its web port ONLY from 10.0.90.12.  The
#   rules live in containers/jellyfin.nix and containers/arr.nix beside the
#   ports they restrict.  The rejected alternative was (b), a UDM-Pro intra-zone
#   ZBF rule.
#
#   WHY (a) AND NOT (b) — this is not a preference, (b) cannot do the job:
#
#     Jellyfin (.10), the arr (.13), qBittorrent's guest (.11) and this
#     container (.12) are all ports on the SAME VLAN on the SAME bridge.
#     Traffic between them is switched at layer 2 by br0 and the frames never
#     reach the UDM-Pro at all.  containers/arr.nix relies on exactly this
#     property in the other direction — it is why the arr needs no ZBF rule to
#     talk to the download client.  A gateway cannot filter traffic it never
#     sees, so an intra-zone rule would be a rule that looks like enforcement
#     and enforces nothing.
#
#     And the adjacency that matters is real, not theoretical.  10.0.90.11 is
#     the qBittorrent microvm: the one workload on ernst that talks to the open
#     internet on its own behalf, which is why invariant #1 gives it its own
#     kernel.  It sits one layer-2 hop from Sonarr's, Radarr's and Prowlarr's
#     web UIs.  Source-restricting those ports to this container is what stops
#     a compromised download client from driving the *arr APIs directly, and it
#     is the single largest thing this milestone buys beyond TLS.
#
#   WHAT (a) DOES NOT COVER, stated plainly:
#
#     - Anything that already has code execution IN THIS CONTAINER.  Traefik is
#       inside the allow-list by construction; source filtering cannot help.
#       This is the cost of collapsing every consumer rule to one address.
#     - The backends' OUTBOUND reach.  Nothing here constrains what Jellyfin or
#       the arr connect out to; that is invariant #1's tiering, not a firewall.
#     - Spoofed sources.  A host on VLAN 90 can forge 10.0.90.12 as its source
#       address; br0 does no source validation.  It would not get replies (they
#       route to the real .12), so this blocks exploitation-by-response but not
#       blind one-shot writes to an unauthenticated API.
#     - Anything on the host itself, which is on VLAN 50 and reaches VLAN 90
#       through the UDM-Pro — a path (b) WOULD have covered.
#
#   WHERE (b) WOULD HAVE BEEN BETTER: it is enforced by a device the containers
#   cannot reconfigure, so a regression in this repo could not silently undo it,
#   and it would cover the host-to-backend path above.  (a) was chosen anyway
#   because covering the intra-VLAN path is worth more than either, and because
#   a rule that lives in the repo deploys atomically with the routes it
#   protects.  DO NOT ADD (b) AS WELL — two sources of truth for one property
#   is how you get a rule nobody dares delete because nobody can prove what it
#   does.
#
#   DEBUGGING CONSEQUENCE, because it will surprise someone: after this
#   deploys, `curl http://10.0.90.10:8096` from your laptop or from ernst FAILS
#   and that is correct.  Reach a backend directly with
#   `nixos-container run jellyfin -- curl -sS localhost:8096/health` instead;
#   `lo` is always trusted by the NixOS firewall.
#
# ── JELLYFIN KEEPS NATIVE AUTH, FOREVER ──────────────────────────────────────
#
#   NEVER put Authelia — or any forward-auth middleware — in front of the
#   Jellyfin route.  This was written here so M7 would not undo it; M7 has
#   landed, the `authelia` middleware below exists, and the jellyfin router
#   still does not carry it.  Keep it that way.
#
#   TV apps, the Android/iOS clients, Chromecast senders and every DLNA-ish
#   device authenticate with Jellyfin's own token API and cannot perform an
#   interactive OIDC redirect.  A forward-auth middleware turns the first
#   request into a 302 to a login page the client has no browser to render, so
#   the app fails with an opaque network error rather than a login prompt.
#   Jellyfin's own user database IS the auth boundary for this route, and it is
#   the right one: it is the only one the clients can speak.
#
#   The arr routes are the opposite case — browser-only, admin-facing — and
#   they are what the forward-auth middleware exists for.  The distinction is
#   not "admin versus household", it is "can the client render a login page and
#   follow a 302".  Anything that cannot must authenticate natively or not be
#   proxied at all.
#
# ── Storage layout on this host (see machines/ernst/disko.nix) ───────────────
#
#   /srv/state/traefik    zdata/state   RW into the container at /var/lib/traefik
#     acme.json                         the certificate store, 0600, uid 3005
#
#   Nothing else persists.  Both configs are generated from this file into the
#   Nix store on every deploy, so the container's own root holds no state worth
#   keeping.
#
#   M18 ADDS A SECOND OCCUPANT OF THIS CONTAINER, and its state is its own:
#   machines/ernst/containers/crowdsec.nix puts the CrowdSec agent, its local
#   API and the firewall bouncer in THIS netns — because this netns is the only
#   place that sees the pre-DNAT source address of a WAN request.  Its
#   decisions database lives at /srv/state/crowdsec on zdata, bound separately.
#   That file co-defines `containers.traefik.config`; read its header before
#   assuming this file is the whole of what runs in here.
{ config, lib, pkgs, ... }:
let
  ############################################################################
  # Identity.
  ############################################################################

  # Guest-side MAC — 02:00:00:<vlan>:00:<seq>, RESERVED for this container by
  # M2b in the allocation table in machines/ernst/networking.nix.  This is the
  # address the UDM-Pro sees and the one the DHCP reservation keys on; never
  # the host-side vb-traefik.
  traefikMac = "02:00:00:90:00:04";
  vlanId     = 90;

  # Host side of the veth pair.  nspawn names it vb-<container> when
  # --network-bridge= is used — "vb-", not "ve-".
  vethName = "vb-traefik";

  # Numeric ids, continuing the 3000-range family that containers/arr.nix and
  # microvms/wg-qbittorrent.nix established.  nspawn passes uids and gids
  # through unmapped, so an id chosen in here is an id on zdata — and
  # /srv/state/traefik is on zdata.  Add a row to the table in
  # machines/ernst/networking.nix for any new one.
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
  arrAddr      = "10.0.90.13";

  # M6.  The monitoring container: Grafana's backend, and the one host on
  # VLAN 90 permitted to read this container's metrics endpoint.
  monitoringAddr = "10.0.90.14";

  # M7.  Authelia.  Two roles in one address: the identity provider this proxy
  # ASKS about every admin request (the forwardAuth middleware below), and the
  # login portal it SERVES at auth.<domain> like any other backend.
  autheliaAddr = "10.0.90.15";

  jellyfinPort = 8096;
  prowlarrPort = 9696;
  sonarrPort   = 8989;
  radarrPort   = 7878;
  grafanaPort  = 3000;
  autheliaPort = 9091;

  # M12.  Three more backends in the SAME arr container, on arrAddr — no new
  # address, no new MAC, no DHCP reservation, no UDM-Pro rule.
  #
  # These three and only these three.  M12 also adds UmlautAdaptarr (5005 and
  # a proxy on 5006) and MediathekArr's Newznab indexer (5008), and neither
  # gets a route: their only client is Prowlarr, in the same netns, over
  # 127.0.0.1.  containers/arr.nix keeps them off its firewall list for the
  # same reason, and 5006 in particular is an HTTP proxy that has no business
  # being reachable.
  bazarrPort       = 6767;
  cleanuparrPort   = 11011;
  mediathekarrPort = 5007;   # the downloader's SABnzbd API and setup wizard
  jellyseerrPort   = 5055;   # M13 — the household's request UI

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
  # one docs/roadmap.md got wrong: nixpkgs' module defaults to 8000, while
  # 13378 is the Docker image's number and what every client expects.
  # containers/arr.nix sets it explicitly for that reason.
  lidarrPort         = 8686;
  kapowarrPort       = 5656;
  questarrPort       = 5000;
  audiobookshelfPort = 13378;

  # M17 — Bindery, in the arr container.  Verified by RUNNING the binary
  # (2026-08-29): BINDERY_PORT, default 8787, kept.
  binderyPort        = 8787;

  # Storyteller, the podman tier's SECOND occupant, on its own address.
  # 02:00:00:90:00:0c → 10.0.90.20, following the 8 + <seq> convention in
  # machines/ernst/networking.nix.
  storytellerAddr = "10.0.90.20";
  storytellerPort = 8001;

  # RomM — the ROM library manager on the podman tier (containers/romm.nix).
  # Its netns firewall accepts this address and no other on ${toString rommPort}.
  rommAddr = "10.0.90.22";
  rommPort = 8080;

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
  # declaration.  `jellyseerr` and `authelia` are M16's two hostnames, and the
  # set has not grown.
  #
  # ADDING A NAME HERE IS GROWING THE INTERNET-FACING SURFACE OF THE HOUSE.
  # It needs: a public A record at the registrar, a row in docs/roadmap.md's
  # ledger, and — for anything that is not Jellyseerr or the portal — an answer
  # to why the unauthenticated attack surface should stop being Authelia.
  #
  # `authelia` IS LOAD-BEARING and is not padding.  Forward-auth is a REDIRECT
  # protocol: an unauthenticated request to jellyseerr answers 302 to
  # https://auth.goclan.org/?rd=…, so if the portal does not resolve and route
  # externally, no external login can ever complete.  M16 recorded this as a
  # corrected premise after its own test plan listed `auth` among the names
  # that must be unreachable; do not re-derive it the hard way.
  wanExposed = [ "jellyseerr" "authelia" ];

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
  withWan = lanRouters:
    let
      names   = lib.attrNames lanRouters;
      missing = lib.filter (n: !(lanRouters.${n} ? entryPoints)) names;
      unknown = lib.filter (n: !(lanRouters ? ${n})) wanExposed;
      stray   = lib.filter (n: lib.elem wanEntryPoint lanRouters.${n}.entryPoints) names;

      # ── The order of the middlewares is deliberate ────────────────────────
      #
      # Rate limit and concurrency cap FIRST, then whatever the LAN twin
      # carries (forward-auth, for everything but the portal).  A flood is shed
      # here rather than being turned into one Authelia authz call per request:
      # Authelia is a single container in the login path of every admin UI in
      # the house, and letting the internet drive it at line rate would hand an
      # attacker a lever on the household's own access.
      mkWan = n: {
        name  = "${n}-wan";
        value = lanRouters.${n} // {
          entryPoints = [ wanEntryPoint ];
          middlewares =
            [ "wan-ratelimit" "wan-inflight" ]
            ++ (lanRouters.${n}.middlewares or [ ]);
        };
      };
    in
      if missing != [ ] then
        throw ''
          traefik.nix: these routers do not name their entryPoints, and Traefik
          binds such a router to EVERY entrypoint — including `wan`, which is
          the internet:
            ${lib.concatStringsSep ", " missing}
          Add `entryPoints = [ "websecure" ];` to each.  See the TWO
          ENTRYPOINTS block in this file's header.
        ''
      else if unknown != [ ] then
        throw ''
          traefik.nix: `wanExposed` names routers that do not exist:
            ${lib.concatStringsSep ", " unknown}
          It takes ROUTER names (e.g. `authelia`), not host labels (`auth`).
        ''
      else if stray != [ ] then
        throw ''
          traefik.nix: these routers put themselves on the `wan` entrypoint by
          hand:
            ${lib.concatStringsSep ", " stray}
          `wan` is the internet, and exposure is an edit to `wanExposed` plus a
          public A record plus a ledger row — never an entryPoints list on an
          existing router.  See the TWO ENTRYPOINTS block in this file's
          header.
        ''
      else lanRouters // lib.listToAttrs (map mkWan wanExposed);

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
  envFile    = "${secretsDir}/cloudflare.env";

  gen = config.clan.core.vars.generators.traefik-acme;

  # The module's default dataDir.  Named here because the ACME storage path in
  # the static config has to agree with the bind mount, and one binding is
  # cheaper to keep in step than two string literals.
  dataDir = "/var/lib/traefik";
in
{
  ##############################################################################
  # Host-side wiring.
  ##############################################################################

  # Certificate store on zdata.  0700 and owned by the service, exactly like
  # /srv/state/{jellyfin,sonarr,radarr,prowlarr}: nothing else has any business
  # reading a private key.
  #
  # NUMERIC ids on purpose — `traefik` is a container user and the host has no
  # matching passwd entry.  Same shape containers/arr.nix uses for uid 3002.
  systemd.tmpfiles.rules = [
    "d /srv/state/traefik 0700 ${toString traefikUid} ${toString traefikGid} -"
  ];

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
    after       = [ "local-fs.target" ];
    before      = [ "container@traefik.service" ];
    requiredBy  = [ "container@traefik.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.coreutils}/bin/install -d -m 0700 -o root -g root ${secretsDir}
      ${pkgs.coreutils}/bin/install -m 0400 -o root -g root \
        ${gen.files."cloudflare.env".path} ${envFile}
    '';
  };

  # Host side of the container's veth — a VLAN-90 port on br0.
  #
  # There is deliberately NO `networking.firewall.allowedTCPPorts` here.  443
  # is opened inside the container's own netns (below); on the host it is not a
  # port at all.  Reachability from the consumer VLANs is the UDM-Pro's job —
  # and after this milestone it is ONE rule per zone, pointing at 10.0.90.12,
  # which is the entire reduction M5 exists to deliver.
  #
  # KeepMaster, not Bridge=: nspawn creates this link AND enslaves it to br0
  # itself (--network-bridge=br0), so Bridge= would make networkd fight nspawn
  # over the master.  KeepMaster leaves the enslavement alone while still
  # applying the [BridgeVLAN] section, which is the only thing wanted from it.
  #
  # No L3 of its own: a bridge port carries no address, and IPv6AcceptRA on a
  # port would have it answer router advertisements meant for the container.
  #
  # 60- prefix so it sorts after the 50-* topology units in
  # machines/ernst/networking.nix and well ahead of the 99-* wildcards.
  systemd.network.networks."60-${vethName}" = {
    matchConfig.Name = vethName;
    networkConfig = {
      KeepMaster          = true;
      LinkLocalAddressing = "no";
      IPv6AcceptRA        = false;
    };
    bridgeVLANs = [ { VLAN = vlanId; PVID = vlanId; EgressUntagged = vlanId; } ];
    # A bridge port's terminal operational state is "enslaved"; it never
    # becomes routable, and waiting for that would hang boot.
    linkConfig.RequiredForOnline = "enslaved";
  };

  # Re-assert the VLAN membership after nspawn has created the veth.
  #
  # Same real race as vb-jellyfin and vb-arr: networkd applies [BridgeVLAN]
  # only once it observes the link's master, and nspawn sets that master out of
  # band from container@traefik.service.  With DefaultPVID = "none" on br0 a
  # miss is fail-CLOSED — no connectivity at all — rather than fail-open onto
  # VLAN 50, which is the right failure but still presents as "everything is
  # down" now that everything is behind this one container.
  #
  # `bridge vlan add` is idempotent, so this agrees with networkd rather than
  # competing with it.  The "-" prefix is deliberate: a backstop must not become
  # a new failure mode, so `bridge` exiting non-zero (link already gone during a
  # restart, say) must not fail the container and restart-loop it.
  #
  # `bridge vlan show dev vb-traefik` remains the check — do not trust silence
  # from either mechanism.
  systemd.services."container@traefik".serviceConfig.ExecStartPost = [
    "-${pkgs.iproute2}/bin/bridge vlan add dev ${vethName} vid ${toString vlanId} pvid untagged"
  ];

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
      type        = "hidden";
    };

    runtimeInputs = [ pkgs.coreutils pkgs.gnugrep ];

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
  containers.traefik = {
    autoStart = true;
    ephemeral = false;          # acme.json persists via the bind mount below

    # Own netns, own L2 identity.  See the file header for why this is a veth
    # on br0 and not a macvlan or a tap.
    privateNetwork  = true;
    hostBridge      = "br0";
    localMacAddress = traefikMac;

    bindMounts = {
      # The certificate store, on zdata.  Remapped to the module's upstream
      # default dataDir so services.traefik needs no path override — the same
      # trick containers/jellyfin.nix uses for /var/lib/jellyfin and
      # containers/arr.nix for /var/lib/{sonarr,radarr,prowlarr}.
      "${dataDir}" = {
        hostPath   = "/srv/state/traefik";
        isReadOnly = false;
      };

      # The staged Cloudflare token, read-only, at the identical path.  See the
      # staging unit above for why this is not a bind of /run/secrets.
      "${secretsDir}" = {
        hostPath   = secretsDir;
        isReadOnly = true;
      };
    };

    ############################################################################
    # NixOS config for the container's own root filesystem.
    ############################################################################
    config = { config, pkgs, lib, ... }: {
      system.stateVersion = "26.05";

      # Matches the host.  Certificate expiry, renewal attempts and every
      # access-log line are rendered in local time, and a container that
      # silently defaults to UTC makes "when did the cert actually renew" a
      # two-hour question.  Same call as containers/arr.nix.
      time.timeZone = "Europe/Berlin";

      ##########################################################################
      # Networking.  The container owns its netns, so it owns all of this.
      ##########################################################################

      # services.resolved asserts !networking.useHostResolvConf, and with a
      # private netns the host's resolv.conf is a stale snapshot of someone
      # else's resolver anyway.  virtualisation/container-config.nix sets it
      # `mkDefault true`, so a plain `false` wins without mkForce.
      networking.useHostResolvConf = false;

      networking.useNetworkd   = true;
      services.resolved.enable = true;

      # eth0 — renamed from host0 by container-init before stage 2 runs.
      #
      # ADDRESS: DHCP, reserved on the UDM-Pro against the pinned MAC.
      # RESOLVER: declared, not inherited.  UseDNS/UseDomains = false so a
      # future change to the Services network's DHCP options cannot silently
      # move this container off Technitium.  "~." is a ROUTING domain, so every
      # lookup goes to 10.0.5.3; "skynet.lan" is the bare-hostname suffix.
      #
      # This resolver is what the BACKEND connections and Let's Encrypt's API
      # hostname resolve through.  The ACME propagation check deliberately does
      # NOT use it — see SPLIT HORIZON in the file header.
      #
      # Check on ernst with:  nixos-container run traefik -- resolvectl status eth0
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

      # 20 s, for the reason containers/jellyfin.nix explains at length:
      # container@traefik is Type=notify with TimeoutStartSec=1min, so a
      # wait-online that blocks for the stock 120 s turns a missing DHCP
      # reservation into a container the host kills and restart-loops, with no
      # reachable state to debug.  At 20 s the container always finishes booting
      # and leaves one obviously failed unit instead.
      systemd.network.wait-online.timeout = 20;

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
      networking.firewall.allowedTCPPorts = [ 80 443 wanPort ];

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

      ##########################################################################
      # Users.  Numeric ids are the interface across the nspawn boundary.
      ##########################################################################

      # The upstream module declares users.users.traefik without a uid (it lets
      # NixOS allocate one dynamically from the system range) and
      # users.groups.traefik without a gid.  Both are plain definitions with no
      # uid/gid attribute, so adding one here is a MERGE and needs no mkForce —
      # unlike containers/arr.nix, where the servarr modules DO set uid from
      # config.ids.uids.* and the override has to fight them.
      #
      # isSystemUser is already true upstream and stays true; it is restated
      # because NixOS infers "effectively a system user" from uid < 1000, and
      # 3005 is not, so the inference stops working the moment the uid is
      # pinned.  containers/arr.nix hit exactly this and the error names
      # neither the uid nor the cause.
      users.users.traefik = {
        isSystemUser = true;
        uid          = traefikUid;
      };
      users.groups.traefik = { gid = traefikGid; };

      ##########################################################################
      # Traefik.
      ##########################################################################
      services.traefik = {
        enable = true;

        # dataDir left at its default — /var/lib/traefik is the bind mount.
        environmentFiles = [ envFile ];

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
          global.checkNewVersion    = false;
          global.sendAnonymousUsage = false;

          # To the journal.  `journalctl -u traefik` inside the container is
          # where the ACME exchange and every routing decision are visible, and
          # it is the instrument the PR test plan uses.
          log.level     = "INFO";

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
            fields.headers.defaultMode  = "drop";
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
            entryPoint            = "metrics";
            addEntryPointsLabels  = true;
            addRoutersLabels      = false;
            addServicesLabels     = false;
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
                to        = "websecure";
                scheme    = "https";
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
              address  = "0.0.0.0:${toString wanPort}";
              http.tls = { };
            };

            websecure = {
              address = "0.0.0.0:443";

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
                    sans = [ "*.${baseDomain}" ];
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
            email   = acmeEmail;
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
              resolvers = [ "1.1.1.1:53" "9.9.9.9:53" ];

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
              address            = "http://${autheliaAddr}:${toString autheliaPort}/api/authz/forward-auth";
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
              burst   = 100;
              period  = "1s";
            };

            # Concurrency, which the rate limit does not cover: 50/s of
            # requests that each take 30 s is not a rate problem, it is 1500
            # open connections to Jellyseerr's single-threaded Node process.
            wan-inflight.inFlightReq.amount = 40;
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
              rule        = "Host(`jellyfin.${baseDomain}`)";
              entryPoints = [ "websecure" ];
              service     = "jellyfin";
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
              rule        = "Host(`auth.${baseDomain}`)";
              entryPoints = [ "websecure" ];
              service     = "authelia";
            };

            # ── The arr stack: admin routes, behind Authelia ───────────────
            #
            # THREE HOSTNAMES, NOT THREE PATH PREFIXES.  containers/arr.nix
            # anticipated this ("M5 can route three paths to one address
            # perfectly well") and subdomains are the better of the two:
            # Sonarr, Radarr and Prowlarr all need a matching `UrlBase` set in
            # their own settings before they will work under a path prefix, and
            # a missing UrlBase presents as a UI that loads a blank page with
            # 404s on every asset.  Distinct hostnames need no UrlBase at all,
            # so there is nothing to keep in step between this file and three
            # web UIs.
            prowlarr = {
              rule        = "Host(`prowlarr.${baseDomain}`)";
              entryPoints = [ "websecure" ];
              middlewares = [ "authelia" ];
              service     = "prowlarr";
            };
            sonarr = {
              rule        = "Host(`sonarr.${baseDomain}`)";
              entryPoints = [ "websecure" ];
              middlewares = [ "authelia" ];
              service     = "sonarr";
            };
            radarr = {
              rule        = "Host(`radarr.${baseDomain}`)";
              entryPoints = [ "websecure" ];
              middlewares = [ "authelia" ];
              service     = "radarr";
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
              rule        = "Host(`bazarr.${baseDomain}`)";
              entryPoints = [ "websecure" ];
              middlewares = [ "authelia" ];
              service     = "bazarr";
            };
            cleanuparr = {
              rule        = "Host(`cleanuparr.${baseDomain}`)";
              entryPoints = [ "websecure" ];
              middlewares = [ "authelia" ];
              service     = "cleanuparr";
            };
            # MediathekArr's DOWNLOADER, which is also its setup wizard — the
            # page a human opens to configure the thing.  The indexer half on
            # 5008 is deliberately not routed.
            mediathekarr = {
              rule        = "Host(`mediathekarr.${baseDomain}`)";
              entryPoints = [ "websecure" ];
              middlewares = [ "authelia" ];
              service     = "mediathekarr";
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
              rule        = "Host(`tvheadend.${baseDomain}`)";
              entryPoints = [ "websecure" ];
              middlewares = [ "authelia" ];
              service     = "tvheadend";
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
              rule        = "Host(`tubesync.${baseDomain}`)";
              entryPoints = [ "websecure" ];
              middlewares = [ "authelia" ];
              service     = "tubesync";
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
              rule        = "Host(`lidarr.${baseDomain}`)";
              entryPoints = [ "websecure" ];
              middlewares = [ "authelia" ];
              service     = "lidarr";
            };
            kapowarr = {
              rule        = "Host(`kapowarr.${baseDomain}`)";
              entryPoints = [ "websecure" ];
              middlewares = [ "authelia" ];
              service     = "kapowarr";
            };
            questarr = {
              rule        = "Host(`questarr.${baseDomain}`)";
              entryPoints = [ "websecure" ];
              middlewares = [ "authelia" ];
              service     = "questarr";
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
              rule        = "Host(`bindery.${baseDomain}`)";
              entryPoints = [ "websecure" ];
              middlewares = [ "authelia" ];
              service     = "bindery";
            };
            # ── Audiobookshelf (M14): NO MIDDLEWARE.  A permanent bypass ────
            #
            # NO `middlewares`, and — like Jellyfin's router — that is the
            # whole point of this one rather than an omission.
            #
            # THE REASON IS INVARIANT #4's JELLYFIN CLAUSE, NOT CONVENIENCE.
            # Audiobookshelf has native mobile and TV clients, and a
            # forward-auth redirect is exactly what those cannot survive: the
            # app speaks to the REST API with a bearer token and has no browser
            # to follow a 302 to auth.goclan.org, so every request would fail
            # in a way that looks like a broken server rather than a login
            # prompt.  App support is a stated requirement for this library.
            #
            # This is the THIRD permanent bypass in the fleet, alongside
            # Jellyfin's native auth and the qBittorrent WebUI, and it is
            # listed as such in docs/roadmap.md's interim-rule ledger — as a
            # `—` row, because it is permanent and must not be mistaken for
            # something to "fix" later by adding the middleware back.
            #
            # WHAT CARRIES THE AUTHENTICATION INSTEAD.  Audiobookshelf's own
            # accounts, and they are now the ENTIRE boundary — the same posture
            # Jellyfin has had since M5 and Jellyseerr since M13.  Two
            # consequences that are NOT theoretical:
            #
            #   1. ITS FIRST-RUN WIZARD IS UNAUTHENTICATED BY CONSTRUCTION.
            #      With no root account yet, the initial-setup page will create
            #      one for whoever loads it first.  With `authelia` in front
            #      that page was protected; without it, it is reachable from
            #      every consumer VLAN the moment the Technitium record
            #      resolves.  THE ADMIN ACCOUNT MUST BE CREATED IMMEDIATELY
            #      after the first deploy — the PR body carries this as an
            #      ordering constraint, not a to-do.
            #   2. THERE IS NO SECOND FACTOR ON THIS NAME.  Authelia's per-user
            #      regulation and 2FA do not apply here.  That is the trade
            #      being made for app support, made deliberately, and it is why
            #      this comment is long.
            #
            # NOT COMPARABLE TO JELLYSEERR'S EXEMPTION, which rests on a
            # different argument (its posture is a Jellyfin-account login, so
            # dropping forward-auth swaps one login for another).  This one
            # rests on the client-compatibility clause.  Both end at the same
            # place; do not merge the reasoning.
            audiobookshelf = {
              rule        = "Host(`audiobookshelf.${baseDomain}`)";
              entryPoints = [ "websecure" ];
              service     = "audiobookshelf";
            };
            storyteller = {
              rule        = "Host(`storyteller.${baseDomain}`)";
              entryPoints = [ "websecure" ];
              middlewares = [ "authelia" ];
              service     = "storyteller";
            };

            # ── RomM: admin route, behind Authelia ────────────────────────
            #
            # The usual admin-surface shape, and NOT one of the client-
            # compatibility carve-outs.  RomM has its own login and an
            # EmulatorJS in-browser player, but every consumer here is a
            # browser on a name the M5 wildcard already covers — the Deck
            # reads its games from a Syncthing replica on local disk, not
            # through this route, so there is no native client whose token
            # handling a forward-auth redirect could break.
            #
            # That distinction matters because it is exactly the argument
            # Jellyfin and Audiobookshelf won and this one does not get to.
            romm = {
              rule        = "Host(`romm.${baseDomain}`)";
              entryPoints = [ "websecure" ];
              middlewares = [ "authelia" ];
              service     = "romm";
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
              rule        = "Host(`slskd.${baseDomain}`)";
              entryPoints = [ "websecure" ];
              middlewares = [ "authelia" ];
              service     = "slskd";
            };

            # ── Jellyseerr: the HOUSEHOLD route — posture set by M16 ───────
            #
            # M13 shipped this router with NO middleware, deliberately, and
            # its comment said M16 would be where the posture changes,
            # reviewed as an ingress change.  M16 made that change, and M18
            # kept it while replacing the mechanism underneath: the name is
            # still reachable FROM THE INTERNET, now through the `wan`
            # entrypoint rather than the Cloudflare Tunnel, and the
            # requirement is unchanged — the unauthenticated attack surface on
            # the external path is AUTHELIA, not Jellyseerr's Node
            # application.
            #
            # M18 SPLIT THE ROUTER, and the reason is narrower than it looks.
            # `jellyseerr-wan` (copied by `withWan`) carries the same
            # `authelia` middleware PLUS the two external limits; this router
            # keeps forward-auth and no limits.  So the auth posture is
            # identical on both paths — which was M16's decision and stands —
            # and what differs is only that the household is not rate-limited
            # in its own house.
            #
            # THE AUTH POSTURE IS STILL UNIFORM, and the alternatives M16
            # rejected are still rejected.  Splitting on ENTRYPOINT is not the
            # thing M16 refused; splitting on CLIENT IDENTITY is:
            #
            #   - a second, internal-only router keyed on ClientIP with no
            #     middleware FAILS OPEN: any request the internal matcher
            #     mis-classifies is served unauthenticated.  This shape fails
            #     CLOSED — a mis-classified internal request meets a login
            #     form, which is an inconvenience, not an exposure.  An
            #     entrypoint cannot be mis-classified: it is which socket the
            #     packet arrived on;
            #   - an Authelia `networks`-based bypass rule for RFC1918
            #     sources trusts X-Forwarded-For arithmetic on the exact
            #     boundary this milestone exists to harden.
            #
            # The cost is that household members hold an Authelia account
            # (group `household` in authelia.nix) alongside their Jellyfin
            # one.  Authelia's remember-me runs a month, so the friction is
            # periodic, not per-visit.
            #
            # "WHO REQUESTED THIS" IS NOT FLATTENED — M13's comment worried
            # it would be.  Forward-auth sits IN FRONT of Jellyseerr; its own
            # Jellyfin-account login (and per-user request attribution)
            # continues underneath, exactly as Grafana keeps its local admin
            # under the same middleware.
            #
            # The name is in authelia.nix's access_control via its OWN rule
            # (household + admins), NOT via `protectedHosts` — that list
            # feeds the admins-only rule, and this is the one protected name
            # in the fleet a non-admin must be able to reach.
            jellyseerr = {
              rule        = "Host(`jellyseerr.${baseDomain}`)";
              entryPoints = [ "websecure" ];
              middlewares = [ "authelia" ];
              service     = "jellyseerr";
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
              rule        = "Host(`grafana.${baseDomain}`)";
              entryPoints = [ "websecure" ];
              middlewares = [ "authelia" ];
              service     = "grafana";
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
          # LOG HYGIENE, not behaviour.  Shipped as a HYPOTHESIS and since
          # CONFIRMED — see the measurement at the bottom of this comment.
          #
          # After M7 deployed, authelia-main's journal filled with:
          #
          #   level=error msg="Request timeout occurred while handling request
          #   from client." error="read tcp 10.0.90.15:9091->10.0.90.12:37010:
          #   i/o timeout" method=GET path=/ status_code=408
          #
          # — one per idle connection, at level=error, from this container's
          # address.  Nothing is broken: every one of those requests was served.
          #
          # The mechanism, as far as it can be reasoned about from here:
          # Authelia's `server.timeouts.read` defaults to 6 s, and Traefik's
          # backend connection pool holds an idle keep-alive connection for
          # `idleConnTimeout`, default 90 s.  Whoever's timer is shorter closes
          # the connection — today that is always Authelia, and fasthttp logs
          # the close against the LAST request it saw on that connection, which
          # is why the line names a path that completed normally minutes ago.
          #
          # Making Traefik hang up first (5 s < 6 s) should mean the connection
          # is always closed by its owner and never by a timeout.  The cost is
          # one TCP handshake per burst on a layer-2 hop that never leaves this
          # host — microseconds, and only when the proxy has been idle.
          #
          # WHY NOT raise Authelia's read timeout instead: that weakens a real
          # server-side protection (a slow-header client holding a connection)
          # to silence a log line, and it would have to exceed Traefik's 90 s
          # to actually work.  The pool is the thing misbehaving; fix the pool.
          #
          # ── CONFIRMED ON ernst, 2026-08-24 ────────────────────────────────
          #
          #   last 408 logged                       17:42:35
          #   container@traefik picked this up      17:52:47
          #   408s after that                       ZERO
          #
          # And not for want of traffic: both accounts registered WebAuthn
          # credentials through this proxy at 18:16 and 18:18, which is exactly
          # the browse-then-idle pattern that used to produce them.  The
          # reasoning above holds — Authelia's 6 s read timeout was closing
          # Traefik's idle pooled connections, and having Traefik hang up at
          # 5 s means the connection is always closed by its owner.
          #
          # Re-check with, if a future nixpkgs bump moves either default:
          #   nixos-container run authelia -- \
          #     journalctl -u authelia-main --since "30 min ago" | grep -c 408
          # Expect 0.  If it is ever not 0, say so HERE rather than leaving a
          # confirmed-once story to be inherited as permanent truth.
          http.serversTransports.shortIdle.forwardingTimeouts.idleConnTimeout = "5s";

          http.services = {
            jellyfin.loadBalancer.servers = [ { url = "http://${jellyfinAddr}:${toString jellyfinPort}/"; } ];
            prowlarr.loadBalancer.servers = [ { url = "http://${arrAddr}:${toString prowlarrPort}/"; } ];
            sonarr.loadBalancer.servers   = [ { url = "http://${arrAddr}:${toString sonarrPort}/"; } ];
            radarr.loadBalancer.servers   = [ { url = "http://${arrAddr}:${toString radarrPort}/"; } ];

            # M12 — same container, same address, three more ports.
            bazarr.loadBalancer.servers       = [ { url = "http://${arrAddr}:${toString bazarrPort}/"; } ];
            cleanuparr.loadBalancer.servers   = [ { url = "http://${arrAddr}:${toString cleanuparrPort}/"; } ];
            mediathekarr.loadBalancer.servers = [ { url = "http://${arrAddr}:${toString mediathekarrPort}/"; } ];

            # M13 — same container, same address, one more port.
            jellyseerr.loadBalancer.servers   = [ { url = "http://${arrAddr}:${toString jellyseerrPort}/"; } ];

            # M8 — its own container on .18.
            tvheadend.loadBalancer.servers    = [ { url = "http://${tvheadendAddr}:${toString tvheadendPort}/"; } ];

            # M9 — its own address, in a podman netns on VLAN 90.
            tubesync.loadBalancer.servers     = [ { url = "http://${tubesyncAddr}:${toString tubesyncPort}/"; } ];

            # M14 — four more ports on the arr container's address …
            lidarr.loadBalancer.servers         = [ { url = "http://${arrAddr}:${toString lidarrPort}/"; } ];
            kapowarr.loadBalancer.servers       = [ { url = "http://${arrAddr}:${toString kapowarrPort}/"; } ];
            questarr.loadBalancer.servers       = [ { url = "http://${arrAddr}:${toString questarrPort}/"; } ];
            audiobookshelf.loadBalancer.servers = [ { url = "http://${arrAddr}:${toString audiobookshelfPort}/"; } ];

            # M17 — a fifth port on the arr container's address.
            bindery.loadBalancer.servers        = [ { url = "http://${arrAddr}:${toString binderyPort}/"; } ];

            # … and one more podman netns of its own, the tier's second.
            storyteller.loadBalancer.servers    = [ { url = "http://${storytellerAddr}:${toString storytellerPort}/"; } ];
            romm.loadBalancer.servers           = [ { url = "http://${rommAddr}:${toString rommPort}/"; } ];

            # … and one in the microvm guest, the first non-container backend.
            slskd.loadBalancer.servers          = [ { url = "http://${slskdAddr}:${toString slskdPort}/"; } ];
            grafana.loadBalancer.servers  = [ { url = "http://${monitoringAddr}:${toString grafanaPort}/"; } ];

            # M7.  The same address the forwardAuth middleware above calls,
            # reached over the same plain-HTTP layer-2 hop — one backend, two
            # paths to it.  The portal is a browser-facing route; the
            # middleware's is a server-to-server call on a different path
            # (/api/authz/forward-auth) of the same listener.
            authelia.loadBalancer = {
              servers = [ { url = "http://${autheliaAddr}:${toString autheliaPort}/"; } ];
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
        ProtectClock            = true;
        ProtectHostname         = true;
        ProtectProc             = "invisible";
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
        RestrictRealtime        = true;
        RestrictSUIDSGID        = true;
        RemoveIPC               = true;
        LockPersonality         = true;
        SystemCallArchitectures = "native";
        SystemCallFilter        = [ "@system-service" "~@privileged" "~@debug" "~@mount" ];
        UMask                   = "0077";
      };

      # `curl` and `dig` are the test plan's instruments: curl proves each
      # backend is reachable from HERE (and, from anywhere else, that it is
      # not), and dig is what checks the split-horizon answer differs from the
      # public one.  `openssl` reads the SANs off the issued certificate.
      environment.systemPackages = with pkgs; [ curl dnsutils openssl ];
      documentation.enable       = false;
      documentation.nixos.enable = false;
    };
  };
}
