{ lib, ... }:
#
# @clanarchy/local-ai — local AI inference and coding agent.
#
# Roles:
#   ollama    — NixOS system service: Ollama daemon with ROCm acceleration
#               tuned for the AMD Radeon 780M iGPU (gfx1103 / Phoenix).
#   opencode  — User-level OpenCode CLI coding agent pointed at the local
#               Ollama endpoint (FOSS alternative to Claude Code).
#
{
  _class = "clan.service";
  manifest.name        = "@clanarchy/local-ai";
  manifest.description = "Local AI inference (Ollama) and OpenCode coding agent.";
  manifest.readme      = builtins.readFile ./local-ai.md;


  # ── Ollama inference server ────────────────────────────────────────────────
  roles.ollama = {
    description = "Ollama daemon with ROCm acceleration (AMD Radeon 780M / gfx1103).";

    interface.options.models = lib.mkOption {
      type        = lib.types.listOf lib.types.str;
      default     = [ "qwen3-coder:8b" ];
      description = "Models to pre-pull when the service starts.";
    };

    interface.options.hsaOverrideGfxVersion = lib.mkOption {
      type        = lib.types.nullOr lib.types.str;
      default     = null;
      example     = "11.0.3";
      description = ''
        Value for `HSA_OVERRIDE_GFX_VERSION`, or null to leave it unset.

        Only needed when the GPU's gfx target is absent from stock ROCm
        kernel libraries, which is the case for AMD APUs — miralda's
        Phoenix iGPU is gfx1103 and needs "11.0.3".  Discrete cards that
        ROCm supports natively (ernst's RX 7900 XTX is gfx1100) must leave
        this null: forcing an override there makes ROCm select the wrong
        kernels for a card that already has correct ones.
      '';
    };

    perInstance = { settings, ... }: {
      nixosModule = { pkgs, lib, ... }: {

        services.ollama = {
          enable     = true;
          # pkgs.ollama-rocm replaces the removed `acceleration = "rocm"` option
          # (nixpkgs dropped that option; the variant packages are the new API).
          package    = pkgs.ollama-rocm;
          loadModels = settings.models;
          # HSA_OVERRIDE_GFX_VERSION is per-machine (see the option's
          # description): APUs whose gfx target is missing from stock ROCm
          # need it, natively-supported discrete cards must not have it.
          environmentVariables = {
            ROCR_VISIBLE_DEVICES = "0";
          } // lib.optionalAttrs (settings.hsaOverrideGfxVersion != null) {
            HSA_OVERRIDE_GFX_VERSION = settings.hsaOverrideGfxVersion;
          };

          # Pin ollama to a static system user instead of the nixpkgs default
          # `DynamicUser = true`.  DynamicUser + impermanence is a permissions
          # trap: on the fleet's ZFS-rollback machines, impermanence creates
          # /persist/var/lib/private/ollama as root:root 0700 (its default
          # ownership when no `user`/`group` is specified on the entry), but
          # the per-boot dynamic uid systemd allocates for ollama cannot write
          # there, so the daemon fails to create /var/lib/ollama/models and
          # every `ollama pull` returns:
          #
          #   400 Bad Request: mkdir /var/lib/ollama/models: permission denied
          #
          # A static system user lets us set matching ownership on the persist
          # entry once, and lets the model store survive upgrades without an
          # activation-time chown against a moving-target uid.
          user  = "ollama";
          group = "ollama";
        };

        users.users.ollama = {
          isSystemUser = true;
          group        = "ollama";
          home         = "/var/lib/ollama";
          createHome   = false;   # StateDirectory creates + owns it
          description  = "Ollama inference daemon";
        };
        users.groups.ollama = { };

        # Belt-and-braces: force DynamicUser off in case a nixpkgs bump ever
        # decides `user`/`group` alone isn't enough to imply it.
        systemd.services.ollama.serviceConfig.DynamicUser = lib.mkForce false;

        # services.ollama.loadModels wires up `ollama-model-loader.service`,
        # which runs `ollama pull` for each configured model when ollama.service
        # starts.  Upstream ships Restart=on-failure with a 1s→exponential
        # ladder; a 1s retry buys nothing if the underlying failure is
        # network / storage related.  Give it 30 s of breathing room so the
        # journal doesn't fill up while the real cause is being investigated.
        systemd.services.ollama-model-loader.serviceConfig = {
          Restart    = lib.mkForce "on-failure";
          RestartSec = lib.mkForce "30s";
        };

        # Many ROCm utilities hard-code /opt/rocm/hip.  Create a symlink so
        # they resolve correctly without patching each binary.
        systemd.tmpfiles.rules = [
          "L+ /opt/rocm/hip - - - - ${pkgs.rocmPackages.clr}"
        ];

        # With DynamicUser off, StateDirectory=ollama manages /var/lib/ollama
        # directly (no /var/lib/private/ollama indirection).  Persist that
        # path with matching ownership so impermanence chown's the source
        # dir at boot before ollama.service tries to write into it.
        environment.persistence."/persist".directories = [
          {
            directory = "/var/lib/ollama";
            user      = "ollama";
            group     = "ollama";
            mode      = "0700";
          }
        ];
      };
    };
  };


  # ── OpenCode coding agent ──────────────────────────────────────────────────
  roles.opencode = {
    description = "OpenCode CLI coding agent wired to the local Ollama endpoint.";

    interface.options = {
      user = lib.mkOption {
        type        = lib.types.str;
        default     = "lgo";
        description = "Home Manager user to install OpenCode for.";
      };
      model = lib.mkOption {
        type        = lib.types.str;
        default     = "ollama/qwen3-coder:8b";
        description = "Default model (format: ollama/<name> for local Ollama models).";
      };
    };

    perInstance = { settings, ... }: {
      nixosModule = { pkgs, ... }: {
        environment.systemPackages = [ pkgs.opencode ];

        home-manager.users.${settings.user} = { lib, ... }: {
          # Point OpenCode at the local Ollama API.
          # ~/.config is persisted for lgo (modules/users/lgo.nix), so this
          # config survives ZFS rollback without an explicit persist entry.
          xdg.configFile."opencode/config.json".text = builtins.toJSON {
            model = settings.model;
            providers.ollama.baseUrl = "http://localhost:11434/v1";
          };
        };
      };
    };
  };
}
