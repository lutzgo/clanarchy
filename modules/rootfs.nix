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
# and each guards its own body on this option.  This file holds only what
# they share.
#
# ── THE CHOICE IS THE MACHINE'S, AND THE KERNEL PIN IS WHY IT CAN BE ───────
#
# OpenZFS is out-of-tree, so it gates the kernel.  That used to make this
# option a derivation of `clanarchy.channel`: stable -> zfs, unstable -> btrfs,
# `readOnly`, on the reasoning that a machine tracking unstable could not also
# carry an out-of-tree filesystem module.
#
# That coupling is retired, because it answered the kernel problem by
# forbidding the combination instead of solving it.  #367 solved it directly
# with an explicit `zfs.latestCompatibleLinuxPackages` pin; nixpkgs has since
# deprecated that attribute and made the DEFAULT kernel the ZFS-compatible
# one, so the guarantee is upstream now and the pin is gone again.  See the
# note next to `fileSystems` below.
#
# This had to go before the fleet could move to one channel.  With the
# derivation in place, putting every machine on unstable would have silently
# switched ernst, miralda, jens and biene — all ZFS — onto the *btrfs*
# rollback path, which looks for `@root` on a partlabel that does not exist,
# in stage 1, where there is no shell and no journal.
#
# So each machine now states its filesystem, and there is no default: a new
# machine that forgets fails the assertion below rather than inheriting a
# guess.  Changing it is still a reinstall — this option describes the disk,
# it does not reshape it.
#
# See docs/guides/first-time-install.md for the one-time blank-snapshot step,
# which differs per backend.
{
  config,
  lib,
  ...
}: {
  options.clanarchy.rootfs = lib.mkOption {
    type = lib.types.enum ["zfs" "btrfs"];
    example = "btrfs";
    description = ''
      Which filesystem backs this machine's root, and therefore which
      impermanence rollback implementation is active.

      **Set this per machine; there is no default.** It describes the disk as
      installed, so changing it is a reinstall, not a deploy. A machine with
      `"zfs"` also gets `zfs.latestCompatibleLinuxPackages` as its kernel (see
      the header) — that pin is what lets a ZFS machine sit on any channel.
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
    # NO EXPLICIT KERNEL PIN, and that is a deliberate reversal.
    #
    # #367 set `boot.kernelPackages = zfs.latestCompatibleLinuxPackages` here,
    # so a ZFS machine could not be handed a kernel its module would not build
    # against — the thing that made it safe to put ZFS machines on a
    # fast-moving channel at all.
    #
    # nixpkgs has since deprecated that attribute: it now aliases the default
    # kernel and warns on use.  Measured 2026-11-01 — `linuxPackages` 6.18.59,
    # `zfs.latestCompatibleLinuxPackages` 6.18.59, the same derivation.  The
    # guarantee moved upstream rather than disappearing: the default kernel is
    # the ZFS-compatible one, and `boot.zfs` fails loudly if that ever stops
    # being true.
    #
    # So this is now one fewer thing for this repo to own.  If a machine ever
    # does need a specific kernel, say so in that machine's configuration.nix
    # — the deprecation message's own advice (`boot.kernelPackages =
    # pkgs.linuxPackages_6_6`).

    # No `boot.initrd.systemd.enable` here any more: nixpkgs removed the
    # scripted initrd, so systemd in stage 1 is the only option and setting
    # it asserts ("Scripted initrd has been removed").  Both impermanence
    # backends still need it — their rollback units are systemd-initrd
    # services — they just get it unconditionally now.
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
      files = ["/etc/machine-id"];
    };

    # ── /var/lib/private MUST BE 0700, AND IMPERMANENCE MAKES IT 0755 ────────
    #
    # systemd puts the state of every `DynamicUser` unit that declares a
    # `StateDirectory` under /var/lib/private, and it REFUSES TO START such a
    # unit if that directory is more permissive than 0700:
    #
    #   Directory "/var/lib/private" already exists, but has mode 0755 that is
    #   too permissive (0700 was requested), refusing.
    #   Failed at step STATE_DIRECTORY spawning …: File exists
    #   status=238/STATE_DIRECTORY
    #
    # Upstream systemd creates it 0700 itself, so this never comes up on an
    # ordinary machine.  On an impermanent one it does: persisting anything
    # under that path makes IMPERMANENCE create the parent, and it creates
    # parents with the default 0755.  The `mode` given on a persist entry
    # applies to the entry itself, not to the directories made to reach it.
    #
    # MEASURED ON ernst 2026-09-24, on M29's deploy: /var/lib/private came out
    # drwxr-xr-x with a correct drwx------ bind mount inside it, and both
    # Wyoming voice servers failed at every start.
    #
    # It is fleet-wide rather than in the module that tripped over it because
    # nothing about it is specific to that service: ANY DynamicUser unit with a
    # StateDirectory on ANY impermanent machine here hits it, and the symptom
    # names systemd rather than impermanence.  tmpfiles runs before
    # multi-user.target, and `d` adjusts an existing directory's mode without
    # touching what is mounted inside it.
    #
    # See service-modules/local-ai.nix's `user` option for this family's other
    # member — the one where the dynamic uid cannot write to a persisted
    # root:root 0700 directory. That one is avoided by not using DynamicUser at
    # all; this one is a property of the path itself and has to be fixed here.
    systemd.tmpfiles.rules = ["d /var/lib/private 0700 root root -"];
  };
}
