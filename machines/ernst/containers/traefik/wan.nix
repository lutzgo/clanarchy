# The `wan` entrypoint's surface, and the guard that enforces it.
#
# Everything that decides WHICH ROUTERS ARE INTERNET-REACHABLE lives here:
# the entrypoint's name and port, the authoritative `wanExposed` list, the
# per-service login paths that get a stricter limit, and `withWan` — which
# THROWS AT EVALUATION if a router omits `entryPoints` or if the set naming
# `wan` is anything but what `wanExposed` generates.
#
# Read the TWO ENTRYPOINTS block in ../traefik.nix's header first.  `grep -rn
# wan machines/ernst/containers/traefik/` is the complete audit of the external
# surface, which is the property M16's tunnel ingress list had and a middleware
# never can.
{
  lib,
  ingressPolicy,
  baseDomain,
}: rec {
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
}
