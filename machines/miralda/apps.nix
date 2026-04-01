{ pkgs, lib, ... }:
{
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "claude-code"
    "signal-desktop"
  ];
  environment.systemPackages = with pkgs; [
    chromium
    librewolf
    firefox
    signal-desktop
    keepassxc
    valent          # KDE Connect protocol — replaces kdePackages.kdeconnect-kde (lighter deps)
    helix
    fzf
    zellij
    yazi
    lazygit
    foot
    libreoffice
    gimp
    darktable
    krita
    normcap         # OCR screen capture
    obs-studio
    bat             # cat with syntax highlighting and paging
    ripgrep
    fd
    xdg-utils
    wtype           # Wayland keyboard input injection (xdotool equivalent)
    claude-code
  ];

  # Valent / KDE Connect protocol — ports 1714-1764 TCP+UDP
  networking.firewall = {
    allowedTCPPortRanges = [{ from = 1714; to = 1764; }];
    allowedUDPPortRanges = [{ from = 1714; to = 1764; }];
  };

  # Podman
  virtualisation.containers.enable = true;
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  # Flatpak
  services.flatpak.enable = true;
}
