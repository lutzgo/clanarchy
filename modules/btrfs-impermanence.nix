# btrfs impermanence backend — active when `clanarchy.rootfs = "btrfs"`.
# The option and the shared persist/stage-1 bits live in modules/rootfs.nix;
# the ZFS sibling is modules/zfs-impermanence.nix.
#
# ── Difference from the ZFS backend: home is NOT rolled back ──────────
# The ZFS module blanks both `zroot/root` and `zroot/home`.  Here only
# `@root` is blanked.  The machine using this is birte, a Steam Deck: the
# `deck` user's home holds Steam and gamescope state that Gaming Mode
# expects to survive reboots, and blanking it would mean re-onboarding the
# Deck on every boot.  `@home` is therefore an ordinary persistent subvol.
#
# The game library gets its own subvol (`@games`, mounted at /persist/steam
# and bind-mounted into deck's home — see machines/birte/deck.nix) so that
# hundreds of GB of downloads are never in the rollback path and can carry
# `nodatacow`, which `@home` should not have.
#
# This is deliberately weaker impermanence than the rest of the fleet.
# Revisit if a second btrfs machine wants strict home rollback — at that
# point this should grow a `clanarchy.rootfs.rollbackHome` toggle rather
# than being changed in place.
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

    # Roll @root back to the blank snapshot on every boot (stage 1).
    #
    # The blank snapshot is seeded automatically on first boot rather than
    # by a manual post-install step (which the ZFS backend does require).
    # That is deliberate: this script deletes @root before restoring it, so
    # a missing @root-blank would leave the machine with no root subvolume
    # at all — unbootable, in stage 1, on a handheld with no easy console.
    # Seeding in-band makes that state unreachable.
    #
    # Unit name matches the ZFS backend's on purpose: modules/vm-variant.nix
    # disables `boot.initrd.systemd.services.rollback` by name so build-vm
    # works for either backend without special-casing.
    boot.initrd.systemd.services.rollback = {
      description = "Rollback btrfs @root to blank";
      wantedBy = [ "initrd.target" ];
      before = [ "sysroot.mount" ];
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = ''
        set -eu
        mkdir -p /btrfs_tmp
        mount -o subvolid=5 ${rootPart} /btrfs_tmp

        if [ ! -e /btrfs_tmp/@root-blank ]; then
          # First boot after install: @root is the pristine freshly-installed
          # system, so capture it as the baseline and leave it in place.
          btrfs subvolume snapshot /btrfs_tmp/@root /btrfs_tmp/@root-blank
        else
          # btrfs refuses to delete a subvolume that still contains
          # subvolumes, so clear any nested ones first.  `subvolume list -o`
          # prints paths relative to the mount point in field 9.
          if [ -e /btrfs_tmp/@root ]; then
            btrfs subvolume list -o /btrfs_tmp/@root | cut -f9 -d' ' |
              while read -r sub; do
                btrfs subvolume delete "/btrfs_tmp/$sub" || true
              done
            btrfs subvolume delete /btrfs_tmp/@root
          fi
          btrfs subvolume snapshot /btrfs_tmp/@root-blank /btrfs_tmp/@root
        fi

        umount /btrfs_tmp
      '';
    };
  };
}
