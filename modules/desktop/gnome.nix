{ config, lib, pkgs, ... }:
{
  options.clanarchy.desktop.gnome = {
    enable = lib.mkEnableOption "GNOME desktop environment";
  };

  config = lib.mkIf config.clanarchy.desktop.gnome.enable {

    # GNOME desktop — Wayland via GDM (default in NixOS ≥25.05)
    services.xserver.enable = true;
    services.displayManager.gdm.enable = true;
    services.desktopManager.gnome.enable = true;

    # Drop apps Sabine won't use (Firefox replaces Epiphany; no tour wizard)
    environment.gnome.excludePackages = with pkgs; [
      gnome-tour
      epiphany
      gnome-contacts
      gnome-music
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

    # ── Home Manager: declarative GNOME settings via dconf ──────────────────
    # All users on this machine share these ergonomic defaults.
    # Per-user overrides go in the user's own HM config.
    home-manager.sharedModules = [{
      dconf.settings = {

        # Interface
        "org/gnome/desktop/interface" = {
          clock-show-date    = true;
          clock-show-weekday = true;
          cursor-size        = 24;
          cursor-theme       = "Adwaita";
          font-antialiasing  = "rgba";
          font-hinting       = "slight";
          # Fonts are set by Stylix's GTK target; leave name/size to it.
        };

        # Window manager
        "org/gnome/desktop/wm/preferences" = {
          button-layout  = "appmenu:minimize,maximize,close";
          num-workspaces = 4;
        };

        # Mutter / compositor
        "org/gnome/mutter" = {
          dynamic-workspaces        = false;
          workspaces-only-on-primary = true;
          edge-tiling               = true;
        };

        # Touchpad — sensible laptop defaults
        "org/gnome/desktop/peripherals/touchpad" = {
          tap-to-click              = true;
          natural-scroll            = true;
          two-finger-scrolling-enabled = true;
          speed                     = 0.2;
          disable-while-typing      = true;
        };

        # Power management (laptop)
        "org/gnome/settings-daemon/plugins/power" = {
          sleep-inactive-battery-type    = "suspend";
          sleep-inactive-battery-timeout = 600;   # 10 min on battery
          sleep-inactive-ac-type         = "suspend";
          sleep-inactive-ac-timeout      = 1800;  # 30 min on AC
          power-button-action            = "suspend";
        };

        # Night Light (reduce blue light in the evening)
        "org/gnome/settings-daemon/plugins/color" = {
          night-light-enabled     = true;
          night-light-temperature = 3500;
          night-light-schedule-automatic = true;
        };

        # Dash / taskbar favourites
        "org/gnome/shell" = {
          favorite-apps = [
            "org.gnome.Nautilus.desktop"
            "firefox.desktop"
            "org.gnome.Console.desktop"
            "libreoffice-writer.desktop"
            "thunderbird.desktop"
          ];
        };

        # Text editor (gedit → gnome-text-editor in GNOME 45+)
        "org/gnome/TextEditor" = {
          show-line-numbers = true;
          highlight-current-line = true;
          wrap-text = false;
        };
      };
    }];
  };
}
