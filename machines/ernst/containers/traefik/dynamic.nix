# Traefik's DYNAMIC configuration: every router, service and middleware.
#
# Separated from ../traefik.nix because it is the half that changes when a
# service is added, and it was nine hundred and fifty lines inside a container
# declaration inside a module.  The argument list below is the complete set of
# peers it reads — computed, not guessed — so what this file depends on is
# visible without reading it.
#
# `withWan` is the guard AND the generator: it copies each router named in
# `wanExposed` onto the `wan` entrypoint and THROWS at evaluation if any router
# here omits `entryPoints`.  See ./wan.nix.
{
  withWan,
  baseDomain,
  jellyfinAddr,
  arrAddr,
  monitoringAddr,
  autheliaAddr,
  jellyfinPort,
  prowlarrPort,
  sonarrPort,
  radarrPort,
  grafanaPort,
  autheliaPort,
  bazarrPort,
  cleanuparrPort,
  mediathekarrPort,
  jellyseerrPort,
  homepagePort,
  tvheadendAddr,
  tvheadendPort,
  tubesyncAddr,
  tubesyncPort,
  lidarrPort,
  kapowarrPort,
  questarrPort,
  audiobookshelfPort,
  binderyPort,
  komgaPort,
  navidromePort,
  storytellerAddr,
  storytellerPort,
  rommAddr,
  rommPort,
  openWebuiAddr,
  openWebuiPort,
  immichAddr,
  immichPort,
  nextcloudAddr,
  nextcloudPort,
  homeassistantAddr,
  homeassistantPort,
  minifluxAddr,
  minifluxPort,
  mailAddr,
  mtaStsPort,
  karakeepAddr,
  karakeepPort,
  massAddr,
  massPort,
  paperlessAddr,
  paperlessPort,
  cwaAddr,
  cwaPort,
  slskdAddr,
  slskdPort,
  ...
}: {
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
}
