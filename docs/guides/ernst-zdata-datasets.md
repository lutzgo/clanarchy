# ernst: creating the zdata datasets

`machines/ernst/disko.nix` declares three datasets on `zdata` — `media`,
`state`, `games` — and disko emits the corresponding NixOS `fileSystems`
entries so `/srv/media`, `/srv/state`, `/srv/games` mount declaratively
on every boot.

Disko itself only runs at first install; on the already-provisioned
pool the datasets have to be created once by hand. This is that
runbook. Do it **before** the first `deploy-ernst switch` that carries
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
```

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
  zdata/media zdata/state zdata/games
```

Expected:

| Dataset       | mp     | recordsize | exec | setuid | devices | atime | compress | encrypt      |
| ------------- | ------ | ---------- | ---- | ------ | ------- | ----- | -------- | ------------ |
| `zdata/media` | legacy | 1M         | off  | off    | off     | off   | zstd     | aes-256-gcm  |
| `zdata/state` | legacy | 128K       | on   | off    | off     | off   | zstd     | aes-256-gcm  |
| `zdata/games` | legacy | 128K       | on   | off    | off     | off   | zstd     | aes-256-gcm  |

## Deploy

Once the datasets exist:

```bash
deploy-ernst switch
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
