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
        };

        # services.ollama.loadModels wires up `ollama-model-loader.service`,
        # which runs `ollama pull` for each configured model when ollama.service
        # starts. On cold boot the loader races DNS: NetworkManager may not have
        # finished associating + DHCP + DNS by the time the pull fires, so it
        # dies with a name-resolution error.
        #
        # Upstream nixpkgs already declares After/Wants=network-online.target on
        # this unit, but that ordering is only meaningful when a `*-wait-online`
        # service actually blocks the target.  On this fleet both wait-online
        # services are masked:
        #   - systemd-networkd-wait-online — clan-core default (see
        #     machines/ernst/networking.nix for the reasoning);
        #   - NetworkManager-wait-online — masked here as well.
        # Unmasking NM-wait-online would add up-to-30s boot delays whenever the
        # laptop is away from home wifi — an unacceptable regression for a
        # roaming Framework 13.  So the ordering is a no-op on this machine and
        # we lean on retry instead: on failure wait 30s and re-run, by which
        # time NM is up and DNS resolves.
        #
        # Upstream also ships Restart=on-failure with a 1s→exponential ladder;
        # codify it here (with a saner 30s base — DNS-at-boot doesn't need a 1s
        # retry) so a future upstream default change doesn't quietly reintroduce
        # the race. RestartSteps/RestartMaxDelaySec from upstream still apply.
        systemd.services.ollama-model-loader.serviceConfig = {
          Restart    = lib.mkForce "on-failure";
          RestartSec = lib.mkForce "30s";
        };

        # Many ROCm utilities hard-code /opt/rocm/hip.  Create a symlink so
        # they resolve correctly without patching each binary.
        systemd.tmpfiles.rules = [
          "L+ /opt/rocm/hip - - - - ${pkgs.rocmPackages.clr}"
        ];

        # Ollama stores downloaded models under /var/lib/ollama, but the NixOS
        # service runs with DynamicUser=true + StateDirectory=ollama, which makes
        # systemd put the real storage in /var/lib/private/ollama and expose it
        # as /var/lib/ollama via a symlink/bind.  Persisting /var/lib/ollama
        # directly conflicts with that mechanism (systemd can't migrate a busy
        # bind mount).  Persist the actual storage path instead.
        environment.persistence."/persist".directories = [
          {
            directory = "/var/lib/private/ollama";
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
