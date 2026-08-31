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
{ config, lib, pkgs, ... }:
let
  # disko names partitions `disk-<disk>-<partition>`.  The disk name is
  # per-machine and deliberately not "main" (see modules/disko/btrfs.nix for
  # why), so derive it from the disko config rather than hardcoding — a
  # hardcoded `disk-main-btrfs` would silently stop matching the moment a
  # machine picked its own name, and this unit runs in stage 1 where that is
  # expensive to debug.
  diskName = builtins.head (builtins.attrNames config.disko.devices.disk);
  rootPart = "/dev/disk/by-partlabel/disk-${diskName}-btrfs";
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
    boot.initrd.systemd.services.rollback = lib.mkIf config.clanarchy.impermanence.rollback.enable {
      description = "Rollback btrfs @root and @home to blank";
      wantedBy = [ "initrd.target" ];
      # NOTE: `after = [ "initrd-root-device.target" ]` was added here on the
      # theory that the unit races udev for the by-partlabel symlink.  It did
      # not fix the failure, and birte stopped booting entirely on the install
      # carrying it — the only other change in that install being an inert
      # facter refresh (bogomips, an event-node number, a loopback entry).
      # Reverted until someone has actually read the journal.  Do not re-add
      # it without evidence.
      before = [ "sysroot.mount" ];
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = ''
        set -eu
        mkdir -p /btrfs_tmp
        # `-t btrfs` is not optional. Without it mount has to autodetect the
        # type, which needs libblkid's superblock probes — absent from the
        # minimal initrd — and the unit dies with
        #   mount: /btrfs_tmp: no valid filesystem type specified.
        # which reads like a broken device and is not one.
        mount -t btrfs -o subvolid=5 ${rootPart} /btrfs_tmp

        # btrfs refuses to delete a subvolume that still contains subvolumes,
        # so clear any nested ones first.  `subvolume list -o` prints paths
        # relative to the filesystem root in field 9.  @games is a top-level
        # sibling, not nested under either target, so it is never touched.
        delete_tree() {
          target="$1"
          [ -e "$target" ] || return 0
          btrfs subvolume list -o "$target" | cut -f9 -d' ' |
            while read -r nested; do
              btrfs subvolume delete "/btrfs_tmp/$nested" || true
            done
          btrfs subvolume delete "$target"
        }

        for sub in @root @home; do
          if [ ! -e "/btrfs_tmp/$sub-blank" ]; then
            # First boot after install: the subvol is the pristine
            # freshly-installed state, so capture it as the baseline and
            # leave it in place.
            btrfs subvolume snapshot "/btrfs_tmp/$sub" "/btrfs_tmp/$sub-blank"
            continue
          fi

          # Reclaim a leftover from a previous interrupted run.
          delete_tree "/btrfs_tmp/$sub-old"

          # Move the live subvolume aside rather than deleting it outright.
          # The previous shape deleted $sub and only then recreated it from
          # $sub-blank, so any failure in between left the machine with no
          # root subvolume at all — unbootable, in stage 1, on a handheld
          # with no keyboard. This way $sub is absent only for the duration
          # of a rename, and if the snapshot below fails the previous root is
          # still on disk as $sub-old and can be renamed back from an
          # installer.
          if [ -e "/btrfs_tmp/$sub" ]; then
            mv "/btrfs_tmp/$sub" "/btrfs_tmp/$sub-old"
          fi

          btrfs subvolume snapshot "/btrfs_tmp/$sub-blank" "/btrfs_tmp/$sub"

          # Only now that the replacement exists is it safe to reclaim.
          delete_tree "/btrfs_tmp/$sub-old"
        done

        umount /btrfs_tmp
      '';
    };

    # Post-boot tripwire, mirroring the ZFS backend's.
    #
    # It matters more here, not less: the btrfs rollback seeds its own blank
    # snapshots, so a first boot where the unit fails leaves the machine with
    # *no* baseline at all and nothing in `systemctl --failed` to say so —
    # initrd unit failures do not carry into the booted system's state.  That
    # is exactly how ernst went a month without impermanence.
    #
    # A failing unit is deliberate: it surfaces in `systemctl --failed` and in
    # the tail of every deploy ("warning: the following units failed: …").
    systemd.services.clanarchy-impermanence-check = {
      description = "Verify the btrfs rollback snapshots this machine depends on exist";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.btrfs-progs ];
      script = ''
        # `-a` prefixes top-level paths with <FS_TREE>/; strip it so the
        # names compare equal to the @root-blank / @home-blank we create.
        subvols=$(btrfs subvolume list -a / | sed 's|.*[[:space:]]path ||; s|^<FS_TREE>/||')

        missing=""
        for sub in @root @home; do
          printf '%s\n' "$subvols" | grep -qx -- "$sub-blank" \
            || missing="$missing $sub-blank"
        done

        if [ -n "$missing" ]; then
          echo "Missing rollback snapshot(s):$missing" >&2
          echo "This machine's root is NOT impermanent — anything written" >&2
          echo "outside /persist survives reboots, contrary to the fleet's" >&2
          echo "design and to what the docs claim." >&2
          echo "" >&2
          echo "The initrd rollback unit seeds these itself on first boot, so" >&2
          echo "their absence means that unit failed. Check:" >&2
          echo "  journalctl -b -u rollback" >&2
          exit 1
        fi

        echo "rollback snapshots present: @root-blank @home-blank"
      '';
    };
  };
}
