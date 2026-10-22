##############################################################################
# roles.opencode — the CLI agent
##############################################################################
{lib, ...}: {
  description = "OpenCode CLI coding agent, pointed at one or more OpenAI-compatible endpoints (local, tunnelled, or both).";

  interface.options = {
    user = lib.mkOption {
      type = lib.types.str;
      default = "lgo";
      description = "Home Manager user to install OpenCode for.";
    };
    providers = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          id = lib.mkOption {
            type = lib.types.str;
            description = "Provider id, as written into OpenCode's `provider` attrset.";
          };
          label = lib.mkOption {
            type = lib.types.str;
            description = "Name OpenCode shows for this endpoint in its model picker.";
          };
          port = lib.mkOption {
            type = lib.types.port;
            description = ''
              Loopback port this endpoint's OpenAI-compatible surface answers
              on — `tunnel.localPort` for the remote one, the backend's own
              port for a local one.

              Per provider rather than derived: the local branch used to
              hardcode 11434 and so could not follow `roles.inference.port`.
            '';
          };
          models = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            description = ''
              Models this endpoint serves, under the names it serves them by.

              Not optional: the OpenAI-compatible driver has no catalogue for
              OpenCode to discover, so an undeclared name is unselectable even
              when the server has it.  A name here must be a key in the
              endpoint's `roles.models` (or an ollama tag, for an ollama
              backend) — it is no longer required to be an ollama registry
              TAG, which is the class of mistake that put `qwen3-coder:8b` —
              a tag that has never existed — into a restart loop for months.

                curl -s localhost:<port>/v1/models | jq -r '.data[].id'
            '';
          };
        };
      });
      default = [];
      description = ''
        Endpoints OpenCode can reach, in preference order.

        A SECOND ENTRY IS THE FALLBACK, AND IT IS A MANUAL ONE.  OpenCode
        reads one `model` at startup and has no automatic failover, so what a
        second provider buys is that `/models` in the TUI is a recovery step
        rather than a dead end.  `ai-status` says which endpoints answer.
      '';
    };

    defaultModel = lib.mkOption {
      type = lib.types.str;
      example = "ernst/qwen3.6-35b-a3b";
      description = ''
        Model OpenCode starts on, as `<provider id>/<model>`.  Must name a
        `providers` entry and one of its `models`; asserted, because the
        symptom otherwise is a 404 from a server three layers away.
      '';
    };

    contextBudgetTokens = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1000;
      description = ''
        Ceiling, in tokens, on the context govim's opencode.nvim integration
        will inject into a prompt (`vim.g.opencode_context_budget_tokens`).
        Over budget it REFUSES to send, which is the point: this is SN1's
        fail-closed guard.

        IT IS PER MACHINE, NOT PER PROVIDER, and there is only one of it.  So
        on a machine with both a 32768 endpoint and a 4096 fallback, a budget
        sized for the former will be silently truncated by the latter —
        ollama answers an over-long prompt HTTP 200 with the HEAD discarded
        (system prompt and tool definitions first) and then fabricates
        plausibly.  llama.cpp answers 400 instead, so the hazard is the
        fallback's alone.

        Set it against the endpoint you actually work on, and re-check it
        when `contextLength` or `roles.models` moves.  Reference points:
        govim's default is 1000, sized for a 4096 window; its own working
        diff measures ~2521 estimated tokens.
      '';
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
        type = lib.types.str;
        default = "ernst.skynet.lan";
        description = "Host running the inference server this machine should talk to.";
      };

      remoteUser = lib.mkOption {
        type = lib.types.str;
        default = "root";
        description = ''
          User to authenticate as on the far end. root, because that is whose
          `authorized_keys` the inference role writes the tunnel key into —
          and the key is restricted to one forward, so it grants no shell.
        '';
      };

      localPort = lib.mkOption {
        type = lib.types.port;
        default = 11435;
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
        type = lib.types.port;
        default = 11434;
        description = ''
          Port the inference server listens on (loopback) at the far end.
          Must match the inference role's `port`, which is also what its
          `permitopen` restriction names.
        '';
      };

      hostNames = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["ernst" "ernst.skynet.lan" "10.0.50.10"];
        description = "Names/addresses the pinned host key below is valid for.";
      };

      hostPublicKey = lib.mkOption {
        type = lib.types.str;
        default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILd954KHVjUAOX06pHP/+ou78tpo6OYKMQL2ew3eUqEt";
        description = ''
          The far end's SSH host public key, pinned so the tunnel never has to
          TOFU. Mirrors `vars/per-machine/ernst/openssh/ssh.id_ed25519.pub/value`
          — the same value `clanarchy.remoteBuilder.hostPublicKey` pins, and it
          has to be updated in both places if ernst's host key is regenerated.
        '';
      };
    };
  };

  perInstance = {settings, ...}: {
    nixosModule = {
      config,
      pkgs,
      pkgs-unstable,
      lib,
      ...
    }: let
      gen = config.clan.core.vars.generators.ollama-tunnel-ssh;

      # Is govim actually in this user's HM generation?
      #
      # modules/users/lgo.nix imports the nvf module only when
      # `clanarchy.users.<user>.editor = "govim"`, and setting an
      # UNDECLARED option is an eval error — so flipping that one line to
      # "helix" would otherwise break every deploy of this machine, a trap
      # laid by a role with no business knowing which editor is selected.
      #
      # The `or null` also covers a user who has no editor option at all
      # (nobody today, but this role's `user` is a free-form string).
      #
      # Checked here on NixOS config and NOT with `options ? programs.nvf`
      # inside the HM module: using `options` to decide a module's own
      # attribute structure is infinite recursion, because the structure
      # is an input to collecting the options being queried.
      govimActive =
        (config.clanarchy.users.${settings.user}.editor or null) == "govim";

      # One `provider.<id>` entry per endpoint.  llama-swap's and ollama's
      # /v1 surfaces are both OpenAI-compatible, so the generic driver is
      # the right one for either.
      providerAttrs = lib.listToAttrs (map (p:
        lib.nameValuePair p.id {
          npm = "@ai-sdk/openai-compatible";
          name = p.label;
          options.baseURL = "http://127.0.0.1:${toString p.port}/v1";
          models = lib.genAttrs p.models (_: {});
        })
      settings.providers);

      declaredModels =
        lib.concatMap (p: map (m: "${p.id}/${m}") p.models) settings.providers;

      # Which endpoints are up, as one command.  Falling back is `/models`
      # in the TUI; this is how you know you need to.
      aiStatus = pkgs.writeShellApplication {
        name = "ai-status";
        runtimeInputs = [pkgs.curl pkgs.jq];
        text =
          lib.concatMapStrings (p: ''
            printf '%-8s 127.0.0.1:%-6s ' ${lib.escapeShellArg p.id} ${toString p.port}
            if out=$(curl -fs --max-time 3 "http://127.0.0.1:${toString p.port}/v1/models" 2>/dev/null); then
              printf 'up    %s\n' "$(printf '%s' "$out" | jq -r '[.data[].id] | join(", ")')"
            else
              printf 'DOWN\n'
            fi
          '')
          settings.providers;
      };

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
          assertions = [
            {
              assertion = settings.providers != [];
              message = ''
                roles.opencode on this machine declares no providers, so
                OpenCode would be installed pointing at nothing.
              '';
            }
            {
              assertion = lib.elem settings.defaultModel declaredModels;
              message =
                "roles.opencode: defaultModel \"${settings.defaultModel}\" names no"
                + " declared provider/model. Declared: "
                + lib.concatStringsSep ", " declaredModels;
            }
          ];

          # FROM UNSTABLE, DELIBERATELY, and this is the copy that wins: nvf
          # APPENDS to $PATH (mnw does `PATH = PATH .. ":" .. extraBinPath`),
          # so a system-wide opencode always shadows the one govim bundles.
          # clan-core's 26.05 pin carries 1.15.10 against opencode.nvim
          # 0.14.0's tested 1.17.4, so this line is the only place the
          # version can be chosen.
          environment.systemPackages = [pkgs-unstable.opencode aiStatus];

          home-manager.users.${settings.user} = {lib, ...}:
            {
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
                model = settings.defaultModel;
                provider = providerAttrs;
                instructions = ["${toolCallRule}"];
              };
            }
            # ── Context budget for govim's opencode.nvim integration ────────
            # See `govimActive` above for why this is conditional.
            // lib.optionalAttrs govimActive {
              # mkForce, and it is not optional: govim sets this global to a
              # bare `1000`, NOT `mkDefault`, so any value from here is a
              # merge CONFLICT rather than an override. Without mkForce the
              # deploy fails outright on jens — and would keep "working" on
              # miralda only because 1000 happens to equal 1000, which is the
              # kind of coincidence that hides the breakage until the day
              # someone raises the budget.
              programs.nvf.settings.vim.globals.opencode_context_budget_tokens =
                lib.mkForce settings.contextBudgetTokens;
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
              owner = "root";
              group = "root";
              mode = "0400";
            };
            files."tunnel_ed25519.pub".secret = false;

            runtimeInputs = [pkgs.openssh];
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
            after = ["network-online.target"];
            wants = ["network-online.target"];
            wantedBy = ["multi-user.target"];

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
              Restart = "always";
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
}
