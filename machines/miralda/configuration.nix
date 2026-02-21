{ ... }:
{
  networking.hostName = "miralda";
  time.timeZone = "Europe/Berlin";

  # Keep flakes usable on the installed system too
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Ensure SSH daemon is present (inventory sshd service manages keys/config)
  services.openssh.enable = true;

  # ZFS in initrd (disko creates pool/datasets, this ensures boot support)
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;

  # Required
  system.stateVersion = "25.11";
}
