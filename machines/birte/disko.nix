{...}: {
  disko.devices = {
    disk.main = {
      type = "disk";
      # IMPORTANT:
      # Boot from the Clan installer USB (via a USB-C hub on the Deck).
      # SSH into the installer, then:
      #   ls -l /dev/disk/by-id/
      # The Deck's internal NVMe shows up as something like:
      #   /dev/disk/by-id/nvme-<model>_<serial>
      # Replace the value below with the full by-id path.
      # DO NOT use /dev/nvme0n1 directly.
      device = "/dev/disk/by-id/CHANGEME-steamdeck-internal-nvme";

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
              extraArgs = ["-n" "ESP"];
              mountOptions = ["umask=0077"];
            };
          };

          # No swap partition — the Deck relies on zram (kernel default) and
          # hybrid-sleep is disabled in configuration.nix. Add a swap partition
          # here + boot.resumeDevice + hybridSleep.enable=true if that changes.

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

      # No encryption — matches biene. Deck's game library isn't sensitive,
      # and encryption would prompt for a passphrase before Gaming Mode.
      rootFsOptions = {
        compression = "zstd";
        atime = "off";
      };

      datasets = {
        root = {
          type = "zfs_fs";
          mountpoint = "/";
        };
        nix = {
          type = "zfs_fs";
          mountpoint = "/nix";
        };
        home = {
          type = "zfs_fs";
          mountpoint = "/home";
          options.mountpoint = "legacy";
        };
        persist = {
          type = "zfs_fs";
          mountpoint = "/persist";
          options.mountpoint = "legacy";
        };
        tmp = {
          type = "zfs_fs";
          mountpoint = "/tmp";
        };
      };
    };
  };
}
