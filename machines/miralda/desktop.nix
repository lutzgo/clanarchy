{ pkgs, inputs, pkgs-unstable, ... }:
{
  programs.niri.enable = true;

  # ReGreet — GTK4 greeter via cage; Stylix-themed in stylix.nix
  programs.regreet.enable = true;

  # UWSM — binPath must be niri-session (not niri): exports WAYLAND_DISPLAY/NIRI_SOCKET
  # to systemd user manager; without --session, UWSM's waitenv times out (30s).
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
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend";
    KillUserProcesses = false;
  };

  # Framework-specific hardware support
  services.fprintd.enable = true;  # fingerprint reader
  services.fwupd.enable = true;    # firmware updates via LVFS

  hardware.graphics.enable = true;

  hardware.graphics.extraPackages = with pkgs; [
    mesa          # provides Rusticl OpenCL via radeonsi driver
    rocmPackages.clr.icd  # optional ROCm ICD — not needed for iGPU, skip unless testing
  ];

  environment.systemPackages = with pkgs; [
    clinfo        # verify OpenCL is visible
  ];

  environment.variables = {
    RUSTICL_ENABLE = "radeonsi";
    XCURSOR_SIZE = "24";
    XCURSOR_THEME = "Adwaita";
    NIXOS_OZONE_WL = "1";
  };

  security.pam.services.login.fprintAuth = true;
  security.pam.services.greetd.fprintAuth = true;
  security.pam.services.sudo.fprintAuth = true;

  # Prevent backpack-wake (bag pressure on lid sensor triggers spurious wake)
  services.udev.extraRules = ''
    SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="LID*", ATTRS{phys}=="PNP0C0D*", TAG-="power-switch"
  '';

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

  # Valent — GCR_SSH_AGENT_PIPE="" prevents gcr from importing the TLS key into
  # gpg-agent (which would trigger a blocking pinentry prompt for the headless service).
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
