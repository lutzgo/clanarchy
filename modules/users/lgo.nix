{ config, lib, pkgs, inputs, pkgs-unstable, ... }:
let
  cfg        = config.clanarchy.users.lgo;
  editorBin  = if cfg.editor == "govim" then "nvim" else "hx";
  editorDesc = if cfg.editor == "govim" then "Neovim" else "Helix";

  # CRX install via first_run_tabs: patched chromium reads /etc/chromium/initial_preferences;
  # --extension-mime-request-handling=always-prompt-for-install (baked in clan.nix overlay).
  crxUrl = id:
    "https://clients2.google.com/service/update2/crx"
    + "?response=redirect&acceptformat=crx2,crx3"
    + "&prodversion=${pkgs.ungoogled-chromium.version}"
    + "&x=id%3D${id}%26uc";

  chromiumFirstRunTabs = [
    "https://github.com/NeverDecaf/chromium-web-store/releases/latest/download/Chromium.Web.Store.crx"
    (crxUrl "cjpalhdlnbpafiamejdnhcphjbkeiagm") # uBlock Origin
    (crxUrl "oboonakemofpalcgghocfoadofidjkkk") # KeePassXC-Browser
    (crxUrl "dbepggeogbaibhgnhhndojpepiihcmeb") # Vimium
    (crxUrl "efobhjmgoddhfdhaflheioeagkcknoji") # Vertical Tabs (nicedoc.io)
  ];
in
{
  imports = [ ../caldav-sync.nix ];

  options.clanarchy.users.lgo = {
    enable = lib.mkEnableOption "lgo power user profile (Niri, browsers, devtools, Noctalia)";
    editor = lib.mkOption {
      type    = lib.types.enum [ "govim" "helix" ];
      default = "govim";
      description = "Default editor: govim (nvf-based Neovim, Stylix-themed) or helix.";
    };
  };

  config = lib.mkIf cfg.enable {

    # nushell must be in /etc/shells for accounts-daemon to enumerate lgo.
    # Without this regreet can't pre-select them; they'd have to type the username every login.
    environment.shells = [ pkgs.nushell ];

    # CalDAV sync: push org TODOs/habits to Nextcloud as VTODO entries.
    clanarchy.caldavSync = {
      enable        = true;
      nextcloudHost = "citizengo.io";
      calendarName  = "lgorg2";
      username      = "lgo";
      orgNoteDir    = "citizengo/notes";
      syncFiles     = [ "todo.org" "habits.org" ];
      journalDir    = "citizengo/notes/journal";
    };

    # Declare nvf's vim.* option namespace for all HM users on this machine.
    # Must be at the NixOS level (sharedModules) so the options exist before
    # any per-user config (common.nix / variants) references them.
    home-manager.sharedModules = lib.optionals (cfg.editor == "govim") [ inputs.govim.homeManagerModules.nvf ];

    users.users.lgo = {
      isNormalUser = true;
      extraGroups  = [ "wheel" "networkmanager" "video" "audio" "input" ]
        # `podman` grants access to /run/docker.sock when the Docker-compatible
        # socket is enabled — required for rootless `docker compose`.
        ++ lib.optional config.clanarchy.apps.containers.enable "podman";
      shell        = pkgs.nushell;
      hashedPasswordFile = config.clan.core.vars.generators.lgo-password.files."hashed-password".path;
      openssh.authorizedKeys.keys = [
        (builtins.readFile ../../machines/miralda/clanarchy_admin.pub)
        (builtins.readFile ../../machines/miralda/yubikey_ed25519.pub)
      ];
    };

    # Clan vars: lgo password generator
    clan.core.vars.generators.lgo-password = {
      files."hashed-password" = {
        secret    = true;
        neededFor = "users";
      };
      prompts."password" = {
        description = "Password for the lgo user (used for sudo and local console login)";
        type        = "hidden";
      };
      script = ''
        ${pkgs.mkpasswd}/bin/mkpasswd -m sha-512 "$(cat "$prompts/password")" > "$out/hashed-password"
      '';
      runtimeInputs = [ pkgs.mkpasswd ];
    };

    # Impermanence paths for lgo
    environment.persistence."/persist".users.lgo = {
      directories = [
        ".gnupg"           # GPG keyring with YubiKey stubs
        ".claude"          # Claude Code credentials + session data
        ".config"          # gh auth token, noctalia/helix/zellij settings, etc.
        ".local/share"
        ".cache/noctalia"  # shell-state.json (version tracking → no wizard/changelog on rollback)
        ".cache/zellij"    # compiled WASM + plugin permission cache (avoids "Allow?" prompt on boot)
        ".local/state/nvim" # undo history, shada, swap — lost on rollback without this
        "Pictures"         # includes Wallpapers/ subdirectory
        "Documents"
        "Downloads"
        "Music"
        "Videos"
        "Desktop"
        "Projects"
        "Public"
        "citizengo"
      ];
      files = [
        ".age/yubikey-identity.txt"  # PIV-backed age identity (recipient stored in clan vars)
      ];
    };

    # claude-code is unfree; HM evaluates pkgs independently from pkgsForSystem so
    # unfree packages must live at the NixOS level (environment.systemPackages uses
    # the pkgsForSystem pkgs which has allowUnfree=true).
    environment.systemPackages = [ pkgs.claude-code ];

    # Chromium initial_preferences: prompt to install lgo's extensions on first run.
    # The privacy policies (managed/privacy.json) live in service-modules/software.nix
    # (chromium role) — they apply to all users on any machine with Chromium.
    # The extension list is lgo-specific and lives here.
    environment.etc."chromium/initial_preferences".text =
      builtins.toJSON { first_run_tabs = chromiumFirstRunTabs; };

    # Reset ~/.config/chromium/First Run on extension list change (hash in /persist).
    systemd.services.chromiumFirstRun = {
      description = "Reset Chromium first-run sentinel on extension config change";
      wantedBy    = [ "multi-user.target" ];
      after       = [ "local-fs.target" ];
      serviceConfig.Type = "oneshot";
      script = let
        hash = builtins.hashString "sha256" (builtins.toJSON chromiumFirstRunTabs);
      in ''
        HASH_FILE="/persist/chromium-config.hash"
        EXPECTED="${hash}"
        if [ ! -f "$HASH_FILE" ] || [ "$(cat "$HASH_FILE" 2>/dev/null)" != "$EXPECTED" ]; then
          for d in /home/*; do
            rm -f "$d/.config/chromium/First Run"
          done
          echo "$EXPECTED" > "$HASH_FILE"
        fi
      '';
    };

    # Home Manager configuration
    home-manager.extraSpecialArgs = { inherit inputs pkgs-unstable; };
    home-manager.users.lgo =
      { pkgs, inputs, config, lib, ... }:
      let
        c = config.lib.stylix.colors;

        zjstatus-wasm = "${inputs.zjstatus.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/zjstatus.wasm";

        zellij-autolock = pkgs.fetchurl {
          url    = "https://github.com/fresh2dev/zellij-autolock/releases/download/0.2.2/zellij-autolock.wasm";
          sha256 = "194fgd421w2j77jbpnq994y2ma03qzdlz932cxfhfznrpw3mdjb9";
        };

        fzf-zellij-src = pkgs.fetchurl {
          url    = "https://raw.githubusercontent.com/k-kuroguro/fzf-zellij/main/bin/fzf-zellij";
          sha256 = "00xbfr53czs511151xfim13w8syrgpsqy8kkl7y3cbklggr4ammn";
        };
        fzf-zellij = pkgs.writeShellScriptBin "fzf-zellij" (builtins.readFile fzf-zellij-src);
      in
      {
        imports = [
          # Browser stack: ungoogled-chromium, librewolf config, firefox+arkenfox,
          # google-chrome, and KeePassXC native messaging for all four browsers.
          ../../machines/miralda/home-modules/browsers.nix
          # Console desktop tools: aerc (TUI email), oama (Gmail OAuth2), w3m (HTML mail).
          ../../machines/miralda/home-modules/console-desktop.nix
        ];

        clanarchy.consoleDesktop.enable = true;

        home.username      = "lgo";
        home.homeDirectory = "/home/lgo";
        home.stateVersion  = "25.11";

        home.sessionVariables = {
          EDITOR = editorBin;
          VISUAL = editorBin;
        };

        # govim — configure via programs.nvf.settings (nvf's HM module namespace).
        # settings accepts the same vim.* options as nvf.lib.neovimConfiguration,
        # including imports, so we pull in govim's common + default modules directly.
        # The Stylix base16 override replaces the catppuccin-mocha hardcoded in common.nix.
        programs.nvf = lib.mkIf (cfg.editor == "govim") {
          enable = true;
          settings = {
            imports = [
              "${inputs.govim}/modules/common.nix"
              "${inputs.govim}/modules/variants/default.nix"
            ];

            # Disable catppuccin from common.nix; apply Stylix palette via nvim-base16.
            vim.theme = lib.mkForce {
              enable = false;
              name = "catppuccin";
              style = "mocha";
              transparent = false;
            };
            vim.extraPlugins = {
              base16-nvim = {
                package = pkgs.vimPlugins.base16-nvim;
              };
            };
            # nvim-base16 expects hex without '#' — Stylix provides exactly that.
            # DAG helpers from nvf (pinned via govim/nvf in flake.nix).
            vim.luaConfigRC.stylixTheme = inputs.nvf.lib.nvim.dag.entryAfter [ "basic" ] ''
              require('base16-colorscheme').setup({
                base00 = '#${c.base00}', base01 = '#${c.base01}', base02 = '#${c.base02}',
                base03 = '#${c.base03}', base04 = '#${c.base04}', base05 = '#${c.base05}',
                base06 = '#${c.base06}', base07 = '#${c.base07}', base08 = '#${c.base08}',
                base09 = '#${c.base09}', base0A = '#${c.base0A}', base0B = '#${c.base0B}',
                base0C = '#${c.base0C}', base0D = '#${c.base0D}', base0E = '#${c.base0E}',
                base0F = '#${c.base0F}',
              })
            '';
          };
        };

        programs.git = {
          enable = true;
          signing.signByDefault = false;  # disabled until GPG/YubiKey signing is verified working
          settings = {
            user.name  = "Lutz Go";
            user.email = "lutz0go@gmail.com";
            gpg.program = "gpg2";
          };
        };

        # GitHub CLI — auth token stored in ~/.config/gh/ (persisted via impermanence).
        programs.gh = {
          enable   = true;
          settings = {
            git_protocol = "https";
            prompt       = "enabled";
          };
        };

        # SSH client config — workaround for gnupg 2.4.x bug:
        # When the server advertises cert-based host keys, OpenSSH activates the
        # publickey-hostbound-v00@openssh.com extension. gnupg fails to sign with
        # card-backed ed25519 keys when this extension is active (no PKSIGN ever sent
        # to scdaemon). Two per-host overrides bypass this — either forcing plain
        # ssh-ed25519 HostKeyAlgorithms (drops the cert path so hostbound isn't
        # negotiated) or PubkeyAuthentication=unbound (opts out of the hostbound
        # extension while keeping cert host keys). See docs/yubikey-ssh-setup.md.
        programs.ssh = {
          enable = true;
          enableDefaultConfig = false;
          # ZeroTier IPs are included so that `clan machines update` (which
          # connects via ZeroTier) also picks up the override.
          settings = {
            "miralda.goclan.org fdda:106a:123a:d561:1099:93da:106a:123a" = {
              HostKeyAlgorithms = "ssh-ed25519";
            };
            "biene.local biene.skynet.lan 10.0.10.105 fdda:106a:123a:d561:1099:93da:ef5d:598c" = {
              HostKeyAlgorithms = "ssh-ed25519";
            };
            "ernst ernst.local ernst.skynet.lan 10.0.50.10 fdda:106a:123a:d561:1099:933e:4c60:711f" = {
              PubkeyAuthentication = "unbound";
            };
            # Stage-1 (initrd) sshd for remote zroot unlock.  Different sshd,
            # different host key from the running system — HostKeyAlias keeps
            # both entries in ~/.ssh/known_hosts without a "REMOTE HOST
            # IDENTIFICATION HAS CHANGED" panic on port switch.  Usage:
            #   ssh ernst-initrd systemd-tty-ask-password-agent --query
            "ernst-initrd" = {
              HostName     = "ernst.skynet.lan";
              Port         = 2222;
              User         = "root";
              HostKeyAlias = "ernst-initrd";
            };

            # Reach ernst over the ZeroTier overlay (works away from home LAN,
            # or when skynet DNS is unavailable).  HostKeyAlias points at the
            # LAN name so ~/.ssh/known_hosts stays a single entry — ernst's
            # sshd serves the same host key regardless of interface.
            #
            # PubkeyAuthentication=unbound repeats the workaround from the
            # `ernst ernst.local ernst.skynet.lan ...` pattern block above:
            # the ssh_config Host name here is literally "ernst-zt", so that
            # pattern list does not match this alias, and without the override
            # openssh negotiates publickey-hostbound-v00 which makes GnuPG
            # 2.4.x refuse to sign with the card-backed ed25519 auth key
            # ("agent refused operation").
            "ernst-zt" = {
              HostName             = "fdda:106a:123a:d561:1099:933e:4c60:711f";
              User                 = "root";
              HostKeyAlias         = "ernst.skynet.lan";
              PubkeyAuthentication = "unbound";
            };
          };
        };

        # Standard XDG user directories (recreated after each ZFS rollback by HM activation).
        xdg.userDirs = {
          enable              = true;
          createDirectories   = true;
          setSessionVariables = true;
        };

        # Nushell — primary login shell
        programs.nushell = {
          enable      = true;
          extraConfig = ''
            $env.config.show_banner = false
          '';
        };

        programs.zsh = {
          enable      = true;
          initContent = ''
            bindkey -v
            export KEYTIMEOUT=1
            bindkey -M viins 'C-e' vi-cmd-mode
          '';
        };

        programs.fzf = {
          enable                   = true;
          enableZshIntegration     = true;
          enableNushellIntegration = false;   # requires fzf ≥ 0.73; nixpkgs 26.05 is older
        };

        programs.helix = lib.mkIf (cfg.editor == "helix") {
          enable   = true;
          settings = {
            editor.shell = [ "zsh" "-c" ];
            keys.normal  = {
              "C-h" = "jump_view_left";
              "C-j" = "jump_view_down";
              "C-k" = "jump_view_up";
              "C-l" = "jump_view_right";
              space = {
                f = "file_picker";
                b = "buffer_picker";
                "/" = "global_search";
                e = ":sh foot -e yazi &";
                g = ":sh foot -T lazygit -e lazygit &";
              };
            };
          };
        };

        # Zellij — multiplexer config written as raw KDL.
        # default_mode=locked means all keys pass through to the terminal by default;
        # autolock plugin handles mode switching when helix/fzf/yazi run.
        xdg.configFile."zellij/config.kdl".text = ''
          default_mode "locked"
          default_shell "nu"
          pane_frames true
          simplified_ui false
          mouse_hover_effects false
          session_serialization false
          show_release_notes false
          show_startup_tips false
          default_layout "default"

          ui {
              pane_frames {
                  rounded_corners true
              }
          }

          plugins {
              autolock location="file:~/.config/zellij/plugins/zellij-autolock.wasm" {
                  is_enabled true
                  triggers "hx|nvim|vim|git|fzf|zoxide|yazi"
                  reaction_seconds "0.3"
                  print_to_log false
              }
          }

          load_plugins {
              autolock
          }

          themes {
              stylix {
                  fg "#${c.base05}"
                  bg "#${c.base00}"
                  black "#${c.base00}"
                  red "#${c.base08}"
                  green "#${c.base0B}"
                  yellow "#${c.base0A}"
                  blue "#${c.base0D}"
                  magenta "#${c.base0E}"
                  cyan "#${c.base0C}"
                  white "#${c.base05}"
                  orange "#${c.base09}"
              }
          }
          theme "stylix"

          keybinds {
              locked clear-defaults=true {
                  bind "Alt g" {
                      MessagePlugin "autolock" { payload "enable"; };
                      SwitchToMode "Normal";
                  }
                  bind "Alt z" {
                      MessagePlugin "autolock" { payload "disable"; };
                      SwitchToMode "Normal";
                  }
              }

              normal clear-defaults=true {
                  bind "Alt h" { MoveFocus "Left"; }
                  bind "Alt j" { MoveFocus "Down"; }
                  bind "Alt k" { MoveFocus "Up"; }
                  bind "Alt l" { MoveFocus "Right"; }

                  bind "Alt n"         { NewPane "Right"; }
                  bind "Alt Shift n"   { NewPane "Down"; }
                  bind "Alt x"         { CloseFocus; }
                  bind "Alt Shift z"   { ToggleFocusFullscreen; }
                  bind "Alt Tab"       { FocusNextPane; }

                  bind "Alt e" { Run "${editorBin}" "." { close_on_exit true; direction "Right"; }; }
                  bind "Alt f" { Run "yazi"   { close_on_exit true; direction "Right"; }; }
                  bind "Alt t" { NewPane "Right"; }

                  bind "Alt 1" { GoToTab 1; }
                  bind "Alt 2" { GoToTab 2; }
                  bind "Alt 3" { GoToTab 3; }
                  bind "Alt 4" { GoToTab 4; }
                  bind "Alt 5" { GoToTab 5; }
                  bind "Alt 6" { GoToTab 6; }
                  bind "Alt 7" { GoToTab 7; }
                  bind "Alt 8" { GoToTab 8; }
                  bind "Alt 9" { GoToTab 9; }

                  bind "Alt s" { SwitchToMode "Scroll"; }

                  bind "Alt d" { Detach; }
                  bind "Alt r" { SwitchToMode "RenameTab"; }

                  bind "Enter" {
                      WriteChars "\u{000D}";
                      MessagePlugin "autolock" {};
                  }

                  bind "Alt g" {
                      MessagePlugin "autolock" { payload "disable"; };
                      SwitchToMode "Locked";
                  }
              }

              scroll clear-defaults=true {
                  bind "j"      { ScrollDown; }
                  bind "k"      { ScrollUp; }
                  bind "d"      { HalfPageScrollDown; }
                  bind "u"      { HalfPageScrollUp; }
                  bind "/"      { SwitchToMode "EnterSearch"; SearchInput 0; }
                  bind "e"      { EditScrollback; SwitchToMode "Locked"; }
                  bind "Esc"    { SwitchToMode "Normal"; }
                  bind "Alt g"  { SwitchToMode "Locked"; }
              }

              entersearch clear-defaults=true {
                  bind "Enter"  { SwitchToMode "Search"; }
                  bind "Esc"    { SwitchToMode "Scroll"; }
              }

              search clear-defaults=true {
                  bind "j"      { ScrollDown; }
                  bind "k"      { ScrollUp; }
                  bind "n"      { Search "down"; }
                  bind "p"      { Search "up"; }
                  bind "Esc"    { SwitchToMode "Scroll"; }
                  bind "Alt g"  { SwitchToMode "Locked"; }
              }

              renametab clear-defaults=true {
                  bind "Enter" { SwitchToMode "Normal"; }
                  bind "Esc"   { UndoRenameTab; SwitchToMode "Normal"; }
              }
          }
        '';

        # Zellij plugins
        xdg.configFile."zellij/plugins/zjstatus.wasm".source    = zjstatus-wasm;
        xdg.configFile."zellij/plugins/zellij-autolock.wasm".source = zellij-autolock;

        # Zellij layout — zjstatus bar at bottom
        xdg.configFile."zellij/layouts/default.kdl".text = ''
          layout {
              default_tab_template {
                  children
                  pane size=1 borderless=true {
                      plugin location="file:~/.config/zellij/plugins/zjstatus.wasm" {
                          format_left  "{mode}#[fg=#${c.base0D},bg=#${c.base00}]#[fg=#${c.base00},bg=#${c.base0D},bold] {session} #[fg=#${c.base0D},bg=#${c.base00}]"
                          format_center "{tabs}"
                          format_right "#[fg=#${c.base03},bg=#${c.base00}]#[fg=#${c.base05},bg=#${c.base03}] {datetime}"
                          format_space "#[bg=#${c.base00}]"

                          hide_frame_for_single_pane "true"
                          border_enabled "false"

                          mode_normal       "#[fg=#${c.base0D},bg=#${c.base00}]#[fg=#${c.base00},bg=#${c.base0D},bold] NORMAL #[fg=#${c.base0D},bg=#${c.base00}]"
                          mode_locked       "#[fg=#${c.base0B},bg=#${c.base00}]#[fg=#${c.base00},bg=#${c.base0B},bold] LOCKED #[fg=#${c.base0B},bg=#${c.base00}]"
                          mode_scroll       "#[fg=#${c.base0A},bg=#${c.base00}]#[fg=#${c.base00},bg=#${c.base0A},bold] SCROLL #[fg=#${c.base0A},bg=#${c.base00}]"
                          mode_search       "#[fg=#${c.base09},bg=#${c.base00}]#[fg=#${c.base00},bg=#${c.base09},bold] SEARCH #[fg=#${c.base09},bg=#${c.base00}]"
                          mode_enter_search "#[fg=#${c.base09},bg=#${c.base00}]#[fg=#${c.base00},bg=#${c.base09},bold] SEARCH #[fg=#${c.base09},bg=#${c.base00}]"
                          mode_rename_tab   "#[fg=#${c.base0E},bg=#${c.base00}]#[fg=#${c.base00},bg=#${c.base0E},bold] RENAME #[fg=#${c.base0E},bg=#${c.base00}]"

                          tab_normal "#[fg=#${c.base03},bg=#${c.base00}]#[fg=#${c.base05},bg=#${c.base03}] {index}  {name} #[fg=#${c.base03},bg=#${c.base00}]"
                          tab_active "#[fg=#${c.base0D},bg=#${c.base00}]#[fg=#${c.base00},bg=#${c.base0D},bold,italic] {index}  {name} #[fg=#${c.base0D},bg=#${c.base00}]"

                          datetime "#[fg=#${c.base05},bg=#${c.base03},bold] {format} "
                          datetime_format "%H:%M"
                          datetime_timezone "Europe/Berlin"
                      }
                  }
              }
          }
        '';

        # Yazi — file manager keybindings
        xdg.configFile."yazi/keymap.toml".text = ''
          [[manager.prepend_keymap]]
          on  = [ "e" ]
          run = "open --with ${editorBin}"
          desc = "Open in ${editorDesc}"

          [[manager.prepend_keymap]]
          on  = [ "s" ]
          run = "shell 'foot --working-directory $PWD'"
          desc = "Open terminal here"

          [[manager.prepend_keymap]]
          on  = [ "g" ]
          run = "shell 'foot -T lazygit -e lazygit'"
          desc = "Lazygit"

          [[manager.prepend_keymap]]
          on  = [ "A" ]
          run = "select_all"
          desc = "Select all"
        '';

        # scdaemon.conf — force scdaemon to use pcscd instead of its built-in CCID driver.
        # Without disable-ccid, scdaemon tries direct libusb/CCID access first and races
        # or conflicts with pcscd, producing "No such device" even when the YubiKey is present.
        home.file.".gnupg/scdaemon.conf" = {
          force = true; # overwrite if a manual file exists from a previous workaround
          text = "disable-ccid\n";
        };

        home.packages = [ fzf-zellij ] ++ (with pkgs; [
          htop
          ripgrep
          fd

          # Terminal + shell tools
          zellij    # terminal multiplexer
          yazi      # file manager
          lazygit   # git TUI
          bat       # cat with syntax highlighting and paging

          # GPG / YubiKey
          gnupg
          yubikey-manager
          yubikey-personalization
          yubioath-flutter
          pcsc-tools

          # Age / clan secret management
          age
          ssh-to-age
          age-plugin-yubikey

          # Clan management
          inputs.clan-core.packages.${pkgs.stdenv.hostPlatform.system}.clan-cli
        ]);
      };
  };
}
