##############################################################################
# roles.search — SearXNG, the stack's only door to the open internet (M20)
#
# ── THE TIER ARGUMENT, WHICH IS WHAT THIS MILESTONE IS ACTUALLY ABOUT ───────
#
# M20 (docs/history.md) opens with a premise, and the premise is FALSE:
#
#   "SearXNG would be the first service here to talk to the open internet
#    on its own behalf"
#
# It would not, and this is checkable in the repo rather than a matter of
# opinion.  containers/arr/ already says of its own occupants: "Prowlarr
# fetches from indexers, Sonarr/Radarr fetch metadata" — outbound, on their
# own behalf, on nspawn.  tubesync pulls arbitrary videos off YouTube.  And
# FlareSolverr, in that same file, RENDERS DELIBERATELY HOSTILE PAGES FROM
# TORRENT INDEXERS IN A REAL BROWSER ENGINE and sits on the PODMAN tier, one
# step *down* from nspawn, with the measurement that justified it attached.
#
# So invariant #1's "moves up a tier when it starts talking to the internet
# on its own behalf" cannot mean bare internet contact — half the fleet would
# be in microvms.  Read against how it has actually been applied, the line it
# draws is a KILLSWITCH REQUIREMENT: M3's guest is a microvm because
# qBittorrent's traffic must never egress on the house IP, and a kernel of
# its own is what makes that enforceable.  arr/ says exactly this in its
# own words — "never talk to the internet on their own behalf IN A WAY THAT
# NEEDS A KILLSWITCH".
#
# SearXNG has no killswitch requirement.  A household member's search query
# leaving on the house IP is what happens when they open a browser; there is
# no privacy or legal property that a VPN egress would preserve and a direct
# one would destroy.  Routing it through M3's guest was considered and
# rejected on evidence already in this repo: arr/ measured eztvx.to
# returning HTTP 200 from the home WAN and HTTP 451 from the IVPN exit, so
# the VPN path makes fetches FAIL that otherwise succeed.  Search engines
# treat datacenter exits far more harshly than indexers do — a VPN egress is
# the configuration most likely to get this instance CAPTCHA'd into
# uselessness.
#
#   microvm — rejected.  Its distinguishing property is a killswitch and a
#             separate kernel; this workload wants neither, would still need
#             the same egress, and would pay a kernel's worth of memory and
#             boot time for a boundary that protects nothing here.
#   podman  — rejected, and this is the one that had a real case.  Upstream
#             SearXNG distributes an image, and the podman tier exists for
#             exactly that.  But nixpkgs carries a full `services.searx`
#             module, so the image buys nothing and costs the thing M21 just
#             paid for in public: a digest to pin, re-pin, and verify against
#             a card/arch it was never built for.  M21's conclusion — "there
#             was no image worth pinning" — applies again.
#   nspawn  — TAKEN.  Real NixOS view, so `services.searx` is used as-is with
#             its upstream unit; systemd hardening available; no image.
#
# WHAT MAKES nspawn SAFE *HERE*, specifically, since the invariant says say
# so rather than assume it:
#
#   1. THE URL SET IS DECLARED, NOT ARBITRARY.  `engineKeepOnly` below is a
#      `keep_only` list, so this instance can contact the engines named there
#      and no others.  That is a materially smaller surface than tubesync
#      (any YouTube URL) or FlareSolverr (any indexer's page), both of which
#      are already on nspawn or below.
#   2. IT HOLDS NOTHING.  No media access, no state directory, no database,
#      no uid on the media group, and the only secret it carries is its own
#      cookie-signing key.  Compromising it yields the ability to make
#      outbound HTTP — which it already had — and sight of the queries.
#   3. IT CANNOT REACH THE STACK IT SERVES.  Traffic goes one way: Open WebUI
#      dials SearXNG.  SearXNG has no route to llama-swap (that is a veth it
#      is not on) and its own firewall accepts one address.
#   4. IT PARSES HTML WITH PYTHON, NOT WITH A BROWSER.  The realistic exploit
#      is a parser bug in a response.  FlareSolverr does the same job with a
#      whole Chromium and is a tier down, with that trade recorded.
#
# ── EGRESS: THE NORMAL PATH, DELIBERATELY ───────────────────────────────────
#
# A VLAN 90 leg with a DHCP reservation, exactly like every other container,
# so its outbound goes through the UDM-Pro where the household's zone policy
# applies and where it is VISIBLE.  The alternative considered was a
# point-to-point veth with host SNAT — the mon0 shape — and it was rejected
# for two concrete reasons: `networking.nat.externalInterface` is a single
# string already claimed by monitoring.nix for "zt+", so a second SNAT domain
# would mean hand-rolling nftables beside the module (a new mechanism, which
# the milestone forbids), and it would hide SearXNG's egress behind ernst's
# own LAN address — the opposite of the "which interface, which address"
# answer M20 owes.
#
# ── NO HOSTNAME, AND THAT IS THE POINT ──────────────────────────────────────
#
# This service appears in NEITHER traefik.nix NOR ingress-policy.nix.  Only
# Open WebUI ever talks to it, so it needs no name, no route, no certificate
# and no forward-auth — which is the roadmap's own stated default position
# and is strictly better than protecting a name that need not exist.  It also
# sidesteps the RomM 403 by construction: machine-to-machine traffic that
# never meets Authelia cannot be broken by it.
##############################################################################
{lib, ...}: {
  description = "SearXNG in an nspawn container on VLAN 90. No hostname; one permitted client.";

  interface.options = {
    mac = lib.mkOption {
      type = lib.types.str;
      example = "02:00:00:90:00:10";
      description = ''
        Container eth0 MAC, allocated in
        machines/ernst/allocations.nix.  The UDM-Pro DHCP reservation keys on
        this, and the reservation must be INSIDE the 10.0.90.6–.254 pool —
        UniFi accepts one outside it and then silently hands out a pool lease
        instead, which M2b, M5 and M6 each lost a round to.
      '';
    };
    uid = lib.mkOption {
      type = lib.types.int;
      description = ''
        Static uid/gid, allocated in machines/ernst/allocations.nix.

        NOTHING ON THE HOST IS OWNED BY IT, which is worth saying because
        every other uid in that table exists to own something.  THIS ROLE HAS
        NO `stateDir` OPTION AT ALL — nixpkgs' searx module declares no
        StateDirectory, regenerates its settings into /run/searx on every
        start, and the container bind-mounts only its secret, read-only.  It
        is pinned anyway so that a process visible on the host
        — nspawn passes uids through unmapped — is attributable to a service
        rather than to an arbitrary number the container allocated.
      '';
    };
    port = lib.mkOption {
      type = lib.types.port;
      default = 8888;
      description = ''
        SearXNG's listener inside the container.  8888 is upstream's own
        default and there is no reason to move it — nothing else lives in
        this netns.
      '';
    };
    allowedSource = lib.mkOption {
      type = lib.types.str;
      example = "10.0.90.23";
      description = ''
        The ONE address permitted to reach `port`.  Open WebUI's VLAN 90
        address, and nothing else on that VLAN — including the qBittorrent
        microvm, which is one layer-2 hop away on this same bridge and whose
        frames therefore never pass the UDM-Pro where a gateway rule could
        filter them.  Same reasoning as `proxyAddress` on the webui role and
        as traefikAddr in containers/arr/.

        ernst's host firewall drops unmatched traffic silently, so a wrong
        value here presents as a search that times out with nothing logged on
        either side.
      '';
    };

    # ── ENGINE SET: CONFIGURATION WITH CONSEQUENCES, NOT A DEFAULT ──────────
    engineKeepOnly = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        # MEASURED ON ernst 2026-09-10, not chosen. See the description.
        "bing" # 10 results, every attempt. The reliable primary
        "yandex" # 15, the best quality measured — nhs.uk et al
        "encyclosearch" # 15, encyclopedic (wikipedia, handwiki)
        "mwmbl" # 30, independent open crawler
        "brave" # INTERMITTENT — see below. Free when it fails
      ];
      description = ''
        The engines this instance may contact, as SearXNG `name` fields.
        Rendered into `use_default_settings.engines.keep_only`, which
        FILTERS THE DEFAULT SET DOWN rather than adding to it: engines not
        named here do not exist in the running instance at all.

        Verified against the shipped `searx/settings.yml` and
        `searx/settings_loader.py` in this nixpkgs' searxng
        (0-unstable-2026-05-16), not from a docs page.  `keep_only` matches on
        `engine.get('name')` — the NAME, not the shortcut — and it is applied
        BEFORE the user `engines` list is merged, which is why the two
        default-disabled entries below can be re-enabled in `engineOverrides`
        only because they also appear here.  An engine named here that does
        not exist upstream is silently dropped, so a typo removes an engine
        rather than failing the build.

        THIS IS THE FIRST OF THE TWO THINGS THAT MAKE nspawn DEFENSIBLE for a
        service that fetches from the internet: the set of hosts it can reach
        is declared here and is short.  Adding an engine widens what a
        hostile response can reach a Python parser through, so it is an
        edit that deserves the same attention as opening a port.

        ── THIS LIST IS MEASURED.  THE FIRST ONE SHIPPED WAS NOT, AND IT
           RETURNED ZERO RESULTS FOR EVERY QUERY ──────────────────────────

        M20 first shipped `duckduckgo, brave, startpage, mojeek, qwant,
        wikipedia, wikidata`, reasoned from what a household instance "should"
        use and explicitly flagged as unverified.  Every one of the four real
        web engines in it is blocked from ernst's address.  Measured
        2026-09-10, first request after a clean restart:

          duckduckgo   CAPTCHA
          startpage    CAPTCHA
          qwant        access denied  (403)
          brave        too many requests  (429)
          mojeek       access denied  (403)

        `number_of_results: 0`, three times in a row, twenty seconds apart.
        The feature was fully deployed, healthy, firewalled correctly, JSON
        enabled — and answered nothing.  Exactly the shape M21's six defects
        had.

        The replacements were found by enabling ~26 candidates and querying
        each one alone.  What actually answers:

          bing           10 results, every attempt      ← the primary
          yandex         15, best quality measured
          encyclosearch  15, encyclopedic
          mwmbl          30, independent crawler
          wiby           12, but old-web pages — poor relevance for health
          quark          10, mostly Chinese-language
          searchmysite    7, personal websites only — very niche

        GOOGLE IS ABSENT, AND NOT FOR THE REASON FIRST GIVEN.  The original
        note said it was excluded because it is the engine most likely to
        CAPTCHA a self-hosted metasearcher.  That reasoning was sound and the
        conclusion was untested; when tested, Google returns `results: 0` with
        NO entry in `unresponsive_engines` at all — it answers, and the parser
        extracts nothing.  It is absent because it does not work, which is a
        stronger reason than the one guessed.

        BRAVE IS KEPT DESPITE BEING UNRELIABLE, deliberately.  It 429s under
        any sustained use, but immediately after a `searx.service` restart it
        answered with the best sources in the whole exercise (Mayo Clinic,
        Cleveland Clinic, NIH ODS).  A 429 comes back fast and SearXNG just
        lists it unresponsive, so an engine that sometimes works and never
        costs more than a fast rejection is worth carrying.  Do not read its
        presence as a claim that it is dependable.

        WIKIPEDIA AND WIKIDATA WERE REMOVED, and this one is not about
        blocking — it is about the consumer.  They answer, but they return
        their content in `infoboxes`, NOT in `results`, and Open WebUI reads
        `payload.get('results', [])` and nothing else
        (retrieval/web/searxng.py).  Verified directly: `?q=Vitamin D
        &engines=wikipedia` returns `results: 0` with a populated infobox.  So
        they contributed nothing to this consumer at any point and were pure
        latency.  A different client that reads infoboxes would want them back.

        ── RESULT QUALITY, MEASURED AFTER THE FIX.  KNOWN AND ACCEPTED ───

        The set above returns 181 results for "how safe is a vitamin D
        supplement", which is not the interesting number.  `searchResultCount`
        on the webui role sends the model only the top FIVE by score, and
        SearXNG's scores here are nearly all 1.0 — position-and-count based,
        with each engine contributing its own list.  So ranking gives almost
        no discrimination and the top five is effectively a round-robin across
        engines: EVERY ENGINE IN THIS LIST SPENDS A SLOT ON EVERY QUERY.  That
        is the real cost of adding one, and it is not visible in a result
        count.

        BING READS THE WORD "safe" AS THE SAFe ACRONYM, reproducibly.  Both
        "how safe is a vitamin D supplement" and "is it safe to take magnesium
        daily" put framework.scaledagile.com and the German Wikipedia article
        on Scaled Agile Framework into the top five.

        IT IS NOT A BROKEN ENGINE and was checked before being written off:
        "how to bake sourdough bread" returns sourdough sites and "linux
        kernel scheduler" returns Linux sites, so the query IS reaching bing.
        It is genuinely bing's reading of a common English word — which makes
        it unfixable from here, and the reason this is a note rather than a
        removal.  Bing is kept for coverage: it answers every time, and the
        alternative is a set of four in which two are intermittent.

        The engines are NOT equal in quality, measured over health queries:
        yandex is consistently the best (nhs.uk, verywellhealth.com), mwmbl is
        better than its low profile suggests (examine.com, greatist.com), and
        encyclosearch is reliable for anything factual.  If the top five is
        ever too noisy in practice, RAISE `searchResultCount` before removing
        an engine — a sixth and seventh slot cost a few hundred tokens and
        reach past the round-robin, whereas dropping an engine loses whatever
        it alone was finding.

        RE-MEASURE AFTER ANY CHANGE, and after a few months regardless —
        engine blocking moves.  Anything listed here that shows up in
        `unresponsive_engines` on every query is contributing nothing:

          systemd-run --machine=openwebui --collect --pipe -q -- \
            curl -s 'http://10.0.90.24:8888/search?q=test&format=json' \
            | jq -rc '{n:(.results|length), unresp:.unresponsive_engines}'
      '';
    };

    engineOverrides = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
      default = [
        # FOUR OF THE FIVE ENGINES THIS INSTANCE USES ARE `disabled: true` IN
        # UPSTREAM'S settings.yml, so without these lines `keep_only` would
        # leave a set that is present but never queried — a second way to
        # arrive at zero results, and one that reports NOTHING in
        # `unresponsive_engines` because an engine that was never asked
        # cannot be unresponsive.  Checked per engine against the shipped
        # settings.yml rather than assumed:
        #
        #   bing           disabled: true    categories: null (→ general)
        #   yandex         disabled: true    categories: [general]
        #   encyclosearch  disabled: true    categories: [general]
        #   mwmbl          disabled: true    categories: null (→ general)
        #   brave          disabled: FALSE   — already on, no entry needed
        {
          name = "bing";
          disabled = false;
        }
        {
          name = "yandex";
          disabled = false;
        }
        {
          name = "encyclosearch";
          disabled = false;
        }
        {
          name = "mwmbl";
          disabled = false;
        }
      ];
      description = ''
        Per-engine overrides, merged BY NAME over whatever `engineKeepOnly`
        left standing (`update_settings` in searx/settings_loader.py).  An
        entry whose name survived the filter is merged into it; an entry
        whose name did not is APPENDED as a new engine definition, which is
        almost never what is wanted — so keep the two lists in step.
      '';
    };

    requestTimeout = lib.mkOption {
      type = lib.types.float;
      default = 5.0;
      description = ''
        `outgoing.request_timeout`, seconds.

        This is a latency budget for a human waiting on a chat reply, not a
        correctness setting: SearXNG returns whatever answered in time and
        lists the rest under `unresponsive_engines`, so a slow engine costs
        results rather than the query.  Upstream's default is 3.0, which
        drops engines that would have answered; 5.0 trades a slower worst
        case for fewer holes.
      '';
    };
  };

  perInstance = {settings, ...}: {
    nixosModule = {
      config,
      pkgs,
      lib,
      ...
    }: let
      vethName = "vb-searxng";
      # Derived from the container name, the way the module derives it —
      # see the note in the webui role, where restating it by hand moved
      # the path out from under the service that reads it.
      secretsDir = "${config.clanarchy.containerDefaults.secretsRoot}/searxng-secrets";
      secretGen = config.clan.core.vars.generators.searxng-secret;

      # ── The leg to the host (M29b) ──────────────────────────────────
      #
      # `web0` rather than `ai4`: the ai-numbered legs all point AT the
      # inference stack, and this one points the other way — a host
      # service reaching into a container.  Naming it in that family would
      # read as a fifth consumer of llama-swap, which it is not.
      #
      # The name is host-global (nspawn uses one name for both ends), and
      # machines/ernst/networking.nix asserts no two containers claim one.
      # fdca:fe94:: is the next free /64 after M29's fe93.
      webVeth = "web0";
      webHost = "fdca:fe94::1";
      webCont = "fdca:fe94::2";
    in {
      ####################################################################
      # The cookie-signing key.  ITS OWN GENERATOR, per invariant #8 and
      # per the rule containers/authelia.nix states: a clan vars generator
      # is ATOMIC, so adding a file to an existing one re-runs the whole
      # script and rotates every other secret in it as a side effect.
      #
      # SearXNG uses `server.secret_key` to sign the preferences cookie.
      # The only client here is a bot that sends no cookies, so this
      # protects very little — but upstream ships the literal string
      # "ultrasecretkey" as its default and a deployment that keeps it is
      # the kind of thing that is embarrassing to explain later.
      ####################################################################
      clan.core.vars.generators.searxng-secret = {
        files."searxng-secret".secret = true;
        files."searxng-secret".restartUnits = ["searxng-secrets.service" "container@searxng.service"];

        runtimeInputs = [pkgs.openssl pkgs.coreutils];
        script = ''
          set -euo pipefail
          # hex, not base64: this value is substituted into a YAML document
          # by envsubst, and an alphabet with no quoting-significant
          # characters cannot produce a settings.yml that parses
          # differently than intended.
          openssl rand -hex 32 | tr -d '\n' > "$out/searxng-secret"
        '';
      };

      ##################################################################
      # The container.
      ##################################################################
      #
      # Declared through modules/containers/nspawn.nix, which generates
      # the staging unit, the host-side veth network, the VLAN backstop,
      # the container preamble, the in-container networking and the
      # firewall — and takes its bridge, VLAN, resolver and search domain
      # from the HOST's `clanarchy.containerDefaults` rather than from
      # this role's settings. That is what makes this role portable: a
      # second container host answers those four questions itself.
      clanarchy.containers.searxng = {
        enable = true;
        mac = settings.mac;

        # NO uid/gid PIN: the in-container `users.users.searx` block below
        # declares the user in full, and a second definition of the same
        # uid is a conflict rather than a pin.

        # ── THE SECRET IS `required`, WHICH INVERTS THE USUAL TOLERANCE ─
        #
        # Everywhere else a missing var stages empty, so the application
        # rejects it in its own terms rather than the container refusing
        # to start. Here empty is worse: envsubst would substitute the
        # empty string and SearXNG would run with an empty cookie-signing
        # key while reporting itself healthy. So the staging unit fails,
        # and because it is `requiredBy` the container, the container does
        # not start — the outcome worth having.
        #
        # The rendered file is an EnvironmentFile for searx-init, whose
        # envsubst pass turns `$SEARXNG_SECRET` in the settings into the
        # value at runtime — which is why this goes through
        # `environmentFile` and never into `settings.server.secret_key`,
        # where the nixpkgs module warns it would be world-readable.
        secrets."searxng.env".SEARXNG_SECRET = {
          file = secretGen.files."searxng-secret".path;
          required = true;
        };

        # mneme's leg, pointing INWARD: it searches the web through this
        # container rather than being given an egress path of its own.
        ula = [
          {
            veth = webVeth;
            hostAddress6 = webHost;
            localAddress6 = webCont;
          }
        ];

        # NOTHING is unconditionally open. Two sources, one port, and they
        # are different address families on different legs: Open WebUI
        # over VLAN 90, and mneme over the point-to-point ULA.
        allowFrom = [
          {
            peer = settings.allowedSource;
            port = settings.port;
          }
          {
            peer = webHost;
            port = settings.port;
          }
        ];

        config = {
          config,
          lib,
          pkgs,
          ...
        }: {
          # Matches the host, for the reason arr/, monitoring.nix and
          # the webui container all give: every timestamp a human reads is
          # local time, and a container that defaults to UTC makes each of
          # them a two-hour question.
          time.timeZone = "Europe/Berlin";

          users.users.searx = {
            isSystemUser = true;
            group = "searx";
            uid = settings.uid;
          };
          users.groups.searx.gid = settings.uid;

          ##############################################################
          # HARDENING.  nixpkgs' searx module ships essentially none —
          # measured on ernst 2026-09-10, the units as deployed scored:
          #
          #   searx.service       9.2 UNSAFE
          #   searx-init.service  9.2 UNSAFE
          #
          # against M20's stated target of <= 2.0.  With the block below,
          # both land at 1.1 OK.
          #
          # ── EXERCISED, NOT ONLY SCORED ───────────────────────────────
          #
          # M19's lesson is that `DeviceAllow=/dev/dri` and
          # MemoryDenyWriteExecute both SCORED WELL WHILE BREAKING THE
          # SYSTEM, so this set was applied as a runtime drop-in on the
          # live container and a real query was run through it before it
          # was written here: 20 results, sources including mayoclinic.org,
          # my.clevelandclinic.org and ods.od.nih.gov.  A search that still
          # works is the evidence; 1.1 is just the number.
          #
          # MemoryDenyWriteExecute IS INCLUDED and is the one to suspect
          # first if a future searxng bump fails to start: CPython itself
          # is fine with W^X, but a C extension that JITs would not be.
          # It was verified working here rather than assumed safe.
          #
          # ── WHAT IS DELIBERATELY NOT SET ─────────────────────────────
          #
          #   PrivateNetwork      — obviously not.  Reaching the internet
          #                         IS this service's whole function.
          #   IPAddressDeny/Allow — the one systemd-analyze still flags.
          #                         An allow-list would have to enumerate
          #                         every address of five search engines,
          #                         which are CDN-hosted and change without
          #                         notice; the rule would fail open in
          #                         practice (silently dropping engines as
          #                         IPs rotate) while looking strict.  The
          #                         containment that actually holds is the
          #                         INBOUND firewall plus the fact that
          #                         this container is on no veth to the
          #                         host — proven by the reachability
          #                         matrix in M20 (docs/history.md), where
          #                         every LAN target times out.
          #   ProtectSystem=strict is safe here BECAUSE searx writes
          #                         nothing: searx-init regenerates
          #                         /run/searx/settings.yml, and
          #                         RuntimeDirectory= already grants that
          #                         path.  If favicons are ever enabled
          #                         they need a ReadWritePaths= entry, and
          #                         the failure will be a clean EROFS.
          ##############################################################
          systemd.services.searx.serviceConfig = {
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
            PrivateTmp = true;
            PrivateDevices = true;
            PrivateUsers = true;
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectKernelLogs = true;
            ProtectControlGroups = true;
            ProtectClock = true;
            ProtectHostname = true;
            ProtectProc = "invisible";
            ProcSubset = "pid";
            RestrictNamespaces = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            LockPersonality = true;
            MemoryDenyWriteExecute = true;
            RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
            SystemCallArchitectures = "native";
            SystemCallFilter = ["@system-service" "~@privileged" "~@resources"];
            CapabilityBoundingSet = [""];
            AmbientCapabilities = [""];
            UMask = "0077";
          };

          # searx-init runs envsubst and writes one file into its own
          # RuntimeDirectory. It needs even less than searx does, but it
          # handles the SECRET, so it gets the same treatment rather than
          # less. ProtectSystem is "full" and not "strict" here: the unit's
          # whole job is to write /run/searx, and RuntimeDirectory= plus
          # RuntimeDirectoryPreserve=yes are set by the upstream module —
          # "strict" would need that path restated as ReadWritePaths and
          # buys nothing over "full" once /home and /etc are covered.
          systemd.services.searx-init.serviceConfig = {
            NoNewPrivileges = true;
            ProtectSystem = "full";
            ProtectHome = true;
            PrivateTmp = true;
            PrivateDevices = true;
            ProtectKernelTunables = true;
            ProtectKernelModules = true;
            ProtectKernelLogs = true;
            ProtectControlGroups = true;
            ProtectClock = true;
            ProtectHostname = true;
            ProtectProc = "invisible";
            ProcSubset = "pid";
            RestrictNamespaces = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            LockPersonality = true;
            RestrictAddressFamilies = ["AF_UNIX"];
            SystemCallArchitectures = "native";
            SystemCallFilter = ["@system-service" "~@privileged" "~@resources"];
            CapabilityBoundingSet = [""];
            AmbientCapabilities = [""];
            UMask = "0077";
          };

          services.searx = {
            enable = true;

            # searx-init reads this to envsubst `$SEARXNG_SECRET` into the
            # generated settings.yml.  The nixpkgs module puts it on BOTH
            # searx-init and searx, which is what makes the substitution
            # and the runtime agree.
            environmentFile = "${secretsDir}/searxng.env";

            # OFF, and this is not laziness — it is the decision the
            # milestone asked to be made rather than inherited.
            #
            # SearXNG's limiter exists to protect a PUBLIC instance from
            # abuse.  This one is reachable from exactly one address,
            # enforced one layer down by the firewall above, so there is no
            # abuse population for it to limit.
            #
            # Turning it on would also require a valkey/redis daemon
            # (`redisCreateLocally`, which the module makes a precondition)
            # for no benefit — and, worse, its botdetection would BLOCK THE
            # ONLY CLIENT: Open WebUI identifies itself with
            #   User-Agent: Open WebUI (…) RAG Bot
            # (retrieval/web/searxng.py, `_SEARXNG_HEADERS`).  A bot filter
            # in front of a service whose sole user is a self-declared bot
            # is a way to build an outage on purpose.
            redisCreateLocally = false;

            settings =
              {
                # ── THE ONE SETTING WITHOUT WHICH NONE OF THIS WORKS ──────
                #
                # Upstream ships `search.formats: [html]` — JSON IS NOT
                # ENABLED BY DEFAULT (searx/settings.yml, line 84).  Open
                # WebUI requests `format=json` unconditionally
                # (retrieval/web/searxng.py), and SearXNG answers a
                # disallowed format with 403.
                #
                # So without this line the feature deploys green, the
                # container is healthy, the firewall is right, and every
                # search fails — which is the exact failure shape this repo
                # keeps paying for.  It is one word and it is the single most
                # likely reason for a future "web search does nothing".
                #
                # `html` is kept alongside it on purpose: this service has no
                # hostname and no UI consumer, but a human debugging it over
                # an SSH forward wants the search page and the /stats view,
                # and the response format is not the boundary — the firewall
                # is.  Dropping `html` would harden nothing and cost the only
                # way in when something is wrong.
                search.formats = ["html" "json"];

                # Autocomplete off.  This RESTATES upstream's own default
                # (settings.yml:46 and settings_defaults.py both ship "") and
                # is here as a pin rather than a change: autocomplete is a
                # per-keystroke outbound request to a search engine, for a UI
                # nobody uses on this instance, and it is exactly the kind of
                # thing a future default flip would turn on silently.
                search.autocomplete = "";

                server = {
                  port = settings.port;
                  # `::`, not `0.0.0.0`, and not the container's own address:
                  # the address is a DHCP lease, so binding it specifically
                  # means binding something this module does not know at
                  # build time.  The firewall above is the boundary, the same
                  # shape the webui container uses.
                  #
                  # IT HAS TO BE `::` BECAUSE THIS LISTENER HAS TWO
                  # CONSUMERS ON DIFFERENT FAMILIES.  M20 wrote `0.0.0.0`
                  # when the only caller was Open WebUI over IPv4 at
                  # 10.0.90.24:8888.  M29b then gave mneme the `web0` leg —
                  # `fdca:fe94::1` → `fdca:fe94::2` — which is IPv6-ONLY, and
                  # did not revisit this line.  Everything else about that
                  # leg was correct: both ends up, the container's accept for
                  # `fdca:fe94::1` on 8888 present, mneme launched with
                  # `--search-url http://[fdca:fe94::2]:8888`.  There was
                  # simply no socket on that family, so every `web_search`
                  # call the agent made failed, and the agent reported it as
                  # "I cannot search the internet".
                  #
                  # `::` serves BOTH, and that depends on
                  # `net.ipv6.bindv6only = 0` — the kernel default, verified
                  # 0 in this container.  If that ever flips, the IPv4
                  # consumer (Open WebUI, and the verification curl against
                  # 10.0.90.24:8888 in the header above) loses its listener
                  # instead, which would be the same failure wearing the
                  # other family's clothes.
                  bind_address = "::";

                  # Substituted by searx-init's envsubst from
                  # environmentFile, so the value is never in the store.
                  secret_key = "$SEARXNG_SECRET";

                  limiter = false; # see redisCreateLocally above
                  public_instance = false;

                  # OFF.  The image proxy makes SearXNG fetch every result
                  # thumbnail itself — outbound requests to arbitrary hosts,
                  # which is precisely the unbounded egress this design is
                  # built to avoid.  Open WebUI asks for `image_proxy=0` per
                  # request anyway; this makes it true instance-wide rather
                  # than dependent on the client asking nicely.
                  image_proxy = false;
                };

                # The engine set, filtered down.  See engineKeepOnly.
                use_default_settings.engines.keep_only = settings.engineKeepOnly;

                outgoing.request_timeout = settings.requestTimeout;

                # A UA suffix would let an engine operator identify this
                # instance; there is nothing to gain by it here and it is one
                # more thing that makes the traffic fingerprintable.
                outgoing.useragent_suffix = "";
              }
              # Merged by name over the kept set. Kept as a separate
              # attribute rather than folded above so the two lists read
              # together — see engineOverrides.
              // lib.optionalAttrs (settings.engineOverrides != []) {
                engines = settings.engineOverrides;
              };
          };
        };
      };
    };
  };
}
