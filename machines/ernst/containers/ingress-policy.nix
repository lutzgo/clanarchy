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
    (h "storyteller")
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
