{...}: {
  networking.hostName = "biene";
  networking.hostId = "cd9ef50b";
  networking.search = ["skynet.lan"];
  time.timeZone = "Europe/Berlin";

  # --- Module activation ---
  clanarchy.roles.laptop = {
    enable = true;
    cpu = "intel"; # update to "intel" if needed
  };

  # Laptop role defaults niri; override it here so only KDE Plasma 6 runs.
  clanarchy.desktop.niri.enable = false;
  clanarchy.desktop.kde.enable = true;

  clanarchy.users.admin.enable = true;
  clanarchy.users.sabine.enable = true;

  clanarchy.wifi.networks = [
    {
      ssid = "skynet";
      varName = "wifi-home";
    }
  ];

  # Keep flakes usable on the installed system too
  nix.settings.experimental-features = ["nix-command" "flakes"];

  # SSH daemon
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  # EFI boot
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # ZFS boot support
  boot.supportedFilesystems = ["zfs"];
  boot.zfs.forceImportRoot = false;
  boot.initrd.systemd.enable = true;

  # Plymouth splash
  boot.plymouth.enable = true;
  boot.kernelParams = ["quiet" "splash"];

  # Impermanence requires these early
  fileSystems."/persist".neededForBoot = true;
  fileSystems."/home".neededForBoot = true;

  home-manager.backupFileExtension = "bak";

  programs.zsh.enable = true;

  system.stateVersion = "25.11";
}
