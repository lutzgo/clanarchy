# Traefik's STATIC configuration: the entrypoints, the ACME resolver and the
# metrics listener — everything that needs a restart rather than a file reload.
#
# The TWO ENTRYPOINTS argument and the ACME/split-horizon argument are in
# ../traefik.nix's header; this file is where they are spelled.
{
  baseDomain,
  acmeEmail,
  metricsPort,
  wanEntryPoint,
  wanPort,
  dataDir,
}: {
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
}
