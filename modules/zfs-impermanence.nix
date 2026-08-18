# ZFS impermanence backend — active when `clanarchy.rootfs = "zfs"` (the
# fleet default).  The option itself and the shared persist/stage-1 bits
# live in modules/rootfs.nix; the btrfs sibling is
# modules/btrfs-impermanence.nix.
{ config, lib, pkgs, ... }:
let
  # The datasets rolled back on every boot. Kept in one place so the stage-1
  # rollback and the post-boot check below cannot disagree about the set.
  rollbackDatasets = [ "zroot/root" "zroot/home" ];
in
{
  config = lib.mkIf (config.clanarchy.rootfs == "zfs") {
    boot.supportedFilesystems = [ "zfs" "exfat" "ntfs" "vfat" ];
    boot.zfs.forceImportRoot = false;

    # Roll back root and home to @blank ZFS snapshots on every boot (stage 1).
    # Create the snapshots once after initial install:
    #   zfs snapshot zroot/root@blank && zfs snapshot zroot/home@blank
    #
    # ── Why this is not just `zfs rollback … || true` ─────────────────────────
    # It used to be, and that hid a broken invariant on ernst for a month: the
    # @blank snapshots had never been created, `|| true` made a missing
    # snapshot indistinguishable from a successful rollback, and the machine
    # quietly accumulated state outside /persist since install.  Nothing
    # anywhere said so — CLAUDE.md described ernst as rolling back, and it was
    # only noticed because a stale symlink survived a reboot it should not
    # have.
    #
    # So the two failure cases are now separated:
    #
    #   * snapshot missing  — cannot be fixed from the initrd, and hard-failing
    #     here would leave an unbootable machine (notably on a fresh install,
    #     before anyone has had the chance to run `zfs snapshot`).  Warn
    #     loudly and carry on; the check unit below turns it into a *visible,
    #     failed* unit once userspace is up.
    #   * rollback itself failed — a real problem (pool trouble, a clone
    #     holding the snapshot).  That now aborts instead of being swallowed.
    boot.initrd.systemd.services.rollback = {
      description = "Rollback ZFS datasets to blank";
      wantedBy = [ "initrd.target" ];
      after = [ "zfs-import-zroot.service" ];
      before = [ "sysroot.mount" ];
      unitConfig.DefaultDependencies = "no";
      serviceConfig.Type = "oneshot";
      script = ''
        set -u
        for ds in ${lib.escapeShellArgs rollbackDatasets}; do
          if zfs list -H -o name -t snapshot "$ds@blank" > /dev/null 2>&1; then
            zfs rollback -r "$ds@blank"
          else
            echo "clanarchy: WARNING — $ds@blank does not exist."
            echo "clanarchy: $ds is NOT being rolled back; this machine is"
            echo "clanarchy: accumulating state outside /persist."
            echo "clanarchy: create it with:  zfs snapshot $ds@blank"
          fi
        done
      '';
    };

    # Post-boot tripwire for the case the initrd can only warn about.
    #
    # Deliberately a *failing* unit rather than a log line: a failed unit shows
    # up in `systemctl --failed` and, more usefully, in the tail of every
    # `nixos-rebuild switch` ("warning: the following units failed: …").  That
    # is the same channel that finally surfaced the ollama mount problem, and
    # it is the one people actually read.
    systemd.services.clanarchy-impermanence-check = {
      description = "Verify the ZFS rollback snapshots this machine depends on exist";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ config.boot.zfs.package ];
      script = ''
        missing=""
        for ds in ${lib.escapeShellArgs rollbackDatasets}; do
          zfs list -H -o name -t snapshot "$ds@blank" > /dev/null 2>&1 \
            || missing="$missing $ds@blank"
        done

        if [ -n "$missing" ]; then
          echo "Missing rollback snapshot(s):$missing" >&2
          echo "This machine's root is NOT impermanent — anything written" >&2
          echo "outside /persist survives reboots, contrary to the fleet's" >&2
          echo "design and to what the docs claim." >&2
          echo "" >&2
          echo "Create them (destroys nothing; snapshots the current state" >&2
          echo "as the new blank baseline, so do it on a freshly-installed" >&2
          echo "or deliberately-cleaned root):" >&2
          for s in $missing; do echo "  zfs snapshot $s" >&2; done
          exit 1
        fi

        echo "rollback snapshots present:${
          lib.concatMapStrings (d: " ${d}@blank") rollbackDatasets
        }"
      '';
    };
  };
}
