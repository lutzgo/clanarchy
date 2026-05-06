{ config, lib, pkgs, ... }:
{
  options.clanarchy.desktop.gnome = {
    enable = lib.mkEnableOption "GNOME desktop environment";
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

    # ── Home Manager: declarative GNOME settings via dconf ───────────────────
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
          night-light-enabled             = true;
          night-light-temperature         = 3500;
          night-light-schedule-automatic  = true;
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
            "org.gnome.Nautilus.desktop"
            "firefox.desktop"
            "org.gnome.Console.desktop"
            "libreoffice-writer.desktop"
            "thunderbird.desktop"
            "com.mattjakeman.ExtensionManager.desktop"
          ];
        };

        # just-perfection — clean up the shell chrome
        "org/gnome/shell/extensions/just-perfection" = {
          activities-button     = false;  # hide Activities button
          app-menu              = false;  # hide app menu in top bar
          search                = true;
          workspace-popup       = false;
          animation             = 2;      # 1=slow 2=default 3=fast 4=off
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
          show-indicator       = true;
          play-audio-on-copy   = false;
          send-notification-on-copy = false;
        };

        # tiling-shell — quarter/half tiling with drag
        "org/gnome/shell/extensions/tilingshell" = {
          enable-move-keybindings = true;
          enable-snap-assistant   = true;
        };
      };
    }];
  };
}
