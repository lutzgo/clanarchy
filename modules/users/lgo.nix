{ config, lib, pkgs, inputs, pkgs-unstable, ... }:
{
  options.clanarchy.users.lgo.enable =
    lib.mkEnableOption "lgo power user profile (Niri, browsers, devtools, Noctalia)";

  config = lib.mkIf config.clanarchy.users.lgo.enable {

    # Niri desktop — required for lgo's HM desktop module
    clanarchy.desktop.niri.enable = lib.mkDefault true;

    users.users.lgo = {
      isNormalUser = true;
      extraGroups  = [ "wheel" "networkmanager" "video" "audio" "input" ];
      shell        = pkgs.nushell;
      hashedPasswordFile = config.clan.core.vars.generators.lgo-password.files."hashed-password".path;
      openssh.authorizedKeys.keys = [
        (builtins.readFile ../../machines/miralda/clanarchy_admin.pub)
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
        ];

        home.username      = "lgo";
        home.homeDirectory = "/home/lgo";
        home.stateVersion  = "25.11";

        home.sessionVariables = {
          EDITOR = "hx";
          VISUAL = "hx";
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
          enable               = true;
          enableZshIntegration = true;
        };

        programs.helix = {
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

                  bind "Alt e" { Run "hx" "." { close_on_exit true; direction "Right"; }; }
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
          run = "open --with hx"
          desc = "Open in Helix"

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

        home.packages = [ fzf-zellij ] ++ (with pkgs; [
          htop
          ripgrep
          fd

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
