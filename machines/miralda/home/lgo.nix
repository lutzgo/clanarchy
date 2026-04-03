{ pkgs, inputs, ... }:
{
  home.username = "lgo";
  home.homeDirectory = "/home/lgo";
  home.stateVersion = "25.11";

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
      $env.EDITOR = "hx"
      $env.VISUAL = "hx"
    '';
  };

  programs.zsh = {
    enable = true;
    # Vi mode — insert mode with Ctrl+e as ergonomic escape
    initContent = ''
      bindkey -v
      export KEYTIMEOUT=1
      bindkey -M viins 'C-e' vi-cmd-mode
      export EDITOR=hx
      export VISUAL=hx
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
  # through to the terminal by default; Alt+g unlocks to normal mode.
  xdg.configFile."zellij/config.kdl".text = ''
    default_mode "locked"
    default_shell "nu"
    pane_frames false
    simplified_ui false
    session_serialization false
    show_release_notes false
    default_layout "compact"

    keybinds {
        // Locked: every key passes through; only Alt+g unlocks
        locked clear-defaults=true {
            bind "Alt g" { SwitchToMode "Normal"; }
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
            bind "Alt z"         { ToggleFocusFullscreen; }
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

            // Return to locked mode
            bind "Alt g" { SwitchToMode "Locked"; }
        }

        // Scroll mode: vim-style navigation, search, and copy
        scroll clear-defaults=true {
            bind "j"      { ScrollDown; }
            bind "k"      { ScrollUp; }
            bind "d"      { HalfPageScrollDown; }
            bind "u"      { HalfPageScrollUp; }
            bind "/"      { SwitchToMode "EnterSearch"; SearchInput 0; }
            bind "e"      { EditScrollback; SwitchToMode "Normal"; }
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

  home.packages = with pkgs; [
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
  ];
}
