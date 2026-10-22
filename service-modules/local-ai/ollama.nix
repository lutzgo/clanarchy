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
{lib, ...}: {
  description = "Ollama with ROCm acceleration. Legacy path — miralda only; ernst uses roles.inference.";

  interface.options.models = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = ["qwen2.5-coder:7b"];
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
    type = lib.types.nullOr lib.types.ints.positive;
    default = null;
    example = 4096;
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
    type = lib.types.nullOr (lib.types.enum ["f16" "q8_0" "q4_0"]);
    default = null;
    example = "q8_0";
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
    type = lib.types.nullOr lib.types.str;
    default = null;
    example = "11.0.3";
    description = ''
      Value for `HSA_OVERRIDE_GFX_VERSION`, or null to leave it unset.

      Only needed when the GPU's gfx target is absent from stock ROCm kernel
      libraries, which is the case for AMD APUs — miralda's Phoenix iGPU is
      gfx1103 and needs "11.0.3".  Discrete cards ROCm supports natively must
      leave this null: forcing an override there makes ROCm select the wrong
      kernels for a card that already has correct ones.
    '';
  };

  perInstance = {settings, ...}: {
    nixosModule = {
      config,
      pkgs,
      lib,
      ...
    }: {
      services.ollama = {
        enable = true;
        package = pkgs.ollama-rocm;
        loadModels = settings.models;
        environmentVariables =
          {
            ROCR_VISIBLE_DEVICES = "0";
          }
          // lib.optionalAttrs (settings.hsaOverrideGfxVersion != null) {
            HSA_OVERRIDE_GFX_VERSION = settings.hsaOverrideGfxVersion;
          }
          // lib.optionalAttrs (settings.contextLength != null) {
            OLLAMA_CONTEXT_LENGTH = toString settings.contextLength;
          }
          // lib.optionalAttrs (settings.kvCacheType != null) {
            OLLAMA_FLASH_ATTENTION = "1";
            OLLAMA_KV_CACHE_TYPE = settings.kvCacheType;
          };

        # Static system user rather than nixpkgs' DynamicUser default.
        # DynamicUser + impermanence is a permissions trap: impermanence
        # creates /persist/var/lib/private/ollama as root:root 0700 and the
        # per-boot dynamic uid cannot write there, so every pull returns
        # `mkdir /var/lib/ollama/models: permission denied`.
        user = "ollama";
        group = "ollama";
      };

      users.users.ollama = {
        isSystemUser = true;
        group = "ollama";
        home = "/var/lib/ollama";
        createHome = false;
        description = "Ollama inference daemon";
      };
      users.groups.ollama = {};

      systemd.services.ollama.serviceConfig.DynamicUser = lib.mkForce false;

      # Upstream ships Restart=on-failure with a 1s→exponential ladder; a 1s
      # retry buys nothing if the underlying failure is network or storage.
      systemd.services.ollama-model-loader.serviceConfig = {
        Restart = lib.mkForce "on-failure";
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
          user = "ollama";
          group = "ollama";
          mode = "0700";
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
}
