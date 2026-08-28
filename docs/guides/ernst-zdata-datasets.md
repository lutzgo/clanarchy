# ernst: creating the zdata datasets

`machines/ernst/disko.nix` declares five datasets on `zdata` — `media`,
`media/movies`, `media/tvshows`, `state`, `games` — and disko emits the
corresponding NixOS `fileSystems` entries so `/srv/media`,
`/srv/media/library/movies`, `/srv/media/library/tvshows`, `/srv/state`,
`/srv/games` mount declaratively on every boot.

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

# /srv/media/library/movies + /srv/media/library/tvshows — dedicated
# sub-datasets so the imported Jellyfin database's absolute paths land
# on stable per-collection dataset boundaries (and Nextcloud can later
# quota/snapshot/audit each collection independently). recordsize=1M
# MUST be set at creation — it only applies to new writes and cannot be
# reset retroactively. devices=off is inherited from zdata/media.
zfs create \
  -o mountpoint=legacy \
  -o recordsize=1M \
  -o exec=off \
  -o setuid=off \
  -o atime=off \
  zdata/media/movies

zfs create \
  -o mountpoint=legacy \
  -o recordsize=1M \
  -o exec=off \
  -o setuid=off \
  -o atime=off \
  zdata/media/tvshows

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

`compression=zstd` and encryption are inherited from the pool root and
should not be restated.

`zdata/backup` is intentionally NOT created here. Reserve it for when
the backup strategy is decided; its properties will likely diverge
(recordsize, compression tuning).

## Verify

Property audit — every value below must match what was requested above:

```bash
zfs get -H -o value \
  mountpoint,recordsize,exec,setuid,devices,atime,compression,encryption \
  zdata/media zdata/media/movies zdata/media/tvshows zdata/state zdata/games
```

Expected:

| Dataset               | mp     | recordsize | exec | setuid | devices | atime | compress | encrypt      |
| --------------------- | ------ | ---------- | ---- | ------ | ------- | ----- | -------- | ------------ |
| `zdata/media`         | legacy | 1M         | off  | off    | off     | off   | zstd     | aes-256-gcm  |
| `zdata/media/movies`  | legacy | 1M         | off  | off    | off     | off   | zstd     | aes-256-gcm  |
| `zdata/media/tvshows` | legacy | 1M         | off  | off    | off     | off   | zstd     | aes-256-gcm  |
| `zdata/state`         | legacy | 128K       | on   | off    | off     | off   | zstd     | aes-256-gcm  |
| `zdata/games`         | legacy | 128K       | on   | off    | off     | off   | zstd     | aes-256-gcm  |

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

## If it goes wrong

- **`cannot mount '/srv/media': directory is not empty`** — a previous
  boot attempted to mount before the dataset existed and NixOS created a
  placeholder directory. Unmount, remove the placeholder, and retry:
  `systemctl stop srv-media.mount && rmdir /srv/media && zfs mount zdata/media`.
- **Wrong recordsize on media** — `recordsize` is set at write time per
  block; changing the property later only affects future writes. If a
  large body of data was written with the wrong size, plan a
  send/receive rewrite.
