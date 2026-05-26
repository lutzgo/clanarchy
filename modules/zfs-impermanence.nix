{ ... }:
{
  boot.supportedFilesystems  = [ "zfs" "exfat" "ntfs" "vfat" ];
  boot.zfs.forceImportRoot   = false;
  boot.initrd.systemd.enable = true;

  # Impermanence requires /persist and /home to be available in stage 1.
  fileSystems."/persist".neededForBoot = true;
  fileSystems."/home".neededForBoot    = true;

  # Roll back root and home to @blank ZFS snapshots on every boot (stage 1).
  # Create the snapshots once after initial install:
  #   zfs snapshot zroot/root@blank && zfs snapshot zroot/home@blank
  boot.initrd.systemd.services.rollback = {
    description = "Rollback ZFS datasets to blank";
    wantedBy    = [ "initrd.target" ];
    after       = [ "zfs-import-zroot.service" ];
    before      = [ "sysroot.mount" ];
    unitConfig.DefaultDependencies = "no";
    serviceConfig.Type = "oneshot";
    script = ''
      zfs rollback -r zroot/root@blank || true
      zfs rollback -r zroot/home@blank || true
    '';
  };

  # Common system-level persist paths shared by all clanarchy machines.
  # Per-machine additions (e.g. /var/lib/flatpak) live in machines/*/configuration.nix
  # or the module that enables the relevant service.
  # Per-user paths are declared in modules/users/*.nix.
  environment.persistence."/persist" = {
    hideMounts = true;
    directories = [
      "/var/lib/nixos"
      "/var/lib/sops-nix"
      "/var/log"
      "/var/lib/systemd"
    ];
    files = [ "/etc/machine-id" ];
  };
}
