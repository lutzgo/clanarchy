# machines/ernst/containers/authelia.nix
#
# Authelia 4.39, in a declarative systemd-nspawn NixOS container.  One identity
# provider behind Traefik, doing two jobs that are easy to confuse:
#
#   1. FORWARD-AUTH for the admin UIs.  Traefik asks this container "may this
#      request through?" before it proxies anything to the *arr or to Grafana.
#      This is what retires ledger row L5 — the interim `mgmt-only` ipAllowList
#      M5 shipped precisely so that M7 would have something to replace.
#   2. OIDC PROVIDER for Grafana, which speaks OpenID Connect natively and
#      therefore gets real users and roles rather than an anonymous pass.
#
# Why nspawn: architecture invariant #1.  Authelia holds credentials and talks
# to nothing on the internet on anyone's behalf — no outbound fetches, no
# attacker-supplied URLs, no SMTP (see NOTIFIER).  Trusted tier, shared kernel.
#
# ── AUTHELIA, NOT KEYCLOAK.  Recorded so it reads as a choice ────────────────
#
#   Keycloak was the alternative and was rejected before any code was written:
#
#     - ONE GO BINARY versus a JVM stack.  Authelia's container is ~50 MB and
#       its resident set is tens of megabytes; Keycloak wants a JVM, a heap
#       setting, and a warm-up.  On a box that also runs a raidz1, a GPU
#       compute service and a TV session, that is not free.
#     - FORWARD-AUTH IS NATIVE.  Authelia's `/api/authz/forward-auth` endpoint
#       exists for exactly the Traefik middleware below.  Keycloak has no
#       equivalent; putting it in front of the *arr means running a second
#       component (oauth2-proxy) as well, i.e. two moving parts where the whole
#       point of this milestone is one.
#     - IT IS STILL AN OIDC PROVIDER, which is the other half of the milestone.
#       Grafana needs a real IdP, and Authelia is one.
#     - NO FEDERATION REQUIREMENT.  Keycloak's weight buys SAML, identity
#       brokering, realms and user federation against LDAP/AD.  This is a
#       household with two accounts and no directory to federate with.  Paying
#       for capability nobody has a use for is how a homelab acquires a service
#       it cannot debug.
#
#   Do not re-litigate this.  What WOULD reopen it: an actual SAML consumer, or
#   a second person's directory to federate against.
#
# ── Networking: veth on br0, Services VLAN 90 ────────────────────────────────
#
#   Copied from containers/traefik.nix, which copied it from
#   containers/jellyfin.nix ("Networking — v2"), the working version of this
#   pattern: KeepMaster rather than Bridge=, the ExecStartPost that settles the
#   VLAN race, and the 20 s wait-online cap that stops a DHCP failure from
#   restart-looping the container.  Read jellyfin.nix's header for the full
#   rationale — including why this is a veth and not a macvlan or a tap.
#
#   MAC 02:00:00:90:00:07 → 10.0.90.15, the next free pair in the allocation
#   table in machines/ernst/networking.nix.  DHCP with a reservation on the
#   UDM-Pro keyed on the pinned MAC, never a static address here: the UDM-Pro
#   owns the subnet and the pool, and a second copy in the repo diverges
#   silently.  The reservation must be INSIDE the pool (10.0.90.6–.254).
#
#   THIS CONTAINER IS NOT REACHABLE FROM ANY CLIENT VLAN, and that is the
#   design.  The only consumer-zone rule on the UDM-Pro points at Traefik's
#   .12; the login portal is served at auth.goclan.org THROUGH Traefik, exactly
#   like every other name.  9091 accepts .12 and nothing else.
#
#   That restriction is not cosmetic.  Authelia's authz endpoints TRUST the
#   X-Forwarded-* headers on every request they receive — they have to, that is
#   how a forward-auth endpoint learns what the user asked for.  Anything that
#   can reach 9091 directly can therefore assert any target URL it likes.  The
#   source restriction is what makes that trust safe, and it is the same
#   mechanism (a) containers/traefik.nix imposes on Jellyfin and the *arr.
#
# ── WHAT IS BEHIND IT, AND WHAT IS NOT ───────────────────────────────────────
#
#   Behind forward-auth:  prowlarr, sonarr, radarr, grafana   (two_factor)
#   Not behind it:        jellyfin                            (forever)
#                         auth.goclan.org itself              (necessarily)
#
#   JELLYFIN IS EXEMPT, PERMANENTLY.  containers/traefik.nix states this at
#   length under "JELLYFIN KEEPS NATIVE AUTH, FOREVER" and it is repeated here
#   because this is the file whose existence creates the temptation: TV apps,
#   the mobile clients, Chromecast senders and every DLNA-ish device
#   authenticate with Jellyfin's own token API and cannot perform an
#   interactive OIDC redirect.  Put this middleware on that route and the app
#   fails with an opaque network error rather than a login prompt.
#
#   THERE ARE NO BYPASS RULES, and that is a finding rather than an omission.
#   The milestone brief said to enumerate the OIDC endpoints and health checks
#   that must be unauthenticated "for the flow to work".  Enumerated, the list
#   is empty: `auth.goclan.org` carries no middleware on its Traefik router at
#   all, so `/.well-known/openid-configuration`, `/api/oidc/authorization`,
#   `/api/oidc/token`, `/api/oidc/userinfo` and `/api/health` are reached
#   without passing through forward-auth in the first place.  A `bypass` rule
#   in access_control would apply to requests Traefik forwards for AUTHORIZATION
#   — and no request to those paths is ever one of those.  Adding rules that
#   cannot match would be worse than adding none: it would read as enforcement.
#
# ── THE ipAllowList IS REMOVED, NOT STACKED.  Decision, with its cost ────────
#
#   M5's `mgmt-only` middleware (10.0.10/24 LAN, 10.0.50/24 Servers, 10.0.70/24
#   travel-wg) is DELETED in this milestone rather than kept underneath
#   forward-auth as defence in depth.  Three reasons, and one real cost:
#
#     - AN IP ALLOW-LIST UNDER AN IdP DEFEATS THE IdP.  The point of adding
#       credentials plus TOTP is that access stops depending on where you are.
#       Keeping the list means valid credentials and a correct TOTP code still
#       fail from a phone on the IoT VLAN or from any network nobody
#       pre-declared — which is most of what this milestone was for.
#     - TWO MECHANISMS FOR ONE PROPERTY is the thing containers/traefik.nix
#       argues against in its own words: "two sources of truth for one property
#       is how you get a rule nobody dares delete because nobody can prove what
#       it does."  The same reasoning applies to the control it shipped as
#       interim.
#     - THE LAYERING IS ALREADY THERE, and it is untouched.  Every backend
#       still refuses its own web port from anything but 10.0.90.12, so the
#       only path to the *arr is through Traefik — and after this PR the only
#       way through Traefik is through here.
#
#   THE COST, stated plainly rather than buried: the LOGIN PORTAL becomes
#   reachable from the IoT VLAN.  The `Allow Traefik` ZBF policy already
#   permits IoT → 10.0.90.12:443, so a compromised smart device can now see a
#   login page it previously could not.  What it meets there is a two_factor
#   policy and Authelia's regulation (below): three failures in five minutes
#   costs a fifteen-minute ban, per user.  That is the trade — an exposed login
#   form in exchange for access that does not depend on the source address.
#
# ── SECRETS ──────────────────────────────────────────────────────────────────
#
#   Five generated, two prompted, none in the store and none in this file.
#
#     authelia-secrets   jwt / session / storage-encryption / oidc-hmac /
#                        oidc-issuer-private-key      GENERATED — nobody types
#                        these, so prompting for them would only invite a weak
#                        value.
#     authelia-users     one password PROMPT per account, hashed with argon2id
#                        by authelia's own CLI, emitted as a users_database.yml
#                        — a human types these into a login form.
#     authelia-oidc      Grafana's client secret, generated ONCE as a pair: the
#                        plaintext for Grafana and the pbkdf2 digest for the
#                        client block here, so the two cannot drift apart.
#
#   STAGED, not bound out of /run/secrets: that path is a symlink to a
#   per-generation directory REPLACED on every deploy, so an nspawn bind
#   established at container start keeps exposing a deleted generation.  Same
#   shape and the same reason as containers/traefik.nix.
#
#   OWNERSHIP DIFFERS FROM TRAEFIK'S, and it matters.  Traefik's token is read
#   by PID 1 as an EnvironmentFile before it drops privileges, so it is
#   0400 root:root.  Authelia reads its own secret files, unprivileged, from
#   the paths in AUTHELIA_*_FILE — so every file here is 0400 uid 3008, inside
#   a 0711 directory.  PR #84 shipped that shape broken once (a file the
#   consumer could read, in a directory it could not traverse); 0711 is what
#   prevents the repeat.
#
#   GENERATE BEFORE YOU DEPLOY.  clan-core cannot know a sops secret's path
#   until the secret exists; until then `files.<n>.path` evaluates to the
#   literal "/no-such-path" and THAT is baked into the staging script.  The
#   failure is fail-closed and loud — the staging unit fails, container@authelia
#   never starts, and there is no identity provider rather than one that lets
#   everything through.
#
# ── NOTIFIER: filesystem, and TOTP enrolment is an operator step ─────────────
#
#   Authelia requires exactly one notifier.  The choices are SMTP and a file.
#   SMTP would mean a mail credential, an outbound path to a mail host, and a
#   third-party dependency in the login path of every admin UI in the house.
#   The file costs one `cat`.
#
#   The consequence is real, it is worse than it first looks, and it cost a
#   round on deploy day.  READ THIS BEFORE ENROLLING ANYONE.
#
#   Authelia 4.39 does not let you register a 2FA device on a merely
#   authenticated session.  It first requires a SESSION ELEVATION: it sends an
#   eight-character ONE-TIME CODE through the notifier, and you type that back
#   before the QR appears.  Our notifier is a file, so "check your email" means
#   reading a file on ernst.  Use the helper:
#
#       authelia-code            # on ernst, as root
#
#   THREE TRAPS, ALL OF WHICH FIRED ON 2026-08-24:
#
#     1. THE FILE IS OVERWRITTEN, NOT APPENDED, and the trap is the opposite
#        of what it looks like.  Authelia's filesystem notifier truncates on
#        every send, so notification.txt always holds EXACTLY the newest
#        notification and nothing else.  Measured: six rows in `one_time_code`,
#        one `Date:` block in the file, mtime frozen at the last send.
#
#        So the file is never stale — YOUR TERMINAL IS.  Read a code, take
#        four minutes over it, and the thing you paste is expired even though
#        the file has since been rewritten with a fresh one.  The errors are
#          "the code didn't match any recorded code challenges"
#        and "the code challenge has expired", and BOTH mean the same thing:
#        the code you typed is not the code that is currently valid.  Re-read
#        the file; do not re-read your scrollback.
#
#        (An earlier revision of this comment asserted the file was
#        append-only and that `cat` showed the oldest code.  That was inferred
#        from a single `tail` and never checked — the same
#        prediction-recorded-as-measurement this repo keeps catching itself
#        doing.  `cat` was fine all along; the AGE is what mattered.)
#     2. THE CODE EXPIRES in five minutes (identity_validation's default).
#        This is the real failure mode, which is why `authelia-code` prints
#        the age in front of the code and says EXPIRED rather than letting a
#        stale one be typed.
#     3. GENERATING CODES IS RATE-LIMITED, in stacked buckets, and clicking
#        again because "it didn't work" is what makes it much worse:
#          Rate Limit Exceeded  bucket=1 delay=35s
#          Rate Limit Exceeded  bucket=2 delay=545s
#          Rate Limit Exceeded  bucket=3 delay=1745s      ← 29 minutes
#        The UI reports this as "Failed to generate the One-Time Code. Please
#        try again later", which sounds like a broken notifier and is not.
#
#        WHILE RATE-LIMITED, NO NEW NOTIFICATION IS WRITTEN — so the file
#        keeps showing the last (expired) code, which reads exactly like "the
#        helper is broken" and is in fact the rate limit being obeyed.  Check
#        the log before believing anything else:
#          nixos-container run authelia -- \
#            journalctl -u authelia-main | grep "Rate Limit"
#
#        THE LIMITER IS IN-MEMORY.  There is no rate-limit table in the
#        schema (checked), so `machinectl restart authelia` clears it
#        immediately — at the cost of every active session, since the session
#        store is in-memory too.  That is the escape hatch when the 29-minute
#        bucket is in the way; STOP CLICKING first, because each click
#        re-arms it.
#
#   The whole flow, once, per account:
#       log in with the password  →  Settings → 2FA → One-Time Password → ADD
#       →  `authelia-code` on ernst  →  type it  →  QR appears  →  scan.
#
#   AND ONE UI TRAP THAT IS NOT OURS: the 2FA page can land on "Security Key"
#   (WebAuthn) even when the account's preferred method is TOTP.  With nothing
#   registered it then shows only "Register device" and no code box, which
#   looks like a broken login.  Click METHODS and pick One-Time Password.
#
# ── Storage layout on this host (see machines/ernst/disko.nix) ───────────────
#
#   /srv/state/authelia   zdata/state   RW into the container at
#                                       /var/lib/authelia-main
#     db.sqlite3                        users' TOTP secrets, sessions' identity
#                                       records, the regulation ledger
#     notification.txt                  the "mail" above
#
#   INVARIANT #7 APPLIES HARDER HERE THAN ANYWHERE ELSE SO FAR.  zroot rolls
#   back; every TOTP secret in the house lives in that one SQLite file.  A
#   deploy that put it on zroot would work perfectly until the next reboot and
#   then lock every account out of every admin UI at once, with the recovery
#   path itself behind the thing that broke.  It is on zdata.
{ config, lib, pkgs, ... }:
let
  ############################################################################
  # Identity.
  ############################################################################

  # Guest-side MAC — 02:00:00:<vlan>:00:<seq>, allocated in the table in
  # machines/ernst/networking.nix against DHCP reservation 10.0.90.15.  This is
  # the address the UDM-Pro sees; never the host-side vb-authelia.
  autheliaMac = "02:00:00:90:00:07";
  vlanId      = 90;

  # Host side of the veth pair.  nspawn names it vb-<container> when
  # --network-bridge= is used — "vb-", not "ve-".
  vethName = "vb-authelia";

  # Numeric ids, continuing the 3000-range family.  3006/3007 are M6's
  # prometheus and grafana.  nspawn passes uids and gids through unmapped, so
  # an id chosen here is an id on zdata — and /srv/state/authelia is on zdata.
  #
  # NOT in group media.  An identity provider has no business holding a handle
  # to the library.
  autheliaUid = 3008;
  autheliaGid = 3008;

  # The instance name.  It decides the unit name (authelia-main.service), the
  # user and group (authelia-main), and StateDirectory (authelia-main) — which
  # is the path the bind mount below has to match.
  instanceName = "main";
  stateDirName = "authelia-${instanceName}";
  dataDir      = "/var/lib/${stateDirName}";

  ############################################################################
  # Names, addresses, ports.
  ############################################################################

  baseDomain = "goclan.org";

  # The portal's own name.  It has to be inside the session cookie's domain
  # (below) or Authelia refuses to start — the cookie it sets on auth.<domain>
  # is the one every other <name>.<domain> presents back.
  authHost = "auth.${baseDomain}";

  # PEER addresses, hard-coded for the same reason containers/traefik.nix
  # hard-codes its backends: a container declaring its OWN address would create
  # a second source of truth that diverges silently from the UDM-Pro's pool,
  # while a reference to a peer cannot diverge quietly — if a reservation
  # moves, the thing that depends on it fails immediately and loudly.
  proxyAddress      = "10.0.90.12";   # traefik   — the only client of 9091
  monitoringAddress = "10.0.90.14";   # M6        — the only client of 9959

  autheliaPort = 9091;

  # M6.  Authelia's own Prometheus telemetry, on its own listener and
  # source-restricted to the monitoring container.  Same shape and the same
  # argument as Traefik's metrics entryPoint: a separate port is restricted
  # once in the container firewall and cannot be re-exposed by adding a router,
  # whereas a route on :443 would be reachable by everything the consumer-zone
  # ZBF rule already permits.
  #
  # Worth having specifically BECAUSE of this milestone: after today, an
  # Authelia that is down is every admin UI in the house being down, and an
  # identity provider nobody watches is the thing that fails silently.
  metricsPort = 9959;

  ############################################################################
  # Accounts.
  #
  # ADD A USER BY ADDING A LINE HERE and re-running `clan vars generate ernst`
  # — the generator's prompts, the users_database.yml and the access-control
  # subject list are all derived from this list, so there is nothing to keep in
  # step.  `sgo` is the expected next entry.
  #
  # Both accounts are in `admins`, which is the only group any rule mentions.
  # A differentiated group (say `viewers`, one_factor on Grafana only) is one
  # entry in `groups` plus one rule below; it is not built because nobody has
  # asked for the distinction, and an access-control matrix for a household of
  # two is a thing to get wrong rather than a thing to have.
  #
  # The email addresses are NOT correspondence addresses.  The notifier writes
  # to a file (see the header), so these are identifiers Authelia uses to
  # address a notification and to let a user log in by email as well as by
  # username.  lgo's is already public — it is the author address on every
  # commit in this repo.
  ############################################################################
  autheliaUsers = [
    { name = "lgo"; displayName = "Lutz";  email = "lutz0go@gmail.com"; groups = [ "admins" ]; }
    { name = "go";  displayName = "Go";    email = "go@${baseDomain}";  groups = [ "admins" ]; }
  ];

  adminGroup = "admins";

  # The names forward-auth protects.  Kept as one list because it is used
  # twice — once for the access-control rule here, once as the thing the
  # Traefik middleware is attached to in containers/traefik.nix.  The two files
  # have to agree, and there is no mechanism that makes them; if a route is
  # added there without a domain here, Authelia's default_policy = "deny"
  # refuses it, which is the right direction to fail in.
  protectedHosts = [
    "prowlarr.${baseDomain}"
    "sonarr.${baseDomain}"
    "radarr.${baseDomain}"
    "grafana.${baseDomain}"

    # M12.  Three more admin UIs in the existing arr container.  All three are
    # browser-only and admin-facing, i.e. the case forward-auth is for — none
    # of them has a TV or mobile client that a redirect would break, so the
    # Jellyfin exemption does not come into it.
    #
    # These MUST stay in step with the routers in containers/traefik.nix.  The
    # comment above says what happens otherwise and it is worth repeating in
    # the direction that actually bites: a route added THERE without a name
    # HERE hits default_policy = "deny" and returns 403 to a user who has just
    # logged in successfully, which reads like an Authelia fault and is a
    # missing line in a list.
    "bazarr.${baseDomain}"
    "cleanuparr.${baseDomain}"
    "mediathekarr.${baseDomain}"
  ];

  ############################################################################
  # Secrets staging.
  ############################################################################
  secretsDir = "/run/authelia-secrets";

  jwtFile        = "${secretsDir}/jwt-secret";
  sessionFile    = "${secretsDir}/session-secret";
  storageKeyFile = "${secretsDir}/storage-encryption-key";
  oidcHmacFile   = "${secretsDir}/oidc-hmac-secret";
  oidcKeyFile    = "${secretsDir}/oidc-issuer-private-key";
  usersFile      = "${secretsDir}/users_database.yml";
  oidcClientFile = "${secretsDir}/oidc-clients.yml";

  secretsGen = config.clan.core.vars.generators.authelia-secrets;
  usersGen   = config.clan.core.vars.generators.authelia-users;
  oidcGen    = config.clan.core.vars.generators.authelia-oidc;

  # Grafana's OIDC redirect target.  Grafana's generic_oauth provider always
  # calls back to <root_url>/login/generic_oauth, and root_url is set from the
  # same domain in service-modules/monitoring.nix.
  grafanaRedirectUri = "https://grafana.${baseDomain}/login/generic_oauth";
in
{
  ##############################################################################
  # Host-side wiring.
  ##############################################################################

  # State on zdata.  0700 and owned by the service, exactly like
  # /srv/state/{jellyfin,sonarr,traefik,monitoring}.
  #
  # NUMERIC ids on purpose — `authelia-main` is a container user and the host
  # has no matching passwd entry.
  systemd.tmpfiles.rules = [
    "d /srv/state/authelia 0700 ${toString autheliaUid} ${toString autheliaGid} -"
  ];

  ##############################################################################
  # `authelia-code` — print the LATEST one-time code, and only that.
  #
  # See NOTIFIER in the file header for why this exists.  THE AGE IS THE POINT,
  # not the extraction: the notifier overwrites the file, so `cat` already
  # showed the right code — what it did not show is that the code was minted
  # sixteen minutes ago and died eleven minutes back.  A five-minute lifetime
  # against forty lines of boilerplate is how a stale paste happens, and both
  # errors Authelia returns for it ("didn't match", "expired") point at the
  # code rather than at the clock.
  #
  # So this prints the value, then the age, then says EXPIRED when it is —
  # which is the one line that would have prevented the whole episode.
  # Rate-limiting means a fresh code may not be obtainable for half an hour, so
  # noticing staleness BEFORE typing is worth more than it sounds.
  #
  # `--wait` EXISTS BECAUSE THE ORDER IS A TRAP, and telling people to get the
  # order right is not a fix.  Reading the file and THEN clicking ADD gets you
  # a code that the click itself invalidates:
  #
  #     id 6  issued 17:09:34  revoked 17:09:43     ← superseded by the next ADD
  #     id 7  issued 17:50:52  expires 17:55:52     ← the live one, unread
  #
  # and Authelia reports typing the first of those as "the code challenge has
  # EXPIRED", which sends you looking at clocks rather than at ordering.  Each
  # ADD mints a new code and revokes the previous one; so does cancelling or
  # closing the dialog.
  #
  # With `--wait` the tool blocks on the file's mtime and prints the code the
  # instant the notifier writes it, so the sequence becomes "run this, then
  # click" and there is no earlier code in scrollback to reach for.  It cannot
  # print a stale one because it only prints on a CHANGE.
  #
  # Root-only by construction: the file is 0600 uid 3008 on zdata and this
  # reads it from the host rather than through the container, so there is no
  # nsenter and nothing to keep in step with the container's paths.
  ##############################################################################
  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "authelia-code";
      runtimeInputs = [ pkgs.coreutils pkgs.gnused pkgs.gnugrep pkgs.gawk ];
      text = ''
        f=/srv/state/authelia/notification.txt

        wait=0
        case "''${1-}" in
          -w|--wait) wait=1 ;;
          "")        ;;
          *)
            echo "usage: authelia-code [--wait]" >&2
            echo "  --wait  block until the NEXT notification is written, then" >&2
            echo "          print it.  Run this BEFORE clicking ADD: the click" >&2
            echo "          revokes whatever code the file already holds." >&2
            exit 2
            ;;
        esac

        if [ "$wait" = 1 ]; then
          # mtime, not content: the notifier rewrites the whole file, and two
          # consecutive codes could in principle be equal.  A changed mtime is
          # the event; the content is just what we read afterwards.
          before=$(stat -c %Y "$f" 2>/dev/null || echo 0)
          echo "waiting for a new one-time code - click ADD now (120s)…" >&2
          n=0
          while [ "$n" -lt 120 ]; do
            n=$(( n + 1 ))
            sleep 1
            now=$(stat -c %Y "$f" 2>/dev/null || echo 0)
            if [ "$now" != "$before" ]; then
              break
            fi
          done
          if [ "$n" -ge 120 ]; then
            echo "authelia-code: no new notification in 120s." >&2
            echo "  Either ADD was not clicked, or the request was rate-limited" >&2
            echo "  - check:  nixos-container run authelia -- \\" >&2
            echo "              journalctl -u authelia-main | grep 'Rate Limit'" >&2
            exit 1
          fi
        fi

        if [ ! -s "$f" ]; then
          echo "authelia-code: no notification has ever been sent." >&2
          echo "  The file is created lazily, on the first one-time code." >&2
          echo "  Log in at https://${authHost} and click ADD under One-Time" >&2
          echo "  Password first, then run this again." >&2
          exit 1
        fi

        # Blocks begin with a "Date: " line; the newest is last.
        start=$(grep -n "^Date: " "$f" | tail -1 | cut -d: -f1)
        if [ -z "$start" ]; then
          echo "authelia-code: no 'Date:' header in $f - unexpected format." >&2
          exit 1
        fi
        block=$(tail -n +"$start" "$f")

        when=$(printf '%s\n' "$block" | sed -n '1s/^Date: \(....-..-.. ..:..:..\).*/\1/p')
        subj=$(printf '%s\n' "$block" | sed -n 's/^Subject: //p' | head -1)
        who=$(printf '%s\n'  "$block" | sed -n 's/^Recipient: //p' | head -1)

        # The payload is the first non-empty line after the first rule of
        # dashes.  That is the code for an elevation notification and the URL
        # for a link-style one, which is why this prints whatever it finds
        # rather than validating a shape.
        val=$(printf '%s\n' "$block" | awk '/^-{10,}/ { seen = 1; next } seen && NF { print; exit }')
        if [ -z "$val" ]; then
          echo "authelia-code: found a notification but no payload in it." >&2
          echo "  Read it directly:  tail -40 $f" >&2
          exit 1
        fi

        age=""
        if [ -n "$when" ]; then
          now=$(date +%s)
          then_=$(date -d "$when" +%s 2>/dev/null || echo "")
          if [ -n "$then_" ]; then
            secs=$(( now - then_ ))
            if [ "$secs" -lt 300 ]; then
              age="$secs s ago"
            else
              age="$(( secs / 60 )) min ago - EXPIRED, request a new one"
            fi
          fi
        fi

        printf '%s\n' "$val"
        printf '\n'
        printf '  for      %s\n' "''${who:-?}"
        printf '  subject  %s\n' "''${subj:-?}"
        printf '  issued   %s  %s\n' "''${when:-?}" "$age"
        # ASCII only in this block, and no backticks.  writeShellApplication
        # runs shellcheck at build time: backticks inside single quotes read as
        # command substitution (SC2016), and an em-dash makes shellcheck's own
        # output fail to encode in the build sandbox, which turns a style
        # warning into a build error naming neither cause.
        printf '\n'
        printf '  Codes expire after 5 minutes, and clicking ADD again revokes\n'
        printf '  this one.  If you already had a code before clicking, it is\n'
        printf '  dead: run "authelia-code --wait" and click AFTER starting it.\n'
        printf '  "Failed to generate the One-Time Code" in the portal is the\n'
        printf '  RATE LIMIT, not a broken notifier; stop clicking and wait.\n'
      '';
    })
  ];

  # Stage every secret where the container can see it.
  #
  # ROTATING ANY OF THEM needs a restart, not just a deploy: this unit's script
  # embeds the sops PATH and not the contents, so systemd sees an unchanged
  # unit and does not re-run it.  The generators below therefore carry
  # `restartUnits`, which is what makes `clan vars generate ernst` +
  # `clan machines update ernst` sufficient.  By hand it is:
  #     systemctl restart authelia-secrets container@authelia
  systemd.services.authelia-secrets = {
    description = "Stage Authelia's secrets and user database for container@authelia";
    after       = [ "local-fs.target" ];
    before      = [ "container@authelia.service" ];
    requiredBy  = [ "container@authelia.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.coreutils ];
    script = ''
      set -euo pipefail

      # 0711: traversable by anyone, listable by nobody.  The files inside are
      # read by the AUTHELIA uid, unprivileged, so it must be able to walk in -
      # and 0700 root:root here would produce EACCES on every one of them with
      # a message that names the file rather than the directory.  See PR #84.
      install -d -m 0711 -o root -g root ${secretsDir}

      ${lib.concatMapStrings (spec: ''
        install -m 0400 -o ${toString autheliaUid} -g ${toString autheliaGid} \
          ${spec.src} ${spec.dst}
      '') [
        { src = secretsGen.files."jwt-secret".path;              dst = jwtFile; }
        { src = secretsGen.files."session-secret".path;          dst = sessionFile; }
        { src = secretsGen.files."storage-encryption-key".path;  dst = storageKeyFile; }
        { src = secretsGen.files."oidc-hmac-secret".path;        dst = oidcHmacFile; }
        { src = secretsGen.files."oidc-issuer-private-key".path; dst = oidcKeyFile; }
        { src = usersGen.files."users_database.yml".path;        dst = usersFile; }
      ]}

      # ── The OIDC client block ───────────────────────────────────────────
      #
      # Built here rather than in the Nix config for one reason: it carries
      # Grafana's client secret DIGEST, and the Nix store is world-readable on
      # this host.  A pbkdf2-sha512 digest of 72 random alphanumerics is not
      # meaningfully crackable - the point is not to publish credential
      # material at all, so there is nothing to argue about later.
      #
      # The digest's own alphabet is base64 with `.` and `/`, so it never
      # contains a single quote and the YAML quoting below is safe.  It DOES
      # contain `$`, which is why the value is written straight out of the file
      # with `tr` rather than through a shell variable.
      umask 077
      {
        echo "identity_providers:"
        echo "  oidc:"
        echo "    clients:"
        echo "      - client_id: 'grafana'"
        echo "        client_name: 'Grafana'"
        printf "        client_secret: '"
        tr -d '[:space:]' < ${oidcGen.files."grafana-client-secret-digest".path}
        echo "'"
        echo "        public: false"
        echo "        authorization_policy: 'two_factor'"
        echo "        require_pkce: true"
        echo "        pkce_challenge_method: 'S256'"
        echo "        consent_mode: 'implicit'"
        echo "        token_endpoint_auth_method: 'client_secret_basic'"
        echo "        redirect_uris:"
        echo "          - '${grafanaRedirectUri}'"
        echo "        scopes:"
        echo "          - 'openid'"
        echo "          - 'profile'"
        echo "          - 'groups'"
        echo "          - 'email'"
      } > ${oidcClientFile}.new
      chown ${toString autheliaUid}:${toString autheliaGid} ${oidcClientFile}.new
      chmod 0400 ${oidcClientFile}.new
      mv -f ${oidcClientFile}.new ${oidcClientFile}
    '';
  };

  # Host side of the container's veth - a VLAN-90 port on br0.
  #
  # There is deliberately NO `networking.firewall.allowedTCPPorts` here.  9091
  # is opened inside the container's own netns; on the host it is not a port at
  # all.  Nothing on any consumer VLAN is permitted to reach this container:
  # the portal is served through Traefik like every other name.
  #
  # KeepMaster, not Bridge=: nspawn creates this link AND enslaves it to br0
  # itself, so Bridge= would make networkd fight nspawn over the master.
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

  # Re-assert the VLAN membership after nspawn has created the veth.  Same real
  # race as vb-jellyfin, vb-arr, vb-traefik and vb-monitoring: networkd applies
  # [BridgeVLAN] only once it observes the link's master, and nspawn sets that
  # master out of band.  `bridge vlan add` is idempotent; the "-" prefix keeps
  # a backstop from becoming a new failure mode.
  #
  # `bridge vlan show dev vb-authelia` remains the check - do not trust silence
  # from either mechanism.
  systemd.services."container@authelia".serviceConfig.ExecStartPost = [
    "-${pkgs.iproute2}/bin/bridge vlan add dev ${vethName} vid ${toString vlanId} pvid untagged"
  ];

  ##############################################################################
  # Vars generators.
  ##############################################################################

  # ── The five values nobody types ──────────────────────────────────────────
  #
  # GENERATED, not prompted, and each one exists for a different reason:
  #
  #   jwt-secret              signs the identity-verification tokens in the
  #                           password-reset and TOTP-registration links.
  #   session-secret          signs/encrypts the session cookie.
  #   storage-encryption-key  encrypts the TOTP secrets and WebAuthn
  #                           credentials AT REST in db.sqlite3.  Changing it
  #                           makes every enrolled second factor
  #                           undecryptable - Authelia ships
  #                           `storage encryption change-key` for the supported
  #                           rotation, and a `clan vars` regeneration is NOT
  #                           it.  clan only runs a generator when its output
  #                           is missing, so this is stable for the life of the
  #                           machine unless someone deletes it deliberately.
  #                           Treat that as a one-way door, exactly like
  #                           Grafana's secret_key in
  #                           service-modules/monitoring.nix.
  #   oidc-hmac-secret        signs OIDC authorization codes and tokens.
  #   oidc-issuer-private-key the RSA key Grafana's ID tokens are signed with,
  #                           published at /jwks.json.  4096-bit: it is issued
  #                           once and never rotated by a deploy, so the cost
  #                           is a few hundred milliseconds one time.
  #
  # `authelia crypto rand` rather than /dev/urandom + tr: it is the same tool
  # that will verify these values, it cannot produce a length or charset
  # Authelia rejects, and it removes the SIGPIPE-under-pipefail trap that
  # `tr -dc … | head -c N` carries.
  clan.core.vars.generators.authelia-secrets = {
    files."jwt-secret".secret              = true;
    files."session-secret".secret          = true;
    files."storage-encryption-key".secret  = true;
    files."oidc-hmac-secret".secret        = true;
    files."oidc-issuer-private-key".secret = true;

    files."jwt-secret".restartUnits              = [ "authelia-secrets.service" "container@authelia.service" ];
    files."session-secret".restartUnits          = [ "authelia-secrets.service" "container@authelia.service" ];
    files."storage-encryption-key".restartUnits  = [ "authelia-secrets.service" "container@authelia.service" ];
    files."oidc-hmac-secret".restartUnits        = [ "authelia-secrets.service" "container@authelia.service" ];
    files."oidc-issuer-private-key".restartUnits = [ "authelia-secrets.service" "container@authelia.service" ];

    runtimeInputs = [ pkgs.authelia pkgs.openssl pkgs.gnused pkgs.coreutils ];

    script = ''
      set -euo pipefail

      # `authelia crypto rand` prints "Random Value: <v>".  sed -n s///p emits
      # nothing at all if the prefix ever changes, which the guard below turns
      # into a failed generator rather than an empty secret file.
      rand() {
        authelia crypto rand --length 64 --charset alphanumeric \
          | sed -n 's/^Random Value: //p' | tr -d '\n'
      }

      for f in jwt-secret session-secret storage-encryption-key oidc-hmac-secret; do
        rand > "$out/$f"
        if [ ! -s "$out/$f" ]; then
          echo "  ✗ authelia crypto rand produced nothing for $f" >&2
          exit 1
        fi
      done

      openssl genrsa -out "$out/oidc-issuer-private-key" 4096 2>/dev/null
      if ! openssl rsa -in "$out/oidc-issuer-private-key" -noout -check >/dev/null 2>&1; then
        echo "  ✗ the generated OIDC issuer key does not verify" >&2
        exit 1
      fi
    '';
  };

  # ── The user database ─────────────────────────────────────────────────────
  #
  # PROMPTED, one password per account in `autheliaUsers`: a human types these
  # into a login form, so a value nobody chose and nobody can remember has to
  # be looked up out of sops every time.  Same call as Grafana's admin password
  # and the Cloudflare token.
  #
  # The file is emitted READ-ONLY and stays that way - `password_reset.disable`
  # is set below, so Authelia never writes to it.  A writable user database
  # inside a container whose root filesystem is rebuilt on every deploy would
  # be state living somewhere nothing persists.
  #
  # HASHED WITH AUTHELIA'S OWN CLI rather than with a generic argon2 tool: the
  # digest string has to be one Authelia's verifier accepts, and the binary
  # that writes it is the binary that reads it.  Defaults are argon2id,
  # m=65536 t=3 p=4 - the profile Authelia recommends for a machine with
  # memory to spare, which this one has.
  clan.core.vars.generators.authelia-users = {
    files."users_database.yml".secret       = true;
    files."users_database.yml".restartUnits = [ "authelia-secrets.service" "container@authelia.service" ];

    prompts = lib.listToAttrs (map (u: {
      name  = "password-${u.name}";
      value = {
        description = "Authelia password for ${u.name} (${u.displayName}) at https://${authHost}";
        type        = "hidden";
      };
    }) autheliaUsers);

    runtimeInputs = [ pkgs.authelia pkgs.gnused pkgs.coreutils ];

    script = ''
      set -euo pipefail
      umask 077

      db="$out/users_database.yml"
      : > "$db"
      echo "users:" >> "$db"

      emit_user() {
        name="$1"; display="$2"; email="$3"; promptfile="$4"; shift 4

        pw=$(tr -d '\n' < "$promptfile")
        if [ "''${#pw}" -lt 12 ]; then
          echo "  ✗ password for $name is shorter than 12 characters." >&2
          echo "    This account reaches every admin UI in the house and, after" >&2
          echo "    this milestone, its login form is visible from the IoT VLAN." >&2
          exit 1
        fi

        # `--password` puts the value on argv, so it is visible in `ps` for the
        # lifetime of this one hash on the machine running `clan vars generate`
        # - a laptop the operator is sitting at.  Authelia's CLI offers no
        # stdin form (`--password`, `--random`, or an interactive terminal
        # prompt, which a generator has no terminal for).  Noted rather than
        # hidden; if it ever matters, the fix is upstream.
        digest=$(authelia crypto hash generate argon2 --password "$pw" \
                   | sed -n 's/^Digest: //p')
        if [ -z "$digest" ]; then
          echo "  ✗ argon2 hashing produced no digest for $name" >&2
          exit 1
        fi

        {
          printf '  %s:\n'                "$name"
          printf '    displayname: "%s"\n' "$display"
          printf '    password: "%s"\n'    "$digest"
          printf '    email: %s\n'         "$email"
          printf '    groups:\n'
          for g in "$@"; do printf '      - %s\n' "$g"; done
        } >> "$db"
      }

      ${lib.concatMapStrings (u: ''
        emit_user ${lib.escapeShellArg u.name} ${lib.escapeShellArg u.displayName} \
          ${lib.escapeShellArg u.email} "$prompts/password-${u.name}" \
          ${lib.escapeShellArgs u.groups}
      '') autheliaUsers}
    '';
  };

  # ── Grafana's OIDC client secret, as a PAIR ───────────────────────────────
  #
  # Authelia stores the client secret HASHED; Grafana needs the plaintext.  Two
  # values that must correspond, so they are produced by ONE generator in one
  # run - the alternative (two generators, or a prompt plus a hand-run hashing
  # command) is two things to keep in step with nothing checking that they
  # agree, and the failure mode is an OIDC login that returns
  # "invalid_client" with no indication which half is wrong.
  #
  # 72 alphanumerics: Authelia's own recommended client-secret length, and long
  # enough that the pbkdf2 digest being readable on this host is not a finding.
  #
  # The PLAINTEXT half is consumed on the other side of the machine - staged
  # into the monitoring container by service-modules/monitoring.nix, which also
  # declares the restartUnits for it, because those units exist only on the
  # machine holding that role.
  clan.core.vars.generators.authelia-oidc = {
    files."grafana-client-secret".secret        = true;
    files."grafana-client-secret-digest".secret = true;

    files."grafana-client-secret-digest".restartUnits =
      [ "authelia-secrets.service" "container@authelia.service" ];

    runtimeInputs = [ pkgs.authelia pkgs.gnused pkgs.coreutils ];

    script = ''
      set -euo pipefail

      secret=$(authelia crypto rand --length 72 --charset alphanumeric \
                 | sed -n 's/^Random Value: //p' | tr -d '\n')
      if [ -z "$secret" ]; then
        echo "  ✗ authelia crypto rand produced no client secret" >&2
        exit 1
      fi
      printf '%s' "$secret" > "$out/grafana-client-secret"

      digest=$(authelia crypto hash generate pbkdf2 --variant sha512 --password "$secret" \
                 | sed -n 's/^Digest: //p')
      if [ -z "$digest" ]; then
        echo "  ✗ pbkdf2 hashing produced no digest for the Grafana client secret" >&2
        exit 1
      fi
      printf '%s' "$digest" > "$out/grafana-client-secret-digest"
    '';
  };

  ##############################################################################
  # The container itself.
  ##############################################################################
  containers.authelia = {
    autoStart = true;
    ephemeral = false;          # db.sqlite3 persists via the bind mount below

    # Own netns, own L2 identity.  See the file header for why this is a veth
    # on br0 and not a macvlan or a tap.
    privateNetwork  = true;
    hostBridge      = "br0";
    localMacAddress = autheliaMac;

    bindMounts = {
      # The SQLite database and the notifier's file, on zdata.  Remapped to the
      # unit's own StateDirectory so services.authelia needs no path override -
      # the same trick containers/jellyfin.nix uses for /var/lib/jellyfin.
      "${dataDir}" = {
        hostPath   = "/srv/state/authelia";
        isReadOnly = false;
      };

      # The staged secrets, read-only, at the identical path.
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

      # Matches the host.  Every "when was this account banned", every session
      # expiry and every line in the access log is rendered in local time, and
      # a container that silently defaults to UTC makes all of them a two-hour
      # question.  Same call as containers/{arr,traefik}.nix.
      time.timeZone = "Europe/Berlin";

      ##########################################################################
      # Networking.  The container owns its netns, so it owns all of this.
      ##########################################################################
      networking.useHostResolvConf = false;
      networking.useNetworkd       = true;
      services.resolved.enable     = true;

      # eth0 - renamed from host0 by container-init before stage 2 runs.
      # DHCP against the UDM-Pro reservation; resolver DECLARED, not inherited,
      # so a future change to the Services network's DHCP options cannot
      # silently move this container off Technitium.
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
      # container@authelia is Type=notify with TimeoutStartSec=1min, so a
      # wait-online that blocks for the stock 120 s turns a missing DHCP
      # reservation into a container the host kills and restart-loops, with no
      # reachable state to debug.
      systemd.network.wait-online.timeout = 20;

      # The container's own firewall, in its own netns.
      #
      # NOTHING is unconditionally open - backend bypass hardening, mechanism
      # (a), and it matters more here than for any other backend: see the
      # X-Forwarded-* paragraph in the file header.  9091 accepts the reverse
      # proxy and 9959 accepts the monitoring container, and no other source
      # reaches either.
      networking.firewall.allowedTCPPorts = [ ];
      networking.firewall.extraCommands = ''
        iptables -A nixos-fw -p tcp -s ${proxyAddress}/32      --dport ${toString autheliaPort} -j nixos-fw-accept
        iptables -A nixos-fw -p tcp -s ${monitoringAddress}/32 --dport ${toString metricsPort}  -j nixos-fw-accept
      '';

      ##########################################################################
      # Users.  Numeric ids are the interface across the nspawn boundary - see
      # the allocation table in machines/ernst/networking.nix.
      #
      # The upstream module declares users.users.authelia-main without a uid
      # (it lets NixOS allocate one from the system range) and the group
      # without a gid, both as plain definitions, so adding them here is a
      # MERGE and needs no mkForce - the same shape containers/traefik.nix
      # found for uid 3005, unlike service-modules/monitoring.nix where the
      # upstream modules set ids from config.ids.* and the override has to
      # fight them.
      #
      # isSystemUser must be restated with the uid: NixOS infers "effectively a
      # system user" from uid < 1000, and 3008 is not, so the inference stops
      # working the moment the uid is pinned.  containers/arr.nix hit exactly
      # this and the error names neither the uid nor the cause.
      ##########################################################################
      users.users."authelia-${instanceName}" = {
        isSystemUser = true;
        uid          = autheliaUid;
        group        = "authelia-${instanceName}";
      };
      users.groups."authelia-${instanceName}" = { gid = autheliaGid; };

      ##########################################################################
      # Authelia.
      ##########################################################################
      services.authelia.instances.${instanceName} = {
        enable = true;

        # The module turns each of these into an AUTHELIA_*_FILE environment
        # variable that Authelia reads ITSELF, unprivileged - which is why the
        # staging unit gives every one of them to uid 3008 rather than to root.
        #
        # oidcIssuerPrivateKeyFile additionally makes the module emit a
        # templated config fragment (X_AUTHELIA_CONFIG_FILTERS=template) that
        # inlines the PEM into identity_providers.oidc.jwks at start.  That is
        # the supported way to keep a private key out of the store, and it is
        # why the key is a FILE here and not a settings value.
        secrets = {
          jwtSecretFile            = jwtFile;
          sessionSecretFile        = sessionFile;
          storageEncryptionKeyFile = storageKeyFile;
          oidcHmacSecretFile       = oidcHmacFile;
          oidcIssuerPrivateKeyFile = oidcKeyFile;
        };

        # The OIDC client block, staged out of sops.  Authelia merges every
        # --config file it is given, and the module's preStart runs
        # `validate-config` across all of them - so a malformed staged file
        # fails the unit before it can serve a single request.
        settingsFiles = [ oidcClientFile ];

        settings = {
          theme = "dark";

          ######################################################################
          # Server.
          #
          # `address` and NOT the deprecated host/port pair: the module warns
          # on the old shape and removes its own default when it sees it.
          #
          # ONLY THE ForwardAuth AUTHZ ENDPOINT IS DECLARED, which replaces
          # Authelia's default set rather than adding to it.  Upstream ships
          # four implementations - ForwardAuth, ExtAuthz, AuthRequest and
          # Legacy - because it does not know which proxy is in front.  This
          # one does.  Three unused authorization endpoints on a port that
          # trusts X-Forwarded-* are three ways to get the semantics subtly
          # wrong, and `legacy` in particular behaves differently from the
          # others in how it derives the target URL.
          ######################################################################
          server = {
            address = "tcp://0.0.0.0:${toString autheliaPort}/";
            endpoints.authz.forward-auth.implementation = "ForwardAuth";
          };

          # To the journal, as text.  `journalctl -u authelia-main` inside the
          # container is where a failed login, a ban and every authz decision
          # are visible, and it is the instrument the PR test plan uses.  The
          # module defaults to JSON, which is the right choice for a log
          # shipper and the wrong one for a human with journalctl.
          log = {
            level  = "info";
            format = "text";
          };

          # M6.  Its own listener; see metricsPort above for why this is not a
          # route on :443.
          telemetry.metrics = {
            enabled = true;
            address = "tcp://0.0.0.0:${toString metricsPort}";
          };

          ######################################################################
          # Sessions.
          #
          # ONE COOKIE, scoped to the apex, because every protected name is one
          # label below it.  `authelia_url` is what the redirect goes to and it
          # MUST be inside `domain` - Authelia refuses to start otherwise,
          # which is the correct failure and worth knowing before you see it.
          #
          # IN-MEMORY SESSION STORE, deliberately: there is no Redis and there
          # will not be one for a single instance.  The consequence is that
          # restarting this container logs everyone out.  That is the right
          # trade - a Redis would be a second stateful service, on the same
          # box, in the login path of every admin UI, to avoid re-entering a
          # TOTP code after a deploy.
          #
          # `expiration` is the hard cap; `inactivity` is the idle timeout;
          # `remember_me` is the opt-in long session the login form offers.
          ######################################################################
          session.cookies = [
            {
              domain       = baseDomain;
              authelia_url = "https://${authHost}";
              name         = "authelia_session";
              expiration   = "12 hours";
              inactivity   = "1 hour";
              remember_me  = "1 month";
            }
          ];

          ######################################################################
          # Storage - SQLite, on zdata.
          #
          # Single instance, no HA requirement, and the working set is a
          # handful of rows: a Postgres here would be a second container and a
          # second backup story for a database that holds two TOTP secrets.
          # See the header for why this path being on zdata is invariant #7's
          # sharpest edge in this repo.
          ######################################################################
          storage.local.path = "${dataDir}/db.sqlite3";

          ######################################################################
          # Notifier - a file.  See NOTIFIER in the header: enrolling TOTP
          # means reading the link out of this file once per account.
          ######################################################################
          notifier = {
            disable_startup_check = true;
            filesystem.filename   = "${dataDir}/notification.txt";
          };

          ######################################################################
          # Authentication backend - the staged users_database.yml.
          #
          # password_reset.disable = true is what keeps that file READ-ONLY,
          # and the reason is not squeamishness: the reset flow mails a link,
          # the notifier is a file on this host, so "reset your password"
          # already means "get a shell on ernst".  Someone who can do that can
          # re-run `clan vars generate ernst`, which is the real reset path and
          # the one that keeps sops as the single source of truth for the hash.
          #
          # refresh_interval is set anyway: Authelia re-reads the file on that
          # interval, so a rotation that restarts the staging unit is picked up
          # without restarting Authelia itself.
          ######################################################################
          authentication_backend = {
            password_reset.disable = true;
            refresh_interval       = "5 minutes";
            file = {
              path            = usersFile;
              watch           = false;
              search.email    = true;
              search.case_insensitive = true;
            };
          };

          ######################################################################
          # Second factor.
          #
          # TOTP is the method, and `default_2fa_method` makes it the one a new
          # account is offered.  WebAuthn is left at its upstream default
          # (available, not default) rather than disabled: lgo carries a
          # YubiKey, this portal is served over HTTPS on a stable origin, and
          # enrolling one later should not need a deploy.  Duo is off because
          # it is unconfigured - it requires an API host and a key, so it
          # cannot be reached by accident.
          ######################################################################
          default_2fa_method = "totp";
          totp = {
            issuer    = baseDomain;
            algorithm = "sha1";     # what every authenticator app implements
            digits    = 6;
            period    = 30;
            skew      = 1;          # ±30 s, for a phone with a drifting clock
          };

          ######################################################################
          # Regulation.
          #
          # THIS IS THE CONTROL THAT REPLACES THE ipAllowList's LAST REAL
          # BENEFIT.  With L5 retired the login form is visible from the IoT
          # VLAN (see the header), so the thing standing between a compromised
          # smart device and a password guess is this: three failures inside
          # five minutes cost a fifteen-minute ban, tracked per user in
          # db.sqlite3 and therefore surviving a restart.
          #
          # Per USER and not per source address - which is the right axis here.
          # An attacker on the LAN can change source address at will and cannot
          # change which account they are guessing at.
          ######################################################################
          regulation = {
            max_retries = 3;
            find_time   = "5 minutes";
            ban_time    = "15 minutes";
          };

          ######################################################################
          # Access control.
          #
          # DENY BY DEFAULT.  Anything Traefik forwards for authorization that
          # is not named below is refused, so adding a route to
          # containers/traefik.nix with the middleware attached and forgetting
          # to add it here fails CLOSED.  That is the whole reason the rule
          # lists domains explicitly rather than matching `*.goclan.org`.
          #
          # ONE RULE, and no bypass rules at all - see the header for why the
          # enumeration the brief asked for came back empty.
          #
          # `subject` makes group membership load-bearing rather than
          # decorative: an account added to users_database.yml without
          # `admins` can authenticate and still reaches nothing.
          ######################################################################
          access_control = {
            default_policy = "deny";
            rules = [
              {
                domain  = protectedHosts;
                policy  = "two_factor";
                subject = [ "group:${adminGroup}" ];
              }
            ];
          };

          ######################################################################
          # OIDC provider.
          #
          # The CLIENTS live in the staged file (see settingsFiles above),
          # because a client secret digest has no business in the Nix store.
          # What is here is everything that is not credential material.
          #
          # `jwks` is NOT set here either - the module writes it from
          # oidcIssuerPrivateKeyFile through its template filter.
          ######################################################################
          identity_providers.oidc = {
            # Authelia's own default lifespans are sensible; the one worth
            # stating is that an ID token outliving the session it was minted
            # from would let Grafana keep a login the portal has already
            # expired.  One hour, matching `inactivity` above.
            lifespans.access_token  = "1 hour";
            lifespans.id_token      = "1 hour";
            lifespans.refresh_token = "90 minutes";

            # Never enable this without knowing what it does: it lets a client
            # skip PKCE and use a plaintext code challenge.  Grafana sends
            # S256, and the client block requires it.
            enforce_pkce = "public_clients_only";
          };
        };
      };

      # NOTE ON THE UPSTREAM HARDENING - MEASURED 2026-08-24, AND IT ALL WORKS.
      #
      # nixpkgs' authelia module sets a large systemd sandbox unconditionally
      # and, unlike the jellyfin module, it is NOT container-aware: there is no
      # `!config.boot.isContainer` guard on any of it.  containers/traefik.nix
      # records that some such options conflict with nspawn's own
      # mount-namespace setup, so this file shipped with nothing overridden and
      # an explicit instruction to record what actually happened.
      #
      # What actually happened, on the first deploy, from
      # `systemctl show authelia-main` inside the container:
      #
      #   ActiveState=active   NRestarts=0   ExecMainStatus=0
      #   ProtectKernelTunables=yes   ProtectKernelModules=yes
      #   ProtectControlGroups=yes    RestrictNamespaces=yes
      #   PrivateUsers=yes            MemoryDenyWriteExecute=yes
      #   ProtectSystem=strict
      #
      # ALL SEVEN ARE IN EFFECT and the service came up first try.  So the
      # concern was unfounded HERE, and the reason is worth keeping: nspawn
      # containers under nixos-containers are privileged (no --private-users),
      # PID 1 inside holds CAP_SYS_ADMIN, and every one of these options is
      # applied by systemd INSIDE that namespace where it has the privilege to
      # do so.  The jellyfin module's guard is about a different case.
      #
      # THE TRANSFERABLE PART is not "these options are fine in nspawn" - it is
      # that pre-emptively deleting six hardening options from an identity
      # provider, on a guess, would have permanently weakened this unit to
      # avert a failure that never occurs.  Do not add a `mkForce false` block
      # here.  If a future nixpkgs bump does break startup, `systemctl status
      # authelia-main` names the option in the message ("Failed to set up mount
      # namespacing", "Operation not permitted") - disable THAT one, and record
      # it here the same way.

      # `curl` is the test plan's instrument - it is what proves the authz
      # endpoint answers from HERE and, run anywhere else, that it does not.
      # `dig` checks the container resolves through Technitium.  `sqlite` reads
      # the regulation and TOTP tables when a login misbehaves.
      environment.systemPackages = with pkgs; [ curl dnsutils sqlite ];
      documentation.enable       = false;
      documentation.nixos.enable = false;
    };
  };
}
