##############################################################################
# roles.inference — llama-swap + llama-server router
##############################################################################
{
  lib,
  mkBridges,
}: {
  description = "llama-swap in front of llama-server in router mode. Loopback only.";

  interface.options = {
    port = lib.mkOption {
      type = lib.types.port;
      default = 11434;
      description = ''
        Loopback port llama-swap listens on — the OpenAI-compatible surface
        every client talks to.

        11434 DELIBERATELY: it is the port ollama had, so existing clients
        and, more importantly, the jens tunnel's
        `permitopen="127.0.0.1:11434"` restriction keep working with no
        change at all.  Moving it means editing the opencode role's
        `remotePort` AND re-deploying jens, in that order.
      '';
    };

    # THERE IS NO `routerPort`.  It named the port llama-server's router
    # listened on, back when this module ran a router and pointed llama-swap
    # at it.  llama-swap has no externally-managed-backend mode — `cmd` is
    # mandatory — so it spawns llama-server itself, which made the router
    # redundant and 11436 unused.  Recorded rather than silently dropped
    # because M19 (docs/history.md) and PHASE0-NOTES.md both describe the
    # two-layer shape, and this is where it stopped being true.

    swapPortRange = lib.mkOption {
      type = lib.types.port;
      default = 11500;
      description = ''
        First port llama-swap hands to the backends it spawns (its
        `startPort`).  They are loopback, ephemeral, and never contacted
        directly.
      '';
    };

    idleTtl = lib.mkOption {
      type = lib.types.ints.positive;
      default = 900;
      example = 300;
      description = ''
        Seconds a backend may sit idle before llama-swap unloads it, freeing
        VRAM for another member of the exclusive group.

        THIS IS THE SETTING THAT MAKES THE WHOLE ARRANGEMENT WORK, because
        llama-server's own router has no idle unload at all — it evicts only
        when `--models-max` is reached, and a non-LLM consumer like ComfyUI
        is not a router model, so it can never trigger that.  Without a ttl
        here the coder model holds 21.8 GiB indefinitely and image generation
        simply fails to find memory.

        900 s is a coding-session number: long enough that a pause to read a
        diff does not cost a 15-second reload, short enough that walking away
        returns the card. Measured reload cost from cold: ~4 s to evict and
        bring the other member up, ~15 s for the 18.5 GiB coder model.
      '';
    };

    # ── THE CARD IS NOT ALL OURS ───────────────────────────────────────
    #
    # llama-swap's `exclusive` group arbitrates the claimants it SPAWNS.
    # It knows nothing about claimants outside it, and on ernst there is a
    # permanent one: the HTPC session's compositor, which holds a
    # framebuffer on the same card every minute of every day.
    #
    # That gap cost the TV eleven minutes on 2026-10-09.  A model sized to
    # fit an *idle* card left 460 MiB, Steam Big Picture needs ~1350, and
    # gamescope answers a failed framebuffer pin by aborting — nine times,
    # with SDDM reloging it in after each one.  The arithmetic had been
    # done correctly against the wrong baseline, in a comment, where
    # nothing could check it.
    #
    # So the baseline becomes a declared number and the evaluator enforces
    # it.  The next person to raise a context length gets a failed eval
    # instead of a coredump on the television.
    vram = {
      totalMiB = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        example = 24560;
        description = ''
          Total VRAM on the inference card, in MiB, as the driver reports
          it — `cat /sys/class/drm/cardN/device/mem_info_vram_total`, which
          is smaller than the marketing figure (a 24 GB card reports 24560
          MiB, not 24576).

          `null` disables the budget check entirely.  Set it on any machine
          whose inference card also drives a display.
        '';
      };

      reserveMiB = lib.mkOption {
        type = lib.types.ints.unsigned;
        default = 0;
        example = 1600;
        description = ''
          VRAM that must stay free for claimants OUTSIDE llama-swap's
          exclusive group — in practice the compositor holding the screen.

          This is not a safety margin, it is a measured floor: sum
          `amdgpu_gem_info` per process with the session idle and nothing
          else on the card.  A model is only allowed to exist if it fits in
          `totalMiB - reserveMiB`.
        '';
      };
    };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/srv/state/local-ai";
      description = ''
        Where models and runtime state live.  On zdata, per architecture
        invariant #7 — and this one is not a formality: the model set is tens
        of GiB and the old ollama store sat on `zroot/persist`, which is the
        pool that is not supposed to carry service data.  18.5 GiB of weights
        were on the root pool for a year because nothing said otherwise.
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "llama";
      description = ''
        Static system user everything in this role runs as.

        STATIC, NOT DynamicUser, and the reason is written in blood in the
        ollama era of this file: DynamicUser + impermanence means the persist
        entry is created root:root 0700 and the per-boot dynamic uid cannot
        write to it, so the daemon fails to create its model directory and
        every fetch dies with a permission error that names the wrong thing.
      '';
    };

    exposeOn = lib.mkOption {
      default = [];
      description = ''
        Point-to-point ULA addresses to expose llama-swap on, one per
        container that needs it.  Each entry gets a systemd socket, a
        socket-activated proxy to llama-swap's loopback port, and ONE
        firewall accept for its declared peer.

        WHY THIS EXISTS AT ALL.  llama-swap binds 127.0.0.1 and stays there;
        a container cannot reach the host's loopback.  M6 solved the same
        problem for Prometheus with a point-to-point veth (mon0), and every
        consumer here needs the same shape: its own /128 pair, its own accept
        rule, and no VLAN exposure whatsoever.

        WHY A LIST RATHER THAN TWO OPTIONS.  There were two consumers by the
        end of the first deploy — the monitoring container scraping /metrics
        and the Open WebUI container doing chat and STT — and the second was
        MISSED because the first had its own bespoke option and the second
        quietly had nothing listening on its address.  Open WebUI's voice
        input span forever and chat had no path either.  One mechanism, one
        list, so adding a consumer cannot half-happen.

        Each entry needs THREE things and all three are load-bearing:
          * a socket on `address` — binding is not enough on its own;
          * a firewall accept for `allowedSource` — ernst's host firewall
            drops anything unmatched, silently, and the proxy never sees the
            packet so it logs nothing;
          * the consumer pointed at `address`, not at localhost.
      '';
      type = lib.types.listOf (lib.types.submodule {
        options = {
          name = lib.mkOption {
            type = lib.types.str;
            example = "monitoring";
            description = "Unit-name suffix. Must be unique and systemd-safe.";
          };
          address = lib.mkOption {
            type = lib.types.str;
            example = "fdca:fe90::1";
            description = ''
              HOST end of the veth to listen on — a literal address, never a
              wildcard. This is the whole containment: the only peer of that
              /128 is the container named below.
            '';
          };
          allowedSource = lib.mkOption {
            type = lib.types.str;
            example = "fdca:fe90::2";
            description = ''
              CONTAINER end, and the one address permitted to connect.
              Its absence is silent — the scrape or request simply times out.
            '';
          };
        };
      });
    };

    remoteClients.enable = lib.mkEnableOption ''
      accepting SSH port-forwards from clan machines that have no usable local
      inference (see the opencode role's `tunnel` option)

      This does NOT put the inference server on the network.  llama-swap stays
      bound to loopback; what this authorises is one dedicated key, restricted
      to forwarding a single loopback port and nothing else — no shell, no
      pty, no agent or X11 forwarding
    '';
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
      inherit (settings) stateDir user port;
      modelsDir = "${stateDir}/models";

      # ROCm llama.cpp, built from the flake's OWN nixpkgs — no new input,
      # which was a hard constraint on this milestone and turned out to cost
      # nothing: stable's llama-cpp takes `rocmSupport` and builds clean for
      # gfx1100.  Measured on the resulting binary (b9190 / b64739e), not on
      # a promise.
      #
      # rocmGpuTargets is a LIST here.  whisper-cpp's argument of the same
      # name is a STRING in the same nixpkgs.  They disagree, and passing the
      # wrong one fails inside cmake option handling with a message that
      # names neither package.
      llamaCpp = pkgs.llama-cpp.override {
        rocmSupport = true;
        rocmGpuTargets = ["gfx1100"];
      };

      # THE SINGLE SOURCE OF TRUTH FOR THE MODEL SET.  Read out of the
      # `models` role's settings for this same machine rather than
      # duplicated here, so the fetcher and the preset INI cannot disagree.
      # `or` guards the case where a machine holds `inference` and not
      # `models` — legal, and means "an inference server with nothing
      # declared", which the assertion below turns into a build error
      # rather than an empty /v1/models at runtime.
      declared =
        roles.models.machines.${machine.name}.settings.models or {};

      # Only the entries llama-server actually serves become preset sections
      # and llama-swap models.  whisper's ggml weights are declared in the
      # same `models` attrset — one fetcher, one hash-verified store — but
      # llama-server cannot load them, and a preset section pointing at a
      # non-GGUF is a router that logs a load error per request.
      modelNames =
        lib.filter (n: declared.${n}.servedByLlama)
        (lib.attrNames declared);

      # Where a declared model's file lands.  Derived, never configured:
      # two names for one path is how the fetcher and the INI drift.
      #
      # `subdir` (M21) is applied HERE as well as in the fetcher, and the
      # two must stay in step — the fetcher's `relOf` is the same
      # expression.  A model with a subdirectory whose server path omitted
      # it would download correctly and then fail to load, per request,
      # with a file-not-found naming a path nothing ever wrote.
      relOf = m: file:
        if m.subdir == ""
        then file
        else "${m.subdir}/${file}";
      fileOf = name: let m = declared.${name}; in "${modelsDir}/${relOf m m.filename}";

      ####################################################################
      # The router's preset INI.
      #
      # Keys are llama-server CLI arguments without their leading dashes
      # (tools/server/README.md, "Model presets"), so `c`, `cache-type-k`
      # and `cache-type-v` are per-model — which is the property SN1 needs:
      # the context window is pinned AT THE PLACE THE MODEL IS DECLARED,
      # not in one global environment variable that a model-tag edit can
      # silently invalidate.
      ####################################################################
      # One llama-server invocation per declared model.  `${PORT}` is
      # llama-swap's own macro, escaped here so Nix leaves it alone.
      #
      # --jinja is not optional: it is what makes llama.cpp use the GGUF's
      # embedded chat template, which for qwen3-coder is the template that
      # renders the <tools> block at all.  -fa on is not cosmetic either —
      # measured 1667 MiB saved at 32k, unlike on ollama where flash
      # attention was a measured no-op.
      llamaCmd = name: let
        m = declared.${name};
      in
        lib.concatStringsSep " " ([
            "${llamaCpp}/bin/llama-server"
            "--host 127.0.0.1 --port \${PORT}"
            "-m ${fileOf name}"
            "-c ${toString m.contextLength}"
            "--cache-type-k ${m.kvCacheType}"
            "--cache-type-v ${m.kvCacheType}"
            "-ngl 999 -fa on --jinja"
            "--alias ${name}"
            "--metrics"

            # ── THINKING IS OFF UNLESS A CLIENT ASKS FOR IT ──────────────
            #
            # Qwen3.6 thinks by default, and a thinking response puts the
            # reasoning in `reasoning_content` and leaves `message.content`
            # EMPTY until the thinking finishes.  A client that reads
            # `content` — which is every plain OpenAI client — therefore
            # gets an empty string, and if it capped max_tokens it gets
            # `finish_reason: "length"` with nothing in it at all.
            #
            # THIS IS NOT HYPOTHETICAL AND IT COST A DAY OF GPU.  #227
            # switched every consumer to this model; Karakeep, which speaks
            # plain OpenAI and cannot be told to send template kwargs,
            # started failing every auto-tag job with
            #
            #     The model ignored our prompt and didn't respond with the
            #     expected JSON
            #     Got no message content from OpenAI
            #
            # and retrying each one forever — 26 inference jobs per 10
            # minutes, GPU pinned at 96%, Tctl at 96 °C, producing nothing.
            # Verified directly against the running server: the same prompt
            # burns all 200 max_tokens on `reasoning_content` and returns
            # `content: ""`, and with `enable_thinking: false` returns
            # `{"tags":["test"]}` in 6 tokens.
            #
            # A SERVER DEFAULT IS THE RIGHT PLACE, not a per-client patch.
            # The clients that want thinking already ask for it explicitly —
            # mneme sends `chat_template_kwargs.enable_thinking` on every
            # request, derived from Ollama's `think` flag
            # (service-modules/pkgs/mneme/mneme.py), and Home Assistant
            # defaults it false for the same reason (#224).  Naive clients
            # are the ones that need a sane default, and they are exactly
            # the ones that cannot set it.
            #
            # Request-level kwargs override this default, which is what
            # keeps mneme's `think: true` path working — verify after
            # deploying, it is the one claim here not tested in advance.
            "--chat-template-kwargs '{\"enable_thinking\":false}'"
          ]
          ++ lib.optional (m.mmproj != null) "--mmproj ${modelsDir}/${relOf m m.mmproj}"
          ++ m.extraArgs);

      ####################################################################
      # llama-swap's config.
      #
      # ONE EXCLUSIVE GROUP holding every GPU consumer.  Membership is what
      # makes the mutual exclusion structural rather than a comment: a
      # backend added to `models` joins the group automatically, and a
      # backend that is NOT in the group would silently be allowed to run
      # beside the 30B and exhaust the card.
      ####################################################################
      # WHISPER IS DELIBERATELY NOT A MEMBER, and this reverses what the
      # milestone set out to build.  The plan was to register Whisper here
      # "so Whisper's VRAM is accounted for".  IT HAS NONE.
      #
      # Measured on ernst 2026-09-09: nixpkgs' whisper-cpp built with
      # `rocmSupport = true` LINKS libamdhip64 but ships no loadable
      # `libggml-hip.so`, so ggml's backend loader finds only CPU and
      # whisper reports:
      #
      #   whisper_backend_init_gpu: device 0: CPU (type: 0)
      #   whisper_backend_init_gpu: no GPU found
      #
      # It runs at ~2.1x realtime on 8 threads (5.2 s for 11 s of audio),
      # which is fine for dictation and costs zero VRAM.
      #
      # So putting it in an `exclusive` group would EVICT THE 18.5 GiB CODER
      # MODEL to run a workload that never touches the card — a ~15 s reload
      # bought for nothing, every time somebody dictates a sentence.  It is
      # still a llama-swap MODEL (below) so it gets a ttl, a health check
      # and one endpoint for Open WebUI to talk to; it is just not in the
      # group that arbitrates the GPU.
      swapMembers =
        modelNames
        ++ lib.optional imagegenEnabled "comfyui";

      speechRole = roles.speech.machines.${machine.name}.settings or null;
      imagegenRole = roles.imagegen.machines.${machine.name}.settings or null;
      speechEnabled = speechRole != null;
      imagegenEnabled = imagegenRole != null;

      ####################################################################
      # ComfyUI — spawned by llama-swap, not run beside it.
      #
      # See the `comfyui` entry in swapConfig.models for why this is a
      # command rather than a container, and service-modules/pkgs/comfyui
      # for why it is a derivation rather than a pinned image.
      ####################################################################
      comfyuiPkg = pkgs.callPackage ../pkgs/comfyui {};

      # ── ONE MODEL STORE, TWO NAMING CONVENTIONS, NO SECOND FETCHER ────
      #
      # roles.models fetches and hash-verifies everything the GPU tier
      # loads, including diffusion checkpoints (`servedByLlama = false`,
      # the same escape hatch whisper's weights use).  ComfyUI, though,
      # DISCOVERS models by scanning category directories rather than being
      # handed a path — so it needs to be told that the store exists and
      # which category each part of it holds.
      #
      # The mapping is DERIVED FROM THE DECLARATIONS, not written out
      # again: a model's `subdir` IS its ComfyUI category, so declaring
      # `subdir = "checkpoints"` in clan.nix is the whole of adding a
      # checkpoint, and a category with nothing declared in it never
      # appears here.  That is the same one-attrset-two-consumers property
      # the preset INI has, extended to a third consumer.
      comfyModelCategories =
        lib.unique
        (lib.filter (s: s != "")
          (lib.mapAttrsToList (_: m: m.subdir) declared));

      # JSON is valid YAML, exactly as it is for llama-swap's config above.
      comfyExtraModelPaths =
        pkgs.writeText "comfyui-extra-model-paths.yaml"
        (builtins.toJSON {
          clanarchy =
            {
              base_path = modelsDir;
              # FALSE deliberately.  `is_default` marks these as the
              # preferred directories for anything that WRITES a model, and
              # nothing should ever write into a hash-verified store managed
              # by the fetcher.  Reads are unaffected — the paths are
              # searched either way.
              is_default = false;
            }
            // lib.listToAttrs (map (c: {
                name = c;
                value = c;
              })
              comfyModelCategories);
        });

      comfyuiCmd = lib.concatStringsSep " " ([
          "${comfyuiPkg}/bin/comfyui"
          "--listen 127.0.0.1 --port \${PORT}"

          # THE STORE COPY IS READ-ONLY AND ComfyUI EXPECTS TO WRITE.  This
          # one flag relocates models, custom_nodes, input, output, temp and
          # user in a single move (comfy/cli_args.py); without it ComfyUI
          # tries to create them next to main.py in /nix/store and dies.
          "--base-directory ${imagegenRole.stateDir}"

          "--extra-model-paths-config ${comfyExtraModelPaths}"
        ]
        ++ imagegenRole.extraArgs);

      swapConfig = {
        healthCheckTimeout = 300;
        logLevel = "info";
        startPort = settings.swapPortRange;

        models =
          # ── llama-swap SPAWNS each model. THERE IS NO ROUTER. ──────────
          #
          # The first cut of this module ran `llama-server` in ROUTER mode
          # and pointed llama-swap at it with `proxy` + `useModelName`,
          # reasoning that the router owns LLM<->LLM swapping and llama-swap
          # owns LLM<->non-LLM.  THAT IS NOT A SHAPE llama-swap SUPPORTS,
          # and it failed on the first real request:
          #
          #   HTTP 500 {"src":"llama-swap",
          #     "error":"unable to get sanitized command: empty command"}
          #
          # `proxy` is not "forward to this external service".  Its own
          # documentation calls it "the URL where llama-swap routes API
          # requests" — i.e. where the process it STARTS will listen, and
          # `cmd` is mandatory (config.go returns "empty command"
          # otherwise).  There is no externally-managed-backend mode.
          #
          # So llama-swap spawns llama-server per model, with that model's
          # own context and KV type on the command line. This is exactly the
          # shape Phase 0's exclusivity proof used, so it is measured rather
          # than hoped: coder resident 21797 MiB -> other member 19118 MiB
          # -> coder back at 21797 MiB.
          #
          # AND IT MAKES THE ROUTER REDUNDANT, which corrects a Phase 0
          # conclusion rather than working around it. The two arguments for
          # the router both evaporate: its lack of an idle unload no longer
          # matters because nothing defers to it, and its phantom `default`
          # model — which recursed into a child router and hung the request
          # — simply never exists. llama.cpp's own warning that router mode
          # is "experimental ... not recommended in untrusted environments"
          # stops applying too. One layer, not two.
          lib.listToAttrs (map (name: {
              inherit name;
              value = {
                cmd = llamaCmd name;
                ttl = settings.idleTtl;
                checkEndpoint = "/health";
                name = declared.${name}.description;
              };
            })
            modelNames)
          # The non-LLM backends ARE spawned by llama-swap, because they
          # are the ones llama-server's router cannot see and therefore
          # cannot arbitrate against.
          // lib.optionalAttrs speechEnabled {
            whisper = {
              cmd = lib.concatStringsSep " " [
                "${speechPackage}/bin/whisper-server"
                "--host 127.0.0.1 --port \${PORT}"
                "-m ${modelsDir}/${speechRole.model}"
                # Makes it OpenAI-shaped with no wrapper in front.  The
                # default is /inference, which Open WebUI does not speak.
                "--inference-path /v1/audio/transcriptions"
                "-t ${toString speechRole.threads}"
                "-l ${speechRole.language}"
              ];
              ttl = settings.idleTtl;
              checkEndpoint = "/health";
              name = "Whisper (speech to text)";

              # HIDDEN FROM /v1/models, because it is not a chat model.
              #
              # Open WebUI builds its model picker from /v1/models, so
              # whisper appeared there as something to converse with — and
              # picking it fails, since whisper-server answers
              # /v1/audio/transcriptions and not /v1/chat/completions. A
              # menu entry whose only behaviour is to break is worse than no
              # entry.
              #
              # `unlisted` skips the listing ONLY (internal/server/api.go:52
              # `if mc.Unlisted { continue }`); routing by model name is
              # untouched, so the STT path keeps working — Open WebUI names
              # `whisper` explicitly in AUDIO_STT_MODEL rather than
              # discovering it.
              unlisted = true;
            };
          }
          // lib.optionalAttrs imagegenEnabled {
            comfyui = {
              # ── M19 WROTE THIS ENTRY IN THE ONE SHAPE llama-swap ───────
              #    DOES NOT SUPPORT, AND M21 IS WHERE IT WAS CAUGHT.
              #
              # It shipped as `proxy` with NO `cmd`, on the reasoning that
              # ComfyUI was already running under podman and llama-swap
              # only needed to know it existed.  That is EXACTLY the
              # externally-managed-backend shape the `models` note above
              # records as impossible — and the failure is identical:
              #
              #   HTTP 500 {"src":"llama-swap",
              #     "error":"unable to get sanitized command: empty command"}
              #
              # doStart() requires BOTH (process_command.go:358-364): a
              # non-empty Proxy, then SanitizedCommand(), which returns
              # "empty command" for an empty Cmd.  The role was never
              # enabled, so nothing exercised it.  The roadmap's "adding
              # ComfyUI to swapMembers is one line" was false.
              #
              # ── AND THE FIX IS WHY M21 LEFT THE PODMAN TIER ───────────
              #
              # llama-swap MUST own the process, because killing it on ttl
              # is the ONLY thing that hands the VRAM back.  This unit runs
              # as the unprivileged `${user}` user and ernst's podman tier
              # is rootful, so it could never have started or stopped a
              # container.  Built instead, ComfyUI is an ordinary child of
              # this unit and inherits its ROCm sandbox — the same
              # arrangement llama-server's model processes already use.
              cmd = comfyuiCmd;

              # `${PORT}` is llama-swap's macro (escaped so Nix leaves it
              # alone): it allocates the port from `startPort` and puts the
              # same number in both the command and the proxy target.
              proxy = "http://127.0.0.1:\${PORT}";
              ttl = settings.idleTtl;
              checkEndpoint = "/system_stats";
              name = "ComfyUI (image generation)";

              # HIDDEN FROM /v1/models, for the reason whisper is — read
              # that note above; this is the same defect with a different
              # backend.  Open WebUI builds its model picker from
              # /v1/models, and ComfyUI answers none of the chat API, so an
              # entry here would be a menu item whose only behaviour is to
              # fail.  Routing by name is untouched, which is what
              # /upstream/comfyui below depends on.
              unlisted = true;
            };
          };

        groups =
          {
            # The card. One member resident at a time, and loading one here
            # evicts anything in another group.
            gpu = {
              swap = true;
              exclusive = true;
              members = swapMembers;
            };
          }
          # ── CPU BACKENDS NEED AN EXPLICIT NON-EXCLUSIVE GROUP ────────────
          #
          # Leaving whisper out of `gpu` was meant to stop a CPU workload from
          # evicting the 18.5 GiB coder model. IT DID THE OPPOSITE, because a
          # model in no explicit group falls into llama-swap's implicit
          # `(default)` group — and that group is built with
          # `Exclusive: true` (internal/config/config.go:562). So an
          # un-grouped model evicts EVERY other group.
          #
          # Measured on ernst 2026-09-09 before the fix: one STT request took
          # VRAM from 21065 MiB to 402 MiB and unloaded qwen3-coder-30b, so
          # dictating a sentence cost a full ~15 s model reload — precisely
          # the cost the exclusion was supposed to avoid.
          #
          # `exclusive = false` is the whole fix; `swap = false` lets several
          # CPU backends coexist if more are ever added.
          // lib.optionalAttrs speechEnabled {
            cpu = {
              swap = false;
              exclusive = false;
              members = ["whisper"];
            };
          };
      };

      swapConfigFile =
        pkgs.writeText "llama-swap.yaml"
        (builtins.toJSON swapConfig); # llama-swap parses YAML; JSON is valid YAML

      speechPackage = pkgs.whisper-cpp.override {
        rocmSupport = true;
        # A STRING here, not a list — whisper-cpp and llama-cpp disagree on
        # the type of this argument in nixpkgs 26.05.  Getting it wrong is
        # an `assert lib.isString value` failure deep in cmake option
        # handling, which does not name this line.
        rocmGpuTargets = speechRole.gpuTarget;
      };

      tunnelPubKeyPath =
        config.clan.core.settings.directory
        + "/vars/shared/ollama-tunnel-ssh/tunnel_ed25519.pub/value";
      tunnelPubKey =
        if builtins.pathExists tunnelPubKeyPath
        then lib.removeSuffix "\n" (builtins.readFile tunnelPubKeyPath)
        else null;
    in
      lib.mkMerge [
        {
          assertions =
            [
              {
                assertion = declared != {};
                message = ''
                  @clanarchy/local-ai: ${machine.name} holds roles.inference but
                  declares no models.  Add it to roles.models — the two are
                  deliberately separate roles reading ONE attrset, so that the
                  fetcher and llama-server's preset INI cannot disagree, and an
                  inference server with an empty model set is a configuration
                  mistake rather than a valid state.
                '';
              }
            ]
            # ── THE VRAM BUDGET ────────────────────────────────────────────
            #
            # One assertion per served model, rather than one for the largest,
            # because the group is `exclusive`: any member can be the resident
            # one, so every member has to fit on its own.  Checking only the
            # biggest would pass a config whose second model is the problem.
            #
            # Skipped entirely when totalMiB is null — a machine whose card
            # drives no display has nothing to reserve against and should not
            # be made to declare a number it cannot measure.
            ++ lib.optionals (settings.vram.totalMiB != null)
            (map (n: let
                m = declared.${n};
                ceiling = settings.vram.totalMiB - settings.vram.reserveMiB;
              in {
                assertion = m.residentVramMiB == null || m.residentVramMiB <= ceiling;
                message = ''
                  @clanarchy/local-ai: model "${n}" does not fit on
                  ${machine.name}'s inference card under the session reserve.

                    measured resident   ${toString m.residentVramMiB} MiB
                    card total          ${toString settings.vram.totalMiB} MiB
                    session reserve     ${toString settings.vram.reserveMiB} MiB
                    ceiling             ${toString ceiling} MiB
                    OVER BY             ${toString (m.residentVramMiB - ceiling)} MiB

                  The reserve is what the compositor holding the TV needs.
                  Taking it is not a slow degradation — gamescope answers a
                  framebuffer pin that returns ENOMEM by calling abort(), and
                  the display manager relogs it in, so the television
                  crash-loops until the model's idle ttl expires.

                  Three levers, cheapest first:

                    * lower `contextLength` — on this architecture only a
                      quarter of the layers hold KV, so halving the window
                      buys a few hundred MiB and costs little;
                    * `extraArgs = [ "--n-cpu-moe N" ]` — moves the expert
                      tensors of the first N layers to system RAM and leaves
                      attention and KV on the GPU;
                    * a smaller quantisation, which is a measurement and not
                      a swap: check tool-call fidelity before believing it.

                  Lowering `vram.reserveMiB` is the lever that LOOKS cheapest
                  and is not — it is a measured floor, not a safety margin.
                '';
              })
              modelNames);

          # A warning, not an assertion: an unmeasured model is allowed —
          # measuring one costs a deploy and a stopped session — but it is
          # invisible to the check above, so it must not also be silent.
          warnings =
            lib.optionals (settings.vram.totalMiB != null)
            (map (n: ''
              @clanarchy/local-ai: model "${n}" has no `residentVramMiB`, so
              ${machine.name}'s VRAM budget cannot check it.  It is exempt
              from the reserve by omission rather than by measurement, which
              is the state the budget exists to make visible.  Measure it with
              the command in the option's description.
            '') (lib.filter (n: declared.${n}.residentVramMiB == null) modelNames));

          ##################################################################
          # User, state, and the model store on zdata.
          ##################################################################
          users.users.${user} = {
            isSystemUser = true;
            group = user;
            home = stateDir;
            createHome = false;
            description = "Local AI inference (llama.cpp)";
          };
          users.groups.${user} = {};

          systemd.tmpfiles.rules =
            [
              "d ${stateDir} 0750 ${user} ${user} -"
              "d ${modelsDir} 0750 ${user} ${user} -"
              # Many ROCm utilities hard-code /opt/rocm/hip.  Inherited from the
              # ollama era and still required.
              "L+ /opt/rocm/hip - - - - ${pkgs.rocmPackages.clr}"
            ]
            # ComfyUI's writable tree, owned by the SAME user llama-swap runs as
            # — it is a child of that unit, not a service with an identity of its
            # own.  Created here rather than in roles.imagegen because that role
            # produces no units at all (see the note on its perInstance), and
            # because the ownership is a fact about THIS role's user.
            #
            # ── custom_nodes IS NOT OPTIONAL, AND ComfyUI DOES NOT CREATE IT ──
            #
            # ComfyUI creates input/, output/, temp/ and user/ under the base
            # directory itself, but `execute_prestartup_script()` runs BEFORE any
            # of that and does a bare `os.listdir(custom_node_path)` on a path
            # nothing has made yet (main.py:201).  With the directory absent it
            # dies during startup:
            #
            #   FileNotFoundError: [Errno 2] No such file or directory:
            #     '<base>/custom_nodes'
            #
            # Found by running the built package, not by reading it — which is
            # the only reason it is here rather than in a journal on ernst after
            # the first image request.  It is created EMPTY and stays that way:
            # see the note in service-modules/pkgs/comfyui/default.nix on why
            # custom nodes are a derivation here rather than a runtime install.
            ++ lib.optionals imagegenEnabled [
              "d ${imagegenRole.stateDir} 0750 ${user} ${user} -"
              "d ${imagegenRole.stateDir}/custom_nodes 0750 ${user} ${user} -"
            ];

          ##################################################################
          # llama-server, router mode.
          #
          # NO HSA_OVERRIDE_GFX_VERSION.  The 7900 XTX is gfx1100 and ROCm
          # supports it natively; forcing an override makes ROCm select the
          # wrong kernels for a card that already has correct ones.  The
          # override belongs only on APUs whose target is absent from stock
          # ROCm — miralda's gfx1103 — and this role does not run there.
          #
          # THERE IS NO `llama-router` UNIT ANY MORE.  It ran llama-server in
          # router mode and llama-swap proxied to it; llama-swap cannot do that
          # (see the `models` note above) and the router turned out to be
          # redundant once llama-swap spawns each model itself.  Everything the
          # router unit carried — the ROCm environment, the device access, the
          # hardening, and the note about what it cannot carry — now lives on
          # llama-swap, because llama-swap is the process that forks
          # llama-server and its children inherit that unit's sandbox.
          ##################################################################
          # llama-swap — the front door, and now the only layer.
          ##################################################################
          services.llama-swap = {
            enable = true;
            # HOST ONLY, and the port is a SEPARATE option.  The module renders
            # `--listen=${listenAddress}:${port}`, so a host:port pair here
            # becomes `--listen=127.0.0.1:11434:8080` and llama-swap exits 1
            # with "too many colons in address" — which then trips the restart
            # limit and presents as `start-limit-hit`, three failures away from
            # the actual cause.  Deployed and hit on 2026-09-09.
            listenAddress = "127.0.0.1";
            port = port;
            # openFirewall stays false.  There is no case in which this port
            # should be reachable off the host; clients that are not on ernst
            # arrive through the SSH forward below.
            openFirewall = false;
            settings = swapConfig;
          };

          systemd.services.llama-swap = {
            # No ordering on the fetch, for the reason the fetch unit records:
            # `After=` also applies to an already-running unit, so it would
            # queue a deploy behind a 25 GiB download.  llama-swap starts fine
            # with no models on disk; a request for one that is missing fails
            # per-request, which is the correct granularity.

            # THERE WAS A 503 GATE HERE AND IT IS GONE (#309).  Do not
            # reinstate it: it stood a `503` + `Retry-After` responder on
            # karakeep's leg whenever the card belonged to something else,
            # and what that bought — measured — was a lower REQUEST RATE on
            # a loopback path.  It did not save the bookmark (karakeep burns
            # its three hard-coded retries and `keepFailedJobs: false` drops
            # it either way), so the benefit was fewer journal lines.  It
            # cost five follow-up fixes in three days and one live outage,
            # and its watchdog stopped this unit whenever an outside claimant
            # held the card — taking the model away from mneme, Assist and
            # OpenCode, which without it merely fail a load and recover.
            #
            # The card is arbitrated instead by the three things that protect
            # something a person would notice: the VRAM reserve, the htpc
            # role's `gpu.preempt.units`, and its crash-loop breaker.  A model
            # that cannot load answers 500.  containers/karakeep.nix records
            # what that costs and why no knob exists to soften it.

            environment = {
              ROCR_VISIBLE_DEVICES = "0";
              HOME = stateDir;
            };

            serviceConfig = {
              User = lib.mkForce user;
              Group = lib.mkForce user;

              # ── llama-swap FORKS llama-server, SO ITS SANDBOX IS THEIRS ────
              #
              # This is the consequence of dropping the router: the model
              # processes are now CHILDREN of this unit and inherit everything
              # set here.  Every ROCm requirement that used to live on
              # llama-router has to live here instead, and getting that wrong
              # would not fail at deploy — it would fail on the first GPU
              # request, which is much later and much less obvious.
              PrivateDevices = false;

              # ── `char-drm`, NOT `/dev/dri` ────────────────────────────────
              #
              # /dev/dri is a DIRECTORY, not a device node.  Naming it in
              # DeviceAllow grants nothing — and because *any* DeviceAllow
              # entry switches the cgroup to allow-list mode, listing it
              # DENIED every render node under it.  `char-drm` is the device
              # group that actually covers /dev/dri/*.
              #
              # HOW THIS PRESENTED, because it is the worst kind: the unit
              # started clean, systemd logged nothing, systemd-analyze scored it
              # no worse, and llama-server fell back to CPU **silently**.  The
              # only symptom was 6.7 tok/s instead of ~100 and VRAM that never
              # moved off idle.  Bisected on ernst 2026-09-09:
              #
              #   DeviceAllow=/dev/kfd + /dev/dri   -> no GPU
              #   DeviceAllow=/dev/kfd + char-drm   -> ROCm0: RX 7900 XTX
              #
              # Same shape as MemoryDenyWriteExecute below: a hardening setting
              # that looks correct, measures as correct, and quietly removes the
              # entire point of the machine.
              DeviceAllow = ["/dev/kfd rw" "char-drm rw"];

              # ComfyUI's base directory is a SECOND writable path, and its
              # absence would not fail here — it would fail inside a spawned
              # child, as a Python traceback about a directory it could not
              # create, at first image request rather than at deploy.
              ReadWritePaths =
                [stateDir]
                ++ lib.optional imagegenEnabled imagegenRole.stateDir;
              NoNewPrivileges = true;
              ProtectHome = true;

              # THE IMPORTANT ONE.  nixpkgs' llama-swap module sets
              # MemoryDenyWriteExecute=true — correct for a Go proxy that
              # spawns nothing, wrong the moment it spawns a ROCm process.
              # The ROCm runtime JITs GPU kernels through libamd_comgr and
              # needs W+X mappings; inherited, this kills every model on first
              # GPU use. It scored a ✓ on systemd-analyze while being actively
              # harmful, which is exactly the kind of green that means nothing.
              MemoryDenyWriteExecute = lib.mkForce false;

              # Same reasoning: the module's syscall filter is sized for the
              # proxy, and the children need the ROCm ioctl surface.
              # @system-service covers ioctl; the two subtractions are kept
              # because nothing in this tree legitimately needs them.
              SystemCallFilter = lib.mkForce ["@system-service" "~@privileged"];
            };
          };
        }
        (mkBridges {
          inherit pkgs;
          # The unit prefix stays `llama-bridge-<consumer>` as it has been since
          # M19: runbooks, journal greps and docs/history.md's L9 row all name
          # it, and a rename would buy nothing.
          unit = "llama-bridge";
          what = "llama-swap";
          targetPort = port;
          bridges = settings.exposeOn;
          extraAfter = ["llama-swap.service"];
        })
        {
          ##################################################################
          # The SSH forward jens uses.
          #
          # `restrict` turns everything off including port forwarding;
          # `port-forwarding` turns exactly that back on and `permitopen`
          # narrows it to one destination.  A forward to loopback:11434 and
          # nothing else — notably not a shell.
          #
          # The generator name is still `ollama-tunnel-ssh`.  RENAMING IT WOULD
          # ROTATE THE KEY on every machine that has one, for cosmetic reasons,
          # and clan rejects a shared generator whose definitions diverge
          # between machines — so a half-finished rename breaks every deploy in
          # the flake, not just this role's.  The name is historical; the thing
          # it names is correct.
          ##################################################################
          users.users.root.openssh.authorizedKeys.keys = lib.optionals (settings.remoteClients.enable && tunnelPubKey != null) [
            ''restrict,port-forwarding,permitopen="127.0.0.1:${toString port}" ${tunnelPubKey}''
          ];

          warnings = lib.optional (settings.remoteClients.enable && tunnelPubKey == null) ''
            local-ai: remoteClients is enabled on this machine but
            vars/shared/ollama-tunnel-ssh/tunnel_ed25519.pub does not exist yet,
            so no key has been authorised and the tunnel will be refused. Run
            `clan vars generate <the client machine>`, then redeploy this one.
          '';
        }
      ];
  };
}
