# Shared Home Manager module for any graphical user on miralda.
{ pkgs, pkgs-unstable, inputs, ... }:
{
  imports = [
    inputs.niri-flake.homeModules.config  # provides programs.niri.settings
    inputs.noctalia.homeModules.default   # provides programs.noctalia-shell option
  ];

  # Niri user config — declarative settings (niri-flake homeModules.config maps to KDL)
  # Note: niri-flake's HM module has no `enable` option; defining settings is sufficient.
  # UWSM manages the session lifecycle, so no niri-side systemd integration is needed.
  #
  # Use pkgs.niri (nixpkgs 25.11) for config.kdl validation instead of niri-flake's
  # bundled niri-stable (25.08), which fails with EMFILE in the Nix sandbox test suite.
  programs.niri = {
    package = pkgs.niri;
    settings = {
      # Framework 13 AMD — 2256x1504 panel at 1.5 scale
      outputs."eDP-1" = {
        scale = 1.25;
      };

      prefer-no-csd = true;

      layout.border.width = 1;

      input = {
        touchpad = {
          tap = true;
          natural-scroll = true;
          dwt = true;  # disable-while-typing
        };
      };

      # Global: rounded corners + 90% opacity.
      # clip-to-geometry clips the window surface itself (not just decorations) to the radius.
      # Heavy GUI apps stay fully opaque for readability.
      window-rules = [
        {
          geometry-corner-radius = {
            top-left = 8.0;
            top-right = 8.0;
            bottom-right = 8.0;
            bottom-left = 8.0;
          };
          clip-to-geometry = true;
          opacity = 0.9;
        }
        {
          matches = [
            { app-id = "^org\\.chromium\\.Chromium$"; }
            { app-id = "^chromium$"; }
            { app-id = "^org\\.gimp\\.GIMP$"; }
            { app-id = "^gimp$"; }
            { app-id = "^libreoffice"; }
            { app-id = "^soffice$"; }
          ];
          opacity = 1.0;
        }
      ];

      # All app launches prefixed with "uwsm app --" so they run as systemd units
      binds = {
        "Mod+Return".action.spawn = [ "uwsm" "app" "--" "foot" ];
        "Mod+Q".action.close-window = {};
        "Mod+Space".action.spawn = [ "uwsm" "app" "--" "fuzzel" ];
        "Mod+Shift+E".action.quit = {};
        "Mod+1".action.focus-workspace = 1;
        "Mod+2".action.focus-workspace = 2;
        "Mod+3".action.focus-workspace = 3;
        "Mod+Shift+1".action.move-window-to-workspace = 1;
        "Mod+Shift+2".action.move-window-to-workspace = 2;
        "Mod+Shift+3".action.move-window-to-workspace = 3;
      };
    };
  };

  # Noctalia shell — configured declaratively via noctalia HM module
  # systemd.enable: creates a user service that starts after graphical-session.target,
  # replacing the fragile spawn-at-startup approach (which fires too early in the session).
  programs.noctalia-shell = {
    enable = true;
    systemd.enable = true;
    # Prevent noctalia from regenerating colors.json from its built-in scheme.
    # AppThemeService calls applyScheme(predefinedScheme) on wallpaper changes —
    # including startup when the wallpaper dir is empty. With predefinedScheme = "",
    # resolveSchemePath returns an invalid path, schemeReader fails silently, and
    # the Stylix-written colors.json is left intact.
    settings.colorSchemes.predefinedScheme = "";
  };

  # Stylix targets — noctalia needs explicit opt-in; KDE has a shellcheck bug so disable it.
  stylix.targets.noctalia-shell.enable = true;
  stylix.targets.kde.enable = false;

  # force = true: noctalia replaces HM symlinks with regular files at runtime (saves
  # settings). On next nixos-rebuild HM would fail with "would be clobbered". Force lets
  # HM overwrite them back to managed symlinks. niri/config.kdl is handled by
  # home-manager.backupFileExtension in configuration.nix (niri-flake uses a different
  # internal home.file key, so adding force here would create a conflicting target).
  xdg.configFile."noctalia/colors.json".force = true;
  xdg.configFile."noctalia/settings.json".force = true;

  # Adopt gtk4 default — stateVersion < 26.05 otherwise inherits gtk3 theme; stylix handles gtk4 theming via css.
  gtk.gtk4.theme = null;

  # Foot terminal — Stylix manages colors and font (MonaspiceAr via stylix.fonts.monospace).
  # dpi-aware=no: Niri handles HiDPI scaling at the compositor level; foot must not double-scale.
  # csd=none: Niri provides server-side decorations (prefer-no-csd=true in niri settings).
  programs.foot = {
    enable = true;
    settings = {
      main = {
        term              = "xterm-256color";
        pad               = "8x8";
        resize-delay-ms   = 100;
        dpi-aware         = "no";
        csd               = "none";
      };
      bell       = { urgent = false; notify = false; visual = false; };
      scrollback = { lines = 10000; multiplier = 3.0; };
      url = {
        launch        = "xdg-open \${url}";
        label-letters = "sadfjklewcmpgh";
        osc8-underline = "url-mode";
      };
      cursor = { style = "block"; blink = false; };
      mouse  = { hide-when-typing = true; alternate-scroll-mode = "yes"; };
      key-bindings = {
        clipboard-copy       = "Control+Shift+c XF86Copy";
        clipboard-paste      = "Control+Shift+v XF86Paste";
        font-increase        = "Control+plus Control+equal Control+KP_Add";
        font-decrease        = "Control+minus Control+KP_Subtract";
        font-reset           = "Control+0 Control+KP_0";
        scrollback-up-page   = "Shift+Page_Up";
        scrollback-down-page = "Shift+Page_Down";
        search-start         = "Control+Shift+r";
        show-urls-launch     = "Control+Shift+u";
      };
    };
  };

  # Starship prompt — copied verbatim from ~/nixconfig/home-modules/shell/starship.nix.
  # Uses '' strings to preserve embedded Nerd Font codepoints literally (Nix has no \u escapes).
  programs.starship = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration  = true;
    settings = {
      format = ''
        $cmd_duration 󰜥 $directory $git_branch
        $character'';

      add_newline = false;

      character = {
        success_symbol = "[   ](bold blue)";
        error_symbol = "[   ](bold red)";
      };

      cmd_duration = {
        min_time = 0;
        format = "[](bold fg:yellow)[󰪢 $duration](bold bg:yellow fg:black)[](bold fg:yellow)";
      };

      directory = {
        truncation_length = 6;
        truncation_symbol = "••/";
        home_symbol = "  ";
        read_only = " 󰌾";
        style = "fg:black bg:green";
        format = "[](bold fg:green)[󰉋 $path]($style)[](bold fg:green)";
      };

      git_branch = {
        symbol = "󰘬";
        format = "󰜥 [](bold fg:cyan)[$symbol $branch(:$remote_branch)](fg:black bg:cyan)[ ](bold fg:cyan)";
        truncation_length = 12;
        truncation_symbol = "";
        style = "bg:cyan";
      };

      git_commit = {
        commit_hash_length = 4;
        tag_symbol = " ";
      };

      git_status = {
        conflicted = " 🏳 ";
        ahead = " 🏎💨 ";
        behind = " 😰 ";
        diverged = " 😵 ";
        untracked = " 🤷‍ ";
        stashed = " 📦 ";
        modified = " 📝 ";
        staged = "[++($count)](green)";
        renamed = " ✍️ ";
        deleted = " 🗑 ";
      };

      git_state = {
        format = "[\($state( $progress_current of $progress_total)\)]($style) ";
        cherry_pick = "[🍒 PICKING](bold red)";
      };

      hostname = {
        ssh_only = false;
        format = "[•$hostname](bg:cyan bold fg:black)[](bold fg:cyan)";
        trim_at = ".local";
        disabled = false;
      };

      username = {
        style_user = "bold bg:cyan fg:black";
        style_root = "red bold";
        format = "[](bold fg:cyan)[$user]($style)";
        disabled = false;
        show_always = true;
      };

      package.disabled = true;
      memory_usage = { disabled = true; threshold = -1; };
      time.disabled = true;
      line_break.disabled = false;

      nix_shell = { format = "via [❄️ $state( \\($name\\))](bold blue) "; };
      python    = { format = "via [🐍 $version](bold green) "; };
      rust      = { format = "via [⚡ $version](bold orange) "; };
      nodejs    = { format = "via [⬢ $version](bold green) "; };
    };
  };

  # Common graphical packages for all desktop users
  home.packages = with pkgs; [
    ghostty   # secondary terminal (foot is default via Mod+Return)
    fuzzel
    grim
    slurp
    wl-clipboard
    playerctl
  ];
}
