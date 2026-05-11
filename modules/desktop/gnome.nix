{ config, lib, pkgs, ... }:
{
  imports = [ ../icon-theme.nix ];

  options.clanarchy.desktop.gnome = {
    enable = lib.mkEnableOption "GNOME desktop environment";
    sabine = lib.mkEnableOption "Sabine's personal GNOME dconf defaults";
  };

  config = lib.mkIf config.clanarchy.desktop.gnome.enable {

    # ── Core GNOME desktop ───────────────────────────────────────────────────
    services.xserver.enable = true;
    services.displayManager.gdm.enable = true;
    services.desktopManager.gnome.enable = true;

    # Drop apps we replace with better alternatives
    environment.gnome.excludePackages = with pkgs; [
      gnome-tour
      epiphany
      gnome-contacts
      gnome-music
    ];

    # ── System packages — extensions + management tools ──────────────────────
    environment.systemPackages = with pkgs; [
      gnome-tweaks
      gnome-extension-manager

      # Extensions (installed system-wide; enabled via dconf below)
      gnomeExtensions.just-perfection
      gnomeExtensions.applications-menu
      gnomeExtensions.pano                # Clipboard manager
      gnomeExtensions.dash-to-panel       # Taskbar — replaces the dash
      gnomeExtensions.dash-to-dock        # Dock alternative (conflicts with dash-to-panel; pick one)
      gnomeExtensions.appindicator        # System tray / status icons
      gnomeExtensions.blur-my-shell
      gnomeExtensions.emoji-copy
      gnomeExtensions.tiling-shell        # Modern auto-tiling
      gnomeExtensions.tilingnome          # Minimalist tiling alternative
      gnomeExtensions.valent              # KDE Connect integration (GNOME side)
      valent                              # KDE Connect app itself
    ] ++ lib.optionals config.clanarchy.desktop.gnome.sabine [
      gnomeExtensions.user-themes         # Shell theme switcher (Sabine uses Stylix shell theme)
    ];

    # NetworkManager — GNOME shell integrates it natively
    networking.networkmanager.enable = true;

    # Pipewire audio
    security.rtkit.enable = true;
    services.pipewire = {
      enable            = true;
      alsa.enable       = true;
      alsa.support32Bit = true;
      pulse.enable      = true;
    };

    # UPower — battery indicator in top bar
    services.upower.enable = true;

    # Fonts
    fonts.packages = with pkgs; [
      nerd-fonts.monaspace
      noto-fonts
      noto-fonts-color-emoji
      inter
    ];
    fonts.fontconfig = {
      defaultFonts = {
        monospace = [ "MonaspiceAr Nerd Font Mono" "Noto Sans Mono" ];
        sansSerif = [ "Inter"                       "Noto Sans"      ];
        serif     = [ "MonaspiceXe Nerd Font Propo" "Noto Serif"     ];
        emoji     = [ "Noto Color Emoji" ];
      };
      hinting  = { enable = true; style = "slight"; };
      subpixel = { rgba = "rgb"; lcdfilter = "default"; };
    };

    environment.variables = {
      XCURSOR_SIZE   = "24";
      XCURSOR_THEME  = "Adwaita";
      NIXOS_OZONE_WL = "1";
    };

    # ── Home Manager: shared declarative GNOME settings ──────────────────────
    home-manager.sharedModules = [{
      # gtk4 theme default changed in HM 26.05; adopt the new null default.
      gtk.gtk4.theme = lib.mkDefault null;

      # Stylix's qt target sets platformTheme.name = "gnome" (deprecated) and
      # uses an unsupported platform value. On GNOME, Qt apps are themed via
      # adwaita-qt automatically — disable the Stylix qt target entirely.
      stylix.targets.qt.enable = false;
      qt.platformTheme.name    = lib.mkDefault "adwaita";

      dconf.settings = {

        # Interface
        "org/gnome/desktop/interface" = {
          clock-show-date    = true;
          clock-show-weekday = true;
          cursor-size        = 24;
          cursor-theme       = "Adwaita";
          font-antialiasing  = "rgba";
          font-hinting       = "slight";
        };

        # Window manager
        "org/gnome/desktop/wm/preferences" = {
          button-layout  = "appmenu:minimize,maximize,close";
          num-workspaces = 4;
        };

        # Mutter / compositor
        "org/gnome/mutter" = {
          dynamic-workspaces         = false;
          workspaces-only-on-primary = true;
          edge-tiling                = true;
        };

        # Touchpad
        "org/gnome/desktop/peripherals/touchpad" = {
          tap-to-click              = true;
          natural-scroll            = true;
          two-finger-scrolling-enabled = true;
          speed                     = 0.2;
          disable-while-typing      = true;
        };

        # Power management
        "org/gnome/settings-daemon/plugins/power" = {
          sleep-inactive-battery-type    = "suspend";
          sleep-inactive-battery-timeout = 600;
          sleep-inactive-ac-type         = "suspend";
          sleep-inactive-ac-timeout      = 1800;
          power-button-action            = "suspend";
        };

        # Night Light
        "org/gnome/settings-daemon/plugins/color" = {
          night-light-enabled            = true;
          night-light-temperature        = 3500;
          night-light-schedule-automatic = true;
        };

        # Text editor
        "org/gnome/TextEditor" = {
          show-line-numbers      = true;
          highlight-current-line = true;
          wrap-text              = false;
        };

        # ── Extensions ───────────────────────────────────────────────────────
        # Enable all extensions except conflicting pairs (pick one from each):
        #   Dock:   dash-to-panel OR dash-to-dock   (dash-to-panel enabled by default)
        #   Tiling: tiling-shell  OR tilingnome      (tiling-shell enabled by default)
        "org/gnome/shell" = {
          enabled-extensions = [
            "just-perfection-desktop@just-perfection"
            "apps-menu@gnome-shell-extensions.gcampax.github.com"
            "pano@elhan.io"
            "dash-to-panel@jderose9.github.com"
            # "dash-to-dock@micxgx.gmail.com"        # conflicts with dash-to-panel
            "appindicatorsupport@rgcjonas.gmail.com"
            "blur-my-shell@aunetx"
            "emoji-copy@felipeftn"
            "tilingshell@ferrarodomenico.com"
            # "tilingnome@rliang.github.com"          # alternative tiling
            "valent@andyholmes.ca"
          ];
          favorite-apps = [
            "io.gitlab.librewolf-community.librewolf.desktop"
            "org.gnome.Nautilus.desktop"
            "org.gnome.Console.desktop"
            "libreoffice-writer.desktop"
            "thunderbird.desktop"
            "com.mattjakeman.ExtensionManager.desktop"
          ];
        };

        # just-perfection — clean up the shell chrome
        "org/gnome/shell/extensions/just-perfection" = {
          activities-button = false;  # hide Activities button
          app-menu          = false;  # hide app menu in top bar
          search            = true;
          workspace-popup   = false;
          animation         = 2;     # 1=slow 2=default 3=fast 4=off
        };

        # blur-my-shell
        "org/gnome/shell/extensions/blur-my-shell" = {
          sigma      = 30;
          brightness = 0.6;
        };
        "org/gnome/shell/extensions/blur-my-shell/overview" = {
          blur     = true;
          pipeline = "pipeline_default";
        };
        "org/gnome/shell/extensions/blur-my-shell/panel" = {
          blur = true;
        };

        # pano — clipboard manager (super+shift+v to open)
        "org/gnome/shell/extensions/pano" = {
          show-indicator            = true;
          play-audio-on-copy        = false;
          send-notification-on-copy = false;
        };

        # tiling-shell — quarter/half tiling with drag
        "org/gnome/shell/extensions/tilingshell" = {
          enable-move-keybindings = true;
          enable-snap-assistant   = true;
        };
      };
    }];

    # ── Sabine's personal dconf defaults ─────────────────────────────────────
    # Applied to home-manager.users.sabine when clanarchy.desktop.gnome.sabine
    # is true.  Values that also appear in sharedModules use lib.mkForce so
    # they take precedence over the shared baseline.
    home-manager.users.sabine = lib.mkIf config.clanarchy.desktop.gnome.sabine
      ({ lib, ... }: with lib.hm.gvariant; {
        dconf.settings = {

          # Wallpaper — explicitly wire Stylix's generated image so GNOME picks it
          # up reliably.  config.stylix.image is captured from the outer NixOS
          # scope and resolves to the biene-wallpaper.png store path.
          # All keys use lib.mkForce so Stylix's own GNOME target cannot
          # override picture-options and revert to a solid-colour background.
          "org/gnome/desktop/background" = {
            picture-uri        = lib.mkForce "file://${config.stylix.image}";
            picture-uri-dark   = lib.mkForce "file://${config.stylix.image}";
            picture-options    = lib.mkForce "zoom";
            color-shading-type = lib.mkForce "solid";
          };

          # Valent (KDE Connect) — advertise device as "biene"
          "ca/andyholmes/valent" = {
            name = "biene";
          };

          # Text editor — same as shared + Stylix colour scheme
          "org/gnome/TextEditor" = {
            highlight-current-line = lib.mkForce true;
            show-line-numbers      = lib.mkForce true;
            style-scheme           = "stylix";
            wrap-text              = lib.mkForce false;
          };

          # ── App folders ────────────────────────────────────────────────────
          "org/gnome/desktop/app-folders" = {
            folder-children = [ "System" "Utilities" "YaST" "Pardus" ];
          };
          "org/gnome/desktop/app-folders/folders/Pardus" = {
            categories = [ "X-Pardus-Apps" ];
            name       = "X-Pardus-Apps.directory";
            translate  = true;
          };
          "org/gnome/desktop/app-folders/folders/System" = {
            apps      = [ "org.gnome.baobab.desktop" "org.gnome.DiskUtility.desktop" "org.gnome.Logs.desktop" "org.gnome.SystemMonitor.desktop" ];
            name      = "X-GNOME-Shell-System.directory";
            translate = true;
          };
          "org/gnome/desktop/app-folders/folders/Utilities" = {
            apps      = [ "org.gnome.Decibels.desktop" "org.gnome.Connections.desktop" "org.gnome.Papers.desktop" "org.gnome.font-viewer.desktop" "org.gnome.Loupe.desktop" ];
            name      = "X-GNOME-Shell-Utilities.directory";
            translate = true;
          };
          "org/gnome/desktop/app-folders/folders/YaST" = {
            categories = [ "X-SuSE-YaST" ];
            name       = "suse-yast.directory";
            translate  = true;
          };

          # ── Break reminders ────────────────────────────────────────────────
          "org/gnome/desktop/break-reminders" = {
            selected-breaks = [ "eyesight" "movement" ];
          };
          "org/gnome/desktop/break-reminders/eyesight" = {
            play-sound = false;
          };
          "org/gnome/desktop/break-reminders/movement" = {
            duration-seconds = mkUint32 300;
            interval-seconds = mkUint32 1800;
            play-sound       = false;
          };

          # Calendar — show week number
          "org/gnome/desktop/calendar" = {
            show-weekdate = true;
          };

          # Automatic timezone
          "org/gnome/desktop/datetime" = {
            automatic-timezone = true;
          };

          # Keyboard layouts: de (primary), us (secondary)
          "org/gnome/desktop/input-sources" = {
            mru-sources = [ (mkTuple [ "xkb" "us" ]) ];
            sources     = [ (mkTuple [ "xkb" "de" ]) (mkTuple [ "xkb" "us" ]) ];
            xkb-options = [];
          };

          # Interface — extends shared baseline with Sabine's preferences
          "org/gnome/desktop/interface" = {
            clock-show-date     = lib.mkForce true;
            clock-show-weekday  = lib.mkForce true;
            color-scheme        = "prefer-dark";
            cursor-blink        = true;
            cursor-blink-time   = 1000;
            cursor-size         = lib.mkForce 24;
            cursor-theme        = lib.mkForce "Adwaita";
            document-font-name  = "MonaspiceXe Nerd Font Propo  10";
            enable-animations   = true;
            enable-hot-corners  = false;
            font-antialiasing   = lib.mkForce "rgba";
            font-hinting        = lib.mkForce "slight";
            font-name           = "MonaspiceNe Nerd Font Propo 11";
            gtk-theme           = "adw-gtk3";
            icon-theme          = config.clanarchy.iconTheme.name;
            monospace-font-name = "MonaspiceAr Nerd Font Mono 11";
            scaling-factor      = mkUint32 1;
            text-scaling-factor = 1.0;
            toolbar-style       = "text";
          };

          # Keyboard — numlock on at login
          "org/gnome/desktop/peripherals/keyboard" = {
            numlock-state = true;
          };

          # Touchpad
          "org/gnome/desktop/peripherals/touchpad" = {
            disable-while-typing         = lib.mkForce true;
            natural-scroll               = lib.mkForce true;
            speed                        = lib.mkForce 0.2;
            tap-to-click                 = lib.mkForce true;
            two-finger-scrolling-enabled = lib.mkForce true;
          };

          # Search — provider order
          "org/gnome/desktop/search-providers" = {
            sort-order = [ "org.gnome.Settings.desktop" "org.gnome.Contacts.desktop" "org.gnome.Nautilus.desktop" ];
          };

          # Never dim / auto-lock
          "org/gnome/desktop/session" = {
            idle-delay = mkUint32 0;
          };

          # Sound theme
          "org/gnome/desktop/sound" = {
            theme-name = "ocean";
          };

          # WM keybindings — Super+arrows for tile/maximize
          "org/gnome/desktop/wm/keybindings" = {
            maximize   = [ "<Super>Up" ];
            unmaximize = [ "<Super>Down" "<Alt>F5" ];
          };

          # 1 workspace (overrides shared default of 4)
          "org/gnome/desktop/wm/preferences" = {
            button-layout  = lib.mkForce "appmenu:minimize,maximize,close";
            num-workspaces = lib.mkForce 1;
          };

          # Eye-of-GNOME — background follows the active GTK/Stylix theme
          "org/gnome/eog/view" = {
            use-background-color = false;
          };

          # System monitor
          "org/gnome/gnome-system-monitor" = {
            show-dependencies    = false;
            show-whose-processes = "user";
          };

          # Mutter
          "org/gnome/mutter" = {
            dynamic-workspaces         = lib.mkForce false;
            edge-tiling                = lib.mkForce true;
            workspaces-only-on-primary = lib.mkForce true;
          };

          # Mutter tiling keybindings
          "org/gnome/mutter/keybindings" = {
            toggle-tiled-left  = [ "<Super>Left" ];
            toggle-tiled-right = [ "<Super>Right" ];
          };

          # Nautilus
          "org/gnome/nautilus/preferences" = {
            default-folder-viewer = "icon-view";
            migrated-gtk-settings = true;
          };

          # Night light — manual schedule (not automatic)
          "org/gnome/settings-daemon/plugins/color" = {
            night-light-enabled            = lib.mkForce true;
            night-light-schedule-automatic = lib.mkForce false;
            night-light-temperature        = lib.mkForce 3500;
          };

          # Power management
          "org/gnome/settings-daemon/plugins/power" = {
            idle-dim                       = false;
            power-button-action            = lib.mkForce "suspend";
            sleep-inactive-ac-timeout      = lib.mkForce 1800;
            sleep-inactive-ac-type         = lib.mkForce "nothing";
            sleep-inactive-battery-timeout = lib.mkForce 600;
            sleep-inactive-battery-type    = lib.mkForce "nothing";
          };

          # ── Shell extensions ───────────────────────────────────────────────
          # Sabine's set differs from the shared baseline:
          #   + user-theme (Stylix shell theme)
          #   - just-perfection, tilingshell, dash-to-dock (explicitly disabled)
          "org/gnome/shell" = {
            disabled-extensions = [
              "dash-to-dock@micxgx.gmail.com"
              "just-perfection-desktop@just-perfection"
              "tilingshell@ferrarodomenico.com"
            ];
            enabled-extensions = lib.mkForce [
              "apps-menu@gnome-shell-extensions.gcampax.github.com"
              "pano@elhan.io"
              "appindicatorsupport@rgcjonas.gmail.com"
              "blur-my-shell@aunetx"
              "emoji-copy@felipeftn"
              "valent@andyholmes.ca"
              "user-theme@gnome-shell-extensions.gcampax.github.com"
              "dash-to-panel@jderose9.github.com"
            ];
            favorite-apps = lib.mkForce [
              "io.gitlab.librewolf-community.librewolf.desktop"
              "thunderbird.desktop"
              "startcenter.desktop"
              "org.gnome.Nautilus.desktop"
              "org.gnome.Console.desktop"
            ];
          };

          # App indicator
          "org/gnome/shell/extensions/appindicator" = {
            icon-brightness = 0.0;
            icon-contrast   = 0.0;
            icon-opacity    = 240;
            icon-saturation = 0.0;
            icon-size       = 0;
          };

          # Blur my shell
          "org/gnome/shell/extensions/blur-my-shell" = {
            brightness       = lib.mkForce 0.6;
            settings-version = 2;
            sigma            = lib.mkForce 30;
          };
          "org/gnome/shell/extensions/blur-my-shell/appfolder" = {
            brightness = 0.6;
            sigma      = 30;
          };
          "org/gnome/shell/extensions/blur-my-shell/coverflow-alt-tab" = {
            pipeline = "pipeline_default";
          };
          "org/gnome/shell/extensions/blur-my-shell/dash-to-dock" = {
            blur               = true;
            brightness         = 0.6;
            pipeline           = "pipeline_default_rounded";
            sigma              = 30;
            static-blur        = true;
            style-dash-to-dock = 0;
          };
          "org/gnome/shell/extensions/blur-my-shell/lockscreen" = {
            pipeline = "pipeline_default";
          };
          "org/gnome/shell/extensions/blur-my-shell/overview" = {
            blur     = lib.mkForce true;
            pipeline = lib.mkForce "pipeline_default";
          };
          "org/gnome/shell/extensions/blur-my-shell/panel" = {
            blur       = lib.mkForce true;
            brightness = 0.6;
            pipeline   = "pipeline_default";
            sigma      = 30;
          };
          "org/gnome/shell/extensions/blur-my-shell/screenshot" = {
            pipeline = "pipeline_default";
          };
          "org/gnome/shell/extensions/blur-my-shell/window-list" = {
            brightness = 0.6;
            sigma      = 30;
          };

          # Dash-to-panel — taskbar layout for biene's built-in display
          # panel-* keys are keyed by monitor EDID ID (CMN-0x00000000).
          "org/gnome/shell/extensions/dash-to-panel" = {
            animate-appicon-hover                  = true;
            animate-appicon-hover-animation-extent = builtins.toJSON { RIPPLE = 4; PLANK = 4; SIMPLE = 1; };
            appicon-margin                         = 0;
            appicon-padding                        = 0;
            context-menu-entries                   = "[{\"title\":\"Terminal\",\"cmd\":\"TERMINALSETTINGS\"},{\"title\":\"System monitor\",\"cmd\":\"gnome-system-monitor\"},{\"title\":\"Files\",\"cmd\":\"nautilus\"}]";
            dot-position                           = "BOTTOM";
            dot-style-focused                      = "DOTS";
            dot-style-unfocused                    = "DOTS";
            focus-highlight-dominant               = false;
            global-border-radius                   = 0;
            hotkeys-overlay-combo                  = "TEMPORARILY";
            intellihide                            = false;
            panel-anchors                          = "{\"CMN-0x00000000\":\"MIDDLE\"}";
            panel-element-positions                = "{\"CMN-0x00000000\":[{\"element\":\"showAppsButton\",\"visible\":false,\"position\":\"stackedTL\"},{\"element\":\"activitiesButton\",\"visible\":false,\"position\":\"stackedTL\"},{\"element\":\"leftBox\",\"visible\":true,\"position\":\"stackedTL\"},{\"element\":\"taskbar\",\"visible\":true,\"position\":\"stackedTL\"},{\"element\":\"centerBox\",\"visible\":true,\"position\":\"stackedBR\"},{\"element\":\"rightBox\",\"visible\":true,\"position\":\"stackedBR\"},{\"element\":\"dateMenu\",\"visible\":true,\"position\":\"stackedBR\"},{\"element\":\"systemMenu\",\"visible\":true,\"position\":\"stackedBR\"},{\"element\":\"desktopButton\",\"visible\":true,\"position\":\"stackedBR\"}]}";
            panel-lengths                          = "{}";
            panel-positions                        = "{}";
            panel-sizes                            = "{\"CMN-0x00000000\":32}";
            scroll-icon-action                     = "NOTHING";
            scroll-panel-action                    = "NOTHING";
            show-apps-icon-file                    = "";
            window-preview-title-position          = "TOP";
          };

          # Just Perfection (disabled for Sabine; settings preserved for if re-enabled)
          "org/gnome/shell/extensions/just-perfection" = {
            accent-color-icon              = true;
            accessibility-menu             = true;
            activities-button              = lib.mkForce true;
            animation                      = lib.mkForce 1;
            app-menu                       = lib.mkForce false;
            controls-manager-spacing-size  = 2;
            dash-icon-size                 = 0;
            invert-calendar-column-items   = true;
            panel                          = true;
            panel-in-overview              = true;
            ripple-box                     = true;
            search                         = lib.mkForce true;
            show-apps-button               = true;
            startup-status                 = 1;
            theme                          = false;
            top-panel-position             = 1;
            window-demands-attention-focus = false;
            window-maximized-on-create     = true;
            window-picker-icon             = true;
            workspace                      = true;
            workspace-peek                 = false;
            workspace-popup                = lib.mkForce true;
            workspaces-in-app-grid         = true;
          };

          # Pano clipboard manager
          "org/gnome/shell/extensions/pano" = {
            play-audio-on-copy        = lib.mkForce false;
            send-notification-on-copy = lib.mkForce false;
            show-indicator            = lib.mkForce true;
          };

          # Tiling Shell (disabled for Sabine; custom layouts preserved)
          "org/gnome/shell/extensions/tilingshell" = {
            enable-move-keybindings        = lib.mkForce true;
            enable-snap-assistant          = lib.mkForce true;
            layouts-json                   = "[{\"id\":\"Layout 1\",\"tiles\":[{\"x\":0,\"y\":0,\"width\":0.22,\"height\":0.5,\"groups\":[1,2]},{\"x\":0,\"y\":0.5,\"width\":0.22,\"height\":0.5,\"groups\":[1,2]},{\"x\":0.22,\"y\":0,\"width\":0.56,\"height\":1,\"groups\":[2,3]},{\"x\":0.78,\"y\":0,\"width\":0.22,\"height\":0.5,\"groups\":[3,4]},{\"x\":0.78,\"y\":0.5,\"width\":0.22,\"height\":0.5,\"groups\":[3,4]}]},{\"id\":\"Layout 2\",\"tiles\":[{\"x\":0,\"y\":0,\"width\":0.22,\"height\":1,\"groups\":[1]},{\"x\":0.22,\"y\":0,\"width\":0.56,\"height\":1,\"groups\":[1,2]},{\"x\":0.78,\"y\":0,\"width\":0.22,\"height\":1,\"groups\":[2]}]},{\"id\":\"Layout 3\",\"tiles\":[{\"x\":0,\"y\":0,\"width\":0.33,\"height\":1,\"groups\":[1]},{\"x\":0.33,\"y\":0,\"width\":0.67,\"height\":1,\"groups\":[1]}]},{\"id\":\"Layout 4\",\"tiles\":[{\"x\":0,\"y\":0,\"width\":0.67,\"height\":1,\"groups\":[1]},{\"x\":0.67,\"y\":0,\"width\":0.33,\"height\":1,\"groups\":[1]}]}]";
            overridden-settings            = "{}";
            selected-layouts               = [ [ "Layout 1" ] [ "Layout 1" ] [ "Layout 1" ] [ "Layout 1" ] ];
            window-use-custom-border-color = false;
          };

          # User theme — apply Stylix-generated shell theme
          "org/gnome/shell/extensions/user-theme" = {
            name = "Stylix";
          };
        };
      });
  };
}
