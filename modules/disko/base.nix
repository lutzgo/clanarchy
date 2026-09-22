# Single-disk disko baseline: GPT with 1G ESP, optional swap, and a
# ZFS pool ("zroot") taking the rest.  Datasets are always the same
# five: root, nix, home (legacy), persist (legacy), tmp.
#
# Callers pass `device` (required, /dev/disk/by-id/... path) and
# optionally toggle swap + encryption.  Machines with multi-disk
# layouts (mirror, raidz, mixed pools) should not use this template
# — write their disko.nix by hand (see machines/ernst/disko.nix).
#
# Parameters:
#   device            — /dev/disk/by-id/... path (required)
#   diskName          — disko's name for this disk, which becomes the GPT
#                       partition label prefix: `disk-<diskName>-<partition>`.
#                       SHOULD be the machine name, and must never be "main".
#
#                       The Clan installer USB is flashed with `--disk main`,
#                       so its ESP is labelled `disk-main-ESP`.  If the
#                       target's ESP carries that same label then during
#                       `clan machines install` both are present and
#                       /dev/disk/by-partlabel/disk-main-ESP is ambiguous —
#                       disko formats, and bootctl writes the bootloader to,
#                       whichever one udev resolved last.
#
#                       This is not hypothetical twice over.  It put birte's
#                       bootloader on the stick (see modules/disko/btrfs.nix,
#                       where the same parameter was added as the fix), and
#                       then on 2026-09-22 it did it again to jens: the
#                       reinstall wrote jens's kernel, initrd and systemd-boot
#                       onto the USB stick, left the internal ESP holding the
#                       2026-09-01 bootloader, and the machine dropped into
#                       initrd emergency at `Failed to start Find NixOS
#                       closure` — the old entry's `init=` naming a closure
#                       that disko had just destroyed.  Observed directly on
#                       miralda with the stick inserted:
#                       /dev/disk/by-partlabel/disk-main-ESP -> ../../sda2.
#
#                       DEFAULTS TO "main" ONLY BECAUSE miralda AND biene ARE
#                       ALREADY INSTALLED WITH THOSE LABELS.  Renaming a disk
#                       relabels nothing on a live machine — labels are set at
#                       partition-creation time — but it *does* repoint the
#                       fileSystems entries disko generates, at a
#                       by-partlabel path that does not exist there.  So each
#                       of those machines needs its /boot (and biene's
#                       resumeDevice) pinned to a by-id path first, and the
#                       rename only takes effect at its next reinstall.
#                       Until then they carry this hazard.  New and
#                       reinstalled machines must pass their own name.
#   enableSwap        — add a swap partition (default false)
#   swapSize          — swap partition size, disko syntax (default "8G")
#   encryptSwap       — randomEncryption on the swap partition
#                       (default true; set false when hybrid-sleep
#                       must resume across reboots — the swap key would
#                       otherwise be lost on suspend-to-both)
#   enableEncryption  — aes-256-gcm on the ZFS pool, passphrase-prompted
#                       at boot (default true)
{
  device,
  diskName ? "main",
  enableSwap ? false,
  swapSize ? "8G",
  encryptSwap ? true,
  enableEncryption ? true,
}:
{ lib, ... }:
{
  disko.devices = {
    disk.${diskName} = {
      type = "disk";
      inherit device;
      content = {
        type = "gpt";
        partitions =
          {
            ESP = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                extraArgs = [ "-n" "ESP" ];
                mountOptions = [ "umask=0077" ];
              };
            };
          }
          // lib.optionalAttrs enableSwap {
            swap = {
              size = swapSize;
              content =
                { type = "swap"; }
                // lib.optionalAttrs encryptSwap { randomEncryption = true; };
            };
          }
          // {
            zfs = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "zroot";
              };
            };
          };
      };
    };

    zpool.zroot = {
      type = "zpool";
      mode = "";

      rootFsOptions =
        {
          compression = "zstd";
          atime = "off";
        }
        // lib.optionalAttrs enableEncryption {
          encryption = "aes-256-gcm";
          keyformat = "passphrase";
          keylocation = "prompt";
        };

      # ── auto-snapshot opt-in ──────────────────────────────────────────
      # clan-core enables `services.zfs.autoSnapshot` for every machine
      # (nixosModules/clanCore/zfs.nix, vendored from srvos), but
      # zfs-auto-snapshot only touches datasets carrying the
      # `com.sun:auto-snapshot` property — see the option description in
      # nixpkgs' zfs.nix.  disko sets no such property, so out of the box
      # those five timers (frequent/hourly/daily/weekly/monthly) run and
      # snapshot nothing.
      #
      # Opt in exactly the two datasets whose contents are not disposable.
      # `root` and `nix` are deliberately excluded: root is rolled back to
      # @blank on every boot (modules/zfs-impermanence.nix) so snapshots of
      # it are worthless, and /nix is reproducible from the flake.
      #
      # NOTE: disko applies dataset properties at creation time, so this
      # only affects machines installed after this lands.  On already-
      # installed machines, apply it once by hand:
      #   zfs set com.sun:auto-snapshot=true zroot/home zroot/persist
      datasets = {
        root    = { type = "zfs_fs"; mountpoint = "/"; };
        nix     = { type = "zfs_fs"; mountpoint = "/nix"; };
        home    = {
          type = "zfs_fs";
          mountpoint = "/home";
          options = {
            mountpoint = "legacy";
            "com.sun:auto-snapshot" = "true";
          };
        };
        persist = {
          type = "zfs_fs";
          mountpoint = "/persist";
          options = {
            mountpoint = "legacy";
            "com.sun:auto-snapshot" = "true";
          };
        };
        tmp     = { type = "zfs_fs"; mountpoint = "/tmp"; };
      };
    };
  };
}
