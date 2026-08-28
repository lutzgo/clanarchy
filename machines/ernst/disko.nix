# ernst — storage layout:
#   zroot   mirror across 1× PM1643a + 1× PM1653 960 GB SAS SSDs (encrypted, system pool)
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
#
# ── mirroredBoots preparation (currently commented out) ────────────────────
# The commented ESP block under `disk.system-b.content.partitions.ESP` below
# is the future layout: a second 1G ESP on system-b so a slot-12 loss no
# longer takes /boot with it (see docs/incidents/ernst-slot12-drop-2026-08-11.md).
#
# Disko does NOT reconcile partition tables on running systems, so
# uncommenting alone does nothing — the partition must be created at
# install time.  Activation procedure, in order:
#
#   1. Uncomment the `ESP` block inside `disk.system-b.content.partitions`
#      below.  Bump its `priority` if system-b's `zfs` partition needs to be
#      shifted (currently it occupies 100% of the disk, so shrink or
#      re-provision — see step 3).
#   2. Uncomment the matching `boot.loader.systemd-boot.mirroredBoots`
#      block in `machines/ernst/configuration.nix`.
#   3. Reinstall system-b's disk (or the whole machine if reinstalling
#      anyway) so disko lays down the new partition table.  Case B of
#      `docs/runbooks/ernst-zroot-drive-replacement.md` becomes the
#      relevant flow when only system-b is being reprovisioned.
#   4. Copy the current ESP contents from system-a to system-b's new ESP
#      and re-run `nixos-rebuild switch` so systemd-boot writes matching
#      entries into both.
{ ... }:
{
  disko.devices = {

    # ── System pool: 2× 960 GB SAS SSD, mirrored ─────────────────────────────
    disk.system-a = {
      type = "disk";
      device = "/dev/disk/by-id/wwn-0x50025380a5914360"; # PM1653 960G  S6M1NN0Y901370
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
        partitions = {
          # ── mirroredBoots follow-up (see header comment) ────────────
          # Uncomment this ESP block at next reinstall of system-b to
          # activate the mirrored /boot layout.  Also uncomment the
          # matching mirroredBoots wiring in configuration.nix.
          #
          # ESP = {
          #   size = "1G";
          #   type = "EF00";
          #   content = {
          #     type         = "filesystem";
          #     format       = "vfat";
          #     mountpoint   = "/boot2";
          #     extraArgs    = [ "-n" "ESP2" ];
          #     mountOptions = [ "umask=0077" ];
          #   };
          # };

          zfs = {
            size    = "100%";
            content = { type = "zfs"; pool = "zroot"; };
          };
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

      # com.sun:auto-snapshot on home/persist only — see the equivalent
      # comment in modules/disko/base.nix.  clan-core enables
      # services.zfs.autoSnapshot fleet-wide, but zfs-auto-snapshot only
      # acts on datasets carrying this property.  root is rolled back to
      # @blank every boot and /nix is reproducible, so neither is worth
      # snapshotting.
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

        # /srv/state — per-service config/state (arr *.db, immich thumbs, …).
        #   Layout below: /srv/state/<service>.
        # recordsize left at 128K default (not restated): SQLite / config /
        #   small-file mixes are hurt by 1M — a 4K write becomes a 1M
        #   read-modify-write.  Default matches the 128K sqlite page pattern.
        # exec stays ON: some services drop helper scripts inside their state
        #   dir and invoke them (sonarr custom scripts, etc.); flipping exec
        #   off here would break that use case.
        # setuid/devices=off: no service needs either on its state dir.
        # com.sun:auto-snapshot=true: this is the one bulk dataset whose
        #   contents are irreplaceable — service databases and config, not
        #   re-downloadable media.  /srv/media and /srv/games deliberately
        #   stay opted out: both are large and re-acquirable, and frequent
        #   snapshots there would pin deleted media forever.
        state = {
          type = "zfs_fs";
          mountpoint = "/srv/state";
          options = {
            mountpoint = "legacy";
            setuid     = "off";
            devices    = "off";
            atime      = "off";
            "com.sun:auto-snapshot" = "true";
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

        # /srv/unsorted — everything worth keeping off the retired Arch server
        # (tomala-server001) that is not media: photos, documents, ebooks,
        # audiobooks, per-person folders.  ~485 GB.
        #
        # Named "unsorted" deliberately.  It is a holding area, not a final
        # home: the contents arrived as one 26-directory tree accumulated over
        # a decade and want triaging into real locations later.  Naming it
        # after its state rather than its contents keeps that honest.
        #
        # recordsize=1M: dominated by audiobooks, photos and video.  ZFS uses
        #   variable block sizes up to recordsize, so the Documents/EBooks
        #   small files are not padded out to 1M.
        # exec/setuid/devices=off: archived user data, never executable — same
        #   reasoning as /srv/media.
        # acltype=posix: the source tree carries POSIX ACLs from the old box's
        #   Nextcloud/Samba setup.  With the ZFS default (acltype=off) rsync
        #   -A would silently drop them; set at dataset birth so nothing is
        #   lost in the copy, even though the ACLs reference uids that do not
        #   exist here and will most likely be flattened during triage.
        # com.sun:auto-snapshot=true: unlike /srv/media this is NOT
        #   re-acquirable.  It is the only remaining copy of the family's
        #   photos and documents once the Arch box is wiped.
        unsorted = {
          type = "zfs_fs";
          mountpoint = "/srv/unsorted";
          options = {
            mountpoint = "legacy";
            recordsize = "1M";
            exec       = "off";
            setuid     = "off";
            devices    = "off";
            atime      = "off";
            acltype    = "posix";
            "com.sun:auto-snapshot" = "true";
          };
        };

        # /srv/gardens — SilverBullet knowledge bases, one per user
        #   (/srv/gardens/lgo, /srv/gardens/go).  Small: ~500 MB.
        #
        # Separate from /srv/unsorted because these are not unsorted at all —
        # they are live, actively edited, and the most irreplaceable thing
        # that came off the old server.  A future SilverBullet container on
        # ernst binds them directly.
        #
        # recordsize left at the 128K default: thousands of small markdown
        #   files, written a few KB at a time.  1M here would turn every note
        #   save into a read-modify-write.
        # com.sun:auto-snapshot=true: notes are edited continuously and an
        #   accidental deletion is invisible until much later.
        gardens = {
          type = "zfs_fs";
          mountpoint = "/srv/gardens";
          options = {
            mountpoint = "legacy";
            exec       = "off";
            setuid     = "off";
            devices    = "off";
            atime      = "off";
            acltype    = "posix";
            "com.sun:auto-snapshot" = "true";
          };
        };

        # /srv/audiobooks — M14.  Audiobookshelf's library, the ebook halves
        #   Storyteller consumes, and the synced EPUB3s it produces.
        #
        # A SEPARATE DATASET, AND NOT A SUBDIRECTORY OF /srv/media.  The
        # distinction matters and it is the opposite of invariant #2's
        # instruction, so it needs its own justification:
        #
        #   Invariant #2 says never to create a sub-dataset UNDER /srv/media,
        #   because a dataset boundary inside the hardlink domain silently
        #   turns every *arr import into a copy.  This is a SIBLING of
        #   /srv/media, not a child of it, so it creates no boundary inside
        #   that domain and cannot cause that failure.
        #
        #   Nothing here is ever hardlinked from anywhere.  Audiobookshelf has
        #   no importer — it scans a directory a human fills — and Storyteller
        #   READS a pair and WRITES a new file rather than linking either.  So
        #   there is no chain to break, which is exactly why docs/roadmap.md
        #   says Audiobookshelf is the one M14 service that does not owe the
        #   hardlink proof.
        #
        # recordsize=1M: audiobooks are large and read sequentially, the same
        #   pattern as /srv/media.  ZFS uses variable block sizes up to the
        #   recordsize, so the EPUB halves are not padded out to 1M.
        # exec/setuid/devices=off: library data, never executable — the
        #   /srv/media reasoning, and it applies with more force here because
        #   Storyteller is the one M14 service running as an opaque container
        #   image (see machines/ernst/containers/storyteller.nix).
        # com.sun:auto-snapshot=true: this is NOT re-acquirable in the way
        #   /srv/media is.  A synced EPUB3 costs an hour of forced alignment to
        #   regenerate, and the DRM-free source pairs are a manual acquisition
        #   rather than something an *arr can fetch again.
        #
        # CREATED BY HAND ONCE, like every other dataset in this block — see
        # the note at the top of `datasets` and docs/guides/ernst-zdata-datasets.md.
        # disko does not create datasets on an existing pool; it only emits the
        # fileSystems entry that mounts them.
        audiobooks = {
          type = "zfs_fs";
          mountpoint = "/srv/audiobooks";
          options = {
            mountpoint = "legacy";
            recordsize = "1M";
            exec       = "off";
            setuid     = "off";
            devices    = "off";
            atime      = "off";
            "com.sun:auto-snapshot" = "true";
          };
        };

        # zdata/backup — reserved.  Not created here; when the backup strategy
        # is chosen we may want a very different recordsize / compression /
        # (perhaps) encryption story, so add it deliberately at that point.
      };
    };
  };
}
