{ pkgs, inputs, pkgs-unstable, ... }:
{
  # Niri compositor (system-level: binary, capabilities, PAM, etc.)
  # niri is overridden with doCheck=false via clan.pkgsForSystem in clan.nix
  programs.niri.enable = true;

  # ReGreet — GTK4 greeter, runs inside cage (Wayland kiosk compositor).
  # programs.regreet enables greetd and configures cage + regreet automatically.
  # Stylix theming is applied via stylix.targets.regreet in stylix.nix.
  # No state is persisted — /var/lib/regreet resets on ZFS rollback, which is fine.
  programs.regreet.enable = true;


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

  # Lid close → suspend to RAM (hybrid-sleep requires swap, which this ZFS layout lacks)
  services.logind.lidSwitch = "suspend";

  # Framework-specific hardware support
  services.fprintd.enable = true;  # fingerprint reader
  services.fwupd.enable = true;    # firmware updates via LVFS

  # Uncomment after enrolling fingerprints with: sudo fprintd-enroll lgo
  security.pam.services.login.fprintAuth = true;
  security.pam.services.greetd.fprintAuth = true;
  security.pam.services.sudo.fprintAuth = true;

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
    nerd-fonts.monaspace      # MonaspiceAr/Ne/Xe/Ra/Rn — terminal, UI, serif
    noto-fonts
    noto-fonts-color-emoji
    inter                     # clean sans-serif for UI
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

  # Valent — KDE Connect protocol service for phone integration.
  # Valent stores its TLS cert as plain PEM files (~/.config/valent/private.pem).
  # Without the environment override, gcr auto-imports the key into gpg-agent,
  # triggering a pinentry passphrase prompt that blocks the headless service.
  systemd.user.services.valent = {
    description = "Valent - KDE Connect protocol";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    environment.GCR_SSH_AGENT_PIPE = "";
    serviceConfig = {
      ExecStart = "${pkgs.valent}/bin/valent --gapplication-service";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # Shared HM desktop module for all graphical users on this machine
  home-manager.sharedModules = [ ./home-modules/desktop.nix ];
  home-manager.extraSpecialArgs = {
    inherit inputs pkgs-unstable;
  };
}
