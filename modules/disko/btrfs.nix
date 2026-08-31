# Single-disk disko baseline: GPT with 1G ESP, optional swap, and a btrfs
# filesystem taking the rest.  Subvolumes are always the same five:
# @root, @nix, @home, @persist, @games.
#
# This is the btrfs sibling of modules/disko/base.nix (ZFS).  It exists for
# machines that must track a fast-moving kernel: btrfs is in-tree, so it
# never gates the kernel the way out-of-tree OpenZFS does.  birte (Steam
# Deck, `clanarchy.channel = "unstable"`, Valve kernel) is the motivating
# case.  Pair it with `clanarchy.rootfs = "btrfs"` so the matching
# impermanence backend is the one that activates.
#
# LUKS is deliberately not offered here.  The only machine using this is a
# handheld console whose game library isn't sensitive, and a passphrase
# prompt before Gaming Mode is a bad experience.  If an encrypted btrfs
# machine ever appears, add a `luks` content layer rather than stretching
# this template.
#
# Parameters:
#   device          — /dev/disk/by-id/... path (required)
#   enableSwap      — add a swap partition (default false)
#   swapSize        — swap partition size, disko syntax (default "8G")
#   encryptSwap     — randomEncryption on the swap partition (default true;
#                     set false when hybrid-sleep must resume across reboots
#                     — the swap key would otherwise be lost on
#                     suspend-to-both)
#   gamesMountpoint — where the @games subvol lands (default "/games").
#                     Machines with a persistent home can point this
#                     straight at the library directory inside it, which
#                     avoids a second bind mount — birte uses
#                     /home/deck/.local/share/Steam.  Whoever sets this is
#                     responsible for the mountpoint's ownership (a fresh
#                     subvol is root:root); see machines/birte/deck.nix.
#   diskName        — disko's name for this disk, which becomes the GPT
#                     partition label prefix: `disk-<diskName>-<partition>`.
#                     MUST be unique per machine, and must never be "main".
#
#                     The Clan installer USB is flashed with `--disk main`,
#                     so its ESP is labelled `disk-main-ESP`. If the target's
#                     ESP carries that same label, then during
#                     `clan machines install` both are present and
#                     /dev/disk/by-partlabel/disk-main-ESP is ambiguous —
#                     bootctl writes the bootloader to whichever udev
#                     resolved last. That silently installed birte's
#                     bootloader onto the USB stick: the Deck's internal ESP
#                     was left empty and the machine could not boot without
#                     the stick in it.
{
  device,
  diskName,
  enableSwap ? false,
  swapSize ? "8G",
  encryptSwap ? true,
  gamesMountpoint ? "/games",
}:
{ lib, ... }:
assert lib.assertMsg (diskName != "main") ''
  modules/disko/btrfs.nix: diskName must not be "main" — it collides with the
  Clan installer USB's partition labels during `clan machines install`.
'';
let
  # Mirrors the ZFS template's rootFsOptions (compression = zstd,
  # atime = off) so both backends behave the same way.
  commonOpts = [ "compress=zstd" "noatime" ];
in
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
            btrfs = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [ "-L" "btrfsroot" ];
                subvolumes = {
                  "@root" = { mountpoint = "/"; mountOptions = commonOpts; };
                  "@nix" = { mountpoint = "/nix"; mountOptions = commonOpts; };
                  "@home" = { mountpoint = "/home"; mountOptions = commonOpts; };
                  "@persist" = { mountpoint = "/persist"; mountOptions = commonOpts; };

                  # Steam library.  Kept out of the rollback path entirely
                  # (see modules/btrfs-impermanence.nix) and mounted
                  # nodatacow: btrfs copy-on-write fragments large,
                  # repeatedly-rewritten game files badly.  nodatacow
                  # implies nodatasum and disables compression for this
                  # subvolume, which is what we want for game assets that
                  # are already compressed.
                  "@games" = {
                    mountpoint = gamesMountpoint;
                    mountOptions = [ "nodatacow" "noatime" ];
                  };
                };
              };
            };
          };
      };
    };
  };
}
