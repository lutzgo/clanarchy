# machines/ernst/containers/ingress-policy.nix
#
# THE ONE PLACE THAT DECIDES WHICH HOSTNAMES CARRY forward-auth AND WHICH
# CANNOT.  Imported by BOTH containers/traefik.nix (which attaches the
# `authelia` middleware to routers) and containers/authelia.nix (which decides
# what `access_control` permits for the requests that reach it).
#
# ── WHY THIS FILE EXISTS AT ALL ──────────────────────────────────────────────
#
#   Before it, the same decision was written down in three places and enforced
#   in none.  containers/authelia.nix said so itself, in the header of the list
#   this file now owns:
#
#     "The two files have to agree, and there is no mechanism that makes them"
#
#   That is not a hypothetical.  It has already cost one production failure:
#   RomM shipped with the `authelia` middleware on its router and its hostname
#   missing from `protectedHosts`, so a user who had just logged in
#   successfully got a 403 — which reads as an Authelia fault and was a missing
#   line in a list.  The comment in that file predicted the failure and the
#   failure happened anyway, which is the argument for a mechanism rather than
#   a fourth comment.
#
#   So: ONE list, TWO consumers, and an evaluation-time guard in traefik.nix
#   that refuses to build if a router disagrees with what is declared here.
#
# ── THE CATEGORIES, AND THE LINE BETWEEN THEM ────────────────────────────────
#
#   The distinction is NOT "admin versus household", and getting that wrong is
#   how the wrong service ends up in the wrong list.  Jellyseerr is a household
#   service and IS protected; Audiobookshelf is a household service and is NOT.
#
#   THE ACTUAL TEST IS: CAN EVERY CLIENT OF THIS HOSTNAME RENDER A LOGIN PAGE
#   AND FOLLOW A 302?
#
#     yes -> `protectedHosts` or `householdHosts`.  forward-auth is free
#            security and costs a redirect the browser handles invisibly.
#     no  -> `appApiHosts`.  forward-auth BREAKS EVERY NATIVE CLIENT, and does
#            so in the worst possible way: the app has no browser to render the
#            portal, so it reports an opaque network error rather than a login
#            prompt.  The user's conclusion is "the server is broken".
#
#   This is the single most likely explanation for any future report of "works
#   in the browser, fails in the app".  Check this file first.
#
# ── appApiHosts IS NOT A CONVENIENCE.  IT IS A DELIBERATE UNAUTHENTICATED  ────
#    SURFACE, AND THE COMPENSATION IS WRITTEN DOWN
#
#   Every name in `appApiHosts` is answered by the APPLICATION, not by
#   Authelia.  When such a name is also in `wanExposed`, its own user database
#   is the entire boundary between the household's library and the internet.
#   There is no second factor on those names: Authelia's per-user regulation
#   and mandatory 2FA do not apply, because Authelia is never consulted.
#
#   What compensates, in the order it is relied on:
#
#     1. THE SERVICE'S OWN ACCOUNTS, which must therefore be strong.  This is
#        a precondition no file here can enforce; it is in the deploy
#        checklist in docs/guides/ernst-app-api-ingress.md.
#     2. `wan-ratelimit` + `wan-inflight`, inherited by every wan router.
#     3. `wan-login-ratelimit`, a MUCH stricter limit attached to the login and
#        token paths only, by higher-priority routers in traefik.nix.  A media
#        client legitimately makes hundreds of requests a minute; it
#        authenticates once.  The two therefore want different numbers, which
#        is the whole reason the login routers exist.
#     4. CrowdSec, which sees the 401s these services emit in Traefik's access
#        log and bans at the packet layer.  See containers/crowdsec.nix for the
#        local scenario that keys on exactly this.
#     5. The services' OWN brute-force controls where they have them —
#        Navidrome ships a login rate limit (5 attempts / 2 min, observed in
#        its startup log at 0.63.2) and Audiobookshelf has failed-login
#        backoff.  Komga has neither, which is stated rather than smoothed.
#
#   WHAT IS DELIBERATELY NOT DONE: geo-restriction to DE/EU source ranges.  It
#   was asked for and is not implementable here on acceptable terms.  Traefik
#   has no native geo filter; the only route to one is a Yaegi plugin fetched
#   from plugins.traefik.io at Traefik's startup, and containers/traefik.nix
#   rejects that pattern explicitly — putting an unpinned network fetch in the
#   start path of the proxy every service sits behind is strictly worse than
#   the thing it would defend against.  CrowdSec already drops at the packet
#   layer and is the answer here.  Recorded so it is a decision and not an
#   oversight.
#
# ── ADDING A SERVICE ─────────────────────────────────────────────────────────
#
#   Put its hostname in EXACTLY ONE of the three lists below.  traefik.nix
#   throws at evaluation if a router's middlewares disagree with the list it is
#   in, or if a routed hostname is in none of them.  Exposing it to the
#   internet is a SEPARATE act — `wanExposed` in traefik.nix, plus a public A
#   record, plus a ledger row in docs/roadmap.md.
{ baseDomain }:

let
  h = name: "${name}.${baseDomain}";
in
rec {
  ############################################################################
  # appApiHosts — EXEMPT FROM forward-auth, PERMANENTLY.
  #
  # Do not "fix" a service by moving it out of this list.  Each entry is here
  # because a native client would break, and the per-service argument is on
  # the router in containers/traefik.nix.  The guard there turns a move into a
  # build failure rather than a support ticket three weeks later.
  ############################################################################
  appApiHosts = [
    # Jellyfin.  TV apps, Android/iOS clients, Chromecast senders and DLNA-ish
    # devices, all authenticating with Jellyfin's own token API.  The oldest
    # exemption in the fleet and the one every other entry is argued against.
    (h "jellyfin")

    # Audiobookshelf.  Native mobile and TV apps with bearer tokens; app
    # support is a stated requirement for this library.
    (h "audiobookshelf")

    # Storyteller.  The SAME argument as Audiobookshelf directly above, for the
    # same household and in a stricter form — and it shipped in protectedHosts
    # until 2026-09-27 because nobody had tried the app yet.
    #
    # MEASURED, not inferred.  With forward-auth in front, the endpoints the
    # Storyteller Reader app actually calls answer like this:
    #
    #   GET  /api/v2/books  -> 302  https://auth.goclan.org/?rd=…
    #   POST /api/v2/token  -> 303  https://auth.goclan.org/?rd=…
    #
    # /api/v2/token is the LOGIN call.  The app posts credentials there and
    # carries a token afterwards; it has no browser, no cookie jar and no way
    # to express a redirect to a portal.  So the redirect does not merely
    # inconvenience the app, it intercepts the one request that would have
    # obtained the credential — the failure is total and looks like a broken
    # server rather than a policy.
    #
    # WHY THIS IS SAFER THAN EVERY OTHER NAME IN THIS LIST: it is NOT in
    # `wanExposed` and is not being added.  The other seven answer the public
    # internet; this one answers the LAN and the VPN only, so dropping
    # forward-auth widens the audience from "LAN browsers that got past
    # Authelia" to "LAN and tunnelled devices", not to everybody.  lgo asked
    # for VPN access specifically (2026-09-27) and this is the narrow form of
    # that request.
    #
    # WHAT CARRIES AUTHENTICATION INSTEAD: Storyteller's own accounts, which
    # are the entire boundary on this name from here on — no second factor and
    # no per-user regulation, exactly as the audiobookshelf ledger row records
    # for its name.  Its settings also expose `disablePasswordLogin` and
    # `authProviders`; neither is configured, so password login is the boundary.
    #
    # THE VPN STILL NEEDS A UDM-PRO POLICY AND THIS CHANGE DOES NOT SUPPLY IT.
    # Tunnelled clients land on VLAN 70 and have no route to VLAN 90 at all —
    # measured 2026-09-19, see docs/guides/ernst-app-api-ingress.md. Removing
    # forward-auth is necessary and not sufficient; without
    # `Allow VPN (70) -> 10.0.90.12:443/tcp` the app still cannot connect, and
    # it will fail in a way that looks identical to this bug.
    (h "storyteller")

    # Komga.  Komelia (Android), Mihon's Komga source extension, and any OPDS
    # v1/v2 reader.  All three authenticate with HTTP Basic or an API key
    # against /api/** and /opds/**; none has a browser.  Komga's per-user
    # library restrictions and age ratings are enforced INSIDE Komga on every
    # one of those paths, so exposing the vhost does not bypass them — that is
    # what makes this exemption safe for the kids' libraries specifically.
    (h "komga")

    # Navidrome.  The Subsonic/OpenSubsonic API at /rest/** is token auth in
    # query parameters by protocol definition; Tempo, Symfonium, play:Sub and
    # every other Subsonic client speak only that.  A 302 to a login portal is
    # not something the Subsonic protocol can express.
    (h "navidrome")

    # Calibre-Web-Automated.  THREE separate app protocols, none of which can
    # follow a redirect: OPDS (basic auth), the Kobo sync endpoint (a device
    # token in the URL path — a Kobo e-reader has no browser at all), and
    # /kosync (KOReader's progress-sync protocol, a custom header auth).
    # Its WEB UI is a different matter and goes to Authelia's OIDC provider
    # instead — see containers/cwa.nix.
    (h "cwa")

    # Immich (M22).  THREE client classes, and the third is why this entry is
    # not simply "another mobile app".
    #
    #   The mobile app (FP5, FP4) posts to /api/auth/login and then carries a
    #   bearer token.  The ordinary appApiHosts argument, same as Jellyfin's.
    #   The Kodi add-on on the TV speaks `x-api-key` over http.client, with no
    #   cookie jar and no browser at all.
    #   A SHARED ALBUM LINK is answered to an ANONYMOUS caller BY DESIGN.  That
    #   is the feature — it is how Sabine, who has no account here, sees the
    #   albums lgo sends her — and forward-auth would break it completely.
    #
    # So part of this vhost is MEANT to be unauthenticated, which no other
    # entry in this list is true of.  The honest statement of the posture is in
    # containers/immich.nix's header: Immich's accounts bound the LIBRARY, and
    # possession of a link bounds anything explicitly shared.  Shared links
    # take an expiry and a password in the UI; use them.
    (h "photos")

    # Nextcloud (M23).  THREE client classes, none of which can follow a 302,
    # and one of them is not a phone app:
    #
    #   The DESKTOP SYNC CLIENT on miralda, jens and biene — already installed
    #   by modules/desktop/noctalia-hm.nix — authenticates with an app password
    #   over /remote.php/dav/** and polls it continuously.
    #   DAVx5 on the phones speaks the same WebDAV/CalDAV/CardDAV endpoints with
    #   no browser anywhere in the process.
    #   vdirsyncer runs from a HEADLESS USER TIMER on miralda
    #   (modules/caldav-sync.nix) and has no way to display a portal, let alone
    #   a second factor.  Its failure mode under forward-auth would be a timer
    #   that quietly reports success while syncing Authelia's login page.
    #
    # THE WEB UI IS A DIFFERENT MATTER and goes to Authelia's OIDC provider
    # instead — see containers/nextcloud.nix and the client block in
    # containers/authelia.nix.  That is CWA's arrangement (OIDC INSTEAD OF the
    # middleware), not Grafana's or Open WebUI's (OIDC AS WELL AS it).
    #
    # UNLIKE photos, NOTHING HERE IS MEANT TO BE ANONYMOUS.  Nextcloud does have
    # public share links, but they are off unless somebody creates one, and this
    # entry does not depend on them the way Immich's does — the argument here is
    # purely the three clients above.
    (h "cloud")

    # Home Assistant (M24).  ONE client class, and it fails the test at the top
    # of this file more completely than anything else in this list.
    #
    #   The companion app on the phones walks /auth/login_flow once, exchanges
    #   the result for a token at /auth/token, and then holds an authenticated
    #   WEBSOCKET open at /api/websocket for the life of the session.  There is
    #   no browser anywhere in that, and no cookie jar for forward-auth to set.
    #
    # THE WEBSOCKET IS WHY THIS IS NOT MERELY "ANOTHER MOBILE APP".  Every other
    # entry here speaks request/response, so the worst forward-auth could do is
    # break each call the same way.  A 302 on an HTTP UPGRADE is not a login
    # prompt the app can act on — it is a handshake that never completes, and
    # what the household sees is a hub that is permanently "connecting".
    #
    # AND THE APP IS A SENSOR, NOT JUST A CLIENT.  Presence detection and zone
    # triggers work by the phone POSTing location to this hostname in the
    # background, with no user present.  There is nobody there to log in even
    # if something could render the form.
    #
    # WHAT DEFENDS IT, since Authelia never sees this name — and note this is
    # NOT Nextcloud's or CWA's arrangement, because there is no OIDC path
    # behind it either (core Home Assistant does not ship OIDC at this version,
    # and the local account is the recovery path for a house whose lights are
    # on this server):
    #
    #   * `ip_ban_enabled` + `login_attempts_threshold = 5`, configured in
    #     containers/home-assistant.nix.  A real per-SOURCE ban, written to
    #     ip_bans.yaml and refused at the application layer until a human
    #     removes the line.  It is the opposite key from Nextcloud's per-ACCOUNT
    #     throttle, so do not read either file as describing the other.
    #   * Native TOTP MFA on Home Assistant's own accounts, enrolled as a deploy
    #     step rather than offered as an option — docs/guides/ernst-app-api-
    #     ingress.md.
    #   * `wan-login-ratelimit` on /auth/login_flow and /auth/token, which is a
    #     clean match here because this application's credential path and its
    #     data path are genuinely different URLs.
    #
    # THAT FIRST CONTROL HAS A PREREQUISITE and it is one line: `trusted_proxies`
    # must name Traefik, or every request looks like it came from 10.0.90.12 and
    # the ban either never fires or takes the whole household offline at once.
    # Ledger row L14's lesson, in a second costume.
    (h "ha")

    # Karakeep (M27).  Bookmarks, archives and the search over them — and the
    # clients that fail the 302 test are ones THIS REPO INSTALLS:
    #
    #   the Karakeep browser extension on all four of lgo's browsers, which
    #   posts to /api/v1/bookmarks with a bearer token;
    #   the FLOCCUS adapter (service-modules/software.nix and
    #   machines/miralda/home-modules/browsers.nix install it on miralda and
    #   jens), syncing the browsers' own bookmark trees with the same token
    #   and no UI whatsoever;
    #   the mobile apps, same again.
    #
    # THAT IS UNUSUAL FOR THIS LIST AND WORTH SAYING PLAINLY.  Every other
    # exemption here is argued from a client somebody might install; this one
    # is argued from clients declared in this repository, on machines this
    # repository deploys.  Moving this name to protectedHosts would break a
    # sync that runs unattended and would show up as bookmarks silently
    # failing to propagate between two laptops.
    #
    # WHAT DEFENDS IT, since it IS on the internet (`wanExposed`, ledger row
    # L17) while Miniflux is not:
    #
    #   * Karakeep's own accounts with password auth DISABLED ENTIRELY
    #     (`DISABLE_PASSWORD_AUTH` + `DISABLE_SIGNUPS`), so the only way to
    #     obtain a session is through Authelia with a second factor, and the
    #     only way to obtain an API token is from inside such a session.
    #   * `wan-ratelimit` + `wan-inflight` at the edge.
    #   * `wan-login-ratelimit` on the credential path.
    #   * CrowdSec reading Traefik's access log.
    (h "karakeep")

    # Music Assistant (M30).  IT SHIPPED IN `protectedHosts` AND MOVED HERE ONE
    # DAY LATER, which is the direction this file's header warns about — so the
    # reason has to be better than "it did not work".
    #
    # THE ORIGINAL ENTRY WAS ARGUED FROM A FACT THAT IS FALSE.  It said "the only
    # client of this hostname is a browser", and therefore that Home Assistant's
    # WebSocket did not matter because the hub reached the container directly on
    # 10.0.90.30:8095, one L2 hop, never through this proxy.  That is not how the
    # integration works.  Read out of the deployed code
    # (homeassistant/components/music_assistant/config_flow.py):
    #
    #     login_url = f"{self.url}/login?{params}"
    #     return self.async_external_step(step_id="auth", url=login_url)
    #
    # `self.url` is the ONE url typed into the config flow, and it is used for
    # BOTH halves: the browser is redirected to `{url}/login`, and the hub's own
    # server-side calls — `GET {url}/info`, `POST {url}/auth/login` for the
    # long-lived token, and the persistent `{url}/ws` — go to the same place.
    # There is no second field for an internal address.
    #
    # So the hostname has a non-browser client after all, and it fails the test
    # at the top of this file exactly as `ha` does: `/ws` is an HTTP UPGRADE with
    # no cookie jar, and a 302 on it is a handshake that never completes.
    #
    # MEASURED RATHER THAN REASONED.  With the hub pointed at the direct address
    # the browser half is what broke instead — it was sent to
    # `http://10.0.90.30:8095/login?...`, which no human's machine may reach
    # (that container admits .12, .27 and .13 and nothing else), so the external
    # step hung on a blank page forever.  Neither URL can satisfy both halves;
    # only dropping the middleware makes one URL work for both.
    #
    # WHAT DEFENDS IT, and this list is unusually strong for a name here because
    # the application was READ rather than assumed (2.8.7):
    #
    #   * its own accounts, with roles (`UserRole.ADMIN`) and a per-user
    #     `player_filter`, so a household account can be scoped to some speakers;
    #   * `auth_middleware` on every route with a short bypass list, and
    #     `require_authentication()` in the handlers;
    #   * `/ws` tracks an authenticated user per connection and refuses admin
    #     commands to a non-ADMIN role — so the path that carries all the control
    #     is token-authenticated, not merely proxied;
    #   * `LoginRateLimiter`, an escalating PER-USERNAME backoff over a 30-minute
    #     window: 3-5 failures 30 s, 6-9 60 s, 10-14 120 s, 15+ 300 s.  Nextcloud's
    #     per-ACCOUNT shape, not Home Assistant's per-SOURCE `ip_ban`.
    #
    # AND IT IS THE ONLY NAME IN THIS LIST THAT IS NOT ON THE INTERNET.  Every
    # other entry here is also in `wanExposed`, which is what makes this list a
    # deliberate unauthenticated surface facing the world; this one is LAN-only,
    # with no public A record and no ledger row.  The compensation stack above is
    # therefore defending the house against the house, which is a different and
    # much smaller claim than the one the header is written for.
    #
    # THE DIRECT-HOP FIREWALL RULE FOR THE HUB IS GONE, not left behind: with the
    # hub arriving through Traefik like everything else, an accept for .27 on
    # 8095 would be a rule nothing uses and whose comment asserted the very thing
    # this entry disproves.  M26's first deploy-day defect REMOVED a firewall
    # rule rather than adding one; same move.
    (h "music")

    # Paperless-ngx (M32).  ONE client class, and it is the cleanest case in
    # this list: the Paperless Mobile app on lgo's and Sabine's phones POSTs
    # credentials to /api/token/, receives a DRF token, and sends it as an
    # `Authorization: Token …` header on every subsequent request.  There is no
    # browser in that process, so there is nothing to render a portal and
    # nothing to follow a 302 — forward-auth would turn every upload and every
    # search into an opaque network error.
    #
    # THE WEB UI GOES TO AUTHELIA'S OIDC PROVIDER INSTEAD, which makes this
    # CWA's and Nextcloud's arrangement (OIDC INSTEAD OF the middleware) rather
    # than Grafana's or Open WebUI's (OIDC AS WELL AS it).  A browser therefore
    # still gets two-factor; see containers/paperless.nix and the client block
    # in containers/authelia.nix.
    #
    # UNLIKE photos, NOTHING HERE IS MEANT TO BE ANONYMOUS, and unlike `music`
    # this one IS on the internet.  So the compensation stack in this file's
    # header is load-bearing rather than defending the house against itself,
    # and the two pieces that carry the most weight for this name are:
    #
    #   `PAPERLESS_ACCOUNT_ALLOW_SIGNUPS = false`, pinned in the container
    #   even though it is already the default, so nobody can register
    #   themselves against a WAN-exposed hostname; and
    #
    #   django-allauth's own rate limiting plus the `wan-login-ratelimit`
    #   router below.  Unlike `cloud`, this name CAN have one — see the
    #   `wanLoginPaths` entry in containers/traefik.nix for why the paths here
    #   are a login surface and Nextcloud's are every sync request.
    #
    # Paperless also offers TOTP of its own (`MFA_TOTP_ISSUER`), which is
    # runtime state and nothing in this repo can set.  It is worth enabling by
    # hand on the local admin, because that account is the recovery path and
    # the recovery path is the one credential the portal cannot protect.
    (h "docs")
  ];

  ############################################################################
  # householdHosts — forward-auth, reachable by non-admins.
  #
  # Its own list and its own access_control rule, deliberately kept out of
  # protectedHosts: that list feeds the admins-only rule, and merging them
  # would either hand `household` every admin UI or lock families out of the
  # request page, depending on which end you merged toward.
  ############################################################################
  householdHosts = [
    (h "jellyseerr")
  ];

  ############################################################################
  # protectedHosts — forward-auth, admins only.
  #
  # The ordinary case: operator-facing browser UIs with no native client a
  # redirect could break.  A route added in traefik.nix without its name here
  # hits Authelia's default_policy = "deny" and returns 403 to a user who has
  # just logged in successfully — the RomM failure described in the header.
  # The guard in traefik.nix now catches that at evaluation instead.
  ############################################################################
  protectedHosts = [
    (h "prowlarr")
    (h "sonarr")
    (h "radarr")
    (h "grafana")
    (h "bazarr")
    (h "cleanuparr")
    (h "mediathekarr")
    (h "tvheadend")
    (h "tubesync")
    (h "lidarr")
    (h "kapowarr")
    (h "questarr")
    (h "slskd")
    (h "bindery")
    (h "romm")

    # Open WebUI (M19).  Browser-only by construction — it IS a web chat client
    # — so it passes the test at the top of this file without argument and gets
    # forward-auth like any other admin surface.
    #
    # IT ALSO CARRIES OIDC, which is not a contradiction and is the Grafana
    # pattern rather than a new one: forward-auth decides whether the request
    # reaches the app at all, and OIDC tells the app WHO the user is so
    # conversations belong to an identity instead of to a shared session. CWA
    # takes OIDC *without* forward-auth for the opposite reason — its Kobo and
    # OPDS clients have no browser — and the two must not be confused.
    (h "chat")

    # The service index (M26).  The EASIEST case this file has, and it is worth
    # saying so explicitly because the name goes on the internet and the recent
    # additions to that set have all been exemptions.
    #
    # It passes the test at the top of this file without argument: the only
    # client is a browser, there is no native application, no bearer token, no
    # WebSocket and no OPDS reader — so there is nothing a 302 could break and
    # no reason to reach for appApiHosts.  Chat's posture, not Home
    # Assistant's.
    #
    # WHAT IS BEHIND THE DOOR IS A MAP, NOT A KEY.  Homepage fetches every
    # statistic server-side and sends the browser rendered numbers, so the ten
    # credentials it holds never cross this boundary in either direction.  That
    # is why one door is enough here and would not be enough for a service that
    # handed the browser a session on something else.
    (h "home")

    # Miniflux (M27).  IT STARTED IN `appApiHosts` AND WAS MOVED HERE, which
    # this file's header says not to do — so the reason has to be good.
    #
    # THE HEADER FORBIDS MOVING A NAME OUT OF `appApiHosts` TO "FIX" IT, i.e.
    # to make a broken client work by weakening the door.  This is the opposite
    # direction: the door is being made STRONGER, and the clients that
    # justified the exemption turned out not to exist here.
    #
    # The original entry argued from Miniflux's Fever (`/fever/`) and Google
    # Reader (`/reader/api/0/**`) APIs, which carry credentials in the request
    # and cannot follow a 302 — a correct argument about protocols nobody in
    # this house uses.  lgo reads in a browser.  So the exemption was buying a
    # weaker posture in exchange for a capability that was never exercised, and
    # M27's own section recorded `protectedHosts` as the tighter alternative at
    # the time the choice was first made.
    #
    # WHAT THIS COSTS, STATED SO IT IS NOT REDISCOVERED AS A FAULT: no native
    # RSS reader — Reeder, NetNewsWire, FocusReader — can ever connect to this
    # hostname again, on the LAN or off it, because forward-auth applies to
    # BOTH entrypoints.  Restoring that capability means moving this name back
    # up, and that is an ingress change with a ledger row, not a preference.
    #
    # WHAT IS UNAFFECTED, because neither goes through Traefik: the service
    # index's widget and Prometheus both reach `10.0.90.28:8080` directly, and
    # Miniflux's own outbound call to Karakeep is a client of THAT service, not
    # of this vhost.
    #
    # It keeps its OIDC client as well — which is now Grafana's arrangement
    # (forward-auth AND OIDC) rather than CWA's, and the two are no longer to
    # be read as the same thing for this name.
    (h "miniflux")
  ];

  ############################################################################
  # The portal itself.  Never carries the middleware it provides — it IS the
  # thing an unauthenticated request is redirected TO, so protecting it with
  # forward-auth is an infinite redirect.  Named here so the guard in
  # traefik.nix can account for every routed hostname rather than carrying an
  # exception it has to special-case silently.
  ############################################################################
  portalHost = h "auth";
}
