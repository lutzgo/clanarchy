{ pkgs, inputs, config, ... }:
let
  c = config.lib.stylix.colors;

  # zjstatus — custom status bar (from flake input)
  zjstatus-wasm = "${inputs.zjstatus.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/zjstatus.wasm";

  # zellij-autolock — auto lock/unlock based on running process
  zellij-autolock = pkgs.fetchurl {
    url = "https://github.com/fresh2dev/zellij-autolock/releases/download/0.2.2/zellij-autolock.wasm";
    sha256 = "194fgd421w2j77jbpnq994y2ma03qzdlz932cxfhfznrpw3mdjb9";
  };

  # fzf-zellij — fzf in floating Zellij panes
  fzf-zellij-src = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/k-kuroguro/fzf-zellij/main/bin/fzf-zellij";
    sha256 = "00xbfr53czs511151xfim13w8syrgpsqy8kkl7y3cbklggr4ammn";
  };
  fzf-zellij = pkgs.writeShellScriptBin "fzf-zellij" (builtins.readFile fzf-zellij-src);
in
{
  home.username = "lgo";
  home.homeDirectory = "/home/lgo";
  home.stateVersion = "25.11";

  # Session-level env vars — inherited by Zellij, niri, and all child processes
  home.sessionVariables = {
    EDITOR = "hx";
    VISUAL = "hx";
  };

  programs.git = {
    enable = true;
    # GPG commit signing via YubiKey
    signing.signByDefault = true;
    settings = {
      user.name  = "Lutz Go";
      user.email = "lutz0go@gmail.com";
      gpg.program = "gpg2";
    };
  };

  # GitHub CLI — auth token stored in ~/.config/gh/ (persisted via impermanence).
  # Run `gh auth login` once to authenticate; subsequent reboots retain the token.
  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "https";
      prompt       = "enabled";
    };
  };

  # Standard XDG user directories.  createDirectories = true ensures they exist
  # after each ZFS rollback (HM recreates them on activation).
  xdg.userDirs = {
    enable                = true;
    createDirectories     = true;
    # Keep session vars (XDG_DOCUMENTS_DIR etc.) in the environment.
    # Explicit true silences the stateVersion-based deprecation warning.
    setSessionVariables   = true;
  };

  # Nushell — primary login shell.  Zsh stays available for compatibility
  # (helix :sh, scripts, fallback logins).
  programs.nushell = {
    enable = true;
    # Suppress the startup banner (equivalent to zsh's no MOTD).
    extraConfig = ''
      $env.config.show_banner = false
    '';
  };

  programs.zsh = {
    enable = true;
    # Vi mode — insert mode with Ctrl+e as ergonomic escape
    initContent = ''
      bindkey -v
      export KEYTIMEOUT=1
      bindkey -M viins 'C-e' vi-cmd-mode
    '';
  };

  # fzf — history search (Ctrl+r), file search (Ctrl+t), cd (Alt+c)
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    # No enableNushellIntegration in this HM version; fzf keybindings are
    # zsh/bash-specific anyway (Ctrl+r in nushell uses built-in history).
  };

  programs.helix = {
    enable = true;
    settings = {
      editor.shell = [ "zsh" "-c" ];  # used for :sh, :pipe, :run-shell-command
      keys.normal = {
        # Pane/split navigation — must match Zellij passthrough (Ctrl+hjkl)
        "C-h" = "jump_view_left";
        "C-j" = "jump_view_down";
        "C-k" = "jump_view_up";
        "C-l" = "jump_view_right";
        # Space leader bindings (space+f is Helix default file picker — kept here for clarity)
        space = {
          f = "file_picker";
          b = "buffer_picker";
          "/" = "global_search";
          # Spawn external tools; & runs in background so Helix is not blocked
          e = ":sh foot -e yazi &";
          g = ":sh foot -T lazygit -e lazygit &";
        };
      };
    };
  };

  # Zellij — multiplexer config written as raw KDL (HM programs.zellij.settings
  # can't express complex keybind trees). default_mode=locked means all keys pass
  # through to the terminal by default; autolock plugin handles mode switching
  # when helix/fzf/yazi run. Colors injected from Stylix.
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
        // Locked: every key passes through
        // Alt+g = re-enable autolock + unlock (autolock manages modes again)
        // Alt+z = disable autolock + unlock (stay in normal regardless of triggers)
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

        // Normal: Alt owns all Zellij actions; Ctrl+hjkl are NOT bound here
        // so they pass through to Helix unmodified
        normal clear-defaults=true {
            // Pane focus
            bind "Alt h" { MoveFocus "Left"; }
            bind "Alt j" { MoveFocus "Down"; }
            bind "Alt k" { MoveFocus "Up"; }
            bind "Alt l" { MoveFocus "Right"; }

            // Pane management
            bind "Alt n"         { NewPane "Right"; }
            bind "Alt Shift n"   { NewPane "Down"; }
            bind "Alt x"         { CloseFocus; }
            bind "Alt Shift z"   { ToggleFocusFullscreen; }
            bind "Alt Tab"       { FocusNextPane; }

            // Launch programs in a new pane (Run opens pane with given command)
            bind "Alt e" { Run "hx" "." { close_on_exit true; direction "Right"; }; }
            bind "Alt f" { Run "yazi"   { close_on_exit true; direction "Right"; }; }
            bind "Alt t" { NewPane "Right"; }

            // Tab navigation (Alt+1-9)
            bind "Alt 1" { GoToTab 1; }
            bind "Alt 2" { GoToTab 2; }
            bind "Alt 3" { GoToTab 3; }
            bind "Alt 4" { GoToTab 4; }
            bind "Alt 5" { GoToTab 5; }
            bind "Alt 6" { GoToTab 6; }
            bind "Alt 7" { GoToTab 7; }
            bind "Alt 8" { GoToTab 8; }
            bind "Alt 9" { GoToTab 9; }

            // Scroll / search / copy
            bind "Alt s" { SwitchToMode "Scroll"; }

            // Session
            bind "Alt d" { Detach; }
            bind "Alt r" { SwitchToMode "RenameTab"; }

            // Re-trigger autolock check (e.g. after pressing Enter in shell)
            bind "Enter" {
                WriteChars "\u{000D}";
                MessagePlugin "autolock" {};
            }

            // Return to locked mode (disable autolock so it doesn't immediately unlock)
            bind "Alt g" {
                MessagePlugin "autolock" { payload "disable"; };
                SwitchToMode "Locked";
            }
        }

        // Scroll mode: vim-style navigation, search, and copy
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

        // Minimal rename-tab mode: confirm with Enter, cancel with Esc
        renametab clear-defaults=true {
            bind "Enter" { SwitchToMode "Normal"; }
            bind "Esc"   { UndoRenameTab; SwitchToMode "Normal"; }
        }
    }
  '';

  # Zellij plugins — WASM files installed to ~/.config/zellij/plugins/
  xdg.configFile."zellij/plugins/zjstatus.wasm".source = zjstatus-wasm;
  xdg.configFile."zellij/plugins/zellij-autolock.wasm".source = zellij-autolock;

  # Zellij layout — zjstatus bar at bottom, replaces compact layout
  xdg.configFile."zellij/layouts/default.kdl".text = ''
    layout {
        default_tab_template {
            children
            pane size=1 borderless=true {
                plugin location="file:~/.config/zellij/plugins/zjstatus.wasm" {
                    format_left  "{mode}#[fg=#${c.base0D},bg=#${c.base00}]#[fg=#${c.base00},bg=#${c.base0D},bold] {session} #[fg=#${c.base0D},bg=#${c.base00}]"
                    format_center "{tabs}"
                    format_right "#[fg=#${c.base03},bg=#${c.base00}]#[fg=#${c.base05},bg=#${c.base03}] {datetime}"
                    format_space "#[bg=#${c.base00}]"

                    hide_frame_for_single_pane "true"
                    border_enabled "false"

                    mode_normal       "#[fg=#${c.base0D},bg=#${c.base00}]#[fg=#${c.base00},bg=#${c.base0D},bold] NORMAL #[fg=#${c.base0D},bg=#${c.base00}]"
                    mode_locked       "#[fg=#${c.base0B},bg=#${c.base00}]#[fg=#${c.base00},bg=#${c.base0B},bold] LOCKED #[fg=#${c.base0B},bg=#${c.base00}]"
                    mode_scroll       "#[fg=#${c.base0A},bg=#${c.base00}]#[fg=#${c.base00},bg=#${c.base0A},bold] SCROLL #[fg=#${c.base0A},bg=#${c.base00}]"
                    mode_search       "#[fg=#${c.base09},bg=#${c.base00}]#[fg=#${c.base00},bg=#${c.base09},bold] SEARCH #[fg=#${c.base09},bg=#${c.base00}]"
                    mode_enter_search "#[fg=#${c.base09},bg=#${c.base00}]#[fg=#${c.base00},bg=#${c.base09},bold] SEARCH #[fg=#${c.base09},bg=#${c.base00}]"
                    mode_rename_tab   "#[fg=#${c.base0E},bg=#${c.base00}]#[fg=#${c.base00},bg=#${c.base0E},bold] RENAME #[fg=#${c.base0E},bg=#${c.base00}]"

                    tab_normal "#[fg=#${c.base03},bg=#${c.base00}]#[fg=#${c.base05},bg=#${c.base03}] {index}  {name} #[fg=#${c.base03},bg=#${c.base00}]"
                    tab_active "#[fg=#${c.base0D},bg=#${c.base00}]#[fg=#${c.base00},bg=#${c.base0D},bold,italic] {index}  {name} #[fg=#${c.base0D},bg=#${c.base00}]"

                    datetime "#[fg=#${c.base05},bg=#${c.base03},bold] {format} "
                    datetime_format "%H:%M"
                    datetime_timezone "Europe/Berlin"
                }
            }
        }
    }
  '';

  # Yazi — file manager keybindings (prepend so defaults are preserved)
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

  home.packages = [
    fzf-zellij
  ] ++ (with pkgs; [
    htop
    ripgrep
    fd

    # GPG / YubiKey
    gnupg
    yubikey-manager       # ykman — YubiKey configuration tool
    yubikey-personalization
    pcsc-tools             # pcsc_scan — verify card is seen

    # Age / clan secret management
    age
    ssh-to-age            # converts SSH pubkey to age recipient format
    age-plugin-yubikey    # PIV-backed age identity on YubiKey

    # Clan management
    inputs.clan-core.packages.${pkgs.stdenv.hostPlatform.system}.clan-cli
  ]);
}
