# machines/ernst/containers/miniflux.nix
#
# Miniflux — the feed reader, and the INTAKE half of M27's reading stack (see
# docs/history.md).  An nspawn container on VLAN 90 serving
# `miniflux.goclan.org` through Traefik on BOTH entrypoints, behind
# forward-auth, with Authelia as its sole identity provider.
#
# ── ITS PLACE IN THE STACK ──────────────────────────────────────────────────
#
#   Miniflux reads; containers/karakeep.nix keeps.  They are one milestone
#   rather than two because each is useless alone: a reader with nowhere to put
#   what it finds is a river, and an archive with nothing flowing into it is a
#   drawer.
#
#   THERE IS NO COUPLING IN THIS FILE, AND THERE IS ONE IN PRACTICE.  As built,
#   the two services share no database and neither calls the other — that part
#   is still true and still deliberate.  But Miniflux ships a first-class
#   Karakeep integration (Settings → Integrations → Karakeep), it is switched
#   ON, and it is what turns "keep this" from a copy-paste into one click in
#   the reader.  Saved entries POST to
#   `https://karakeep.goclan.org/api/v1/bookmarks` with their own API key,
#   tagged `miniflux, new`.
#
#   IT GOES THROUGH TRAEFIK BY NAME rather than to 10.0.90.29 directly, for the
#   reason containers/homepage.nix gives about reaching Nextcloud: the direct
#   route would cost an accept rule in containers/karakeep.nix and a hardcoded
#   peer, to save one layer-2 hop on a request that happens when a human clicks
#   Save.  `karakeep.goclan.org` carries no forward-auth, so the token passes
#   straight through.
#
#   IT IS NOT DECLARED HERE because it cannot be: Miniflux keeps integration
#   settings per-user in its own database, the same situation as Nextcloud's
#   serverinfo token.  docs/guides/reading-stack.md carries the four fields.
#
# ── WHY THE nspawn TIER ─────────────────────────────────────────────────────
#
#   `services.miniflux` is a first-class NixOS module at this pin.  The podman
#   tier on this host exists for upstreams that ship only an OCI image
#   (storyteller, cwa, romm, tubesync); Miniflux is not one of them, and the
#   upstream project's own preferred deployment is a single Go binary against
#   PostgreSQL, which is exactly what the module builds.  containers/
#   nextcloud.nix argues the tier question at length and this file takes the
#   same side for the same reason.
#
# ── forward-auth AND OIDC — GRAFANA'S ARRANGEMENT, AND NOT THE ONE IT ───────
#    SHIPPED WITH
#
#   `miniflux.goclan.org` is in `protectedHosts` (containers/ingress-policy.nix)
#   and its router carries the `authelia` middleware.  Forward-auth decides
#   whether a request arrives at all; the OIDC client below decides whose it
#   is.  That is Grafana's and Open WebUI's shape.
#
#   IT SHIPPED AS AN `appApiHosts` EXEMPTION and was moved one day later, when
#   off-LAN access was wanted.  The original argument was Miniflux's Fever
#   (/fever/) and Google Reader (/reader/api/0/**) APIs, which carry
#   credentials in the request and cannot follow a 302 — true about the
#   protocols, and false about this house, where nobody uses a native reader.
#   So the exemption bought a capability nobody exercised at the price of a
#   weaker door, and exposing it to the internet was the moment that stopped
#   being free.  containers/ingress-policy.nix carries the full argument.
#
#   THE COST IS PERMANENT AND WORTH KNOWING: no native RSS reader can connect
#   to this hostname again, on the LAN or off it, because forward-auth applies
#   to both entrypoints.  Restoring that is an ingress change with a ledger
#   row, not a setting.
#
#   UNAFFECTED, because neither goes through Traefik: the service index's
#   widget and Prometheus both reach 10.0.90.28:8080 directly across VLAN 90.
#
# ── IT HAS NO LOCAL ACCOUNT, AND THAT IS THE OPPOSITE OF WHAT M24 CHOSE ─────
#
#   `CREATE_ADMIN = 0` plus `DISABLE_LOCAL_AUTH` below means there is no
#   username/password login here at all — if Authelia is down, Miniflux is
#   unreachable.  containers/home-assistant.nix deliberately keeps a local
#   account for the opposite reason, and the difference is not taste:
#
#     * Home Assistant runs the lights.  A house whose front door depends on a
#       second service being healthy is a worse house.
#     * NOTHING depends on Miniflux.  An hour without the feed reader is an
#       hour without the feed reader.
#
#   So the recovery path here is "fix Authelia", and buying a second credential
#   store to avoid that would be paying a permanent cost for a temporary
#   inconvenience.  If this ever stops being true, the escape hatch is one line
#   (`DISABLE_LOCAL_AUTH = "false"`) plus an admin generator in the shape
#   containers/nextcloud.nix uses.
#
# ── IT TAKES NO uid FROM THE 3000 BLOCK, AND THAT IS RECORDED ON PURPOSE ────
#
#   machines/ernst/networking.nix asks that a milestone which DECLINES a number
#   say so, because a reader who finds a new service and no row has to be able
#   to tell "recorded as taking none" from "somebody forgot".  Miniflux takes
#   none: the nixpkgs module runs the daemon under `DynamicUser`, so the only
#   uid that touches zdata here is PostgreSQL's — 71, a well-known NixOS static
#   id, exactly as in containers/nextcloud.nix.
#
# ── NO NEW DATASET ──────────────────────────────────────────────────────────
#
#   The write profile is a PostgreSQL database and nothing else: Miniflux
#   stores article text in the database and downloads no media.  That is
#   `zdata/state`'s profile exactly (128K, auto-snapshot on), so this service
#   gets a directory there and no `disko.nix` change — the same call M24 made
#   for Home Assistant.  docs/guides/ernst-zdata-datasets.md records the
#   negative case.
{
  config,
  pkgs,
  lib,
  ...
}: let
  ##############################################################################
  # Identity.
  ##############################################################################
  # Not ours to choose: a well-known NixOS static id (`ids.uids.postgres`).  It
  # lands on zdata unmapped like every other container uid here.  The
  # 3000-block convention does not apply to it and it must not be renumbered
  # into the block.  See the header — this is the ONLY uid this container puts
  # on the pool.
  postgresUid = 71;
  postgresGid = 71;

  ##############################################################################
  # Peers, ports and paths.
  ##############################################################################

  # The one VLAN-90 peer allowed to reach the web surface.  Every client — a
  # browser, a phone reader over the LAN — arrives through it.  M5's
  # backend-bypass hardening, mechanism (a).
  traefikAddr = "10.0.90.12";

  # The service index (M26), which fetches the unread count with an API token.
  # Tagged with this name in every container that carries a widget so one grep
  # finds them all.
  dashboardAddr = "10.0.90.13";

  # The monitoring container (M6).  Unlike most services on this host, Miniflux
  # has a REAL OpenMetrics endpoint — see the metrics note further down.
  monitoringAddr = "10.0.90.14";

  minifluxAddr = "10.0.90.28";
  minifluxPort = 8080;

  baseDomain = "goclan.org";
  hostName = "miniflux.${baseDomain}";

  # Authelia's portal, as the OIDC issuer.  Restated rather than shared, for
  # the same reason baseDomain is restated in traefik.nix and authelia.nix.
  #
  # NOTE THE ABSENT SUFFIX.  Miniflux's OIDC library appends
  # `/.well-known/openid-configuration` itself, and upstream's documentation is
  # explicit that this part must NOT be in the value.  containers/karakeep.nix
  # takes the FULL URL in its equivalent variable, because that application
  # wants the other form — two adjacent files, two different conventions, both
  # read out of the application that consumes them rather than assumed from
  # each other.  That is M23's lesson stated as a habit.
  autheliaIssuer = "https://auth.${baseDomain}";

  stateRoot = "/srv/state/miniflux";

  ##############################################################################
  # Secrets staging.
  #
  # NOT a bind of /run/secrets itself: that path is a symlink to a
  # per-generation directory which is REPLACED on every deploy, so an nspawn
  # bind established at container start would keep exposing a deleted
  # generation.  A directory we own has a stable identity and is rewritten in
  # place.  containers/traefik.nix carries the long form of this.
  ##############################################################################
  secretsDir = "/run/miniflux-secrets";
  oidcEnvFile = "${secretsDir}/oidc.env";
  bridgeEnvFile = "${secretsDir}/bridge.env";

  # M28's bridge (see the section at the bottom of this file).  Its two values
  # are both copied out of a WEB UI by a human — Miniflux generates the webhook
  # secret, Karakeep mints the API key — so this is a prompted generator, not a
  # generated one, and that is the shape SN5 warns about.  The script below
  # handles it the way containers/homepage.nix does.
  bridgeGen = config.clan.core.vars.generators.miniflux-karakeep-bridge;

  # Declared in containers/authelia.nix, beside the other relying parties —
  # ONE GENERATOR PER RELYING PARTY is that file's rule, and it is why this
  # reaches across rather than declaring its own.  Authelia takes the DIGEST;
  # this container takes the PLAINTEXT half of the same pair.
  oidcGen = config.clan.core.vars.generators.authelia-oidc-miniflux;
in {
  ##############################################################################
  # Host side — the directories, the secrets and the veth.
  ##############################################################################

  # ── NO tmpfiles RULES IN THIS FILE, AND containers/immich.nix IS WHY ───────
  #
  # ── The container, declared rather than assembled ─────────────────────────
  #
  # The `<svc>-dirs` and `<svc>-secrets` units, the `60-vb-miniflux` network,
  # the VLAN backstop, the five-line `containers.<n>` preamble, the 26-line
  # in-container networking block and the firewall pair are all generated by
  # modules/containers/nspawn.nix now. The comments that used to explain each
  # of them lived here in nine near-identical copies across the tree; they are
  # in the module, once.
  #
  # What stays here is what is actually about Miniflux: which peers may reach
  # it, which credentials it needs, and the service itself.
  clanarchy.containers.miniflux = {
    enable = true;

    # Sequence 14 in machines/ernst/allocations.nix, which asserts that this
    # matches its row — a mistyped MAC costs the DHCP reservation silently.
    mac = "02:00:00:90:00:14";

    # Not ours to choose: a well-known NixOS static id (`ids.uids.postgres`).
    # It lands on zdata unmapped like every other container uid here, and must
    # NOT be renumbered into the 3000 block. This is the only uid this
    # container puts on the pool.
    stateDirs = [
      {
        path = stateRoot;
        owner = "root";
        group = "root";
        mode = "0755";
      }
      # The PARENT of the version directory is bound, not the version
      # directory itself, so a future PostgreSQL major bump lands beside the
      # old one on zdata instead of on the container's rootfs.
      {
        path = "${stateRoot}/postgresql";
        owner = postgresUid;
        group = postgresGid;
        mode = "0700";
      }
    ];

    # TWO FILES, NOT FOUR LINES IN ONE, because the two are consumed by
    # different units: systemd reads an EnvironmentFile per service, and
    # giving miniflux.service the bridge's Karakeep token would put a
    # credential in a process with no use for it.
    secrets = {
      "oidc.env" = {
        OAUTH2_CLIENT_ID = {value = "miniflux";};
        OAUTH2_CLIENT_SECRET = {file = oidcGen.files."miniflux-client-secret".path;};
      };
      "bridge.env" = {
        WEBHOOK_SECRET = {file = bridgeGen.files."webhook-secret".path;};
        KARAKEEP_API_TOKEN = {file = bridgeGen.files."karakeep-api-token".path;};
      };
    };

    bindMounts."/var/lib/postgresql" = {
      hostPath = "${stateRoot}/postgresql";
      isReadOnly = false;
    };

    # The only peers allowed at the web surface. Everything else — including a
    # curl from ernst itself — is refused, by design.
    allowFrom = [
      {
        peer = traefikAddr;
        port = minifluxPort;
      } # every browser arrives here
      {
        peer = dashboardAddr;
        port = minifluxPort;
      } # the service index's unread count
      {
        peer = monitoringAddr;
        port = minifluxPort;
      } # a real OpenMetrics endpoint
    ];
  };
  clan.core.vars.generators.miniflux-karakeep-bridge = {
    files."webhook-secret".secret = true;
    files."karakeep-api-token".secret = true;

    # WITHOUT THESE THE VALUES NEVER REACH THE CONTAINER.  The staging script
    # embeds the sops PATH rather than the contents, so rewriting an encrypted
    # file leaves the unit byte-identical and systemd — seeing a `oneshot` with
    # `RemainAfterExit` still active — never re-runs it.  M27 shipped exactly
    # that bug in `homepage-tokens` and it presented as two dashboard tiles
    # failing with nothing in any log.
    files."webhook-secret".restartUnits = [
      "miniflux-secrets.service"
      "container@miniflux.service"
    ];
    files."karakeep-api-token".restartUnits = [
      "miniflux-secrets.service"
      "container@miniflux.service"
    ];

    prompts."webhook-secret" = {
      description = "Miniflux webhook secret (Settings -> Integrations -> Webhook, after saving the endpoint). Miniflux generates it; copy it here.";
      type = "hidden";
    };
    prompts."karakeep-api-token" = {
      description = "Karakeep API key for the Miniflux bridge (Karakeep -> Settings -> API keys). Make a SEPARATE one labelled 'miniflux-bridge'.";
      type = "hidden";
    };

    runtimeInputs = [pkgs.coreutils];
    script = ''
      cat "$prompts/webhook-secret"     > "$out/webhook-secret"
      cat "$prompts/karakeep-api-token" > "$out/karakeep-api-token"
    '';
  };

  # ── The container, declared rather than assembled ─────────────────────────
  clanarchy.containers.miniflux.config = {
    config,
    pkgs,
    lib,
    ...
  }: let
    bridgePkg = pkgs.callPackage ./pkgs/miniflux-karakeep-bridge.nix {};
  in {
    services.miniflux = {
      enable = true;

      # Local PostgreSQL over the unix socket at /run/postgresql.
      #
      # THIS FILE THEREFORE DECLARES NO DATABASE PASSWORD AND NO DATABASE
      # STAGING UNIT, the same argument containers/immich.nix and
      # containers/nextcloud.nix both make: socket connections use peer
      # authentication, and a credential that is never checked is a
      # credential that should not exist.
      createDatabaseLocally = true;

      config = {
        # 0.0.0.0, not the module's localhost default: the listener has to be
        # reachable across the veth.  What bounds it is the firewall above,
        # which is the boundary the rest of this host relies on too.
        LISTEN_ADDR = "0.0.0.0:${toString minifluxPort}";

        # Miniflux builds absolute URLs from this — share links, the OIDC
        # redirect, and the cookie path.  Getting it wrong fails closed at
        # Authelia with `invalid_redirect_uri`, which reads as an Authelia
        # fault.  Nextcloud's `overwriteprotocol` note is the same trap.
        BASE_URL = "https://${hostName}";

        # ── Authentication.  SEE THE HEADER — this removes local login ────
        #
        # CREATE_ADMIN = 0 means the module does not require (and asserts
        # against) an `adminCredentialsFile`, so there is no admin generator
        # in this file at all.  DISABLE_LOCAL_AUTH hides the password form.
        # OAUTH2_USER_CREATION is what lets the first Authelia login create
        # the account, which is the only way an account can exist here.
        CREATE_ADMIN = 0;
        DISABLE_LOCAL_AUTH = "true";
        OAUTH2_PROVIDER = "oidc";
        OAUTH2_OIDC_PROVIDER_NAME = "Authelia";
        OAUTH2_USER_CREATION = 1;

        # No `/.well-known/openid-configuration` suffix — the library appends
        # it.  See the note on autheliaIssuer in the let block.
        OAUTH2_OIDC_DISCOVERY_ENDPOINT = autheliaIssuer;

        # Registered verbatim as the client's sole redirect_uri in
        # containers/authelia.nix.  The path is Miniflux's, not a convention:
        # /oauth2/oidc/callback.
        OAUTH2_REDIRECT_URL = "https://${hostName}/oauth2/oidc/callback";

        # ── Metrics.  A REAL endpoint, unlike most services on this host ──
        #
        # containers/nextcloud.nix declines a Prometheus job because its
        # serverinfo endpoint is token-authenticated JSON and a target
        # pointed at it could only ever read `up == 0` — M13's Ollama lesson,
        # SN3.  Miniflux is the other case: /metrics is a genuine OpenMetrics
        # exposition, so service-modules/monitoring.nix DOES get a job here.
        #
        # METRICS_ALLOWED_NETWORKS is a SECOND gate in front of it, inside
        # the application, and it defaults to 127.0.0.1/8 — so without this
        # line the scrape would be refused by Miniflux itself even though the
        # firewall let it through, and the job would read `up == 0` with
        # nothing in the container's log saying why.
        METRICS_COLLECTOR = 1;
        METRICS_ALLOWED_NETWORKS = "${monitoringAddr}/32";

        # ── THE LINE WITHOUT WHICH M28's BRIDGE RECEIVES NOTHING ─────────
        #
        # MEASURED 2026-09-20, and it is M23's Nextcloud finding in a second
        # costume.  Miniflux has its own SSRF guard, and it refused every
        # webhook delivery:
        #
        #     Unable to send new entries to Webhook … nb_entries=1
        #     error="connection to private network is blocked:
        #            host \"127.0.0.1\" resolves to a non-public IP address"
        #
        # The bridge was correctly configured, listening, and signature-
        # verified end to end by hand — it simply never got a request,
        # because Miniflux would not make one.  Nothing failed; a unit that
        # is never called looks exactly like a unit that works.
        #
        # ── TWO OPTIONS EXIST AND ONLY THE NARROW ONE IS SET ─────────────
        #
        # Read out of the built binary rather than guessed:
        #
        #   INTEGRATION_ALLOW_PRIVATE_NETWORKS  — integrations (this)
        #   FETCHER_ALLOW_PRIVATE_NETWORKS      — FEED FETCHING (not this)
        #
        # The second one is the dangerous half and stays OFF.  A feed URL is
        # attacker-controlled the moment you subscribe to something, so a
        # fetcher permitted into RFC1918 is a server-side request forgery
        # primitive pointed at VLAN 90.  An INTEGRATION target is a URL the
        # administrator typed into a settings page, and here it is
        # 127.0.0.1:8081 — a process in this same namespace.
        #
        # So this relaxes the guard for the one destination we chose and
        # leaves it in force for the one an outsider influences.
        INTEGRATION_ALLOW_PRIVATE_NETWORKS = 1;
      };
    };

    ##########################################################################
    # M28 — the Miniflux → Karakeep bridge.
    #
    # ── WHY IT LIVES IN THIS CONTAINER ────────────────────────────────────
    #
    # Its ONLY client is Miniflux, in this same namespace, so the webhook is
    # a loopback call: no MAC, no address, no DHCP reservation, no uid, no
    # veth and no firewall rule anywhere.  containers/homepage.nix makes the
    # same argument for living inside containers.arr — put a service where
    # its caller already is, and the network question does not arise.
    #
    # ── WHAT IT IS FOR, GIVEN KARAKEEP SUBSCRIBES TO RSS ITSELF ───────────
    #
    # Karakeep's own feed subscriptions take a name, a URL, an enabled flag
    # and a tag-import toggle — no rules, no keyword blocking, no regex.  So
    # for a feed you want in full, Karakeep alone is the right answer and
    # this bridge is redundant; docs/guides/reading-stack.md says so.
    #
    # What this buys is FILTERING.  Miniflux's per-feed block/keep rules
    # decide what survives, and only survivors are forwarded.  Its rewrite
    # rules matter just as much, for a reason that is not obvious: Karakeep
    # deduplicates on the EXACT url, so `?utm_source=...` makes a second
    # bookmark for the same page.  Stripping those before forwarding is
    # something no amount of work on Karakeep's side could do.
    #
    # ── `PORT` IS AN ADDRESS, NOT A NUMBER, AND ITS DEFAULT IS WRONG ──────
    #
    # Upstream passes this string straight to `http.ListenAndServe`, so it
    # must be Go's `host:port` form.  Two traps in one variable:
    #
    #   * `PORT = "8081"` does NOT work — Go rejects it with "missing port in
    #     address".  The colon is mandatory.
    #   * the default is `":8080"`, which is BOTH a collision with Miniflux
    #     itself (LISTEN_ADDR above) and a bind on every interface, including
    #     the VLAN-90 leg.  Either alone would be a defect.
    #
    # 127.0.0.1 is therefore load-bearing rather than tidy: it is what keeps
    # the webhook off VLAN 90 entirely, so the container firewall needs no
    # rule for it and nothing outside this namespace can reach it.
    ##########################################################################
    systemd.services.miniflux-karakeep-bridge = {
      description = "Forward Miniflux entries to Karakeep";
      wantedBy = ["multi-user.target"];
      after = ["network.target"];

      environment = {
        PORT = "127.0.0.1:8081";

        # Through Traefik by name, not to 10.0.90.29 directly — the same
        # call the in-app integration makes, and for the same reason: the
        # direct route costs an accept rule in containers/karakeep.nix and a
        # hardcoded peer address.  `karakeep.goclan.org` is an appApiHosts
        # name, so the bearer token passes straight through forward-auth.
        KARAKEEP_API_URL = "https://karakeep.${baseDomain}";

        # THE WHOLE POINT.  Without this the bridge only forwards entries a
        # human has explicitly starred, which is the manual workflow this
        # milestone exists to replace.
        SAVE_NEW_ENTRIES = "true";

        # Deliberately FALSE, and it interacts with M27's workflow.  Adding
        # forwarded entries to a list would make them `is:inlist`, which is
        # exactly what the `Inbox` smart list (`-is:archived -is:inlist`)
        # excludes — so every arriving item would skip the triage queue it is
        # supposed to land in.  Unfiled is the correct state for something
        # nobody has looked at yet.
        ADD_TO_LIST = "false";
      };

      serviceConfig = {
        ExecStart = lib.getExe bridgePkg;
        EnvironmentFile = bridgeEnvFile;

        # No state, no files, nothing to own.  DynamicUser also gives the
        # hardening set (ProtectSystem=strict, PrivateTmp, NoNewPrivileges …)
        # for free, which is worth more here than a static uid would be —
        # this process holds a Karakeep API token and parses attacker-shaped
        # input from the internet's feeds.
        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = "10s";

        CapabilityBoundingSet = [""];
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        PrivateDevices = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        RestrictAddressFamilies = ["AF_INET" "AF_INET6"];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
      };
    };

    # The client id and secret, out of the staged environment file rather
    # than out of the store.  A drop-in rather than a `config` entry for the
    # reason the staging unit's header gives.
    #
    # An ADDITIVE directive: `EnvironmentFile=` accumulates, so this does not
    # replace anything the module sets (it sets none) and needs none of the
    # empty-string reset that ExecStart would.
    systemd.services.miniflux.serviceConfig.EnvironmentFile = [oidcEnvFile];
  };
}
