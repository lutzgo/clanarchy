# Root filesystem strategy + the impermanence bits common to both backends.
#
# Every clanarchy machine is impermanent: `/` is rolled back to a blank
# snapshot on each boot and anything worth keeping is bind-mounted back in
# from `/persist`.  *How* that rollback happens depends on the filesystem,
# so the mechanism lives in the two sibling modules:
#
#   clanarchy.rootfs = "zfs"    -> modules/zfs-impermanence.nix
#   clanarchy.rootfs = "btrfs"  -> modules/btrfs-impermanence.nix
#
# Both are imported unconditionally by `commonBase` (see lib/mk-machine.nix)
# and each guards its own body on this option, the same way modules/channel.nix
# guards the pkgs swap.  This file holds only what they share.
#
# Why two backends: ZFS is the fleet default and gives us encryption plus
# cheap dataset snapshots.  But OpenZFS is out-of-tree, so it gates the
# kernel — which is a problem on a machine that has to track a fast-moving
# one.  birte (Steam Deck, `clanarchy.channel = "unstable"`, Valve kernel)
# uses btrfs for exactly that reason: it is in-tree and never holds the
# kernel back.  See docs/guides/first-time-install.md for the one-time
# blank-snapshot step, which differs per backend.
{ lib, ... }:
{
  options.clanarchy.rootfs = lib.mkOption {
    type = lib.types.enum [ "zfs" "btrfs" ];
    default = "zfs";
    example = "btrfs";
    description = ''
      Which filesystem backs this machine's root, and therefore which
      impermanence rollback implementation is active.
      - `zfs`   — the fleet default (miralda, biene, ernst).
      - `btrfs` — in-tree, does not gate the kernel; used by birte.
    '';
  };

  options.clanarchy.impermanence.rollback.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Whether the stage-1 rollback unit runs. Setting this false leaves the
      machine's root mutable — impermanence is off — but keeps the layout,
      the persist bind-mounts and everything else intact.

      This is an escape hatch, not a configuration choice. Its purpose is to
      get a machine that fails in stage 1 to a point where it can be logged
      into and debugged, without a reinstall and without hand-editing the
      kernel command line on hardware that may not have a keyboard. A machine
      left in this state is accumulating state outside /persist, and
      clanarchy-impermanence-check will not save you — it verifies the blank
      snapshots exist, not that anything rolls back to them.
    '';
  };

  config = {
    # Impermanence needs /persist and /home mounted in stage 1, and the
    # rollback units in both backends are systemd-initrd services.
    boot.initrd.systemd.enable = true;
    fileSystems."/persist".neededForBoot = true;
    fileSystems."/home".neededForBoot = true;

    # System-level persist paths shared by all clanarchy machines.
    # Per-machine additions (e.g. /var/lib/flatpak) live in
    # machines/*/configuration.nix or the module enabling the service.
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
  };
}
