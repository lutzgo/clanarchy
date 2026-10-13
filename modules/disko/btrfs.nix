# Single-disk disko baseline: GPT with 1G ESP, optional swap, and a btrfs
# filesystem taking the rest.  Subvolumes are always the same five:
# @root, @nix, @home, @persist, @games.
#
# This is the btrfs sibling of modules/disko/base.nix (ZFS).  It exists for
# machines that must track a fast-moving kernel: btrfs is in-tree, so it
# never gates the kernel the way out-of-tree OpenZFS does.  birte (Steam
# Deck, `clanarchy.channel = "unstable"`, Valve kernel) is the motivating
# case.  The matching impermanence backend activates on its own: modules/
# rootfs.nix derives `clanarchy.rootfs` from `clanarchy.channel`, so a machine
# using this template is already on btrfs by construction.
#
# Encryption is OPT-IN here, which is the opposite of the ZFS template's
# default, and the asymmetry is deliberate.  ZFS encrypts natively and every
# machine using base.nix wants it; btrfs has no native encryption, so this
# template wraps the filesystem in LUKS instead — and the one machine using it
# today is a handheld console whose game library is not sensitive and for whom
# a passphrase prompt before Gaming Mode is a bad experience.  So `false` by
# default, and a machine that wants it says so.
#
# Parameters:
#   device          — /dev/disk/by-id/... path (required)
#   enableSwap      — add a swap partition (default false)
#   swapSize        — swap partition size, disko syntax (default "8G")
#   encryptSwap     — randomEncryption on the swap partition (default true;
#                     set false when hybrid-sleep must resume across reboots
#                     — the swap key would otherwise be lost on
#                     suspend-to-both)
#   enableEncryption — wrap the btrfs partition in LUKS2, passphrase-prompted
#                     at boot (default false).  Note the prompt comes BEFORE
#                     stage-1 can roll back, so a machine with this on needs
#                     either a keyboard at boot or
#                     `clanarchy.initrdSsh.enable` to unlock remotely.
#   luksName        — /dev/mapper name for the unlocked volume
#                     (default "cryptroot").  Only meaningful with
#                     enableEncryption; it must be unique per machine only in
#                     the sense that a machine has one root.
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
  enableEncryption ? false,
  luksName ? "cryptroot",
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

  # The filesystem itself, independent of whether it sits on bare partition or
  # on a LUKS mapping. Pulled out so the two cases cannot drift: the subvolume
  # set is the thing modules/btrfs-impermanence.nix knows about.
  btrfsContent = {
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
              content =
                if enableEncryption then {
                  type = "luks";
                  name = luksName;
                  # Discards reach the SSD through the mapping. Standard for
                  # flash; it does leak which blocks are in use, which is the
                  # usual and accepted trade.
                  settings.allowDiscards = true;
                  content = btrfsContent;
                } else
                  btrfsContent;
            };
          };
      };
    };
  };
}
