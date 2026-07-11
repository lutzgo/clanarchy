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
  enableSwap ? false,
  swapSize ? "8G",
  encryptSwap ? true,
  enableEncryption ? true,
}:
{ lib, ... }:
{
  disko.devices = {
    disk.main = {
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

      datasets = {
        root    = { type = "zfs_fs"; mountpoint = "/"; };
        nix     = { type = "zfs_fs"; mountpoint = "/nix"; };
        home    = { type = "zfs_fs"; mountpoint = "/home";    options.mountpoint = "legacy"; };
        persist = { type = "zfs_fs"; mountpoint = "/persist"; options.mountpoint = "legacy"; };
        tmp     = { type = "zfs_fs"; mountpoint = "/tmp"; };
      };
    };
  };
}
