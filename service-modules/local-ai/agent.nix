##############################################################################
# roles.agent — mneme, the household agent daemon (M29)
#
# ── WHY THERE IS A DAEMON IN FRONT OF llama-swap AT ALL ────────────────────
#
# Home Assistant on ernst is 2026.5.4, and that release cannot be pointed at
# a local model.  Verified by reading nixpkgs' own component list in both
# channels rather than by trying it:
#
#   nixpkgs 26.05        (HA 2026.5.4)  ollama, openai_conversation, wyoming
#   nixpkgs-unstable     (HA 2026.8.1)  ... plus llama_cpp
#
# The native `llama_cpp` conversation integration — "a local llama.cpp
# server, or any OpenAI-compatible endpoint" — arrived in 2026.8.  And
# `openai_conversation` in 2026.5.4 defines no base-URL constant at all
# (homeassistant/components/openai_conversation/const.py at tag 2026.5.4):
# it can only reach api.openai.com, which is the opposite of the requirement.
#
# What 2026.5.4 DOES have is `ollama`, and it is not a second-class path: its
# entity.py builds `tools` from `chat_log.llm_api.tools`, streams, and loops
# until `unresponded_tool_results` is empty, and its config flow exposes
# CONF_LLM_HASS_API — "Control Home Assistant".  Everything Assist needs.
#
# So mneme speaks the Ollama wire protocol on its north side.  That is a
# translation layer, not an architecture: the daemon has to sit in the
# request path anyway, because that is where the constitution is injected
# (and, from M29b, the memory wiki's index), so the protocol it presents is a
# free choice.  It presents BOTH — /api/chat for Home Assistant today and
# /v1/chat/completions for Open WebUI, opencode and nvf — and the migration
# when ernst's nixpkgs reaches 2026.8 is a config-flow change in a browser.
#
# ── THREE PATHS NOT TAKEN, SO THEY ARE NOT RE-PROPOSED ────────────────────
#
#   * `pkgs-unstable.home-assistant`.  A three-release jump with a one-way
#     recorder migration, on the machine that runs the house, to avoid a
#     contained protocol shim with build-time tests.  Bad trade.
#   * A HACS-downloaded conversation integration.  M24b states the cost out
#     loud: what HACS downloads is the one thing on ernst that is not in this
#     repository.  Putting the model path there would move the most
#     load-bearing integration in the hub out of the repo.
#   * Vendoring core's `llama_cpp` as a customComponent.  It rides ChatLog
#     internals that moved between 2026.5 and 2026.8, so it would be a
#     backport with no upstream and no test.
#
# ── IT TAKES NO ADDRESS, NO uid AND NO LEDGER ROW ─────────────────────────
#
# mneme is a host service beside llama-swap, not a container: its upstream is
# ernst's own loopback, and its one consumer reaches it over the same
# point-to-point ULA mechanism every other loopback consumer uses.  So there
# is no MAC, no DHCP reservation, no Traefik router, no hostname and nothing
# for the UDM-Pro to know.  Sequence 16 / 10.0.90.30 / uid 3039 stay free.
##############################################################################
{
  lib,
  mkBridges,
}: {
  description = "mneme — the household agent daemon in front of llama-swap.";

  interface.options = {
    port = lib.mkOption {
      type = lib.types.port;
      default = 11435;
      description = ''
        Loopback port mneme listens on.

        11435 rather than anything else because it is the port the fleet
        already associates with "llama-swap, one hop away": jens forwards
        ernst's 11434 to its own 11435 (see roles.opencode).  Nothing shares
        a machine with both, so the reuse costs nothing and the number is
        already in people's heads.
      '';
    };

    model = lib.mkOption {
      type = lib.types.str;
      example = "qwen3-coder-30b";
      description = ''
        The model mneme serves, and the ONLY entry its /api/tags returns.

        It must name a key of `roles.models` on this machine — asserted
        below, because a name that llama-swap does not serve produces a clean
        404 from llama-swap and a conversation agent that answers every
        request with an error, which looks like a broken model rather than a
        typo.

        NAMING ANYTHING OTHER THAN THE RESIDENT MODEL COSTS A GPU EVICTION
        PER UTTERANCE.  llama-swap runs its LLMs in an exclusive group, so a
        second text model unloads the coder model every time somebody speaks
        to the house and reloads it the next time the coding agent is used —
        21 GiB off zdata, each way.  containers/karakeep.nix names
        `qwen3-coder-30b` for exactly this reason and so does this role.
      '';
    };

    upstream = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        OpenAI-compatible base URL, including `/v1`.  Empty means "llama-swap
        on this machine", derived from roles.inference's own port so the two
        cannot disagree.
      '';
    };

    exposeOn = lib.mkOption {
      default = [];
      description = ''
        Containers that may reach mneme, as point-to-point ULA peers.

        Identical in shape and in hazards to roles.inference's option of the
        same name, and generated by the same function — see the module header.
        THE VETH ITSELF IS A FOURTH REQUIREMENT this option cannot express:
        the consuming container declares `extraVeths.<name>`, the name is
        host-global, and machines/ernst/networking.nix asserts that no two
        containers claim one.  M29 added that assertion because Open WebUI
        had already lost its leg to a name collision and nothing reported it.
      '';
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            example = "hass";
            description = "Unit-name suffix; must be systemd-safe.";
          };
          address = lib.mkOption {
            type = lib.types.str;
            example = "fdca:fe93::1";
            description = "The HOST end of the point-to-point link.";
          };
          allowedSource = lib.mkOption {
            type = lib.types.str;
            example = "fdca:fe93::2";
            description = "The CONTAINER end — the only permitted peer.";
          };
        };
      });
    };

    logLevel = lib.mkOption {
      type = lib.types.enum ["DEBUG" "INFO" "WARNING" "ERROR"];
      default = "INFO";
      description = ''
        DEBUG logs every translated request, which is how a tool call that
        Home Assistant never executes gets attributed to the right side of
        the translation.  It also logs the whole conversation, including
        whatever the household said, into the journal — so it is a debugging
        setting and not a default.
      '';
    };

    # ── M29b: memory, web search, image generation ────────────────────────
    memory = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Give the agent a git-versioned markdown wiki it can read and write.

          OFF BY DEFAULT because it is the option that makes the agent keep
          things.  Turning it on creates a repository on zdata and gives the
          model four tools that write to it.
        '';
      };
      stateDir = lib.mkOption {
        type = lib.types.path;
        default = "/srv/state/mneme";
        description = ''
          Parent of the wiki.  `/srv/state` by the test in
          docs/guides/ernst-zdata-datasets.md: a tree of small markdown files
          and a git object store is that dataset's write profile, and its
          `com.sun:auto-snapshot=true` is what matters — a fact the household
          told the agent once is not re-acquirable from anywhere.
        '';
      };
      contextBudget = lib.mkOption {
        type = lib.types.ints.positive;
        default = 6000;
        description = ''
          Characters of constitution plus memory injected into every turn.

          A CHARACTER count, not a token count, and approximate on purpose —
          see the note on `build_context` in mneme.py.  6000 is roughly 1500
          tokens against a 32768 window, so memory costs under 5% of the
          context and the conversation keeps the rest.
        '';
      };
      staleDays = lib.mkOption {
        type = lib.types.ints.positive;
        default = 180;
        description = ''
          `mneme-lint` reports pages untouched for longer than this.  It
          never deletes anything — this module removes no facts.
        '';
      };
    };

    webSearch = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Give the agent a `web_search` tool backed by SearXNG.";
      };
      url = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "http://[fdca:fe94::2]:8888";
        description = ''
          SearXNG's base URL as reached FROM THIS HOST.

          Not the VLAN-90 address.  SearXNG's container firewall admits one
          peer and the host's route to 10.0.90.24 hairpins out through the
          UDM-Pro and back — so M29b gives it a point-to-point leg instead,
          the same argument M6's mon0 makes.  The container end of that leg
          is what belongs here.
        '';
      };
    };

    # ── THE DOCUMENT ARCHIVE (M32b) ────────────────────────────────────
    #
    # Paperless-ngx on `docs.goclan.org`, reached over the `doc0` leg.  This
    # is `webSearch`'s shape with one addition: a TOKEN FILE rather than a
    # token, because the whole ExecStart of this unit is visible in
    # `systemctl cat mneme`.
    documents = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Give the agent `document_search` and `document_read` over the
          household's scanned paper.

          The account behind the token is READ-ONLY by construction —
          `containers/paperless.nix` provisions it with four `view_*`
          permissions and no password, and DELETE, PATCH and the upload
          endpoint were measured answering 403 to it.
        '';
      };
      url = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "http://[fdca:fe95::2]:28981";
        description = ''
          Paperless's base URL as reached FROM THIS HOST.

          Not the VLAN-90 address: the host's route to 10.0.90.32 goes via
          10.0.50.1, so every search would hairpin out through the UDM-Pro
          and back.  M29b hit this reaching SearXNG and the answer was a
          point-to-point leg; `doc0` is the same shape, and the container end
          of it is what belongs here.
        '';
      };
      tokenFile = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "/run/secrets/vars/paperless-mneme-token/token";
        description = ''
          File holding paperless's API token for the `mneme` account, read
          once at startup.

          A PATH AND NOT A VALUE: mneme takes its whole configuration as
          flags so that `systemctl cat mneme` shows the entire behaviour, and
          a credential is the one thing that must not be in there.  mneme
          runs on the host, so the per-generation symlink under /run/secrets
          is fine — the staging dance in the container files exists because
          an nspawn bind would pin a deleted generation, which does not apply
          here.
        '';
      };
    };

    imageGen = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Give the agent a `generate_image` tool backed by ComfyUI.

          ── IT IS THE ONE TOOL WITH A RUNNING COST ────────────────────────

          ComfyUI is a member of llama-swap's EXCLUSIVE GPU group, so every
          picture EVICTS the resident 21 GiB language model and the next
          request reloads it — roughly 15 s each way, and it stalls this
          agent and lgo's coding agent both.  The tool's own description
          tells the model so, because a model that does not know an action is
          expensive will take it on a whim.
        '';
      };
      url = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "http://127.0.0.1:11434/upstream/comfyui";
        description = ''
          ComfyUI through llama-swap.  LOOPBACK, and that is the whole reason
          this tool needs no network work: mneme is a host service and
          llama-swap's `/upstream/comfyui` proxy is on 127.0.0.1.  Verified
          200 from the host on 2026-09-25 before this was written.
        '';
      };
      outputDir = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "/srv/state/home-assistant/www/mneme";
        description = ''
          Where the finished PNG is written.

          HOME ASSISTANT SERVES THE PICTURE, NOT mneme, and that is a
          delivery decision rather than a convenience.  mneme listens on a
          point-to-point ULA that only the hub can reach, so a URL it served
          itself would be unreachable from the browser that has to show it.
          The hub serves its own `www/` at `/local/`, that directory is on
          this host, and the hub is already behind Traefik with a public
          name — so this is the only delivery that adds no listener, no route
          and no hostname.

          THE COST, stated: the agent writes into the hub's state tree, and
          `www` has to be traversable by this service.  See the `hass-dirs`
          unit in machines/ernst/containers/home-assistant.nix, which owns
          that tree and therefore owns the permission.
        '';
      };
      publicBase = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "https://ha.goclan.org/local/mneme";
        description = ''
          The URL prefix `outputDir` is served at.  This is what the model
          hands the household, so it has to be the name a phone off the LAN
          resolves too — which `ha.goclan.org` is, split-horizon.
        '';
      };
      checkpoint = lib.mkOption {
        type = lib.types.str;
        default = "sd_xl_base_1.0.safetensors";
        description = ''
          Must be the `filename` of a `roles.models` entry with
          `subdir = "checkpoints"`.  ComfyUI resolves it through the
          generated extra_model_paths.yaml, so a name that is not declared
          there is a per-request load error.
        '';
      };
      steps = lib.mkOption {
        type = lib.types.ints.positive;
        default = 25;
        description = "Sampler steps. 25 is SDXL's usual quality/time knee.";
      };
      width = lib.mkOption {
        type = lib.types.ints.positive;
        default = 1024;
        description = "SDXL is trained at 1024; smaller degrades badly.";
      };
      height = lib.mkOption {
        type = lib.types.ints.positive;
        default = 1024;
      };
      negative = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Negative prompt applied to every generation.";
      };
      timeoutSec = lib.mkOption {
        type = lib.types.ints.positive;
        default = 600;
        description = ''
          Ceiling on one generation.  Generous because a first picture
          includes evicting the language model AND loading a 6.9 GiB
          checkpoint off zdata.
        '';
      };
    };

    readTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 600;
      description = ''
        Seconds to wait on a stalled upstream socket.  Deliberately large and
        deliberately NOT a total request timeout: llama-swap may have to load
        a 21 GiB model off zdata before the first token, which is why
        containers/karakeep.nix sets INFERENCE_JOB_TIMEOUT_SEC to 300 rather
        than the 30 s default.  A total timeout would abort a healthy load.
      '';
    };
  };

  perInstance = {
    settings,
    roles,
    machine,
    ...
  }: {
    nixosModule = {
      config,
      pkgs,
      lib,
      ...
    }: let
      mneme = pkgs.callPackage ../pkgs/mneme {};

      inferencePort =
        roles.inference.machines.${machine.name}.settings.port or 11434;
      upstream =
        if settings.upstream != ""
        then settings.upstream
        else "http://127.0.0.1:${toString inferencePort}/v1";

      declared =
        roles.models.machines.${machine.name}.settings.models or {};

      mem = settings.memory;
      wikiDir = "${mem.stateDir}/wiki";

      # ── uid 3039 (M29b), AND IT IS LOAD-BEARING NOW ──────────────────
      #
      # M29 ran this daemon under DynamicUser because it owned nothing on
      # disk.  A git repository under /srv/state changes that: nspawn and
      # virtiofs pass ids through unmapped, so whatever uid systemd
      # allocated on a given boot is the uid on zdata — and a per-boot
      # identity on the pool is exactly what the uid table in
      # machines/ernst/networking.nix exists to prevent.  M27 made the same
      # call for Meilisearch and went the other way (leave it off the
      # pool); here the data must be persistent, so the identity must be.
      uid = 3039;
    in
      lib.mkMerge [
        {
          assertions = [
            {
              # The same shape as roles.inference's assertion, and for the
              # same reason: a model name that nothing serves fails at
              # runtime, per request, with a 404 three layers from the typo.
              assertion = declared == {} || declared ? ${settings.model};
              message = ''
                @clanarchy/local-ai: roles.agent on ${machine.name} serves
                "${settings.model}", which is not a key of roles.models on
                that machine.  Declared: ${
                  lib.concatStringsSep ", " (lib.attrNames declared)
                }.
              '';
            }
          ];

          systemd.services.mneme = {
            description = "mneme — household agent daemon";
            wantedBy = ["multi-user.target"];
            # Ordering only.  mneme answers /api/tags and /healthz without
            # llama-swap, and Home Assistant's config flow calls exactly
            # those — so a mneme that starts first is useful, and one that
            # REQUIRED llama-swap would take the conversation agent's
            # configuration UI down with it.
            after =
              ["network.target" "llama-swap.service"]
              ++ lib.optional mem.enable "mneme-dirs.service";
            # BLOCKING, not advisory: without the wiki the memory tools would
            # fail per call with a path error, and a guard that only warns is
            # a guard nobody reads.
            requires = lib.optional mem.enable "mneme-dirs.service";

            # git is on the PATH rather than in the package, so which git
            # makes the commits is visible here.
            path = lib.optional mem.enable pkgs.git;

            serviceConfig = {
              ExecStart = lib.concatStringsSep " " ([
                  (lib.getExe mneme)
                  "--listen 127.0.0.1"
                  "--port ${toString settings.port}"
                  "--upstream ${upstream}"
                  "--model ${settings.model}"
                  "--soul-dir ${mneme}/${mneme.soulSubdir}"
                  "--read-timeout ${toString settings.readTimeout}"
                  "--log-level ${settings.logLevel}"
                ]
                ++ lib.optionals mem.enable [
                  "--wiki ${wikiDir}"
                  "--context-budget ${toString mem.contextBudget}"
                ]
                ++ lib.optionals settings.webSearch.enable [
                  "--search-url ${settings.webSearch.url}"
                ]
                ++ lib.optionals settings.documents.enable [
                  "--documents-url ${settings.documents.url}"
                  "--documents-token-file ${settings.documents.tokenFile}"
                ]
                ++ lib.optionals settings.imageGen.enable [
                  "--image-url ${settings.imageGen.url}"
                  "--image-output-dir ${settings.imageGen.outputDir}"
                  "--image-public-base ${settings.imageGen.publicBase}"
                  "--image-checkpoint ${settings.imageGen.checkpoint}"
                  "--image-steps ${toString settings.imageGen.steps}"
                  "--image-width ${toString settings.imageGen.width}"
                  "--image-height ${toString settings.imageGen.height}"
                  "--image-timeout ${toString settings.imageGen.timeoutSec}"
                ]
                ++ lib.optionals
                (settings.imageGen.enable && settings.imageGen.negative != "")
                ["--image-negative '${settings.imageGen.negative}'"]);
              Restart = "on-failure";
              RestartSec = "5s";

              # ── STATIC uid WHEN IT KEEPS ANYTHING (M29b) ──────────────
              #
              # M29 ran this DynamicUser because the daemon owned nothing on
              # disk.  A wiki changes that, and the reason is the one this
              # file already gives for llama-swap's `llama` user and that
              # roles.voice paid for in M29's first deploy: ids pass through
              # unmapped onto zdata, and a per-boot identity on the pool is
              # what the uid table exists to prevent.  With memory off it
              # keeps nothing and stays dynamic.
              DynamicUser = !mem.enable;
              User = lib.mkIf mem.enable "mneme";
              Group = lib.mkIf mem.enable "mneme";
              # The wiki is the ONE path outside the store it may write.
              ReadWritePaths =
                lib.optional mem.enable mem.stateDir
                ++ lib.optional settings.imageGen.enable settings.imageGen.outputDir;
              NoNewPrivileges = true;
              PrivateDevices = true;
              PrivateTmp = true;
              ProtectSystem = "strict";
              ProtectHome = true;
              CapabilityBoundingSet = [""];
              AmbientCapabilities = [""];
              RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
              SystemCallFilter = ["@system-service" "~@resources" "~@privileged"];
              SystemCallErrorNumber = "EPERM";
              SystemCallArchitectures = "native";
              ProtectProc = "invisible";
              ProcSubset = "pid";
              ProtectClock = true;
              ProtectHostname = true;
              ProtectKernelLogs = true;
              ProtectKernelTunables = true;
              ProtectKernelModules = true;
              ProtectControlGroups = true;
              RestrictNamespaces = true;
              RestrictRealtime = true;
              RestrictSUIDSGID = true;
              LockPersonality = true;
              MemoryDenyWriteExecute = true;
              RemoveIPC = true;
              UMask = "0077";

              # ── LOOPBACK, PLUS THE PEERS ITS TOOLS ARE POINTED AT ────
              #
              # This said "Loopback only.  Everything else arrives through a
              # bridge", and that is true of everything that reaches mneme
              # and false of everything mneme reaches.  Home Assistant comes
              # IN over `ai3` through a socket proxy, so the daemon only ever
              # sees 127.0.0.1 — but `web_search` and `document_search` go
              # OUT, to a container's end of a point-to-point leg, and an
              # egress filter that allows only loopback drops them.
              #
              # MEASURED 2026-10-06, as the mneme uid under this exact
              # filter:
              #
              #   http://[fdca:fe95::2]:28981/api/  -> 000 (blocked)
              #   http://[fdca:fe94::2]:8888/       -> 000 (blocked)
              #   http://127.0.0.1:11434/v1/models  -> 200
              #
              # and with the peer added, 302 and 200 respectively.  The
              # symptom is a TIMEOUT rather than a refusal, because the
              # packets are dropped — so the model reports that the search
              # "did not work" and offers to try again, which reads as a
              # flaky service rather than as a policy.
              #
              # `web_search` HAS BEEN BLOCKED SINCE M29b and nobody noticed,
              # because the journal shows the tool was never once invoked:
              # it was shipped, enabled, and never asked for.  `document_search`
              # is what exercised the path first.
              #
              # DERIVED FROM THE URLS RATHER THAN LISTED, so a leg that moves
              # cannot leave this behind — the same reason traefik.nix
              # extracts hostnames from its rules instead of keeping a second
              # map.  A URL whose host is not a bracketed literal contributes
              # nothing, which is correct: those are reached some other way
              # and should be argued for separately.
              IPAddressDeny = "any";
              IPAddressAllow = let
                # POSIX BRACKET EXPRESSIONS, NOT \[ — `builtins.match` is
                # ERE and rejects a backslash-escaped bracket outright.
                # machines/ernst/networking.nix's `addrOf` carries the same
                # note for the same reason; this is the second place it
                # bites.
                # AND IT THROWS RATHER THAN RETURNING null, because a
                # peer this cannot parse is a tool that is offered to the
                # model and then times out on every call — the exact
                # failure this block is being written to fix, reintroduced
                # silently.  An eval error naming the option is strictly
                # better than a model apologising for a flaky service.
                hostOfUrl = what: url: let
                  m = builtins.match "https?://[[]([^]]+)[]].*" url;
                in
                  if m == null
                  then
                    throw ''
                      local-ai: roles.agent ${what}.url is ${url}, which has
                      no bracketed IPv6 literal for a host, so mneme's egress
                      filter cannot be derived from it.

                      mneme runs under IPAddressDeny=any. A peer that is not
                      in IPAddressAllow is DROPPED, and the tool times out
                      rather than failing — which the model reports as the
                      service being unavailable.

                      Use the container end of a point-to-point leg
                      (http://[fdca:feNN::2]:PORT), or widen IPAddressAllow
                      here deliberately and say why.
                    ''
                  else "${builtins.head m}/128";
                peers =
                  []
                  ++ lib.optional settings.webSearch.enable
                  (hostOfUrl "webSearch" settings.webSearch.url)
                  ++ lib.optional settings.documents.enable
                  (hostOfUrl "documents" settings.documents.url);
              in
                ["localhost"] ++ peers;
            };
          };

          environment.systemPackages = [mneme];

          # ── The wiki's identity and its directory ────────────────────────
          users.users.mneme = lib.mkIf mem.enable {
            inherit uid;
            isSystemUser = true;
            group = "mneme";
            home = mem.stateDir;
            createHome = false;
            description = "Household agent memory (mneme)";
          };
          users.groups.mneme = lib.mkIf mem.enable {gid = uid;};

          # A GUARD, NOT A tmpfiles RULE, and for the reason every other
          # service on this host gives: activation does not re-run
          # systemd-tmpfiles-setup in time, and a service that writes to
          # /srv/state before the dataset is mounted writes onto the ROOT
          # pool — where it is silently lost at the next rollback.  Immich
          # measured that; this is the same shape.
          systemd.services.mneme-dirs = lib.mkIf mem.enable {
            description = "Prepare and verify mneme's memory on zdata";
            wantedBy = ["multi-user.target"];
            after = ["srv-state.mount"];
            requires = ["srv-state.mount"];
            before = ["mneme.service"];
            requiredBy = ["mneme.service"];
            path = [pkgs.git pkgs.util-linux pkgs.coreutils];
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
            };
            script = ''
              set -euo pipefail

              # findmnt on the PARENT: --target on a leaf that does not exist
              # yet returns nothing, which would read as "wrong dataset".
              src=$(findmnt --noheadings --output SOURCE --target /srv/state || true)
              if [ "$src" != "zdata/state" ]; then
                echo "mneme-dirs: /srv/state is '$src', expected 'zdata/state'." >&2
                echo "Refusing to write the memory wiki onto the root pool," >&2
                echo "where a rollback would silently discard it. Fix with:" >&2
                echo "  zfs create -o recordsize=128K -o exec=on \\" >&2
                echo "    -o com.sun:auto-snapshot=true zdata/state" >&2
                exit 1
              fi

              install -d -o ${toString uid} -g ${toString uid} -m 0750 ${mem.stateDir}
              install -d -o ${toString uid} -g ${toString uid} -m 0750 ${wikiDir}

              # git init is idempotent and this is the only place it happens,
              # so a wiki cannot exist without being a repository — which is
              # the whole audit story.
              if [ ! -d ${wikiDir}/.git ]; then
                git -C ${wikiDir} init -q -b main
                git -C ${wikiDir} config user.name mneme
                git -C ${wikiDir} config user.email mneme@goclan.org
              fi
              for d in ${lib.concatStringsSep " " ["00-core" "01-people" "02-devices" "03-routines" "04-facts"]}; do
                install -d -o ${toString uid} -g ${toString uid} -m 0750 ${wikiDir}/"$d"
              done
              chown -R ${toString uid}:${toString uid} ${wikiDir}
            '';
          };

          # ── The nightly pass ────────────────────────────────────────────
          #
          # SN4 SAYS A FAILED ONESHOT ON A TIMER IS SILENT, and it is already
          # answered here rather than needing a new rule: ernst sets
          # `exporters.systemd = true`, so node_exporter reports this unit's
          # failed state and monitoring.nix's `SystemdUnitFailed` fires on
          # it.  That is why there is no bespoke alert for this service — the
          # general mechanism covers a host unit, and a second rule aimed at
          # one unit would be the kind of duplication that later disagrees
          # with the general one.
          #
          # (It is the CONTAINER units that mechanism cannot see, which is
          # what `exporters.containers` exists for.  This runs on the host.)
          systemd.services.mneme-lint = lib.mkIf mem.enable {
            description = "Rebuild mneme's memory index and report problems";
            after = ["mneme-dirs.service"];
            requires = ["mneme-dirs.service"];
            path = [pkgs.git];
            serviceConfig = {
              Type = "oneshot";
              User = "mneme";
              Group = "mneme";
              ExecStart = lib.concatStringsSep " " [
                "${mneme}/bin/mneme-lint"
                "--wiki ${wikiDir}"
                "--stale-days ${toString mem.staleDays}"
              ];
              ReadWritePaths = [mem.stateDir];
              NoNewPrivileges = true;
              PrivateDevices = true;
              ProtectSystem = "strict";
              ProtectHome = true;
              IPAddressDeny = "any"; # it reads files; it needs no network
            };
          };

          systemd.timers.mneme-lint = lib.mkIf mem.enable {
            description = "Nightly mneme memory lint";
            wantedBy = ["timers.target"];
            timerConfig = {
              OnCalendar = "daily";
              # The wiki is small, so this is about not colliding with the
              # snapshot and GC timers rather than about load.
              RandomizedDelaySec = "30m";
              Persistent = true;
            };
          };
        }

        (mkBridges {
          inherit pkgs;
          unit = "mneme-bridge";
          what = "mneme";
          targetPort = settings.port;
          bridges = settings.exposeOn;
          extraAfter = ["mneme.service"];
        })
      ];
  };
}
