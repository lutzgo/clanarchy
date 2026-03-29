{ pkgs, inputs, pkgs-unstable, ... }:
{
  # Niri compositor (system-level: binary, capabilities, PAM, etc.)
  # niri is overridden with doCheck=false via clan.pkgsForSystem in clan.nix
  programs.niri.enable = true;

  # greetd with tuigreet — only show UWSM-managed sessions; remember last choice.
  # No --cmd: that would add a spurious third "Niri" entry alongside niri.desktop
  # and niri-uwsm.desktop. --remember-session persists the last selection.
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --remember-session --default-session niri-uwsm.desktop";
        user = "greeter";
      };
    };
  };

  # UWSM — systemd session manager; registers niri and generates niri-uwsm.desktop.
  # binPath must be niri-session, not niri: niri-session detects when it runs as a
  # systemd user service and execs "niri --session", which exports WAYLAND_DISPLAY
  # and NIRI_SOCKET to the systemd user manager. Without --session, UWSM's waitenv
  # times out (30s) and sends SIGTERM because WAYLAND_DISPLAY never appears.
  programs.uwsm = {
    enable = true;
    waylandCompositors.niri = {
      prettyName = "Niri";
      comment = "Niri compositor managed by UWSM";
      binPath = "/run/current-system/sw/bin/niri-session";
    };
  };

  # XDG portal — gtk portal is the recommended choice for Niri
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.common.default = "gtk";
  };

  # Power management — power-profiles-daemon (NOT TLP — they conflict on Framework AMD)
  services.power-profiles-daemon.enable = true;

  # Framework-specific hardware support
  services.fprintd.enable = true;  # fingerprint reader
  services.fwupd.enable = true;    # firmware updates via LVFS

  # Prevent backpack-wake (bag pressure on lid sensor triggers spurious wake)
  services.udev.extraRules = ''
    SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="LID*", ATTRS{phys}=="PNP0C0D*", TAG-="power-switch"
  '';

  # HiDPI cursor + Wayland env flags
  environment.variables = {
    XCURSOR_SIZE = "24";
    XCURSOR_THEME = "Adwaita";
    NIXOS_OZONE_WL = "1";
  };

  # Pipewire audio
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # NetworkManager
  networking.networkmanager.enable = true;

  # UPower — required by Noctalia battery widget
  services.upower.enable = true;

  # Fonts
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    noto-fonts
    noto-fonts-color-emoji
  ];
  fonts.fontconfig.defaultFonts = {
    monospace = [ "JetBrainsMono Nerd Font" ];
    sansSerif = [ "Noto Sans" ];
  };

  # Shared HM desktop module for all graphical users on this machine
  home-manager.sharedModules = [ ./home-modules/desktop.nix ];
  home-manager.extraSpecialArgs = {
    inherit inputs pkgs-unstable;
  };
}
