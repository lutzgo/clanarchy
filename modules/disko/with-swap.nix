# Template disko config for new machines: 1G ESP + swap partition + ZFS rest.
#
# Usage: import this file and set disko.devices.disk.main.device to the
# stable /dev/disk/by-id/... path of the target disk.
#
# Swap strategy: zswap (compressed in-memory cache backed by disk swap).
# Enable via boot.kernelParams in the machine's configuration.nix:
#
#   boot.kernelParams = [ "zswap.enabled=1" "zswap.compressor=zstd" "zswap.max_pool_percent=20" ];
#
# zswap keeps a compressed pool in RAM (up to 20% of RAM) and only evicts to
# the physical swap partition under memory pressure.  This reduces disk I/O
# compared to raw swap while keeping the disk partition as a fallback.
#
# Alternative — ZRAM (pure RAM compression, no disk fallback):
#   zramSwap = { enable = true; algorithm = "zstd"; memoryPercent = 50; };
# ZRAM is better for machines without a swap partition; zswap is better when
# a disk partition is present (disk acts as overflow, less RAM wasted on buffers).
#
# NOTE: Do NOT apply this template to miralda — miralda has its own disko.nix
# without swap (ZFS pool occupies the entire remaining space after the ESP).
{ swapSize ? "8G" }:
{
  disko.devices = {
    disk.main = {
      type = "disk";
      # Set this to the stable disk ID before installation:
      #   ls -l /dev/disk/by-id/
      device = "/dev/disk/by-id/CHANGEME";

      content = {
        type = "gpt";

        partitions = {
          ESP = {
            size = "1G";
            type = "EF00";
            content = {
              type       = "filesystem";
              format     = "vfat";
              mountpoint = "/boot";
              extraArgs  = [ "-n" "ESP" ];
              mountOptions = [ "umask=0077" ];
            };
          };

          swap = {
            size    = swapSize;
            content = {
              type      = "swap";
              randomEncryption = true;
            };
          };

          zfs = {
            size    = "100%";
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

      rootFsOptions = {
        compression  = "zstd";
        atime        = "off";
        encryption   = "aes-256-gcm";
        keyformat    = "passphrase";
        keylocation  = "prompt";
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
