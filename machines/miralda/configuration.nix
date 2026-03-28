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

  # EFI System Partition — must be a proper systemd mount so bootctl
  # can see it inside the isolated mount namespace used by systemd-run
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
    options = [ "fmask=0022" "dmask=0022" ];
  };

  # Impermanence requires these to be available early
  fileSystems."/persist".neededForBoot = true;
  fileSystems."/home".neededForBoot = true;

  # Required
  system.stateVersion = "25.11";
}
