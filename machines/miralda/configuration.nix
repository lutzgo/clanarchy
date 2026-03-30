{ ... }:
{
  networking.hostName = "miralda";
  networking.hostId = "ebeed95c";
  time.timeZone = "Europe/Berlin";

  # Keep flakes usable on the installed system too
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Ensure SSH daemon is present (inventory sshd service manages keys/config)
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  # Use systemd-boot (EFI)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # ZFS in initrd (disko creates pool/datasets, this ensures boot support)
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;
  boot.initrd.systemd.enable = true;

  # Impermanence requires these to be available early
  fileSystems."/persist".neededForBoot = true;
  fileSystems."/home".neededForBoot = true;

  # HM backup extension: when nixos-rebuild finds a regular file where it wants to
  # create a managed symlink (e.g. niri/config.kdl written by niri itself), back it
  # up with this suffix rather than failing. Applies to all users.
  home-manager.backupFileExtension = "bak";

  # Required
  system.stateVersion = "25.11";
}
