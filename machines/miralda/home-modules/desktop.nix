# Shared Home Manager module for any graphical user on miralda.
{ pkgs, pkgs-unstable, inputs, config, lib, ... }:
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

      layout.border = { enable = true; width = 1; };
      layout.focus-ring.width = 1;

      input = {
        touchpad = {
          tap = true;
          natural-scroll = true;
          dwt = true;  # disable-while-typing
        };
      };

      # Window rules: rounded corners, focus-aware opacity.
      # Rules are evaluated in order; the last matching rule for each property wins.
      # Baseline:  focused = 0.90, unfocused = 0.75
      # Exception: heavy GUI apps (Chromium, GIMP, LibreOffice) stay fully opaque.
      window-rules = [
        {
          # Global baseline: 8px rounded corners + 90% opacity
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
          # Unfocused windows dim to 75%
          matches = [{ is-focused = false; }];
          opacity = 0.75;
        }
        {
          # Heavy GUI apps: always fully opaque regardless of focus
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

        # Floating terminal scratchpad (Mod+Shift+Return → foot -T scratch)
        {
          matches = [{ app-id = "^foot$"; title = "^scratch$"; }];
          open-floating = true;
          default-column-width = { fixed = 1000; };
          default-window-height = { fixed = 650; };
        }

        # KeePassXC — floating scratchpad at a comfortable size
        {
          matches = [{ app-id = "^org\\.keepassxc\\.KeePassXC$"; }];
          open-floating = true;
          default-column-width = { fixed = 900; };
          default-window-height = { fixed = 650; };
        }

        # GIMP — open floating (toolboxes are separate windows)
        {
          matches = [{ app-id = "^gimp$"; } { app-id = "^org\\.gimp\\.GIMP$"; }];
          open-floating = true;
        }

        # Chromium — open maximized
        {
          matches = [{ app-id = "^chromium$"; } { app-id = "^org\\.chromium\\.Chromium$"; }];
          open-maximized = true;
        }

        # Lazygit floating terminal (foot -T lazygit -e lazygit)
        {
          matches = [{ app-id = "^foot$"; title = "^lazygit$"; }];
          open-floating = true;
          default-column-width = { fixed = 1200; };
          default-window-height = { fixed = 800; };
        }
      ];

      # All app launches prefixed with "uwsm app --" so they run as systemd units
      binds = {
        # --- Focus navigation ---
        "Mod+H".action.focus-column-left  = {};
        "Mod+L".action.focus-column-right = {};
        "Mod+J".action.focus-window-down  = {};
        "Mod+K".action.focus-window-up    = {};

        # --- Move windows/columns ---
        "Mod+Shift+H".action.move-column-left  = {};
        "Mod+Shift+L".action.move-column-right = {};
        "Mod+Shift+J".action.move-window-down  = {};
        "Mod+Shift+K".action.move-window-up    = {};

        # --- Launch ---
        "Mod+Return".action.spawn = [ "uwsm" "app" "--" "foot" ];
        # foot -T scratch → matched by window rule → opens floating
        "Mod+Shift+Return".action.spawn = [ "uwsm" "app" "--" "foot" "-T" "scratch" ];
        "Mod+Space".action.spawn        = [ "uwsm" "app" "--" "fuzzel" ];
        "Mod+E".action.spawn = [ "uwsm" "app" "--" "foot" "-e" "hx" "." ];
        "Mod+F".action.spawn = [ "uwsm" "app" "--" "foot" "-e" "yazi" ];

        # --- Window management ---
        "Mod+Q".action.close-window           = {};
        "Mod+V".action.toggle-window-floating = {};
        "Mod+M".action.maximize-column        = {};
        "Mod+F11".action.fullscreen-window    = {};
        "Mod+Tab".action.focus-window-previous = {};

        # --- Session ---
        "Mod+Shift+E".action.quit = {};
        # Reload config via spawn (load-config-file is CLI-only, not a keybind action)
        "Mod+Shift+R".action.spawn = [ "niri" "msg" "action" "load-config-file" ];

        # --- Workspaces 1-9 ---
        "Mod+1".action.focus-workspace = 1;
        "Mod+2".action.focus-workspace = 2;
        "Mod+3".action.focus-workspace = 3;
        "Mod+4".action.focus-workspace = 4;
        "Mod+5".action.focus-workspace = 5;
        "Mod+6".action.focus-workspace = 6;
        "Mod+7".action.focus-workspace = 7;
        "Mod+8".action.focus-workspace = 8;
        "Mod+9".action.focus-workspace = 9;
        "Mod+Shift+1".action.move-window-to-workspace = 1;
        "Mod+Shift+2".action.move-window-to-workspace = 2;
        "Mod+Shift+3".action.move-window-to-workspace = 3;
        "Mod+Shift+4".action.move-window-to-workspace = 4;
        "Mod+Shift+5".action.move-window-to-workspace = 5;
        "Mod+Shift+6".action.move-window-to-workspace = 6;
        "Mod+Shift+7".action.move-window-to-workspace = 7;
        "Mod+Shift+8".action.move-window-to-workspace = 8;
        "Mod+Shift+9".action.move-window-to-workspace = 9;
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
    # Suppress startup popups: changelog and setup wizard are shown when
    # shell-state.json is absent (cache lost after ZFS rollback). Disabling the
    # changelog here prevents it even on a fresh cache. The setup wizard is
    # suppressed by persisting ~/.cache/noctalia/ in impermanence.nix.
    settings.general.showChangelogOnStartup = false;
    # Bar: floating style at the top of the screen
    settings.bar.position = "top";
    settings.bar.barType  = "floating";
    # Dock: auto-hides at the top edge of the screen
    settings.dock.position    = "top";
    settings.dock.displayMode = "auto_hide";
    # Wallpaper directory — matches where wallpapers.nix installs our PNGs.
    # Noctalia scans this directory for its picker; explicit so it survives
    # any future XDG_PICTURES_DIR changes.
    settings.wallpaper.directory = "/home/lgo/Pictures/Wallpapers";
  };

  # Stylix targets — noctalia needs explicit opt-in; KDE has a shellcheck bug so disable it.
  stylix.targets.noctalia-shell.enable = true;
  stylix.targets.kde.enable = false;

  # Override Noctalia accent colors for a distinctly Gruvbox look.
  # The Stylix target defaults mPrimary=base0D (muted teal) which doesn't read as Gruvbox.
  # Orange (base09) as primary, teal/aqua (base0C) as secondary — both iconic Gruvbox accents.
  # lib.mkForce overrides the Stylix target's default assignments.
  programs.noctalia-shell.colors = lib.mkForce (
    let c = config.lib.stylix.colors; in {
      mPrimary          = "#${c.base09}";  # Gruvbox orange
      mOnPrimary        = "#${c.base00}";
      mSecondary        = "#${c.base0C}";  # Gruvbox teal/aqua
      mOnSecondary      = "#${c.base00}";
      mTertiary         = "#${c.base0B}";  # Gruvbox green
      mOnTertiary       = "#${c.base00}";
      mError            = "#${c.base08}";
      mOnError          = "#${c.base00}";
      mSurface          = "#${c.base00}";
      mOnSurface        = "#${c.base05}";
      mHover            = "#${c.base09}";
      mOnHover          = "#${c.base00}";
      mSurfaceVariant   = "#${c.base01}";
      mOnSurfaceVariant = "#${c.base04}";
      mOutline          = "#${c.base03}";
      mShadow           = "#${c.base00}";
    }
  );

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
  programs.foot = {
    enable = true;
    settings = {
      main = {
        term              = "xterm-256color";
        pad               = "8x8";
        resize-delay-ms   = 100;
        dpi-aware         = "no";
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
        show-urls-launch     = "Control+Shift+o";
      };
    };
  };

  # Starship prompt — copied verbatim from ~/nixconfig/home-modules/shell/starship.nix.
  # Uses '' strings to preserve embedded Nerd Font codepoints literally (Nix has no \u escapes).
  programs.starship = {
    enable = true;
    enableBashIntegration    = true;
    enableZshIntegration     = true;
    enableNushellIntegration = true;
    settings = {
      format = ''
        $cmd_duration 󰜥 $directory $git_branch
        $character'';

      add_newline = false;

      character = {
        success_symbol = "[   ](bold blue)";
        error_symbol = "[   ](bold red)";
      };

      cmd_duration = {
        min_time = 0;
        format = "[](bold fg:yellow)[󰪢 $duration](bold bg:yellow fg:black)[](bold fg:yellow)";
      };

      directory = {
        truncation_length = 6;
        truncation_symbol = "••/";
        home_symbol = "  ";
        read_only = " 󰌾";
        style = "fg:black bg:green";
        format = "[](bold fg:green)[󰉋 $path]($style)[](bold fg:green)";
      };

      git_branch = {
        symbol = "󰘬";
        format = "󰜥 [](bold fg:cyan)[$symbol $branch(:$remote_branch)](fg:black bg:cyan)[ ](bold fg:cyan)";
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
        format = "[•$hostname](bg:cyan bold fg:black)[](bold fg:cyan)";
        trim_at = ".local";
        disabled = false;
      };

      username = {
        style_user = "bold bg:cyan fg:black";
        style_root = "red bold";
        format = "[](bold fg:cyan)[$user]($style)";
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
