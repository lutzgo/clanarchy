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

    # ── zdata: raidz1, encrypted, bulk-storage datasets ──────────────────────
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

      # Datasets on the bulk pool.
      #
      # These declarations describe the intended layout for a fresh disko
      # install.  On the already-provisioned pool disko does NOT reconcile
      # — the datasets must be created once by hand from a matching runbook
      # (docs/guides/ernst-zdata-datasets.md).  After that the fileSystems
      # entries disko emits from the block below take over declaratively.
      #
      # Design constraint (not to be revisited): the arr suite, qBittorrent,
      # and every media library share ONE dataset — zdata/media — so that
      # hardlinks work across downloads/ and library/.  Downloads and library
      # are plain subdirectories under /srv/media, never sub-datasets.
      #
      # Compression + atime are inherited from rootFsOptions.  Encryption is
      # inherited too (single per-pool raw key on /persist/zdata.key).
      datasets = {
        # /srv/media — single hardlink domain for arr + qBittorrent + libraries.
        # recordsize=1M: finished media files are large and read sequentially
        #   by Jellyfin/Plex; the sustained sequential-read pattern dominates
        #   over the in-flight torrent piece writes, and 1M gives ~200 KiB per
        #   drive on a 6-wide raidz1 (a healthy stripe unit for the SAS SSDs).
        # exec/setuid/devices=off: media data must never execute or grant
        #   privilege — a compromised *arr container should not be able to
        #   stage a payload on the bulk pool and run it.
        # atime=off: pool-inherited, restated for local clarity.
        media = {
          type = "zfs_fs";
          mountpoint = "/srv/media";
          options = {
            mountpoint = "legacy";
            recordsize = "1M";
            exec       = "off";
            setuid     = "off";
            devices    = "off";
            atime      = "off";
          };
        };

        # /srv/media/library/movies + /srv/media/library/tvshows — sub-datasets
        # under zdata/media, each carrying the same 1M/exec-off/setuid-off/
        # atime-off properties.  They exist as their own datasets (rather than
        # plain subdirectories under /srv/media) so that the old Jellyfin
        # database — imported wholesale to preserve watch state — can find
        # every path it recorded under a stable, dedicated dataset boundary,
        # and so that Nextcloud external-storage exposure of the same tree
        # later has a clean per-collection dataset it can quota, snapshot,
        # and audit independently of downloads/ and other bulk-pool tenants.
        # recordsize=1M / exec/setuid/atime = the same reasons as zdata/media
        # above (large sequential-read media, no execution or privilege ever).
        # These MUST be created at dataset birth: recordsize only applies to
        # new writes and cannot be reset retroactively without send/receive.
        "media/movies" = {
          type = "zfs_fs";
          mountpoint = "/srv/media/library/movies";
          options = {
            mountpoint = "legacy";
            recordsize = "1M";
            exec       = "off";
            setuid     = "off";
            atime      = "off";
          };
        };
        "media/tvshows" = {
          type = "zfs_fs";
          mountpoint = "/srv/media/library/tvshows";
          options = {
            mountpoint = "legacy";
            recordsize = "1M";
            exec       = "off";
            setuid     = "off";
            atime      = "off";
          };
        };

        # /srv/state — per-service config/state (arr *.db, immich thumbs, …).
        #   Layout below: /srv/state/<service>.
        # recordsize left at 128K default (not restated): SQLite / config /
        #   small-file mixes are hurt by 1M — a 4K write becomes a 1M
        #   read-modify-write.  Default matches the 128K sqlite page pattern.
        # exec stays ON: some services drop helper scripts inside their state
        #   dir and invoke them (sonarr custom scripts, etc.); flipping exec
        #   off here would break that use case.
        # setuid/devices=off: no service needs either on its state dir.
        state = {
          type = "zfs_fs";
          mountpoint = "/srv/state";
          options = {
            mountpoint = "legacy";
            setuid     = "off";
            devices    = "off";
            atime      = "off";
          };
        };

        # /srv/games — future Steam library.  Created now so the properties
        # are set once at dataset birth; some (recordsize) cannot be changed
        # retroactively for existing data.
        # exec=on: game binaries MUST execute — this is the entire point of
        #   the dataset, and it deliberately differs from /srv/media where
        #   nothing on the pool should be runnable.
        # setuid/devices=off: nothing under a games library should ever need
        #   setuid or a device node; disable both defensively.
        games = {
          type = "zfs_fs";
          mountpoint = "/srv/games";
          options = {
            mountpoint = "legacy";
            setuid     = "off";
            devices    = "off";
            atime      = "off";
          };
        };

        # zdata/backup — reserved.  Not created here; when the backup strategy
        # is chosen we may want a very different recordsize / compression /
        # (perhaps) encryption story, so add it deliberately at that point.
      };
    };
  };
}
