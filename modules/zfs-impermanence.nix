# ZFS impermanence backend — active when `clanarchy.rootfs = "zfs"` (the
# fleet default).  The option itself and the shared persist/stage-1 bits
# live in modules/rootfs.nix; the btrfs sibling is
# modules/btrfs-impermanence.nix.
{ config, lib, ... }:
{
  config = lib.mkIf (config.clanarchy.rootfs == "zfs") {
    boot.supportedFilesystems = [ "zfs" "exfat" "ntfs" "vfat" ];
    boot.zfs.forceImportRoot = false;

    # Roll back root and home to @blank ZFS snapshots on every boot (stage 1).
    # Create the snapshots once after initial install:
    #   zfs snapshot zroot/root@blank && zfs snapshot zroot/home@blank
    boot.initrd.systemd.services.rollback = {
      description = "Rollback ZFS datasets to blank";
      wantedBy = [ "initrd.target" ];
      after = [ "zfs-import-zroot.service" ];
      before = [ "sysroot.mount" ];
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = ''
        zfs rollback -r zroot/root@blank || true
        zfs rollback -r zroot/home@blank || true
      '';
    };
  };
}
