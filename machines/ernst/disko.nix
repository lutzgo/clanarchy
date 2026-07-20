# ernst — storage layout:
#   zroot   mirror across 2× PM1643a 960 GB SAS SSDs   (encrypted, system pool)
#   zdata   raidz1 across  6× PM1643a 15.36 TB SAS SSDs (encrypted, data pool)
#
# Both pools use aes-256-gcm.  zroot is unlocked with a passphrase prompt in
# stage 1.  zdata is unlocked in stage 2 by zfs-import-zdata.service, which
# reads a 32-byte raw key from a keyfile on zroot (/persist/zdata.key) — one
# interactive prompt per boot, no console needed for the bulk pool.  See
# `boot.zfs.extraPools` in machines/ernst/configuration.nix and the Phase 4
# one-time-setup docs.  The `keyformat = "passphrase"` / `keylocation =
# "prompt"` set on the pool below is the INITIAL install-time value; after
# `zfs change-key -o keyformat=raw -o keylocation=file:///persist/zdata.key
# zdata` the on-pool metadata is the source of truth (disko does not manage
# it after install).
#
# Before installing:
#   ssh root@<installer-ip>
#   ls -l /dev/disk/by-id/
# and replace every CHANGEME-… below with a real stable disk-id path.
#
# ESP + swap live only on system-a.  If system-a's disk dies you can boot a
# recovery USB, `dd` the ESP partition over from a backup, or extend this file
# later with a second ESP + boot.loader.systemd-boot.mirroredBoots.  Swap is
# 16 GB and randomly-encrypted at every boot — the key never persists, so
# hibernation is not supported.
{ ... }:
{
  disko.devices = {

    # ── System pool: 2× 960 GB SAS SSD, mirrored ─────────────────────────────
    disk.system-a = {
      type = "disk";
      device = "/dev/disk/by-id/wwn-0x5002538b7263f800"; # PM1643a 960G  S5G1NC0T602213
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "1G";
            type = "EF00";
            content = {
              type         = "filesystem";
              format       = "vfat";
              mountpoint   = "/boot";
              extraArgs    = [ "-n" "ESP" ];
              mountOptions = [ "umask=0077" ];
            };
          };
          swap = {
            size = "16G";
            content = {
              type             = "swap";
              randomEncryption = true;
              discardPolicy    = "both";
            };
          };
          zfs = {
            size    = "100%";
            content = { type = "zfs"; pool = "zroot"; };
          };
        };
      };
    };

    disk.system-b = {
      type = "disk";
      device = "/dev/disk/by-id/wwn-0x5002538b722787f0"; # PM1643a 960G  S5G1NC0T203063
      content = {
        type = "gpt";
        partitions.zfs = {
          size    = "100%";
          content = { type = "zfs"; pool = "zroot"; };
        };
      };
    };

    # ── Data pool: 6× 15.36 TB SAS SSD, raidz1 ───────────────────────────────
    # Ordered by serial number for repeatability across re-installs.
    disk.data-1 = { type = "disk"; device = "/dev/disk/by-id/wwn-0x5002538b0213bbe0"; # PM1643a 15.36T  S5DENE0T100746
      content = { type = "gpt"; partitions.zfs = { size = "100%"; content = { type = "zfs"; pool = "zdata"; }; }; };
    };
    disk.data-2 = { type = "disk"; device = "/dev/disk/by-id/wwn-0x5002538b0213bc20"; # PM1643a 15.36T  S5DENE0T100750
      content = { type = "gpt"; partitions.zfs = { size = "100%"; content = { type = "zfs"; pool = "zdata"; }; }; };
    };
    disk.data-3 = { type = "disk"; device = "/dev/disk/by-id/wwn-0x5002538b0213bc30"; # PM1643a 15.36T  S5DENE0T100751
      content = { type = "gpt"; partitions.zfs = { size = "100%"; content = { type = "zfs"; pool = "zdata"; }; }; };
    };
    disk.data-4 = { type = "disk"; device = "/dev/disk/by-id/wwn-0x5002538b0213bc80"; # PM1643a 15.36T  S5DENE0T100756
      content = { type = "gpt"; partitions.zfs = { size = "100%"; content = { type = "zfs"; pool = "zdata"; }; }; };
    };
    disk.data-5 = { type = "disk"; device = "/dev/disk/by-id/wwn-0x5002538b0214e620"; # PM1643a 15.36T  S5DENE0T100909
      content = { type = "gpt"; partitions.zfs = { size = "100%"; content = { type = "zfs"; pool = "zdata"; }; }; };
    };
    disk.data-6 = { type = "disk"; device = "/dev/disk/by-id/wwn-0x5002538b0311c2b0"; # PM1643a 15.36T  S5DENA0W101156
      content = { type = "gpt"; partitions.zfs = { size = "100%"; content = { type = "zfs"; pool = "zdata"; }; }; };
    };

    # ── zroot: mirror, encrypted, root filesystems ───────────────────────────
    zpool.zroot = {
      type = "zpool";
      mode = "mirror";

      rootFsOptions = {
        compression = "zstd";
        atime       = "off";
        encryption  = "aes-256-gcm";
        keyformat   = "passphrase";
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

    # ── zdata: raidz1, encrypted, no mountpoints (datasets created later) ────
    zpool.zdata = {
      type = "zpool";
      mode = "raidz1";

      rootFsOptions = {
        compression = "zstd";
        atime       = "off";
        encryption  = "aes-256-gcm";
        keyformat   = "passphrase";
        keylocation = "prompt";
        # Pool is for bulk storage; do not auto-mount at /.
        mountpoint  = "none";
      };
    };
  };
}
