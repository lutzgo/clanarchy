{ ... }:
{
  disko.devices = {
    disk.main = {
      type = "disk";
      # IMPORTANT:
      # Boot from the Clan installer USB.
      # SSH into the installer:
      #   ssh root@<installer-ip>
      #
      # Then determine the stable disk ID with:
      #   ls -l /dev/disk/by-id/
      #
      # Choose the correct disk and replace the value below
      # with the full path, e.g.:
      #   /dev/disk/by-id/nvme-Samsung_SSD_980_PRO_1TB_S6XYZ123456
      #
      # DO NOT use /dev/sda or /dev/nvme0n1 directly.
      device = "/dev/disk/by-id/REPLACE_ME";

      content = {
        type = "gpt";

        partitions = {
          ESP = {
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          };

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
      mode = "single";

      rootFsOptions = {
        compression = "zstd";
        atime = "off";

        encryption = "aes-256-gcm";
        keyformat = "passphrase";
        keylocation = "prompt";
      };

      datasets = {
        root = { type = "zfs_fs"; mountpoint = "/"; };
        nix = { type = "zfs_fs"; mountpoint = "/nix"; };
        home = { type = "zfs_fs"; mountpoint = "/home"; };
        persist = { type = "zfs_fs"; mountpoint = "/persist"; };
        tmp = { type = "zfs_fs"; mountpoint = "/tmp"; };
      };
    };
  };
}
