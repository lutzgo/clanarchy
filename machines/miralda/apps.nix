{ pkgs, lib, ... }:
{
  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) [
    "claude-code"
  ];
  environment.systemPackages = with pkgs; [
    chromium
    keepassxc
    kdePackages.kdeconnect-kde
    helix
    foot
    libreoffice
    gimp
    claude-code
  ];

  # KDE Connect — open required firewall ports
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
