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
      default     = [ "qwen2.5-coder:7b" ];
      description = ''
        Models to pre-pull when the service starts.

        Tags must exist in ollama's library — a wrong one is not a warning,
        it fails the pull and leaves ollama-model-loader.service in a restart
        loop. This defaulted to `qwen3-coder:8b` for a long time, which has
        never existed (qwen3-coder publishes only 30b and 480b), so the
        loader had been failing on every machine since it was introduced.

        Check before changing:
          curl -s -o /dev/null -w '%{http_code}\n' \
            https://registry.ollama.ai/v2/library/<name>/manifests/<tag>

        The default is deliberately a small model: it is what an unremarkable
        laptop can run without a dedicated GPU. Machines with VRAM to spare
        should say so explicitly in their own settings.
      '';
    };

    interface.options.contextLength = lib.mkOption {
      type        = lib.types.nullOr lib.types.ints.positive;
      default     = null;
      example     = 32768;
      description = ''
        Value for `OLLAMA_CONTEXT_LENGTH`, or null to leave it unset.

        Leave it unset and ollama derives the context PER MODEL, so the tag in
        `models` above silently sets the context window for every client with
        no diff that shows it.  Measured 2026-08-25: `qwen3-coder:30b` → 32768,
        `qwen2.5-coder:7b` → 4096.

        That matters because exceeding the window is NOT an error.  Ollama
        truncates the prompt to roughly num_ctx/2, KEEPS THE TAIL, discards the
        head — which is where the system message and the tool definitions live
        — and returns HTTP 200 with no flag set anywhere in the response.
        Measured: a 17,083-token prompt became 4,098 at num_ctx=8192, tool
        calling went 0/6, and the model answered a question about the discarded
        head by INVENTING a placeholder-shaped MAC address.  Reading the config
        back would have shown `num_ctx: 8192` and told you nothing; the only
        way to catch it is to measure the thing itself.

        So pin it explicitly, per machine.  It is sized against VRAM, not
        against taste: 32768 is right for ernst's 24 GiB 7900 XTX and would be
        wrong for an iGPU running out of shared system RAM.
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

        `q8_0` is what makes a 65536 context fit in the 7900 XTX's 24 GiB at
        all — measured 22482 MiB fully resident, versus 24471 MiB and a spill
        to system RAM on f16 — for about 11% of decode speed.  Flash attention
        ALONE saves nothing (measured identical to baseline); it is the
        enabler, not the saving.

        WEIGH THIS AGAINST THE TOOL-CALL COST, which is real and was measured
        on 2026-08-26 only because Phase 0 had measured VRAM and tool calling
        in separate runs and never together:

          KV     baseline system prompt    reinforced system prompt
          f16    83%, 83%                  100%
          q8_0   40%, 36%                  100%

        Interleaved, n=30 per arm, same prompt and context throughout.  **q8_0
        roughly halves tool-call reliability unless the client's system prompt
        explicitly demands the `<tool_call>` wrapper** — see local-ai.md for
        why that one tag is the whole failure.  With that reinforcement in
        place the KV type stops mattering and q8_0 is free.  Without it, this
        setting quietly trades agent reliability for VRAM.
      '';
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

    interface.options.remoteClients.enable = lib.mkEnableOption ''
      accepting SSH port-forwards from clan machines that have no usable local
      ollama (see the opencode role's `tunnel` option)

      This does NOT put ollama on the network. The daemon stays bound to
      loopback; what this authorises is one dedicated key, restricted to
      forwarding a single loopback port and nothing else — no shell, no pty,
      no agent or X11 forwarding
    '';

    perInstance = { settings, ... }: {
      nixosModule = { config, pkgs, lib, ... }:
        let
          # Read the client's public half straight out of the repo rather than
          # declaring the generator here too. Declaring it on both ends makes
          # the two `files` sets differ, and clan rejects a shared generator
          # whose definitions diverge between machines. Same pattern, and the
          # same reason, as modules/nix-remote-builder.nix.
          tunnelPubKeyPath =
            config.clan.core.settings.directory
            + "/vars/shared/ollama-tunnel-ssh/tunnel_ed25519.pub/value";

          # Absent until the client's `clan vars generate` has run. Degrade
          # quietly: a machine that cannot evaluate would wedge unrelated clan
          # operations across the whole flake.
          tunnelPubKey =
            if builtins.pathExists tunnelPubKeyPath then
              lib.removeSuffix "\n" (builtins.readFile tunnelPubKeyPath)
            else
              null;
        in
        {

        # `restrict` turns everything off, including port forwarding; the
        # `port-forwarding` that follows turns exactly that back on, and
        # `permitopen` narrows it to the one destination. The result grants a
        # forward to loopback:11434 and nothing else — notably not a shell.
        users.users.root.openssh.authorizedKeys.keys =
          lib.optionals (settings.remoteClients.enable && tunnelPubKey != null) [
            ''restrict,port-forwarding,permitopen="127.0.0.1:11434" ${tunnelPubKey}''
          ];

        warnings = lib.optional (settings.remoteClients.enable && tunnelPubKey == null) ''
          local-ai: remoteClients is enabled on this machine but
          vars/shared/ollama-tunnel-ssh/tunnel_ed25519.pub does not exist yet,
          so no key has been authorised and the tunnel will be refused. Run
          `clan vars generate <the client machine>`, then redeploy this one.
        '';

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
          } // lib.optionalAttrs (settings.contextLength != null) {
            OLLAMA_CONTEXT_LENGTH = toString settings.contextLength;
          } // lib.optionalAttrs (settings.kvCacheType != null) {
            # Flash attention is the prerequisite for a quantised KV cache, so
            # it is set here rather than exposed as a separate knob that could
            # be forgotten.  On its own it is a measured no-op.
            OLLAMA_FLASH_ATTENTION = "1";
            OLLAMA_KV_CACHE_TYPE   = settings.kvCacheType;
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

          # The models directory must exist before ollama.service starts.
          #
          # nixpkgs' ollama module puts `cfg.models` (= <home>/models) in
          # ReadWritePaths, and systemd refuses to set up the unit's mount
          # namespace when a ReadWritePaths entry is missing:
          #
          #   ollama.service: Failed to set up mount namespacing:
          #     /var/lib/ollama/models: No such file or directory
          #   status=226/NAMESPACE
          #
          # StateDirectory=ollama creates /var/lib/ollama but not the subdir,
          # and nothing else did either: while the persist bind mount was
          # broken (see the symlink note above) ollama had been writing into
          # /var/lib/private/ollama instead, so the persisted directory was
          # never populated. Repairing the mount exposed that it was empty and
          # ollama stopped starting — a latent problem, not a new one.
          #
          # tmpfiles runs after local-fs.target, so this lands inside the
          # persist bind mount rather than under it. Mode matches the 0700 the
          # persist entry declares for the parent.
          "d /var/lib/ollama/models 0700 ollama ollama -"
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

        # Clear the DynamicUser-era symlink before the bind mount runs.
        #
        # While ollama ran under DynamicUser, systemd owned /var/lib/ollama as
        # a *symlink* to private/ollama.  Turning DynamicUser off (above) stops
        # anything from recreating it, but does not remove the one already on
        # disk — and systemd refuses to mount onto a path that traverses a
        # symlink:
        #
        #   var-lib-ollama.mount: Mount path /var/lib/ollama is not canonical
        #     (contains a symlink).
        #   Failed to mount /var/lib/ollama.
        #
        # The mount then fails on every single boot and every `nixos-rebuild
        # switch` exits 4, while ollama quietly writes to the unpersisted
        # /var/lib/private/ollama instead of the persisted directory.
        #
        # On a machine whose root really is rolled back each boot this would
        # clear itself after one reboot.  ernst's does not — zroot/root@blank
        # has never been created, so the rollback in
        # modules/zfs-impermanence.nix is a silent no-op (it ends in `|| true`)
        # and the stale symlink survives indefinitely.  Hence a unit rather
        # than a one-off manual `rm`.
        #
        # Ordering mirrors the mount unit itself, which impermanence generates
        # with DefaultDependencies=false and Before=local-fs.target; this has
        # to be earlier still.  Deliberately narrow: it removes the path only
        # when it is a symlink, so a real directory — the normal case, and the
        # one that could hold models — is never touched.
        systemd.services.ollama-statedir-canonicalize = {
          description = "Remove stale /var/lib/ollama symlink before its bind mount";
          wantedBy    = [ "var-lib-ollama.mount" ];
          before      = [ "var-lib-ollama.mount" ];
          unitConfig.DefaultDependencies = false;
          serviceConfig = {
            Type            = "oneshot";
            RemainAfterExit = true;
            ExecStart = pkgs.writeShellScript "ollama-statedir-canonicalize" ''
              if [ -L /var/lib/ollama ]; then
                echo "removing stale symlink /var/lib/ollama -> $(readlink /var/lib/ollama)"
                rm -f /var/lib/ollama
              fi
            '';
          };
        };
      };
    };
  };


  # ── OpenCode coding agent ──────────────────────────────────────────────────
  roles.opencode = {
    description = "OpenCode CLI coding agent, pointed at a local or tunnelled Ollama endpoint.";

    interface.options = {
      user = lib.mkOption {
        type        = lib.types.str;
        default     = "lgo";
        description = "Home Manager user to install OpenCode for.";
      };
      model = lib.mkOption {
        type        = lib.types.str;
        default     = "ollama/qwen2.5-coder:7b";
        description = ''
          Default model, as `<provider-id>/<ollama tag>`. The provider id is
          always `ollama` here — it is the key this role writes into
          `provider` in OpenCode's config.

          Must name a model the endpoint's ollama role actually pulls, or
          OpenCode asks for something that was never fetched. miralda's ollama
          pulls `qwen2.5-coder:7b`; ernst's pulls `qwen3-coder:30b`.
        '';
      };

      tunnel = {
        enable = lib.mkEnableOption ''
          reaching a REMOTE ollama over an SSH port-forward instead of a local
          one. For machines with no GPU worth the name, or none ollama can use

          ollama on the far end is not, and should not be, exposed on the
          network: `services.ollama` binds 127.0.0.1 and
          machines/ernst/networking.nix records that deliberately ("M11 changes
          ernst's attack surface not at all"). A forward keeps that true — the
          listener stays loopback-only on both ends
        '';

        remoteHost = lib.mkOption {
          type        = lib.types.str;
          default     = "ernst.skynet.lan";
          description = "Host running the ollama this machine should talk to.";
        };

        remoteUser = lib.mkOption {
          type        = lib.types.str;
          default     = "root";
          description = ''
            User to authenticate as on the far end. root, because that is
            whose `authorized_keys` the ollama role writes the tunnel key
            into — and the key is restricted to one forward, so it grants no
            shell (see the ollama role's `remoteClients` option).
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
            context and believes the answer. The port is uniform across the
            fleet for the same reason: one number to check, everywhere.

            Sanity check what you reached:
              curl -s localhost:11435/api/tags | jq -r '.models[].name'
          '';
        };

        remotePort = lib.mkOption {
          type        = lib.types.port;
          default     = 11434;
          description = "Port ollama listens on (loopback) at the far end.";
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
            The far end's SSH host public key, pinned so the tunnel never has
            to TOFU. Mirrors
            `vars/per-machine/ernst/openssh/ssh.id_ed25519.pub/value` — the
            same value `clanarchy.remoteBuilder.hostPublicKey` pins, and it
            has to be updated in both places if ernst's host key is ever
            regenerated.
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

          # The one instruction that decides whether tool calling works at all
          # against qwen3-coder. The model drops the OPENING <tool_call> tag
          # while still emitting the closing one, ollama's parser matches the
          # literal string, and the whole call is emitted as prose with
          # `tool_calls: null`. Measured 5/40 valid calls at baseline, 80/80
          # with this line, under both KV cache types.
          #
          # It is not optional on ernst: that instance runs `kvCacheType =
          # "q8_0"`, which halves tool-call reliability at a baseline system
          # prompt (40%/36% vs f16's 83%/83%) and costs nothing once this is
          # sent. The full measurement is in the kvCacheType option
          # description and in local-ai.md.
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
              # whole block and fell through to its own defaults, which is why
              # this never worked.
              xdg.configFile."opencode/config.json".text = builtins.toJSON {
                "$schema" = "https://opencode.ai/config.json";
                model = settings.model;
                provider.ollama = {
                  # Ollama's /v1 surface is OpenAI-compatible, so the generic
                  # OpenAI-compatible driver is the right one; there is no
                  # ollama-specific npm package to name here.
                  npm = "@ai-sdk/openai-compatible";
                  name = "Ollama (${if settings.tunnel.enable then settings.tunnel.remoteHost else "local"})";
                  options = { inherit baseURL; };
                  # Declaring the model explicitly matters: this provider has
                  # no model catalogue for opencode to discover, so an
                  # undeclared tag is not selectable even when ollama has it.
                  models.${lib.removePrefix "ollama/" settings.model} = { };
                };
                instructions = [ "${toolCallRule}" ];
              };
            };
          }

          # ── SSH forward to a remote ollama ──────────────────────────────
          (lib.mkIf settings.tunnel.enable {

            # Dedicated keypair, generated as a SHARED var so the far end can
            # read the public half straight out of the repo. Declared by the
            # CLIENT only — declaring it on both ends makes the two `files`
            # sets differ, and clan rejects a shared generator whose
            # definitions diverge between machines, which blocks every
            # install/update in the flake rather than just this one. Same
            # pattern, and the same reasoning, as
            # modules/nix-remote-builder.nix.
            #
            # It cannot reuse the remote-builder key: that one is authorised
            # on ernst with `command="nix-daemon --stdio",restrict`, and
            # `restrict` drops port forwarding.
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
              description = "SSH port-forward to ${settings.tunnel.remoteHost}'s ollama";
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
