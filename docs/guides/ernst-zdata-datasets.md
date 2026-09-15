# ernst: creating the zdata datasets

`machines/ernst/disko.nix` declares nine datasets on `zdata` — `media`,
`state`, `games`, `roms`, `unsorted`, `gardens`, `audiobooks`, `photos`,
`nextcloud` — and disko emits the corresponding NixOS `fileSystems` entries so
`/srv/media`, `/srv/state`, `/srv/games`, `/srv/roms`, `/srv/unsorted`,
`/srv/gardens`, `/srv/audiobooks`, `/srv/photos` and `/srv/nextcloud` mount
declaratively on every boot.

> **`zdata/media/movies` and `zdata/media/tvshows` are gone**, and this file
> described them for a year after they stopped existing. They were **collapsed
> into plain subdirectories** of `zdata/media` in
> [#20](https://github.com/lutzgo/clanarchy/pull/20): hardlinks cannot cross a
> ZFS dataset boundary, and the \*arr import path depends on them. That is
> architecture invariant #2 — **no dataset boundary inside the hardlink
> domain** — and it is why `audiobooks`, `roms` and `photos` below are all
> SIBLINGS of `zdata/media` rather than children. Do not re-create them.

Disko itself only runs at first install; on the already-provisioned
pool the datasets have to be created once by hand. This is that
runbook. Do it **before** the first `clan machines update ernst` that carries
this change — otherwise activation will try to mount datasets that do
not exist and the mount units will fail (recoverable, but noisy).

## Prerequisites

- `zdata` is imported and unlocked (`zpool status zdata` shows `ONLINE`,
  `zfs list zdata` returns without an error).
- SSH access to ernst as root.

## Create the datasets

The properties below must match `machines/ernst/disko.nix` exactly. If
you change them, change both.

```bash
ssh root@ernst.skynet.lan

# /srv/media — single hardlink domain: arr suite + qBittorrent + libraries.
# recordsize=1M for large sequential-read media files; exec/setuid/devices
# off so the bulk pool can never execute code or grant privilege.
zfs create \
  -o mountpoint=legacy \
  -o recordsize=1M \
  -o exec=off \
  -o setuid=off \
  -o devices=off \
  -o atime=off \
  zdata/media

# NOTE: there is no `zfs create zdata/media/movies` or `.../tvshows` here.
# They existed once and were collapsed into plain subdirectories — see the
# note at the top of this file. Invariant #2.

# /srv/state — per-service config and state. Layout below: /srv/state/<svc>.
# recordsize left at the 128K default (small random writes from SQLite etc.
# are hurt by 1M). exec stays ON — some services drop and invoke helper
# scripts inside their state dir.
zfs create \
  -o mountpoint=legacy \
  -o setuid=off \
  -o devices=off \
  -o atime=off \
  zdata/state

# /srv/games — future Steam library. exec=on because game binaries must
# execute (this is why it differs from media). setuid/devices off defensively.
zfs create \
  -o mountpoint=legacy \
  -o setuid=off \
  -o devices=off \
  -o atime=off \
  zdata/games

# /srv/audiobooks — M14. Audiobookshelf's library, the DRM-free ebook
# halves, and Storyteller's /data (its database and the synced EPUB3s it
# produces). A SIBLING of zdata/media, never a child: invariant #2 forbids
# a dataset boundary INSIDE the hardlink domain, and nothing here is ever
# hardlinked anyway. auto-snapshot because a synced EPUB3 costs an hour of
# forced alignment to regenerate and the source pairs are acquired by hand.
zfs create \
  -o mountpoint=legacy \
  -o recordsize=1M \
  -o exec=off \
  -o setuid=off \
  -o devices=off \
  -o atime=off \
  -o com.sun:auto-snapshot=true \
  zdata/audiobooks
```

> **`-o mountpoint=legacy` is not decoration on any of these, and this
> dataset is where that was learned.** A ZFS dataset whose `mountpoint`
> property is anything else **cannot be mounted by `mount(8)` at all** —
> `zfs` refuses outright. NixOS mounts every dataset here through a
> generated `.mount` unit, so without `legacy` the unit fails; and because
> a `fileSystems` entry is `RequiredBy` `local-fs.target` by default, that
> failure takes `local-fs.target` with it and the machine boots into
> **emergency**: no sshd, no containers, no microvm.
>
> That is exactly what happened on **2026-08-28**, when M14 shipped
> `zdata/audiobooks` in `disko.nix` without adding it to this file — so
> there was no command to copy, and the dataset was created without the
> property. The machine had to be recovered from the boot menu.
>
> Two things changed as a result: this section exists, and
> `/srv/audiobooks` now carries **`nofail`** (see `machines/ernst/disko.nix`)
> so that a library dataset can never again be a hard boot dependency of the
> whole NAS. `audiobooks-tree.service` fails loudly instead.
>
> **disko does not create datasets on an existing pool.** It only emits the
> `fileSystems` entry that mounts them. Adding a dataset to `disko.nix`
> without running the `zfs create` here is therefore a deploy that fails,
> not a deploy that creates it.

```bash
# /srv/roms — the ROM library RomM manages (containers/romm.nix), and the
# master copy Syncthing replicates to birte's RetroDECK.
#
# ITS OWN DATASET RATHER THAN A DIRECTORY UNDER /srv/games, because of exec.
# /srv/games carries exec ON so Steam and Questarr's PC game binaries can run;
# a ROM is data that an emulator reads and nothing ever executes, so it has no
# business on the one dataset in this pool where files may run.
#
# recordsize=1M MUST be set at creation — dominated by large disc images, and
# it cannot be changed retroactively for existing data.
#
# com.sun:auto-snapshot=true, unlike /srv/media and /srv/games which opt out as
# re-acquirable. Syncthing is NOT a backup: it propagates deletions to birte
# within seconds, so snapshots are the only thing standing between an
# accidental delete and losing the library on both machines.
zfs create \
  -o mountpoint=legacy \
  -o recordsize=1M \
  -o exec=off \
  -o setuid=off \
  -o devices=off \
  -o atime=off \
  -o com.sun:auto-snapshot=true \
  zdata/roms
```

```bash
# /srv/photos — M22.  Immich's media location (containers/immich.nix): the
# originals it owns plus the thumbnails, previews and encoded videos it
# derives from them.
#
# A SIBLING of zdata/media, never a child — invariant #2 forbids a dataset
# boundary inside the hardlink domain, and nothing here is hardlinked anyway
# (Immich copies an upload into its own storage-template path and owns it).
#
# NOT a subdirectory of /srv/state either.  Immich's DATABASE lives there;
# its LIBRARY lives here, because the two want opposite recordsizes.
#
# recordsize=1M MUST be set at creation — JPEGs, 25–40 MB DNGs and video.
# It only applies to new writes and cannot be fixed retroactively.
#
# com.sun:auto-snapshot=true, and this is the least negotiable one in this
# file.  These are the family's photographs, and this is the one library on
# the pool that PEOPLE DELETE FROM — from a phone, with a swipe.  Immich's
# trash is a database flag with a retention period, not a filesystem undo.
zfs create \
  -o mountpoint=legacy \
  -o recordsize=1M \
  -o exec=off \
  -o setuid=off \
  -o devices=off \
  -o atime=off \
  -o com.sun:auto-snapshot=true \
  zdata/photos
```

```bash
# /srv/unsorted + /srv/gardens — the rescued Arch server (#66). Added to this
# file retroactively: both were created correctly at the time, but neither had
# a section here, which is the same gap that put ernst in emergency on
# 2026-08-28. They are written down now so a rebuild does not have to
# reverse-engineer them from `disko.nix`.
#
# acltype=posix on BOTH, and it is not defensive: the source tree arrived
# carrying POSIX ACLs from the old box's Nextcloud/Samba setup, and acltype
# cannot be added usefully after the fact. Note that the NEW Nextcloud below
# does NOT get it — it keeps its sharing model in its own database.
#
# recordsize differs between them, which is the whole reason they are two
# datasets and not one: /srv/unsorted is a decade of photographs, video and
# archives (1M), and /srv/gardens is thousands of small markdown notes written
# a few KB at a time (the 128K default — 1M would turn every note save into a
# read-modify-write).
zfs create \
  -o mountpoint=legacy \
  -o recordsize=1M \
  -o exec=off \
  -o setuid=off \
  -o devices=off \
  -o atime=off \
  -o acltype=posix \
  -o com.sun:auto-snapshot=true \
  zdata/unsorted

zfs create \
  -o mountpoint=legacy \
  -o exec=off \
  -o setuid=off \
  -o devices=off \
  -o atime=off \
  -o acltype=posix \
  -o com.sun:auto-snapshot=true \
  zdata/gardens
```

```bash
# /srv/nextcloud — M23.  Nextcloud's `home` (containers/nextcloud.nix): its
# config/, its store-apps/ and the household's synced files under data/.
#
# A SIBLING of zdata/media, never a child — invariant #2, same as photos.
# Nextcloud reads /srv/media as READ-ONLY external storage and never writes
# into it, so there is no hardlink relationship to preserve either way.
#
# NOT a subdirectory of /srv/state, for the reason photos is not: the DATABASE
# lives on /srv/state/nextcloud (128K, small random writes from PostgreSQL) and
# the FILE STORE lives here (1M). Two opposite recordsizes, two datasets.
#
# recordsize=1M MUST be set at creation. recordsize is a MAXIMUM, so the small
# files in config/ cost nothing; what it buys is that a 4 GB upload is not
# 32,768 records. Nextcloud writes user files whole over WebDAV PUT and never
# partially rewrites a large one, which is the access pattern that would make
# 1M wrong.
#
# com.sun:auto-snapshot=true, as non-negotiable here as it is on photos and for
# a sharper reason: SYNC IS NOT BACKUP AND IT IS NOT ONE-DIRECTIONAL. A file
# deleted on a laptop is deleted here moments later, and Nextcloud's trash is a
# database flag with a retention period, not a filesystem-level undo.
#
# NO acltype=posix, unlike unsorted and gardens above — see the note there.
zfs create \
  -o mountpoint=legacy \
  -o recordsize=1M \
  -o exec=off \
  -o setuid=off \
  -o devices=off \
  -o atime=off \
  -o com.sun:auto-snapshot=true \
  zdata/nextcloud
```

`compression=zstd` and encryption are inherited from the pool root and
should not be restated.

`zdata/backup` is intentionally NOT created here. Reserve it for when
the backup strategy is decided; its properties will likely diverge
(recordsize, compression tuning).

## Verify

Property audit — every value below must match what was requested above:

```bash
zfs get -H -o name,property,value \
  mountpoint,recordsize,exec,setuid,devices,atime,acltype,compression,encryption,com.sun:auto-snapshot \
  zdata/media zdata/state zdata/games zdata/roms zdata/unsorted zdata/gardens \
  zdata/audiobooks zdata/photos zdata/nextcloud
```

Expected:

| Dataset            | mp     | recordsize | exec | setuid | devices | atime | acltype | snapshot | compress | encrypt     |
| ------------------ | ------ | ---------- | ---- | ------ | ------- | ----- | ------- | -------- | -------- | ----------- |
| `zdata/media`      | legacy | 1M         | off  | off    | off     | off   | off     | —        | zstd     | aes-256-gcm |
| `zdata/state`      | legacy | 128K       | on   | off    | off     | off   | off     | true     | zstd     | aes-256-gcm |
| `zdata/games`      | legacy | 128K       | on   | off    | off     | off   | off     | —        | zstd     | aes-256-gcm |
| `zdata/roms`       | legacy | 1M         | off  | off    | off     | off   | off     | true     | zstd     | aes-256-gcm |
| `zdata/unsorted`   | legacy | 1M         | off  | off    | off     | off   | posix   | true     | zstd     | aes-256-gcm |
| `zdata/gardens`    | legacy | 128K       | off  | off    | off     | off   | posix   | true     | zstd     | aes-256-gcm |
| `zdata/audiobooks` | legacy | 1M         | off  | off    | off     | off   | off     | true     | zstd     | aes-256-gcm |
| `zdata/photos`     | legacy | 1M         | off  | off    | off     | off   | off     | true     | zstd     | aes-256-gcm |
| `zdata/nextcloud`  | legacy | 1M         | off  | off    | off     | off   | off     | true     | zstd     | aes-256-gcm |

> **`com.sun:auto-snapshot` is the column that silently does nothing if it is
> wrong.** `services.zfs.autoSnapshot` is on fleet-wide, but it only touches
> datasets carrying this property — and, exactly like `mountpoint=legacy`, disko
> applies it at CREATION and never reconciles it afterwards. A dataset created
> without it is not snapshotted and nothing says so. Fix on an existing dataset
> with `zfs set com.sun:auto-snapshot=true <dataset>`; see
> `docs/runbooks/zfs-auto-snapshot-optin.md`.

## Deploy

Once the datasets exist:

```bash
clan machines update ernst
```

Confirm the mounts landed:

```bash
ssh root@ernst.skynet.lan
mount | grep '/srv/'
# Expected:
#   zdata/media on /srv/media type zfs (...)
#   zdata/state on /srv/state type zfs (...)
#   zdata/games on /srv/games type zfs (...)

findmnt /srv/media  # confirms device=zdata/media, fstype=zfs
```

The three datasets that carry `nofail` — `/srv/audiobooks`, `/srv/photos` and
`/srv/nextcloud` — will **not** fail the boot if they are missing or
mis-propertied. Their consumers refuse to start instead, which is the point.
Check those directly rather than trusting a clean boot:

```bash
systemctl status audiobooks-tree immich-dirs nextcloud-dirs
```

Each prints the exact `zfs create` line to run if its dataset is wrong.

## If it goes wrong

- **`cannot mount '/srv/media': directory is not empty`** — a previous
  boot attempted to mount before the dataset existed and NixOS created a
  placeholder directory. Unmount, remove the placeholder, and retry:
  `systemctl stop srv-media.mount && rmdir /srv/media && zfs mount zdata/media`.
- **Wrong recordsize on media** — `recordsize` is set at write time per
  block; changing the property later only affects future writes. If a
  large body of data was written with the wrong size, plan a
  send/receive rewrite.
