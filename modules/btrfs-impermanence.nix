# btrfs impermanence backend — active when `clanarchy.rootfs = "btrfs"`.
# The option and the shared persist/stage-1 bits live in modules/rootfs.nix;
# the ZFS sibling is modules/zfs-impermanence.nix.
#
# Behaviourally equivalent to the ZFS backend: both `@root` and `@home` are
# blanked on every boot, so only state declared through
# `environment.persistence` survives.  One rule across the fleet — a Deck
# is not an excuse for a machine whose contents nobody can account for.
#
# The game library therefore lives on its own `@games` subvol, mounted
# outside the rollback path (default /games) and symlinked into the user's
# home — see machines/birte/deck.nix.  Keeping it out of `@home` means
# hundreds of GB of downloads are never rolled back, and lets it carry
# `nodatacow`, which `@home` should not have.  Mounting it *outside* home
# also matters because the persisted `.local/share` is an impermanence
# bind-mount: a subvol mounted underneath that path would be shadowed by
# the bind and silently disappear.
{ config, lib, ... }:
let
  # disko names partitions `disk-<disk>-<partition>`; ours is disk.main /
  # partition `btrfs` (see modules/disko/btrfs.nix).  The rollback runs
  # before sysroot.mount, so it addresses the raw partition rather than a
  # mounted path.
  rootPart = "/dev/disk/by-partlabel/disk-main-btrfs";
in
{
  config = lib.mkIf (config.clanarchy.rootfs == "btrfs") {
    boot.supportedFilesystems = [ "btrfs" "exfat" "ntfs" "vfat" ];

    # Roll @root and @home back to their blank snapshots on every boot
    # (stage 1).
    #
    # The blank snapshots are seeded automatically on first boot rather than
    # by a manual post-install step (which the ZFS backend does require).
    # That is deliberate: this deletes a subvolume before restoring it, so a
    # missing `-blank` snapshot would leave the machine with no root subvol
    # at all — unbootable, in stage 1, on a handheld with no easy console.
    # Seeding in-band makes that state unreachable.
    #
    # Unit name matches the ZFS backend's on purpose: modules/vm-variant.nix
    # disables `boot.initrd.systemd.services.rollback` by name so build-vm
    # works for either backend without special-casing.
    boot.initrd.systemd.services.rollback = {
      description = "Rollback btrfs @root and @home to blank";
      wantedBy = [ "initrd.target" ];
      before = [ "sysroot.mount" ];
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = ''
        set -eu
        mkdir -p /btrfs_tmp
        mount -o subvolid=5 ${rootPart} /btrfs_tmp

        for sub in @root @home; do
          if [ ! -e "/btrfs_tmp/$sub-blank" ]; then
            # First boot after install: the subvol is the pristine
            # freshly-installed state, so capture it as the baseline and
            # leave it in place.
            btrfs subvolume snapshot "/btrfs_tmp/$sub" "/btrfs_tmp/$sub-blank"
          else
            # btrfs refuses to delete a subvolume that still contains
            # subvolumes, so clear any nested ones first.  `subvolume list -o`
            # prints paths relative to the mount point in field 9.  @games is
            # a top-level sibling, not nested here, so it is never touched.
            if [ -e "/btrfs_tmp/$sub" ]; then
              btrfs subvolume list -o "/btrfs_tmp/$sub" | cut -f9 -d' ' |
                while read -r nested; do
                  btrfs subvolume delete "/btrfs_tmp/$nested" || true
                done
              btrfs subvolume delete "/btrfs_tmp/$sub"
            fi
            btrfs subvolume snapshot "/btrfs_tmp/$sub-blank" "/btrfs_tmp/$sub"
          fi
        done

        umount /btrfs_tmp
      '';
    };
  };
}
