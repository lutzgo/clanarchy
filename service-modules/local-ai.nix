{ lib, ... }:
#
# @clanarchy/local-ai — local AI inference, voice, vision and image generation.
#
# ── WHAT REPLACED WHAT, AND WHY (M19) ────────────────────────────────────────
#
# This module used to be `roles.ollama` + `roles.opencode`.  Ollama is gone from
# ernst, replaced by llama-swap in front of llama-server in router mode.  The
# migration was measured before it was taken — the full Phase 0 record is in
# ~/.local/share/m19-llamacpp/PHASE0-NOTES.md and summarised in docs/roadmap.md
# §M19.  Three results decided it:
#
#   1. CONTEXT OVERFLOW STOPS BEING SILENT.  This is the whole reason.  Ollama
#      answers an over-long prompt with HTTP 200, truncates to ~num_ctx/2,
#      KEEPS THE TAIL AND DISCARDS THE HEAD — where the system message and the
#      tool definitions live — and sets no flag anywhere.  Measured again on
#      2026-09-08: a 16,694-token prompt became 4,098 tokens and the model
#      INVENTED a placeholder-shaped MAC address rather than declining.
#      llama-server refuses the same request outright:
#
#        HTTP 400  request (16694 tokens) exceeds the available context size
#                  (8192 tokens), try increasing it
#
#      That is standing note SN1's core hazard removed at the mechanism, not
#      documented around.
#
#   2. THE `<tool_call>` DEFECT FOLLOWS THE MODEL, NOT THE PARSER.  M11 found
#      qwen3-coder drops the OPENING <tool_call> tag while emitting its closing
#      partner, and blamed ollama's compiled Go parser only until it looked.
#      llama.cpp parses through the GGUF's own Jinja template — a completely
#      independent implementation — and fails identically: 26/30 dropped-tag
#      failures on the worst condition, and ZERO "tag present but unparsed" in
#      any of eight cells across both servers.  So `toolCallRule` below is NOT
#      deleted by this migration; it is the fix on both, and it is still total
#      (60/60 with it, on each server).
#
#   3. DECODE IS WITHIN NOISE AT f16, AND q8_0 LOST ITS REASON TO EXIST.
#      Interleaved, n=5 cycles, same card, same day:
#
#        llama-server f16  32k   21799 MiB   107.5 tok/s   (-3.1%)
#        llama-server q8_0 32k   20361 MiB    94.6 tok/s   (-14.7%)
#        ollama       q8_0 32k   20163 MiB   110.9 tok/s   (control)
#
#      ernst ran q8_0 only because f16 at 64k SPILLED on ollama.  On llama.cpp
#      f16 at 32768 — the window ernst actually declares — fits with 2761 MiB
#      to spare.  So the fleet default moves back to f16 and q8_0 becomes a
#      per-model opt-in with a price tag written next to it.
#
# ── WHY TWO LAYERS, llama-swap AND llama-server'S OWN ROUTER ─────────────────
#
# The obvious objection is that llama-server's router already swaps models, so
# llama-swap is redundant.  It is not, and this is a measurement rather than a
# preference — two of them:
#
#   (a) THE ROUTER NEVER FREES VRAM WHEN IDLE.  Its only unload path is
#       `unload_lru()`, driven solely by `--models-max` being reached
#       (tools/server/server-models.cpp).  There is no idle timeout anywhere in
#       it; the one `timeout` field on a model is `stop_timeout`, for shutdown.
#       So an idle coder model sits on 21.8 GiB forever and a NON-LLM consumer
#       — ComfyUI, whisper-server — can never displace it, because it is not a
#       router "model" at all.  llama-swap's per-model `ttl` plus an
#       `exclusive` group is exactly the missing mechanism, and it is the only
#       thing on this machine that knows the 30B and ComfyUI cannot coexist in
#       24 GiB.
#
#   (b) THE ROUTER ADVERTISES A PHANTOM MODEL THAT RECURSES.  `/v1/models` on
#       the router lists `default` alongside the declared set — it is built
#       from the router's own argv.  Requesting it makes the router SPAWN A
#       CHILD OF ITSELF IN ROUTER MODE and wait for it forever; the request
#       hangs with no response at all.  Clients that pick the first entry from
#       /v1/models — several do — hang.  llama-swap's /v1/models is its
#       declared map and nothing else, and an undeclared name is a clean 404.
#
# So: llama-server's router handles LLM<->LLM swapping and per-model context,
# llama-swap handles LLM<->non-LLM exclusion and hides (b).  llama.cpp itself
# calls router mode "experimental … not recommended in untrusted environments",
# which is a third reason not to make it the front door.
#
# ── THE PORT IS 11434 ON PURPOSE ─────────────────────────────────────────────
#
# llama-swap takes the port ollama had.  Every existing client keeps working
# unchanged, and — the part that matters for security review — the jens tunnel's
# `permitopen="127.0.0.1:11434"` restriction stays exactly as it was.  Nothing
# about the SSH forward changes.
#
# ── ROLES ────────────────────────────────────────────────────────────────────
#
#   inference — llama-swap + llama-server router.  Loopback only.
#   models    — declarative model set.  Fetched to zdata, hash-verified, and
#               the SAME attrset renders the router's preset INI, so a model
#               cannot exist in one and not the other.
#   opencode  — the CLI agent, pointed at llama-swap (local or tunnelled).
#   speech    — whisper.cpp STT on an OpenAI-shaped endpoint.
#   imagegen  — ComfyUI, podman tier.
#   webui     — Open WebUI in an nspawn container on VLAN 90.
#
{
  _class = "clan.service";
  manifest.name        = "@clanarchy/local-ai";
  manifest.description = "Local AI: llama.cpp inference, voice, vision and image generation.";
  manifest.readme      = builtins.readFile ./local-ai.md;

  ##############################################################################
  # Shared option type for a declared model.
  #
  # ONE ATTRSET, TWO CONSUMERS: the fetcher and the preset INI.  That is the
  # whole design requirement — a model that is downloaded but not declared to
  # the router, or declared but never fetched, is the failure this shape makes
  # unrepresentable.
  ##############################################################################
  # (declared inside roles.models below; kept adjacent to its only consumer)

  ##############################################################################
  # roles.inference — llama-swap + llama-server router
  ##############################################################################
  roles.inference = {
    description = "llama-swap in front of llama-server in router mode. Loopback only.";

    interface.options = {
      port = lib.mkOption {
        type        = lib.types.port;
        default     = 11434;
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

      routerPort = lib.mkOption {
        type        = lib.types.port;
        default     = 11436;
        description = ''
          Loopback port llama-server's router listens on.  llama-swap is its
          only client; nothing else should ever be pointed here.

          Not 11435 — that is the port the opencode role's SSH forward binds on
          a CLIENT machine, and reusing the number across the two ends of a
          tunnel is how somebody eventually debugs the wrong process.
        '';
      };

      swapPortRange = lib.mkOption {
        type        = lib.types.port;
        default     = 11500;
        description = ''
          First port llama-swap hands to the backends it spawns (its
          `startPort`).  They are loopback, ephemeral, and never contacted
          directly.
        '';
      };

      idleTtl = lib.mkOption {
        type        = lib.types.ints.positive;
        default     = 900;
        example     = 300;
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

      stateDir = lib.mkOption {
        type        = lib.types.path;
        default     = "/srv/state/local-ai";
        description = ''
          Where models and runtime state live.  On zdata, per architecture
          invariant #7 — and this one is not a formality: the model set is tens
          of GiB and the old ollama store sat on `zroot/persist`, which is the
          pool that is not supposed to carry service data.  18.5 GiB of weights
          were on the root pool for a year because nothing said otherwise.
        '';
      };

      user = lib.mkOption {
        type        = lib.types.str;
        default     = "llama";
        description = ''
          Static system user everything in this role runs as.

          STATIC, NOT DynamicUser, and the reason is written in blood in the
          ollama era of this file: DynamicUser + impermanence means the persist
          entry is created root:root 0700 and the per-boot dynamic uid cannot
          write to it, so the daemon fails to create its model directory and
          every fetch dies with a permission error that names the wrong thing.
        '';
      };

      metricsProxy = {
        enable = lib.mkEnableOption ''
          a loopback-to-mon0 socket proxy so the monitoring container can scrape
          llama-server's /metrics

          THIS IS A DELIBERATE, NARROW EXPOSURE CHANGE AND IT MUST BE READ AS
          ONE.  M11 recorded that it "changes ernst's attack surface not at
          all"; M19 no longer gets to say that, and pretending otherwise would
          be exactly the kind of claim this repo makes a point of not making.

          What it actually is: llama-server stays bound to 127.0.0.1.  A
          separate systemd-socket-proxyd unit listens on the HOST END OF mon0 —
          the point-to-point IPv6 ULA veth whose only peer is the monitoring
          container — and forwards to the router's loopback port.  Nothing on
          any VLAN can reach it; the monitoring container can.  That container
          already holds Grafana and an Authelia OIDC client secret, so it is
          not a new trust boundary, but it IS a second listener where there was
          one, and the ledger row says so
        '';

        address = lib.mkOption {
          type        = lib.types.str;
          default     = "";
          example     = "fdca:fe90::1";
          description = ''
            Host end of the monitoring veth (mon0) to bind the proxy to.  Must
            match `monHostAddr` in service-modules/monitoring.nix.  Empty with
            `enable = true` is an evaluation error rather than a proxy on a
            wildcard address.
          '';
        };
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

    perInstance = { settings, roles, machine, ... }: {
      nixosModule = { config, pkgs, lib, ... }:
        let
          inherit (settings) stateDir user port routerPort;
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
            rocmSupport    = true;
            rocmGpuTargets = [ "gfx1100" ];
          };

          # THE SINGLE SOURCE OF TRUTH FOR THE MODEL SET.  Read out of the
          # `models` role's settings for this same machine rather than
          # duplicated here, so the fetcher and the preset INI cannot disagree.
          # `or` guards the case where a machine holds `inference` and not
          # `models` — legal, and means "an inference server with nothing
          # declared", which the assertion below turns into a build error
          # rather than an empty /v1/models at runtime.
          declared =
            (roles.models.machines.${machine.name}.settings.models or { });

          # Only the entries llama-server actually serves become preset sections
          # and llama-swap models.  whisper's ggml weights are declared in the
          # same `models` attrset — one fetcher, one hash-verified store — but
          # llama-server cannot load them, and a preset section pointing at a
          # non-GGUF is a router that logs a load error per request.
          modelNames = lib.filter (n: declared.${n}.servedByLlama)
                                  (lib.attrNames declared);

          # Where a declared model's file lands.  Derived, never configured:
          # two names for one path is how the fetcher and the INI drift.
          fileOf = name: "${modelsDir}/${declared.${name}.filename}";

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
          presetIni = pkgs.writeText "llama-models.ini" (''
            version = 1

            ; Global defaults.  Anything here is overridden by a model's own
            ; section.  --jinja is not optional: it is what makes llama.cpp use
            ; the GGUF's embedded chat template, which for qwen3-coder is the
            ; template that renders the <tools> block at all.
            [*]
            jinja = true
            flash-attn = on
            n-gpu-layers = 999

          '' + lib.concatStringsSep "\n" (map (name:
            let m = declared.${name}; in ''
              [${name}]
              model = ${fileOf name}
              c = ${toString m.contextLength}
              cache-type-k = ${m.kvCacheType}
              cache-type-v = ${m.kvCacheType}
              ${lib.optionalString (m.mmproj != null)
                "mmproj = ${modelsDir}/${m.mmproj}"}
              ${lib.concatStringsSep "\n" m.extraArgs}
            '') modelNames));

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
          swapMembers = modelNames
            ++ lib.optional imagegenEnabled "comfyui";

          speechRole   = roles.speech.machines.${machine.name}.settings or null;
          imagegenRole = roles.imagegen.machines.${machine.name}.settings or null;
          speechEnabled   = speechRole   != null;
          imagegenEnabled = imagegenRole != null;

          swapConfig = {
            healthCheckTimeout = 300;
            logLevel           = "info";
            startPort          = settings.swapPortRange;

            models =
              # Every declared LLM is proxied to the ROUTER, not spawned:
              # llama-server's router owns LLM<->LLM swapping and per-model
              # context, and duplicating that here would give two components an
              # opinion about the same thing.  `proxy` + `useModelName` is
              # llama-swap's pass-through shape.
              lib.listToAttrs (map (name: {
                inherit name;
                value = {
                  proxy         = "http://127.0.0.1:${toString routerPort}";
                  useModelName  = name;
                  ttl           = settings.idleTtl;
                  checkEndpoint = "/health";
                  name          = declared.${name}.description;
                };
              }) modelNames)

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
                  ttl           = settings.idleTtl;
                  checkEndpoint = "/health";
                  name          = "Whisper (speech to text)";
                };
              }
              // lib.optionalAttrs imagegenEnabled {
                comfyui = {
                  # Already running under podman; llama-swap only needs to know
                  # it exists so the exclusive group can evict the LLM for it.
                  proxy         = "http://127.0.0.1:${toString imagegenRole.port}";
                  ttl           = settings.idleTtl;
                  checkEndpoint = "/system_stats";
                  name          = "ComfyUI (image generation)";
                };
              };

            groups.gpu = {
              swap      = true;
              exclusive = true;
              members   = swapMembers;
            };
          };

          swapConfigFile = pkgs.writeText "llama-swap.yaml"
            (builtins.toJSON swapConfig);   # llama-swap parses YAML; JSON is valid YAML

          speechPackage = pkgs.whisper-cpp.override {
            rocmSupport    = true;
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
            if builtins.pathExists tunnelPubKeyPath then
              lib.removeSuffix "\n" (builtins.readFile tunnelPubKeyPath)
            else null;
        in
        {
          assertions = [
            {
              assertion = declared != { };
              message = ''
                @clanarchy/local-ai: ${machine.name} holds roles.inference but
                declares no models.  Add it to roles.models — the two are
                deliberately separate roles reading ONE attrset, so that the
                fetcher and llama-server's preset INI cannot disagree, and an
                inference server with an empty model set is a configuration
                mistake rather than a valid state.
              '';
            }
            {
              assertion = !settings.metricsProxy.enable
                          || settings.metricsProxy.address != "";
              message = ''
                @clanarchy/local-ai: metricsProxy.enable is true on
                ${machine.name} but metricsProxy.address is empty.  It must be
                the host end of mon0 (see monHostAddr in
                service-modules/monitoring.nix).  Refusing to default it: an
                empty bind address is a wildcard, and a wildcard here would put
                the inference API on every VLAN.
              '';
            }
          ];

          ##################################################################
          # User, state, and the model store on zdata.
          ##################################################################
          users.users.${user} = {
            isSystemUser = true;
            group        = user;
            home         = stateDir;
            createHome   = false;
            description  = "Local AI inference (llama.cpp)";
          };
          users.groups.${user} = { };

          systemd.tmpfiles.rules = [
            "d ${stateDir} 0750 ${user} ${user} -"
            "d ${modelsDir} 0750 ${user} ${user} -"
            # Many ROCm utilities hard-code /opt/rocm/hip.  Inherited from the
            # ollama era and still required.
            "L+ /opt/rocm/hip - - - - ${pkgs.rocmPackages.clr}"
          ];

          ##################################################################
          # llama-server, router mode.
          #
          # NO HSA_OVERRIDE_GFX_VERSION.  The 7900 XTX is gfx1100 and ROCm
          # supports it natively; forcing an override makes ROCm select the
          # wrong kernels for a card that already has correct ones.  The
          # override belongs only on APUs whose target is absent from stock
          # ROCm — miralda's gfx1103 — and this role does not run there.
          ##################################################################
          systemd.services.llama-router = {
            description = "llama-server (router mode) for ${machine.name}";
            wantedBy    = [ "multi-user.target" ];

            # ── IT DOES NOT REQUIRE THE FETCH, AND THAT IS THE FIX ──────────
            #
            # It used to `requires` + `wants` it.  That put a 25 GiB download on
            # the ACTIVATION CRITICAL PATH: `clan machines update ernst` sat for
            # thirteen minutes on the first deploy with no progress output,
            # which is indistinguishable from a hang — and it is exactly the
            # failure shape this repo keeps writing notes about, except here the
            # deploy looked broken while working correctly.  Measured on the
            # first real deploy, 2026-09-09: llama-models-fetch was the only
            # running job while multi-user.target and graphical.target waited.
            #
            # It cost on EVERY deploy, not just the first: the fetcher re-hashes
            # the whole model store on each run, which is ~1 minute of blocking
            # for a store that has not changed.
            #
            # The router does not need the models at startup.  It is a ROUTER —
            # it reads the preset INI, lists the models, and opens no weights
            # until a request names one (measured: VRAM stays at idle after
            # start, and only rises on the first chat request).  So a missing
            # file is a per-request error, not a startup failure, and the
            # correct dependency is ordering-only.
            #
            # NOT EVEN `after`.  The first attempt at this fix kept an ordering
            # dependency on the fetch, reasoning that it was free because
            # `After=` does not pull a unit in.  IT IS NOT FREE: `After=` also
            # applies when the other unit is ALREADY RUNNING, so a deploy that
            # started while a download was in progress left llama-router
            # `inactive` with its start job **waiting** — queued behind a
            # 40-minute download, which is the same blocked deploy the previous
            # commit set out to fix, reintroduced one line lower down.
            # Measured on ernst 2026-09-09, twice.
            #
            # There is nothing to order.  The router opens no weights at
            # startup, and llama-models-fetch calls `systemctl try-restart
            # llama-router` when it completes, which is the only coupling the
            # two actually need and it points the other way.
            after = [ "network.target" "local-fs.target" ];

            environment = {
              ROCR_VISIBLE_DEVICES = "0";
              HOME                 = stateDir;
              LLAMA_CACHE          = "${stateDir}/cache";
            };

            serviceConfig = {
              ExecStart = lib.concatStringsSep " " [
                "${llamaCpp}/bin/llama-server"
                "--host 127.0.0.1"
                "--port ${toString routerPort}"
                "--models-preset ${presetIni}"
                # ONE resident model at a time.  The card holds 24560 MiB and
                # the coder model alone is 21.8 GiB at 32k; two would spill and
                # M11 measured what spilling costs.
                "--models-max 1"
                "--metrics"
              ];
              User       = user;
              Group      = user;
              Restart    = "always";
              RestartSec = "10s";

              # Hardening.  Kept to what a process that mmaps 18 GiB from a
              # zdata path and talks to /dev/kfd can actually carry.
              # MemoryDenyWriteExecute is ABSENT ON PURPOSE: the ROCm runtime
              # JITs GPU kernels and dies under it.  Stated rather than
              # silently omitted, per the roadmap's hardening note.
              NoNewPrivileges      = true;
              PrivateTmp           = true;
              PrivateDevices       = false;   # needs /dev/kfd + /dev/dri
              DeviceAllow          = [ "/dev/kfd rw" "/dev/dri rw" ];
              ProtectSystem        = "strict";
              ProtectHome          = true;
              ReadWritePaths       = [ stateDir ];
              ProtectKernelTunables = true;
              ProtectKernelModules  = true;
              ProtectControlGroups  = true;
              RestrictNamespaces    = true;
              RestrictSUIDSGID      = true;
              RestrictRealtime      = true;
              LockPersonality       = true;
              RemoveIPC             = true;
              SystemCallArchitectures = "native";
              # AF_UNIX for the ROCm/KFD ioctl helpers, AF_INET for the
              # listener.  No AF_NETLINK, no AF_PACKET.
              RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];

              # ── The second pass, after the first deploy scored 6.0 MEDIUM ──
              #
              # The settings above are the ones that were obvious; systemd-
              # analyze scored them at 6.0, against a target of <= 2.0. Almost
              # all of the remaining cost was two omissions worth 0.1-0.3 each:
              # no capability bounding set at all, and no system-call filter.
              # Neither is difficult for this process — it opens a socket, reads
              # files and talks to /dev/kfd — so they are added rather than
              # excused.
              CapabilityBoundingSet = [ "" ];
              AmbientCapabilities   = [ "" ];
              SystemCallFilter      = [ "@system-service" "~@resources" "~@privileged" ];
              SystemCallErrorNumber = "EPERM";
              ProtectProc           = "invisible";
              ProcSubset            = "pid";
              ProtectClock          = true;
              ProtectHostname       = true;
              ProtectKernelLogs     = true;
              UMask                 = "0077";
              # Loopback only. The listener is 127.0.0.1 and the one remote
              # thing this process does is nothing at all — models arrive via
              # llama-models-fetch, not through here.
              IPAddressDeny         = "any";
              IPAddressAllow        = [ "localhost" ];

              # ── WHAT IT STILL CANNOT CARRY, AND WHY ───────────────────────
              #
              # MemoryDenyWriteExecute — ABSENT DELIBERATELY. The ROCm runtime
              #   JITs GPU kernels through libamd_comgr, which requires W+X
              #   mappings. Setting it makes the process die on first GPU use.
              #   This is the one the roadmap's hardening note says to state
              #   rather than silently omit.
              # PrivateDevices / DeviceAllow — /dev/kfd and /dev/dri ARE the
              #   point of this unit. DeviceAllow above narrows it to those two.
              # PrivateNetwork — it is a network listener (0.5, the single
              #   largest remaining item, and irreducible).
              # PrivateUsers — breaks /dev/kfd access under ROCm.
              # RootDirectory — no benefit beside ProtectSystem=strict here,
              #   and it would need the whole ROCm closure re-bound inside.
            };
          };

          ##################################################################
          # llama-swap — the front door.
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
            port          = port;
            # openFirewall stays false.  There is no case in which this port
            # should be reachable off the host; clients that are not on ernst
            # arrive through the SSH forward below.
            openFirewall  = false;
            settings      = swapConfig;
          };

          systemd.services.llama-swap = {
            after    = [ "llama-router.service" ];
            wants    = [ "llama-router.service" ];
            serviceConfig = {
              User  = lib.mkForce user;
              Group = lib.mkForce user;
              # llama-swap FORKS THE BACKENDS, so it needs the same device
              # access they do — whisper-server and any future spawned backend
              # inherit this unit's namespace.
              PrivateDevices = false;
              DeviceAllow    = [ "/dev/kfd rw" "/dev/dri rw" ];
              ReadWritePaths = [ stateDir ];
              NoNewPrivileges = true;
              ProtectHome     = true;
            };
          };

          ##################################################################
          # The metrics path.
          #
          # llama-server's /metrics is NOT a plain scrape: on the router it
          # answers HTTP 400 "model name is missing from the request" unless a
          # model is named in the query string.  Measured 2026-09-09.  The
          # matching Prometheus job therefore carries `params.model`; see
          # service-modules/monitoring.nix.  A plain /metrics job would be a
          # permanent up == 0, which is exactly the shape M13 refused to add
          # for ollama.
          ##################################################################
          systemd.services.llama-metrics-proxy =
            lib.mkIf settings.metricsProxy.enable {
              description = "Expose llama-server /metrics to the monitoring container over mon0";
              after       = [ "llama-router.service" ];
              wants       = [ "llama-router.service" ];
              wantedBy    = [ "multi-user.target" ];
              serviceConfig = {
                ExecStart = lib.concatStringsSep " " [
                  "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd"
                  "127.0.0.1:${toString routerPort}"
                ];
                Restart    = "always";
                RestartSec = "10s";
                DynamicUser = true;
                NoNewPrivileges = true;
                PrivateDevices  = true;
                ProtectSystem   = "strict";
                ProtectHome     = true;
                MemoryDenyWriteExecute = true;
                RestrictAddressFamilies = [ "AF_INET6" "AF_UNIX" ];
              };
            };

          systemd.sockets.llama-metrics-proxy =
            lib.mkIf settings.metricsProxy.enable {
              description = "mon0-only listener for llama-server metrics";
              wantedBy    = [ "sockets.target" ];
              socketConfig = {
                # A LITERAL ADDRESS, never a wildcard.  This is the whole
                # containment: the only peer of that /128 is the monitoring
                # container.
                ListenStream  = "[${settings.metricsProxy.address}]:${toString routerPort}";
                BindIPv6Only  = "ipv6-only";
              };
            };

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
          users.users.root.openssh.authorizedKeys.keys =
            lib.optionals (settings.remoteClients.enable && tunnelPubKey != null) [
              ''restrict,port-forwarding,permitopen="127.0.0.1:${toString port}" ${tunnelPubKey}''
            ];

          warnings = lib.optional (settings.remoteClients.enable && tunnelPubKey == null) ''
            local-ai: remoteClients is enabled on this machine but
            vars/shared/ollama-tunnel-ssh/tunnel_ed25519.pub does not exist yet,
            so no key has been authorised and the tunnel will be refused. Run
            `clan vars generate <the client machine>`, then redeploy this one.
          '';
        };
    };
  };

  ##############################################################################
  # roles.models — the declarative model set
  ##############################################################################
  roles.models = {
    description = "Models to fetch and declare. Fetched to zdata, hash-verified.";

    interface.options.models = lib.mkOption {
      default = { };
      description = ''
        The models this machine serves, keyed by the name clients request.

        NO IMPERATIVE PULL.  The ollama era of this module had a `models` list
        of registry tags and a `ollama pull` loader, and it failed in the two
        ways that arrangement always fails: a tag that never existed
        (`qwen3-coder:8b`, which sat in a restart loop for months because
        qwen3-coder publishes only 30b and 480b), and a context window that
        moved silently whenever the tag was edited.  Here a model is a URL, a
        hash and a context — all three reviewed together, in one place, and the
        SAME attrset renders both the fetcher and llama-server's preset INI.

        EVERY url AND hash MUST BE VERIFIED BEFORE IT IS WRITTEN DOWN:

          nix store prefetch-file --hash-type sha256 --json <url> | jq -r .hash

        The fetcher verifies again at runtime, so a wrong hash is a failed unit
        rather than a corrupt model — but a wrong URL that happens to resolve
        is not something a hash can catch after the fact.
      '';
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = {
          url = lib.mkOption {
            type        = lib.types.str;
            description = "Direct download URL for the GGUF. Must be verified before it is committed.";
          };
          hash = lib.mkOption {
            type        = lib.types.str;
            example     = "sha256-…";
            description = "SRI hash of the file at `url`, from `nix store prefetch-file`.";
          };
          filename = lib.mkOption {
            type        = lib.types.str;
            default     = baseNameOf name;
            description = "Name the file is stored under in the model directory.";
          };
          description = lib.mkOption {
            type        = lib.types.str;
            default     = name;
            description = "Human-readable label, shown in client model pickers.";
          };

          contextLength = lib.mkOption {
            type    = lib.types.ints.positive;
            example = 32768;
            description = ''
              `-c` for this model, and NO DEFAULT ON PURPOSE — every model must
              state its own window.

              This is where standing note SN1 now lives, and the placement is
              the point.  Under ollama the window was derived from the model
              tag and set by one global environment variable, so editing which
              model was served silently changed the context for every client
              with no diff that showed it.  Here it sits on the model, is
              required, and moves only when someone edits this line.

              What overflowing it now does is ALSO different, and better: on
              llama.cpp it is HTTP 400 naming both numbers, where ollama
              returned HTTP 200 with the head of the prompt silently discarded
              and a fabricated answer in place of a refusal.

              Size it against VRAM.  Measured on ernst's 24560 MiB card with
              the 30B: f16 at 32768 is 21799 MiB resident; f16 at 65536 spills.
            '';
          };

          kvCacheType = lib.mkOption {
            type        = lib.types.enum [ "f16" "q8_0" "q4_0" ];
            default     = "f16";
            description = ''
              `--cache-type-k` and `--cache-type-v` for this model. BOTH, always
              — see below.

              f16 BY DEFAULT, which reverses ernst's ollama-era setting, and
              the reversal is a measurement.  q8_0 was adopted only because f16
              at 65536 spilled to system RAM on ollama.  On llama.cpp f16 at
              32768 — the window ernst actually declares — fits with 2761 MiB
              to spare, and q8_0 costs 14.7% of decode there (94.6 vs 107.5
              tok/s, interleaved, n=5).  So it buys nothing at the declared
              window.

              Take q8_0 when a model genuinely needs a 64k window: that is
              21990 MiB resident at ~95 tok/s, against f16's 24529 MiB which
              does not fit.

              DO NOT QUANTISE ONLY K.  `-ctk q8_0` with V left at f16 costs
              ~45% OF DECODE (57.1 tok/s vs ~100) to save 887 MiB — a measured
              trap, not a middle ground.  This option sets both, which is why
              it is one option and not two.

              The tool-call cost M11 attributed to q8_0 (40% vs f16's 83% at a
              baseline system prompt) is NOT a factor here: with the
              `<tool_call>` reinforcement the opencode role ships, both are
              100% on both servers. The choice is purely speed for context.
            '';
          };

          servedByLlama = lib.mkOption {
            type        = lib.types.bool;
            default     = true;
            description = ''
              Whether this entry becomes a section in llama-server's preset INI.

              False for weights that the GPU tier loads but llama-server does
              not — whisper's ggml model is the case that exists.  Such an entry
              is still FETCHED AND HASH-VERIFIED by the same oneshot, which is
              the whole reason it is declared here rather than in the role that
              consumes it: one model store, one verification path, one place to
              look when a file is missing.
            '';
          };

          mmproj = lib.mkOption {
            type        = lib.types.nullOr lib.types.str;
            default     = null;
            description = ''
              Filename of the multimodal projector, for vision or audio models.
              It is a SECOND file with its own URL and hash — declare it as its
              own entry in `extraFiles` and name it here.
            '';
          };

          extraFiles = lib.mkOption {
            type = lib.types.attrsOf (lib.types.submodule {
              options = {
                url  = lib.mkOption { type = lib.types.str; description = "Verified URL."; };
                hash = lib.mkOption { type = lib.types.str; description = "SRI hash."; };
              };
            });
            default     = { };
            description = ''
              Additional files fetched alongside the model, keyed by filename.
              Projectors for vision models live here — llama.cpp needs the
              projector and the weights as two files.
            '';
          };

          extraArgs = lib.mkOption {
            type        = lib.types.listOf lib.types.str;
            default     = [ ];
            example     = [ "temp = 0.7" ];
            description = ''
              Extra preset INI lines for this model, verbatim.  Keys are
              llama-server arguments without leading dashes.
            '';
          };
        };
      }));
    };

    perInstance = { settings, roles, machine, ... }: {
      nixosModule = { config, pkgs, lib, ... }:
        let
          inf = roles.inference.machines.${machine.name}.settings or null;
          stateDir  = if inf != null then inf.stateDir else "/srv/state/local-ai";
          user      = if inf != null then inf.user else "llama";
          modelsDir = "${stateDir}/models";

          # One fetch job per file: the model itself plus anything in
          # extraFiles.  Flattened here so the script below is a plain loop
          # rather than nested shell.
          jobs = lib.flatten (lib.mapAttrsToList (name: m:
            [ { file = m.filename; inherit (m) url hash; } ]
            ++ lib.mapAttrsToList (fn: f: { file = fn; inherit (f) url hash; }) m.extraFiles
          ) settings.models);
        in
        {
          assertions = [ {
            assertion = inf != null;
            message = ''
              @clanarchy/local-ai: ${machine.name} holds roles.models but not
              roles.inference.  Fetching models onto a machine that serves none
              is almost certainly a mistake in clan.nix; if it is deliberate,
              say so here rather than removing this assertion.
            '';
          } ];

          ##################################################################
          # The fetcher.
          #
          # A ONESHOT, NOT A PACKAGE.  These are 18 GiB blobs and architecture
          # invariant #7 puts them on zdata; a fixed-output derivation would
          # put them in the store on zroot, which is the pool that rolls back
          # and the one with no room for them.  That is the same reasoning
          # M14's hand-rolled derivations record, applied to data rather than
          # to code.
          #
          # Idempotent by hash: a file already present and correct is skipped,
          # so this is cheap on every boot and self-healing after a partial
          # download.  A hash MISMATCH is a hard failure that leaves the old
          # file alone — never a silent overwrite, because the thing on the
          # other side of a wrong model is an agent that sounds fine.
          ##################################################################
          # ── STARTED BY A TIMER, NOT BY multi-user.target ──────────────────
          #
          # See the long note on llama-router: as a `wantedBy` unit this put a
          # 25 GiB download on the activation critical path and made the first
          # deploy look like a hang for thirteen minutes.  A .timer is pulled in
          # by timers.target, and starting a timer completes instantly, so
          # activation returns while the fetch runs behind it.
          #
          # restartIfChanged = false is the other half.  Without it, ADDING a
          # model changes this unit's script, switch-to-configuration restarts
          # it, and the whole download is back on the critical path — the exact
          # defect, reintroduced by the exact edit most likely to trigger it.
          systemd.timers.llama-models-fetch = {
            description = "Fetch declared local-ai models shortly after boot";
            wantedBy    = [ "timers.target" ];
            timerConfig = {
              OnBootSec   = "30s";
              AccuracySec = "5s";
              Unit        = "llama-models-fetch.service";
            };
          };

          systemd.services.llama-models-fetch = {
            description = "Fetch and verify declared local-ai models";
            after       = [ "network-online.target" ];
            wants       = [ "network-online.target" ];

            # Deliberately NOT wantedBy multi-user.target — the timer above owns
            # starting it.  A deploy that ADDS a model therefore does not fetch
            # it immediately; run `systemctl start llama-models-fetch` (it is
            # idempotent) or wait for the next boot.  That is the documented
            # cost of keeping deploys non-blocking, and it is the right trade:
            # adding a model is rare and deliberate, deploying is neither.
            restartIfChanged = false;
            stopIfChanged    = false;

            serviceConfig = {
              Type            = "oneshot";
              RemainAfterExit = true;
              User            = user;
              Group           = user;
              # 18 GiB over a domestic line is not a 90-second job.
              TimeoutStartSec = "6h";
              StateDirectory  = "local-ai-fetch";
              NoNewPrivileges = true;
              PrivateTmp      = true;
              PrivateDevices  = true;
              ProtectSystem   = "strict";
              ProtectHome     = true;
              ReadWritePaths  = [ stateDir ];
              MemoryDenyWriteExecute = true;
              RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_UNIX" ];
            };

            script = ''
              set -euo pipefail
              mkdir -p ${modelsDir}

              fetch() {
                local file="$1" url="$2" want="$3"
                local dest="${modelsDir}/$file"

                if [ -f "$dest" ]; then
                  local have
                  have=$(${pkgs.nix}/bin/nix hash file --type sha256 --sri "$dest")
                  if [ "$have" = "$want" ]; then
                    echo "ok      $file"
                    return 0
                  fi
                  echo "MISMATCH $file: have $have, want $want" >&2
                  echo "         refusing to overwrite; move it aside by hand" >&2
                  return 1
                fi

                # RESUMABLE, and it has to be.  Measured on the first deploy:
                # HuggingFace served the first three files at ~29 MB/s and then
                # throttled the 18 GiB one to 2 MB/s — a 77-minute tail.  A
                # download that long WILL be interrupted, by a deploy, a reboot
                # or an operator, and without --continue-at every interruption
                # discarded everything: `fetch` tests for the FINAL name, so a
                # rerun re-opened "$dest.part" and started from zero.  8.8 GiB
                # was nearly thrown away exactly that way.
                #
                # `--continue-at -` resumes from the current .part length. If
                # the server ignores Range, curl fails loudly rather than
                # silently appending to a truncated file — and the hash check
                # below is the backstop for anything subtler.
                if [ -f "$dest.part" ]; then
                  echo "resume  $file (from $(${pkgs.coreutils}/bin/stat -c %s "$dest.part") bytes)"
                else
                  echo "fetch   $file"
                fi
                ${pkgs.curl}/bin/curl -fSL --retry 5 --retry-delay 10 \
                  --continue-at - -o "$dest.part" "$url"
                local got
                got=$(${pkgs.nix}/bin/nix hash file --type sha256 --sri "$dest.part")
                if [ "$got" != "$want" ]; then
                  rm -f "$dest.part"
                  echo "HASH MISMATCH after download of $file" >&2
                  echo "  want $want" >&2
                  echo "  got  $got" >&2
                  return 1
                fi
                mv -f "$dest.part" "$dest"
                echo "done    $file"
              }

              ${lib.concatMapStringsSep "\n" (j:
                ''fetch ${lib.escapeShellArg j.file} ${lib.escapeShellArg j.url} ${lib.escapeShellArg j.hash}''
              ) jobs}
            '';

            # Pick the router up once the models are actually on disk.
            #
            # Needed because the router reads its preset INI at startup: a model
            # whose file did not exist yet is listed but unusable until it
            # re-reads. `try-restart` and not `restart`, so this is a no-op when
            # the router is deliberately stopped rather than something that
            # starts it behind an operator's back. `-` prefixed so a failure
            # here cannot turn a completed 25 GiB download into a failed unit.
            postStart = "-${pkgs.systemd}/bin/systemctl try-restart llama-router.service";
          };
        };
    };
  };

  ##############################################################################
  # roles.speech — whisper.cpp STT
  ##############################################################################
  roles.speech = {
    description = "Whisper speech-to-text on an OpenAI-shaped endpoint, arbitrated by llama-swap.";

    interface.options = {
      model = lib.mkOption {
        type        = lib.types.str;
        default     = "ggml-large-v3-turbo-q5_0.bin";
        description = ''
          Filename of the whisper ggml model inside the model directory.  It is
          declared and fetched by `roles.models` like everything else — the
          filename here must match a key there.
        '';
      };
      language = lib.mkOption {
        type        = lib.types.str;
        default     = "auto";
        description = ''
          `-l`.  "auto" detects per utterance, which is what a bilingual
          household needs; pinning "de" is faster and wrong the moment somebody
          dictates an English package name.
        '';
      };
      threads = lib.mkOption {
        type        = lib.types.ints.positive;
        default     = 8;
        description = ''
          `-t`.  The 9950X has 16 cores; 8 leaves room for the containers that
          share this machine.  Whisper on this card is GPU-bound anyway — this
          matters for the mel spectrogram, not the decode.
        '';
      };
      gpuTarget = lib.mkOption {
        type        = lib.types.str;
        default     = "gfx1100";
        description = ''
          `rocmGpuTargets` for the whisper-cpp build.  A STRING, unlike
          llama-cpp's list-typed argument of the same name in nixpkgs 26.05 —
          passing a list here fails an `assert lib.isString value` deep in
          cmake option handling that does not mention this option.

          IT DOES NOT CURRENTLY BUY A GPU, and that is measured rather than
          assumed.  `rocmSupport = true` produces a binary that links
          libamdhip64.so.7 and libamd_comgr.so.3 — so the override is genuinely
          in effect, and checking `ldd` alone would tell you it worked — but the
          build emits no loadable `libggml-hip.so`, and ggml discovers backends
          by loading `libggml-<backend>.so` out of its own lib directory.  So at
          runtime:

            load_backend: loaded CPU backend from …/libggml-cpu-zen4.so
            whisper_backend_init_gpu: device 0: CPU (type: 0)
            whisper_backend_init_gpu: no GPU found

          llama-cpp's ROCm build DOES ship libggml-hip.so, which is why the same
          override works there and not here.  The option is kept because the
          build is otherwise correct and this is a packaging gap that may close;
          when it does, whisper becomes a real GPU consumer and MUST then be
          added to the exclusive group in the inference role.  Until then it is
          CPU, ~2.1x realtime on 8 threads, and costs no VRAM.
        '';
      };
    };

    perInstance = { ... }: {
      # Deliberately empty.
      #
      # WHY THIS ROLE PRODUCES NO UNITS OF ITS OWN: whisper-server must be
      # SPAWNED BY llama-swap, not run beside it, or it is outside the
      # exclusive group and can hold VRAM while the coder model wants it —
      # which is the exact failure this milestone exists to prevent.  So the
      # role carries settings and the inference role reads them and builds the
      # backend entry.  A unit here would be a second, competing owner.
      #
      # SPEACHES WAS THE BRIEF'S CHOICE AND IS NOT TAKEN.  Two reasons, both
      # checked rather than assumed: it is not in nixpkgs at all (its
      # dependencies are — faster-whisper 1.2.1, ctranslate2 4.7.2, kokoro — but
      # the server is not), and its STT path runs through CTranslate2, whose GPU
      # backend is CUDA.  On a 7900 XTX that is a CPU path with extra steps.
      # pkgs.whisper-cpp builds with rocmSupport for gfx1100 out of the flake's
      # own nixpkgs, and its whisper-server takes --inference-path, so
      # `--inference-path /v1/audio/transcriptions` is OpenAI-shaped with no
      # wrapper and no new input.
      nixosModule = { ... }: { };
    };
  };

  ##############################################################################
  # roles.imagegen — ComfyUI on the podman tier
  ##############################################################################
  roles.imagegen = {
    description = "ComfyUI image generation, podman tier, exclusive with the LLM on the GPU.";

    interface.options = {
      image = lib.mkOption {
        type        = lib.types.str;
        description = ''
          Fully-qualified ComfyUI ROCm image reference, DIGEST-PINNED.

          NO DEFAULT, AND THAT IS THE POINT.  There is no first-party ComfyUI
          container image — checked 2026-09-09 — so every candidate is a
          community build, and pinning one by digest on the machine that fronts
          the array is a trust decision an operator has to make explicitly
          rather than inherit from a module default.  It is also why this role
          is opt-in: a machine that does not set `image` gets no ComfyUI.

          Verify a digest before writing it:
            skopeo inspect docker://<ref> | jq -r .Digest
        '';
      };
      port = lib.mkOption {
        type        = lib.types.port;
        default     = 8188;
        description = "Loopback port ComfyUI listens on. llama-swap is its only client.";
      };
      stateDir = lib.mkOption {
        type        = lib.types.path;
        default     = "/srv/state/comfyui";
        description = "Models, outputs and custom nodes. On zdata, invariant #7.";
      };
      uid = lib.mkOption {
        type        = lib.types.int;
        description = ''
          Static uid, allocated in the table in machines/ernst/networking.nix.
          podman passes uids through unmapped for the rootful tier, so a number
          chosen here IS a uid on the pool.
        '';
      };
    };

    perInstance = { settings, ... }: {
      nixosModule = { config, pkgs, lib, ... }: {
        assertions = [ {
          assertion = lib.hasInfix "@sha256:" settings.image;
          message = ''
            @clanarchy/local-ai: roles.imagegen.image must be pinned by DIGEST
            (contain "@sha256:"), not by tag.  A tag is a moving reference to
            a community-built image with GPU device access on the machine that
            fronts the array; M9 pinned by digest for the same reason and this
            role does not get to be the exception.
          '';
        } ];

        systemd.tmpfiles.rules = [
          "d ${settings.stateDir} 0750 ${toString settings.uid} ${toString settings.uid} -"
          "d ${settings.stateDir}/models 0750 ${toString settings.uid} ${toString settings.uid} -"
          "d ${settings.stateDir}/output 0750 ${toString settings.uid} ${toString settings.uid} -"
        ];

        virtualisation.oci-containers.containers.comfyui = {
          image = settings.image;
          # ROOTFUL, like the rest of the podman tier on ernst (M9). /dev/kfd
          # cannot be handed to a rootless container without a device rule that
          # amounts to the same access with more moving parts.
          extraOptions = [
            "--device=/dev/kfd"
            "--device=/dev/dri"
            "--group-add=keep-groups"
            "--security-opt=seccomp=unconfined"   # ROCm's ioctls
            # LOOPBACK ONLY. The container publishes to 127.0.0.1 and llama-swap
            # is its only client; nothing on any VLAN reaches it.
            "--network=host"
          ];
          environment = {
            # No HSA override: gfx1100 is natively supported (invariant #5's
            # card). See the inference role for the full reasoning.
            HSA_OVERRIDE_GFX_VERSION = "";
            COMFYUI_PORT = toString settings.port;
          };
          volumes = [
            "${settings.stateDir}/models:/root/comfy/ComfyUI/models:rw"
            "${settings.stateDir}/output:/root/comfy/ComfyUI/output:rw"
          ];
          cmd = [
            "--listen" "127.0.0.1"
            "--port" (toString settings.port)
          ];
        };
      };
    };
  };

  ##############################################################################
  # roles.webui — Open WebUI in an nspawn container on the Services VLAN
  ##############################################################################
  roles.webui = {
    description = "Open WebUI on VLAN 90 behind Traefik + Authelia, talking only to llama-swap.";

    interface.options = {
      mac = lib.mkOption {
        type        = lib.types.str;
        example     = "02:00:00:90:00:0f";
        description = ''
          Container eth0 MAC, allocated in the table in
          machines/ernst/networking.nix.  The UDM-Pro DHCP reservation keys on
          this; a reservation outside the 10.0.90.6–.254 pool is accepted by
          UniFi and then silently ignored, which M2b, M5 and M6 each lost a
          round to.
        '';
      };
      uid = lib.mkOption {
        type        = lib.types.int;
        description = "Static uid/gid, allocated in machines/ernst/networking.nix.";
      };
      vlan = lib.mkOption {
        type    = lib.types.int;
        default = 90;
        description = "Services VLAN.";
      };
      bridge = lib.mkOption {
        type    = lib.types.str;
        default = "br0";
        description = "Host bridge the container's eth0 is enslaved to.";
      };
      resolver = lib.mkOption {
        type    = lib.types.str;
        default = "10.0.5.3";
        description = "Technitium. Declared, not inherited from DHCP.";
      };
      searchDomain = lib.mkOption {
        type    = lib.types.str;
        default = "skynet.lan";
        description = "Search suffix inside the container.";
      };
      port = lib.mkOption {
        type    = lib.types.port;
        default = 8080;
        description = "Open WebUI's listener inside the container.";
      };
      stateDir = lib.mkOption {
        type    = lib.types.path;
        default = "/srv/state/open-webui";
        description = "Bind-mounted to /var/lib/open-webui. On zdata, invariant #7.";
      };
      hostName = lib.mkOption {
        type    = lib.types.str;
        example = "chat.goclan.org";
        description = ''
          Public hostname.  MUST have a Technitium record BEFORE this is
          deployed and before the name is typed anywhere — M17's NXDOMAIN
          lesson: a browser that gets NXDOMAIN once caches it, and the fix then
          looks like a broken deploy.

          Must also appear in `protectedHosts` in
          machines/ernst/containers/ingress-policy.nix, or Authelia's
          default_policy = "deny" returns 403 to a user who has just logged in
          successfully — the RomM failure that file exists to prevent.
        '';
      };
      proxyAddress = lib.mkOption {
        type    = lib.types.str;
        default = "10.0.90.12";
        description = ''
          Traefik's address.  The container firewall permits this and only
          this, so a backend-bypass attempt from anywhere else on VLAN 90 —
          including the qBittorrent microvm one layer-2 hop away — times out
          rather than reaching the app.
        '';
      };
      inferenceAddress = lib.mkOption {
        type    = lib.types.str;
        example = "fdca:fe91::1";
        description = ''
          Host end of THIS container's veth to ernst, where llama-swap is
          reachable.  Open WebUI talks to the inference stack and to nothing
          else on the host.

          Same shape as M6's mon0 and for the same reason: llama-swap is bound
          to the host's loopback and a container cannot reach that, so the link
          is an explicit point-to-point ULA rather than opening the port.
        '';
      };
      oidc = {
        enable = lib.mkEnableOption "OIDC login against Authelia";
        issuerUrl = lib.mkOption {
          type    = lib.types.str;
          default = "https://auth.goclan.org";
          description = "Authelia's issuer. `/.well-known/openid-configuration` is derived from it.";
        };
        clientId = lib.mkOption {
          type    = lib.types.str;
          default = "open-webui";
          description = "Must match the client_id in machines/ernst/containers/authelia.nix.";
        };
      };
      speechUrl = lib.mkOption {
        type    = lib.types.nullOr lib.types.str;
        default = null;
        description = "OpenAI-shaped STT base URL, normally llama-swap. Null disables voice input.";
      };
      imageUrl = lib.mkOption {
        type    = lib.types.nullOr lib.types.str;
        default = null;
        description = "ComfyUI base URL. Null disables image generation.";
      };
    };

    perInstance = { settings, machine, ... }: {
      nixosModule = { config, pkgs, lib, ... }:
        let
          oidcGen = config.clan.core.vars.generators.authelia-oidc-openwebui;
          secretsDir = "/run/open-webui-secrets";
          vethName = "vb-openwebui";
          aiVeth   = "ai0";
          aiHost   = settings.inferenceAddress;
          aiCont   = "fdca:fe91::2";
          swapUrl  = "http://[${aiHost}]:11434";
        in
        {
          ##################################################################
          # The OIDC client secret. ITS OWN GENERATOR.
          #
          # containers/authelia.nix states the rule and the reason: a clan vars
          # generator is ATOMIC, so adding a file to an existing one re-runs the
          # whole script and hands every other relying party a new secret as a
          # side effect. Grafana and CWA each have their own; so does this.
          #
          # The pair WITHIN this generator is still atomic, which is the part
          # that matters — Authelia stores a PBKDF2 digest and the client sends
          # the plaintext, so the two must come out of one `rand` call.
          ##################################################################
          clan.core.vars.generators.authelia-oidc-openwebui = {
            files."openwebui-client-secret".secret        = true;
            files."openwebui-client-secret-digest".secret = true;
            files."openwebui-client-secret-digest".restartUnits =
              [ "authelia-secrets.service" "container@authelia.service" ];
            files."openwebui-client-secret".restartUnits =
              [ "open-webui-secrets.service" "container@openwebui.service" ];

            runtimeInputs = [ pkgs.authelia pkgs.gnused pkgs.coreutils ];
            script = ''
              set -euo pipefail
              secret=$(authelia crypto rand --length 72 --charset alphanumeric \
                         | sed -n 's/^Random Value: //p' | tr -d '\n')
              [ -n "$secret" ] || { echo "  ✗ no client secret produced" >&2; exit 1; }
              printf '%s' "$secret" > "$out/openwebui-client-secret"

              digest=$(authelia crypto hash generate pbkdf2 --variant sha512 --password "$secret" \
                         | sed -n 's/^Digest: //p')
              [ -n "$digest" ] || { echo "  ✗ no digest produced" >&2; exit 1; }
              printf '%s' "$digest" > "$out/openwebui-client-secret-digest"
            '';
          };

          ##################################################################
          # Stage the secret host-side, then bind-mount it in.
          #
          # NEVER point an in-container unit at /run/secrets/vars/… — clan var
          # paths do not exist inside an nspawn container's mount namespace and
          # the failure is a silent 243/CREDENTIALS. Staging into a directory
          # that IS bind-mounted is the fleet pattern.
          ##################################################################
          systemd.services.open-webui-secrets = {
            description = "Stage Open WebUI's OIDC secret for its container";
            wantedBy    = [ "multi-user.target" ];
            before      = [ "container@openwebui.service" ];
            serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
            script = ''
              set -euo pipefail
              install -d -m 0750 -o ${toString settings.uid} -g ${toString settings.uid} ${secretsDir}
              # Open WebUI reads its env from a file; render the whole line so
              # the value never appears in a unit's Environment= (world-readable
              # via `systemctl show`).
              umask 077
              printf 'OAUTH_CLIENT_SECRET=%s\n' \
                "$(cat ${oidcGen.files."openwebui-client-secret".path})" \
                > ${secretsDir}/oidc.env.new
              chown ${toString settings.uid}:${toString settings.uid} ${secretsDir}/oidc.env.new
              chmod 0400 ${secretsDir}/oidc.env.new
              mv -f ${secretsDir}/oidc.env.new ${secretsDir}/oidc.env
            '';
          };

          systemd.tmpfiles.rules = [
            "d ${settings.stateDir} 0750 ${toString settings.uid} ${toString settings.uid} -"
          ];

          ##################################################################
          # Host side of the Services-VLAN veth.
          #
          # KeepMaster rather than Bridge= because nspawn creates AND enslaves
          # this link itself; no L3 because a bridge port carries none;
          # "enslaved" rather than "routable" because a bridge port never
          # reaches routable and waiting for it hangs boot.
          ##################################################################
          systemd.network.networks."60-${vethName}" = {
            matchConfig.Name = vethName;
            networkConfig = {
              KeepMaster          = true;
              LinkLocalAddressing = "no";
              IPv6AcceptRA        = false;
            };
            bridgeVLANs = [ {
              VLAN           = settings.vlan;
              PVID           = settings.vlan;
              EgressUntagged = settings.vlan;
            } ];
            linkConfig.RequiredForOnline = "enslaved";
          };

          # Re-assert the VLAN after nspawn has created the veth. The same real
          # race as vb-jellyfin / vb-arr / vb-traefik / vb-monitoring: networkd
          # applies [BridgeVLAN] only once it observes the link's master, and
          # nspawn sets that master out of band. Idempotent, "-" prefixed so a
          # backstop cannot become a new failure mode.
          systemd.services."container@openwebui".serviceConfig.ExecStartPost = [
            "-${pkgs.iproute2}/bin/bridge vlan add dev ${vethName} vid ${toString settings.vlan} pvid untagged"
          ];

          containers.openwebui = {
            autoStart = true;
            ephemeral = false;

            privateNetwork  = true;
            hostBridge      = settings.bridge;
            localMacAddress = settings.mac;

            # Leg 2 — the point-to-point link to the host, carrying exactly one
            # thing: requests to llama-swap. /128 on each end, so
            # nixos-containers adds the matching host route on both sides and
            # there is no on-link assumption to get wrong.
            extraVeths.${aiVeth} = {
              hostAddress6  = aiHost;
              localAddress6 = aiCont;
            };

            bindMounts = {
              "/var/lib/open-webui" = {
                hostPath   = settings.stateDir;
                isReadOnly = false;
              };
              ${secretsDir} = {
                hostPath   = secretsDir;
                isReadOnly = true;
              };
            };

            config = { config, lib, ... }: {
              system.stateVersion = "26.05";

              # ── OPEN WEBUI IS UNFREE, AND THE ALLOWANCE STAYS IN HERE ─────
              #
              # nixpkgs marks open-webui unfree because of the branding clause
              # in its licence (below), so without an allowance evaluation
              # fails with:
              #
              #   error: Refusing to evaluate package 'open-webui-0.11.0'
              #          because it has an unfree license
              #
              # ernst does NOT set `allowUnfree`.  It carries a narrow
              # `allowUnfreePredicate` from modules/roles/htpc.nix listing the
              # Steam packages, and that file says explicitly why: "this role is
              # expected to land on otherwise-headless boxes (ernst fronts the
              # NAS array), and 'we needed Steam' shouldn't quietly open the
              # whole machine to unfree packages."  Adding open-webui to a list
              # about Steam would be the wrong file, and widening the host to
              # blanket allowUnfree would be exactly what that comment forbids.
              #
              # A container is its own nixosSystem with its own nixpkgs, so the
              # allowance is scoped to the one evaluation that needs it and the
              # host's predicate is untouched.  The cost is a second nixpkgs
              # instantiation and no lib/overlays.nix in here — the overlays are
              # a niri sandbox fix and chromium privacy flags, neither of which
              # this container has any use for.
              #
              # THE LICENCE, recorded so nobody has to rediscover it: Open WebUI
              # is BSD-3-clause plus a fourth clause forbidding removal or
              # alteration of "Open WebUI" branding — EXCEPT where the total
              # number of end users does not exceed FIFTY in any rolling 30-day
              # period.  This household is comfortably under that, so the
              # exemption applies and the branding may be left alone anyway.
              # If this is ever exposed to more than fifty people, that changes.
              nixpkgs.config.allowUnfreePredicate =
                pkg: builtins.elem (lib.getName pkg) [ "open-webui" ];

              # Matches the host, for the reason arr.nix and monitoring.nix
              # both give: every timestamp a human reads is local time, and a
              # container that defaults to UTC makes each of them a two-hour
              # question.
              time.timeZone = "Europe/Berlin";

              networking.useHostResolvConf = false;
              networking.useNetworkd       = true;
              services.resolved.enable     = true;

              systemd.network.networks."10-eth0" = {
                matchConfig.Name = "eth0";
                networkConfig = {
                  DHCP         = "ipv4";
                  DNS          = settings.resolver;
                  Domains      = "~. ${settings.searchDomain}";
                  IPv6AcceptRA = false;
                };
                dhcpV4Config = { UseDNS = false; UseDomains = false; };
                linkConfig.RequiredForOnline = "routable";
              };

              systemd.network.networks."20-${aiVeth}" = {
                matchConfig.Name = aiVeth;
                address = [ "${aiCont}/128" ];
                routes  = [ { Destination = "${aiHost}/128"; Scope = "link"; } ];
                networkConfig.IPv6AcceptRA = false;
                # "no", for the reason monitoring.nix measured and wrote down:
                # a veth pair has no carrier until both ends are up, and the
                # host end is brought up by container@…'s postStart, which runs
                # only after the container has finished booting. Requiring any
                # state here waits for an event its own completion is a
                # precondition for.
                linkConfig.RequiredForOnline = "no";
              };
              systemd.network.wait-online.timeout = 20;

              # NOTHING is unconditionally open. Traefik and only Traefik.
              networking.firewall = {
                enable = true;
                extraCommands = ''
                  iptables -A nixos-fw -p tcp --dport ${toString settings.port} \
                    -s ${settings.proxyAddress} -j nixos-fw-accept
                '';
              };

              users.users.open-webui = {
                isSystemUser = true;
                group = "open-webui";
                uid   = settings.uid;
              };
              users.groups.open-webui.gid = settings.uid;

              # ── DynamicUser OFF.  THE SAME TRAP THIS MODULE ALREADY ────────
              #    DOCUMENTED FOR OLLAMA, IN A SECOND FORM.
              #
              # nixpkgs' open-webui module ships `DynamicUser = true` with
              # `StateDirectory = "open-webui"`.  That combination is
              # incompatible with a bind-mounted state directory, and it fails
              # in a way that names neither:
              #
              #   Found pre-existing public StateDirectory= directory
              #     /var/lib/open-webui, migrating to /var/lib/private/open-webui.
              #   Apparently, service previously had DynamicUser= turned off,
              #     and has now turned it on.
              #   Failed to set up special execution directory in /var/lib:
              #     Device or resource busy
              #   status=238/STATE_DIRECTORY
              #
              # systemd wants to MOVE /var/lib/open-webui under /var/lib/private
              # so the per-boot dynamic uid can own it.  It is a bind mount, so
              # the move is EBUSY and the unit never starts — which presents at
              # the front door as Traefik's "Bad Gateway", three layers away.
              #
              # The `ollama` role in this same file carries the other half of
              # this lesson: DynamicUser + a persisted directory means the
              # per-boot uid cannot write to a root-owned 0700 path. Same root
              # cause, different symptom. A STATIC uid is the answer in both
              # cases — here it also has to match the ownership the host-side
              # tmpfiles rule sets on ${settings.stateDir}.
              systemd.services.open-webui.serviceConfig = {
                DynamicUser = lib.mkForce false;
                User        = "open-webui";
                Group       = "open-webui";
              };

              services.open-webui = {
                enable   = true;
                host     = "0.0.0.0";
                port     = settings.port;
                stateDir = "/var/lib/open-webui";
                environmentFile = "${secretsDir}/oidc.env";

                environment = {
                  # ── The one setting that makes this declarative ──────────
                  #
                  # Open WebUI's "PersistentConfig" writes most of the settings
                  # below into its own database ON FIRST LAUNCH and thereafter
                  # the DATABASE WINS — so a changed env var deploys green and
                  # does nothing, which is the exact failure shape this repo
                  # keeps rediscovering (the recyclarr duplicate instance, the
                  # opencode config that never parsed, SN1's silent truncation).
                  # False makes the environment authoritative on every boot,
                  # which is the only way a Nix-rendered config means anything.
                  ENABLE_PERSISTENT_CONFIG = "False";

                  ANONYMIZED_TELEMETRY = "False";
                  DO_NOT_TRACK         = "True";
                  SCARF_NO_ANALYTICS   = "True";

                  WEBUI_URL = "https://${settings.hostName}";

                  # ── The model backend ───────────────────────────────────
                  # llama-swap, over the point-to-point veth. Its /v1 surface
                  # is OpenAI-compatible; there is no ollama API here any more.
                  ENABLE_OPENAI_API   = "True";
                  ENABLE_OLLAMA_API   = "False";
                  OPENAI_API_BASE_URL = "${swapUrl}/v1";
                  # llama-swap requires no key. A placeholder rather than empty
                  # because the OpenAI client library refuses to send a request
                  # with no Authorization header at all.
                  OPENAI_API_KEY      = "sk-no-key-required";

                  # ── Auth ────────────────────────────────────────────────
                  WEBUI_AUTH = "True";
                } // lib.optionalAttrs settings.oidc.enable {
                  ENABLE_OAUTH_SIGNUP        = "True";
                  OAUTH_MERGE_ACCOUNTS_BY_EMAIL = "True";
                  OAUTH_CLIENT_ID            = settings.oidc.clientId;
                  OPENID_PROVIDER_URL        = "${settings.oidc.issuerUrl}/.well-known/openid-configuration";
                  # DERIVED FROM THE 0.11.0 SOURCE, not from a docs page — the
                  # same discipline containers/authelia.nix applied to CWA.
                  # main.py registers TWO routes for this callback:
                  #
                  #   @app.get('/oauth/{provider}/login/callback')   <- current
                  #   @app.get('/oauth/{provider}/callback')         <- "Legacy"
                  #
                  # and the SSO provider is registered under the literal key
                  # `oidc` (config.py: OAUTH_PROVIDERS['oidc'] = …), so the
                  # provider segment is `oidc` and not OAUTH_PROVIDER_NAME,
                  # which is only the label on the button.
                  #
                  # The current path is used here and BOTH are registered on the
                  # Authelia side, so an upstream removal of the legacy route
                  # cannot break login. Do not confuse either with
                  # `/oauth/clients/<id>/callback`, which is a different feature
                  # (Open WebUI acting as an OAuth client to MCP servers).
                  OPENID_REDIRECT_URI        = "https://${settings.hostName}/oauth/oidc/login/callback";
                  OAUTH_PROVIDER_NAME        = "Authelia";
                  OAUTH_SCOPES               = "openid email profile groups";
                  # The local password form STAYS, and it is break-glass, not
                  # laziness: monitoring.nix makes the same call for Grafana.
                  # If Authelia is down, every admin UI in the house is down,
                  # and this is the one that can still be reached over an SSH
                  # forward to debug it.
                  ENABLE_LOGIN_FORM          = "True";
                } // lib.optionalAttrs (settings.speechUrl != null) {
                  AUDIO_STT_ENGINE              = "openai";
                  AUDIO_STT_OPENAI_API_BASE_URL = "${settings.speechUrl}/v1";
                  AUDIO_STT_OPENAI_API_KEY      = "sk-no-key-required";
                  AUDIO_STT_MODEL               = "whisper";
                  # TTS is the BROWSER's, deliberately — see the role header in
                  # local-ai.md. Nothing in nixpkgs serves an OpenAI-shaped
                  # /v1/audio/speech, and the Web Speech API costs no VRAM on a
                  # card this milestone is already arbitrating.
                  AUDIO_TTS_ENGINE              = "";
                } // lib.optionalAttrs (settings.imageUrl != null) {
                  ENABLE_IMAGE_GENERATION = "True";
                  IMAGE_GENERATION_ENGINE = "comfyui";
                  COMFYUI_BASE_URL        = settings.imageUrl;
                };
              };
            };
          };
        };
    };
  };

  ##############################################################################
  # roles.ollama — MIRALDA ONLY, and deliberately kept
  #
  # ernst moved to llama.cpp in M19.  miralda did not, and this role exists so
  # that it does not have to as a side effect.
  #
  # WHY NOT MIGRATE IT TOO.  The case M19 measured is a 24 GiB discrete card
  # with a 30B model.  miralda is a Phoenix 780M iGPU (gfx1103) running a 7B out
  # of SHARED SYSTEM RAM, which is a different problem: the VRAM arbitration
  # that justifies llama-swap does not apply, the HSA override does, and M11
  # noted in passing that the override is not even working there — miralda's
  # ollama runs at 100% CPU.  Migrating it is a real question with its own
  # measurement and it is not this milestone's.
  #
  # NO ROCm/CONTEXT MEASUREMENTS FROM M19 APPLY HERE.  Everything below is the
  # ollama-era behaviour, unchanged, including the silent-truncation hazard that
  # llama.cpp removed on ernst.  SN1 is therefore still LIVE on miralda, which
  # is why `contextLength` remains required reading rather than a formality.
  ##############################################################################
  roles.ollama = {
    description = "Ollama with ROCm acceleration. Legacy path — miralda only; ernst uses roles.inference.";

    interface.options.models = lib.mkOption {
      type        = lib.types.listOf lib.types.str;
      default     = [ "qwen2.5-coder:7b" ];
      description = ''
        Models to pre-pull when the service starts.

        Tags must exist in ollama's library — a wrong one is not a warning, it
        fails the pull and leaves ollama-model-loader.service in a restart loop.
        This defaulted to `qwen3-coder:8b` for a long time, which has never
        existed (qwen3-coder publishes only 30b and 480b), so the loader had
        been failing on every machine since it was introduced.

        Check before changing:
          curl -s -o /dev/null -w '%{http_code}\n' \
            https://registry.ollama.ai/v2/library/<name>/manifests/<tag>

        THIS IS THE FAILURE MODE roles.models REPLACES on ernst: there, a model
        is a URL and a hash that are verified at fetch time and again at every
        boot, so "a tag that never existed" is not a representable state.
      '';
    };

    interface.options.contextLength = lib.mkOption {
      type        = lib.types.nullOr lib.types.ints.positive;
      default     = null;
      example     = 4096;
      description = ''
        Value for `OLLAMA_CONTEXT_LENGTH`, or null to leave it unset.

        PIN IT.  Left unset, ollama derives the context PER MODEL, so the tag in
        `models` above silently sets the context window for every client with no
        diff that shows it.  Measured: `qwen3-coder:30b` → 32768,
        `qwen2.5-coder:7b` → 4096.

        Exceeding the window is NOT an error on ollama.  The prompt is truncated
        to roughly num_ctx/2, the TAIL IS KEPT and the HEAD DISCARDED — which is
        where the system message and the tool definitions live — and HTTP 200 is
        returned with no flag anywhere.  Re-measured 2026-09-08 during M19: a
        16,694-token prompt became 4,098 tokens and the model answered a question
        about the discarded head by INVENTING a placeholder-shaped MAC address.

        llama.cpp refuses the same request with HTTP 400 naming both numbers,
        which is why ernst moved.  On this role the hazard is unchanged and
        pinning the window is the only defence.
      '';
    };

    interface.options.kvCacheType = lib.mkOption {
      type        = lib.types.nullOr (lib.types.enum [ "f16" "q8_0" "q4_0" ]);
      default     = null;
      example     = "q8_0";
      description = ''
        Value for `OLLAMA_KV_CACHE_TYPE`, or null for ollama's default (f16).
        Setting anything other than null also sets `OLLAMA_FLASH_ATTENTION=1`,
        which is its prerequisite.

        On ollama, flash attention ALONE saves nothing (measured identical to
        baseline) — it is the enabler, not the saving.  Note this is NOT true of
        llama.cpp, where `-fa on` saves 1667 MiB at 32k; do not carry the
        ollama-era statement across.

        q8_0 roughly HALVES tool-call reliability at a baseline system prompt
        (40%/36% vs f16's 83%/83%) and costs nothing once the client sends the
        `<tool_call>` reinforcement the opencode role ships.  At a 4096 window
        it buys nothing worth having, so miralda leaves this null.
      '';
    };

    interface.options.hsaOverrideGfxVersion = lib.mkOption {
      type        = lib.types.nullOr lib.types.str;
      default     = null;
      example     = "11.0.3";
      description = ''
        Value for `HSA_OVERRIDE_GFX_VERSION`, or null to leave it unset.

        Only needed when the GPU's gfx target is absent from stock ROCm kernel
        libraries, which is the case for AMD APUs — miralda's Phoenix iGPU is
        gfx1103 and needs "11.0.3".  Discrete cards ROCm supports natively must
        leave this null: forcing an override there makes ROCm select the wrong
        kernels for a card that already has correct ones.
      '';
    };

    perInstance = { settings, ... }: {
      nixosModule = { config, pkgs, lib, ... }: {

        services.ollama = {
          enable     = true;
          package    = pkgs.ollama-rocm;
          loadModels = settings.models;
          environmentVariables = {
            ROCR_VISIBLE_DEVICES = "0";
          } // lib.optionalAttrs (settings.hsaOverrideGfxVersion != null) {
            HSA_OVERRIDE_GFX_VERSION = settings.hsaOverrideGfxVersion;
          } // lib.optionalAttrs (settings.contextLength != null) {
            OLLAMA_CONTEXT_LENGTH = toString settings.contextLength;
          } // lib.optionalAttrs (settings.kvCacheType != null) {
            OLLAMA_FLASH_ATTENTION = "1";
            OLLAMA_KV_CACHE_TYPE   = settings.kvCacheType;
          };

          # Static system user rather than nixpkgs' DynamicUser default.
          # DynamicUser + impermanence is a permissions trap: impermanence
          # creates /persist/var/lib/private/ollama as root:root 0700 and the
          # per-boot dynamic uid cannot write there, so every pull returns
          # `mkdir /var/lib/ollama/models: permission denied`.
          user  = "ollama";
          group = "ollama";
        };

        users.users.ollama = {
          isSystemUser = true;
          group        = "ollama";
          home         = "/var/lib/ollama";
          createHome   = false;
          description  = "Ollama inference daemon";
        };
        users.groups.ollama = { };

        systemd.services.ollama.serviceConfig.DynamicUser = lib.mkForce false;

        # Upstream ships Restart=on-failure with a 1s→exponential ladder; a 1s
        # retry buys nothing if the underlying failure is network or storage.
        systemd.services.ollama-model-loader.serviceConfig = {
          Restart    = lib.mkForce "on-failure";
          RestartSec = lib.mkForce "30s";
        };

        systemd.tmpfiles.rules = [
          "L+ /opt/rocm/hip - - - - ${pkgs.rocmPackages.clr}"
          # nixpkgs' ollama module puts <home>/models in ReadWritePaths, and
          # systemd refuses to set up the mount namespace when one is missing:
          #   status=226/NAMESPACE, /var/lib/ollama/models: No such file
          # StateDirectory creates the parent but not this subdirectory.
          "d /var/lib/ollama/models 0700 ollama ollama -"
        ];

        environment.persistence."/persist".directories = [
          {
            directory = "/var/lib/ollama";
            user      = "ollama";
            group     = "ollama";
            mode      = "0700";
          }
        ];

        # ERNST'S ollama-statedir-canonicalize UNIT IS GONE WITH THIS REWRITE.
        # It removed a stale DynamicUser-era symlink at /var/lib/ollama before
        # impermanence bind-mounted over it, and it existed because ernst's
        # rollback was a silent no-op so the symlink survived indefinitely.
        # ernst no longer runs ollama at all; miralda's rollback genuinely
        # works, so a stale symlink there clears itself on the next boot. The
        # unit is not carried forward rather than being carried forward
        # unexamined.
      };
    };
  };

  ##############################################################################
  # roles.opencode — the CLI agent
  ##############################################################################
  roles.opencode = {
    description = "OpenCode CLI coding agent, pointed at a local or tunnelled llama-swap.";

    interface.options = {
      user = lib.mkOption {
        type        = lib.types.str;
        default     = "lgo";
        description = "Home Manager user to install OpenCode for.";
      };
      model = lib.mkOption {
        type        = lib.types.str;
        default     = "local/qwen3-coder-30b";
        description = ''
          Default model, as `<provider-id>/<model name>`.  The provider id is
          always `local` here — it is the key this role writes into `provider`
          in OpenCode's config.

          The model half must name a key in the endpoint's `roles.models`, or
          OpenCode asks for something that was never declared and llama-swap
          answers 404.  It no longer has to be an ollama registry TAG, which is
          the class of mistake that put `qwen3-coder:8b` — a tag that has never
          existed — into a restart loop for months.

          Check what the endpoint actually serves before trusting an answer:
            curl -s localhost:11435/v1/models | jq -r '.data[].id'
        '';
      };
      providerName = lib.mkOption {
        type        = lib.types.str;
        default     = "local";
        description = "Provider id written into OpenCode's config.";
      };

      tunnel = {
        enable = lib.mkEnableOption ''
          reaching a REMOTE inference server over an SSH port-forward instead of
          a local one. For machines with no GPU worth the name, or none ROCm can
          use

          The far end is not, and should not be, exposed on the network:
          llama-swap binds 127.0.0.1 and machines/ernst/networking.nix records
          that deliberately. A forward keeps that true — the listener stays
          loopback-only on both ends
        '';

        remoteHost = lib.mkOption {
          type        = lib.types.str;
          default     = "ernst.skynet.lan";
          description = "Host running the inference server this machine should talk to.";
        };

        remoteUser = lib.mkOption {
          type        = lib.types.str;
          default     = "root";
          description = ''
            User to authenticate as on the far end. root, because that is whose
            `authorized_keys` the inference role writes the tunnel key into —
            and the key is restricted to one forward, so it grants no shell.
          '';
        };

        localPort = lib.mkOption {
          type        = lib.types.port;
          default     = 11435;
          description = ''
            Local port the forward listens on, loopback only.

            11435 rather than the obvious 11434 because miralda runs its OWN
            ollama on 11434 — machines/ernst/networking.nix records that as a
            fleet fact precisely so nobody copies `ssh -L 11434:...` and either
            gets a bind failure or, worse, silently talks to a local 7B at 4096
            context and believes the answer.

            Sanity check what you reached:
              curl -s localhost:11435/v1/models | jq -r '.data[].id'
          '';
        };

        remotePort = lib.mkOption {
          type        = lib.types.port;
          default     = 11434;
          description = ''
            Port the inference server listens on (loopback) at the far end.
            Must match the inference role's `port`, which is also what its
            `permitopen` restriction names.
          '';
        };

        hostNames = lib.mkOption {
          type        = lib.types.listOf lib.types.str;
          default     = [ "ernst" "ernst.skynet.lan" "10.0.50.10" ];
          description = "Names/addresses the pinned host key below is valid for.";
        };

        hostPublicKey = lib.mkOption {
          type        = lib.types.str;
          default     = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILd954KHVjUAOX06pHP/+ou78tpo6OYKMQL2ew3eUqEt";
          description = ''
            The far end's SSH host public key, pinned so the tunnel never has to
            TOFU. Mirrors `vars/per-machine/ernst/openssh/ssh.id_ed25519.pub/value`
            — the same value `clanarchy.remoteBuilder.hostPublicKey` pins, and it
            has to be updated in both places if ernst's host key is regenerated.
          '';
        };
      };
    };

    perInstance = { settings, ... }: {
      nixosModule = { config, pkgs, lib, ... }:
        let
          gen = config.clan.core.vars.generators.ollama-tunnel-ssh;

          baseURL =
            if settings.tunnel.enable then
              "http://127.0.0.1:${toString settings.tunnel.localPort}/v1"
            else
              "http://127.0.0.1:11434/v1";

          # ── THE ONE INSTRUCTION THAT DECIDES WHETHER TOOL CALLING WORKS ──
          #
          # M19 asked whether this survives the move off ollama, since the
          # original diagnosis was about ollama's compiled Go parser. IT DOES,
          # and the measurement is the strongest evidence in the milestone that
          # the defect is the MODEL's:
          #
          #   condition                    llama.cpp        ollama
          #   baseline, "go find X"        4/30   (13%)     4/30   (13%)
          #   + this rule                  30/30 (100%)     30/30 (100%)
          #   baseline, "read this file"  21/30   (70%)     4/30   (13%)
          #   + this rule                  30/30 (100%)     30/30 (100%)
          #
          # ZERO "tag present but unparsed" in all eight cells. Two unrelated
          # parsers — ollama's Go one and llama.cpp's GGUF Jinja template —
          # reject exactly the same malformed output at the same rate. The model
          # drops the OPENING <tool_call> tag while still emitting the closing
          # one, and restating that one tag fixes it completely on both.
          #
          # So this file is NOT deleted by the llama.cpp migration. Deleting it
          # takes tool calling from 100% to 13% on the worst condition.
          toolCallRule = pkgs.writeText "opencode-tool-call-rule.md" ''
            CRITICAL OUTPUT RULE: every function call MUST begin with a literal
            <tool_call> line and end with a literal </tool_call> line. The opening
            <tool_call> tag is mandatory and is the most commonly omitted part. Never
            emit <function=...> unless the immediately preceding line is <tool_call>.
          '';
        in
        lib.mkMerge [

          {
            environment.systemPackages = [ pkgs.opencode ];

            home-manager.users.${settings.user} = { lib, ... }: {
              # ~/.config is persisted for lgo (modules/users/lgo.nix), so this
              # config survives ZFS rollback without an explicit persist entry.
              #
              # SCHEMA NOTE, because this file was wrong for a long time and
              # failed silently: opencode 1.x wants `provider.<id>` with an
              # `npm` driver and `options.baseURL`. The previous
              # `providers.ollama.baseUrl` (plural key, camelCase `baseUrl`, no
              # driver) matches no version of the schema — opencode ignored the
              # whole block and fell through to its own defaults.
              xdg.configFile."opencode/config.json".text = builtins.toJSON {
                "$schema" = "https://opencode.ai/config.json";
                model = settings.model;
                provider.${settings.providerName} = {
                  # llama-swap's /v1 surface is OpenAI-compatible, so the
                  # generic OpenAI-compatible driver is the right one.
                  npm = "@ai-sdk/openai-compatible";
                  name = "llama.cpp (${if settings.tunnel.enable then settings.tunnel.remoteHost else "local"})";
                  options = { inherit baseURL; };
                  # Declaring the model explicitly matters: this provider has no
                  # model catalogue for opencode to discover, so an undeclared
                  # name is not selectable even when the server has it.
                  models.${lib.removePrefix "${settings.providerName}/" settings.model} = { };
                };
                instructions = [ "${toolCallRule}" ];
              };
            };
          }

          # ── SSH forward to the remote inference server ───────────────────
          (lib.mkIf settings.tunnel.enable {

            # Dedicated keypair, generated as a SHARED var so the far end can
            # read the public half straight out of the repo. Declared by the
            # CLIENT only — declaring it on both ends makes the two `files` sets
            # differ, and clan rejects a shared generator whose definitions
            # diverge between machines, which blocks every install/update in the
            # flake rather than just this one.
            #
            # STILL NAMED ollama-tunnel-ssh. See the note in the inference role:
            # renaming rotates the key on every machine that has one, for
            # cosmetic reasons, and a half-finished rename of a SHARED generator
            # breaks every deploy in the flake.
            clan.core.vars.generators.ollama-tunnel-ssh = {
              share = true;

              files."tunnel_ed25519" = {
                secret = true;
                owner  = "root";
                group  = "root";
                mode   = "0400";
              };
              files."tunnel_ed25519.pub".secret = false;

              runtimeInputs = [ pkgs.openssh ];
              script = ''
                ssh-keygen -t ed25519 -N "" -C "clanarchy-ollama-tunnel" \
                  -f "$out/tunnel_ed25519"
              '';
            };

            programs.ssh.knownHosts."clanarchy-ollama-tunnel" = {
              inherit (settings.tunnel) hostNames;
              publicKey = settings.tunnel.hostPublicKey;
            };

            # A system service, not a user one: the private key is root-owned
            # 0400 (clan vars), and lgo's own SSH access to ernst authenticates
            # with the YubiKey, which needs gpg-agent inside an interactive
            # session and so cannot carry a background tunnel.
            systemd.services.ollama-tunnel = {
              description = "SSH port-forward to ${settings.tunnel.remoteHost}'s inference server";
              after    = [ "network-online.target" ];
              wants    = [ "network-online.target" ];
              wantedBy = [ "multi-user.target" ];

              serviceConfig = {
                ExecStart = lib.concatStringsSep " " [
                  "${pkgs.openssh}/bin/ssh"
                  "-NT"
                  # Fail loudly instead of holding open a session that forwards
                  # nothing — without this the unit looks healthy while every
                  # request to localhost is refused.
                  "-o ExitOnForwardFailure=yes"
                  "-o ServerAliveInterval=30"
                  "-o ServerAliveCountMax=3"
                  "-o StrictHostKeyChecking=yes"
                  "-o IdentitiesOnly=yes"
                  "-i ${gen.files."tunnel_ed25519".path}"
                  "-L 127.0.0.1:${toString settings.tunnel.localPort}:127.0.0.1:${toString settings.tunnel.remotePort}"
                  "${settings.tunnel.remoteUser}@${settings.tunnel.remoteHost}"
                ];
                # A laptop loses this link every time it sleeps or roams.
                # Restarting always (not just on-failure) is the point.
                Restart    = "always";
                RestartSec = "10s";
                DynamicUser = false;
                User = "root";
              };
              # Don't let a laptop that is off the home LAN burn its restart
              # budget and give up permanently.
              startLimitIntervalSec = 0;
            };
          })
        ];
    };
  };
}
