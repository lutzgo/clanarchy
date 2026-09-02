# Emulation on birte

Two pieces of software, because one no longer covers the whole range:

| | RetroDECK | Eden |
|---|---|---|
| **Consoles** | everything up to and including the Switch's predecessors | Switch 1 only |
| **Installed as** | Flatpak, `net.retrodeck.retrodeck` (imperative — `services.flatpak.packages` does not exist in this nixpkgs) | Nix package `pkgs.eden`, via `clanarchy.apps.emulation.switch.enable` |
| **Config lives in** | `~/.var/app/net.retrodeck.retrodeck/` | `~/.config/eden` + `~/.local/share/eden` |
| **Game data lives in** | `~/retrodeck` → `/games/retrodeck` | wherever you point it; `/games` has the space |
| **Into Steam via** | its own bundled Steam ROM Manager | one manual "Add a Non-Steam Game" |

RetroDECK [removed Switch emulation permanently in February 2026][rd-switch] —
DMCA exposure the volunteer project chose not to carry — and its own
announcement tells users to run a Switch emulator themselves alongside it.
That is the entire reason Eden is packaged separately rather than being
redundant with RetroDECK.

[rd-switch]: https://retrodeck.readthedocs.io/en/latest/blog/2026/02/19/february-2026---extra-switch-emulation-support---will-be-removed/

## The impermanence trap — read this first

birte rolls `@root` **and `@home`** back to blank subvolumes on every boot
(see [Impermanence](impermanence.md)). Only paths declared in
`machines/birte/deck.nix` survive.

Flatpak apps keep **all** of their state under `~/.var/app/<app-id>/` — not in
`.config`, not in `.local/share`. `/var/lib/flatpak` was already persisted, so
installed Flatpaks came back after a reboot, but they came back *freshly
installed and completely unconfigured*. `deck.nix` now persists `.var/app`,
which is what makes RetroDECK's setup stick at all.

The second half is the data folder. `~/retrodeck` is a `tmpfiles` `L+` symlink
onto `/games/retrodeck`, on the `@games` subvolume — outside the rollback path,
outside the impermanence bind-mounts, `nodatacow`, and where the free space is.

Both changes landed together. **If you configured RetroDECK before deploying
them, that configuration is already gone** — redo the first-run wizard after
the deploy, not before.

## RetroDECK first run

```bash
clan machines update birte
```

Then, in Desktop Mode, launch RetroDECK and answer the wizard:

- **Data folder: pick "Internal"**. It resolves to `~/retrodeck`, which is
  already the symlink onto `/games/retrodeck`. There is no custom path to
  enter, and nothing to re-enter after a reinstall.
- Do **not** pick the SD card option unless a card is actually in the slot —
  birte's library lives on the internal NVMe.

The tree it creates:

```
/games/retrodeck/
├── roms/<system>/     # nes/, snes/, gba/, psx/ … one folder per system
├── bios/              # BIOS and firmware, flat
├── saves/  states/    # per-emulator save and save-state trees
└── .downloaded_media/ # scraped art — can grow to many GB
```

ROMs go in the matching system folder; a NES game in `roms/nes/`. BIOS files go
in `bios/`, though [a few components also want firmware next to the ROM][rd-bios].

[rd-bios]: https://retrodeck.readthedocs.io/en/latest/wiki_management/bios-firmware/

## Getting them into Steam

### RetroDECK — use its bundled Steam ROM Manager

RetroDECK has [shipped Steam ROM Manager since 0.9.0b][rd-srm]. It adds
*individual games* as non-Steam shortcuts, pulls artwork from SteamGridDB, and
applies RetroDECK's Steam Input layouts — which is the part that matters,
because a hand-made shortcut gets none of the controller mapping.

- **Bulk / one-off**: Configurator → Open Component → Steam ROM Manager.
- **Keep it current**: Configurator → Steam Tools → **Automatic Steam Sync** →
  Yes. New ROMs then appear in Steam without re-running anything.

Steam only re-reads its shortcut list at startup, so after either one:
**restart Steam** — switching Gaming Mode → Desktop Mode → Gaming Mode is
enough, and is the fast way to do it on the Deck.

[rd-srm]: https://retrodeck.readthedocs.io/en/latest/wiki_utility_guides/srm/srm-guide/

### Eden — one manual shortcut

Eden is a single application, so there is nothing to bulk-import:
Steam → Games → **Add a Non-Steam Game** → tick **Eden** → Add.

Two things make that shortcut durable, and both are deliberate:

- Eden's desktop entry uses a bare `Exec=eden %f`, and the package is in
  `environment.systemPackages`, so what Steam resolves and stores is
  `/run/current-system/sw/bin/eden`. That path is stable across rebuilds. Had
  the entry carried a `/nix/store/…` path, Steam would have baked it into
  `shortcuts.vdf` and the shortcut would have broken at the next garbage
  collection.
- `shortcuts.vdf` itself lives under `~/.local/share/Steam`, which is a symlink
  to `/games`. It is outside the rollback, so shortcuts added by hand survive
  reboots — the same mechanism that keeps the Steam library itself.

Eden needs Switch keys (`prod.keys`, `title.keys`) dumped from your own
console; it looks for them in the `keys/` folder of its data directory, which
you can open from inside the app. Both `~/.config/eden` and `~/.local/share/eden`
are already persisted for `deck`, so wherever it puts them, they stay.

Switch dumps themselves belong in `/srv/roms/roms/switch/` on ernst — that
directory already exists and already replicates to
`/games/retrodeck/roms/switch/` on the Deck, so Eden can simply be pointed at
the synced copy. RomM indexes them too (`switch` is one of its platforms).

### Anything launched from Gaming Mode needs its library env cleaned

**Symptom:** a non-Steam shortcut works perfectly from the KDE menu in Desktop
Mode and does nothing at all in Gaming Mode.

**Cause:** Steam exports its own `LD_LIBRARY_PATH`, pointing at the bundled
Ubuntu-12 Steam Runtime, to everything it launches. Those libraries shadow the
ones every Nix-built binary is linked against. Measured on birte:

```console
$ chromium            # with Steam's LD_LIBRARY_PATH
chromium: /games/ubuntu12_32/steam-runtime/usr/lib/x86_64-linux-gnu/libnss3.so:
          version `NSS_3.30' not found (required by …/chromium)
```

It is not specific to browsers — with that variable set, plain coreutils fails
the same way (`head`, `tr`: `libattr.so.1: version 'ATTR_1.3' not found`), which
is a good way to recognise it.

**Fix:** in Steam, right-click the shortcut → Properties → **Launch Options**:

```
env -u LD_LIBRARY_PATH -u LD_PRELOAD %command%
```

Desktop Mode is unaffected because launching from the KDE menu never goes
through Steam.

### What Steam actually records in a shortcut

Steam stores a desktop entry's `Exec` field **literally** — it does not resolve
it. From birte's `shortcuts.vdf`:

| Shortcut | Stored `Exe` | |
|---|---|---|
| Chromium | `"chromium"` | bare name, resolved via PATH at launch |
| Eden | `"eden"` | same |
| Google Chrome | `"/nix/store/awfz…/bin/google-chrome-stable"` | **store path — will break** |

A bare name is fine here because `/run/current-system/sw/bin` is on the
gamescope session's PATH. A baked-in `/nix/store` path is not: it breaks at the
next update plus garbage collection. google-chrome's upstream desktop entry
uses an absolute `Exec`, so that is what Steam captured.

If a shortcut dies after an update, re-add it with **Browse** and pick
`/run/current-system/sw/bin/<name>` explicitly rather than letting Steam scan
the desktop entry.

## The ROM library, and self-hosting RomM

The RetroDECK tree above is *deliberately* a valid [RomM][romm] library root.
RomM's recommended layout and RetroDECK's are the same shape:

```
RomM "structure A"          RetroDECK
library/                    /games/retrodeck/
├── roms/<platform>/        ├── roms/<system>/
└── bios/<platform>/        └── bios/            ← flat, not per-platform
```

So `/games/retrodeck` can be handed to RomM as its library root as-is. Two
caveats, neither fatal:

- **Platform folder names.** RomM matches folders against its own platform
  slugs; RetroDECK uses ES-DE system names. They agree on the common ones
  (`nes`, `snes`, `gba`, `psx`) and diverge on others. RomM handles that with
  an explicit mapping under `system.platforms` in its `config.yml` — no
  renaming of RetroDECK's folders required.
- **BIOS.** RomM expects `bios/<platform>/`, RetroDECK keeps `bios/` flat. The
  BIOS tree is optional in RomM, so the simplest answer is to let RomM index
  ROMs only.

RomM also [exports ES-DE metadata][romm-exports]: with it enabled, a scan
writes a `gamelist.xml` into each platform folder alongside `covers/` and
`screenshots/`. RetroDECK's frontend *is* ES-DE, so scraping can happen once on
the server and be consumed directly by the Deck instead of scraping per-device.

[romm]: https://romm.app/
[romm-exports]: https://docs.romm.app/latest/reference/exports/

### Where the library lives: ernst masters, birte syncs

`machines/ernst/containers/romm.nix` runs RomM on the podman tier — its third
occupant, after TubeSync and Storyteller — at `romm.<domain>` behind Authelia.

```
ernst   /srv/roms/            ← zdata/roms, the authoritative library
          roms/<platform>/         RomM scans this
          bios/<platform>/
             │
        Syncthing (folders `roms` and `bios`)
             │
birte   /games/retrodeck/
          roms/<system>/           RetroDECK plays this, offline
          bios/
          saves/ states/ …        ← NOT synced, deck's alone
```

A **network mount was rejected**. It is simpler and avoids the second copy, and
it makes the library unreachable whenever the Deck is away from the house —
which is what a Steam Deck is *for*. The cost of the choice actually made is a
full second copy on birte's NVMe, taken deliberately.

Three details in that diagram are load-bearing:

- **Two Syncthing folders, not one root.** Pairing `/srv/roms` with
  `/games/retrodeck` wholesale would push the Deck's save games and its entire
  scraped-art cache onto the server as a side effect. `roms` and `bios` are
  exactly the subtrees that correspond on both machines.
- **Saves are not synced.** That is a separate decision with its own conflict
  semantics (two machines, same game, two save files) and should not be
  acquired by accident.
- **Syncthing is not a backup** — it replicates deletions faithfully and fast.
  `zdata/roms` therefore sets `com.sun:auto-snapshot=true`, unlike its
  neighbours `/srv/media` and `/srv/games` which opt out as re-acquirable.
  Snapshots are the only thing between an accidental delete and losing it on
  both machines within seconds.

The library is on **its own dataset, not under `/srv/games`**, and the reason is
the `exec` property: `/srv/games` carries exec *on* because Steam and Questarr's
PC games are binaries that must run. A ROM is data — an emulator reads it,
nothing executes it — so `zdata/roms` is `exec=off,setuid=off,devices=off`.

### Deploying it

`zdata/roms` must be created by hand before the first deploy that carries it,
like every other dataset on that pool — see
[ernst zdata datasets](ernst-zdata-datasets.md). Then:

```bash
clan machines update ernst
clan machines update birte
```

Syncthing pairing is automatic between clan peers (identities come from clan
vars), but the folders must be **accepted once** in each machine's Syncthing UI.

### After the first start

- **Metadata.** Only [Hasheous](https://hasheous.org/) is enabled out of the
  box, because it is the one source needing no account. IGDB, SteamGridDB,
  ScreenScraper and RetroAchievements each want credentials tied to a personal
  account; add them as environment variables when you have them. They are
  deliberately not clan vars — a `prompts` generator would block
  `clan vars generate ernst` on values that may not exist yet.
- **Platform names.** RomM matches folder names against its own platform slugs
  and RetroDECK uses ES-DE system names. They agree on the common ones and
  diverge on others; map the rest under `system.platforms` in RomM's
  `config.yml` (in `/srv/state/romm/config`) rather than renaming anything on
  disk — the folder names on disk are what RetroDECK reads.
- **ES-DE metadata export.** Enabling it in RomM's config writes a
  `gamelist.xml` into each platform folder alongside `covers/` and
  `screenshots/`. RetroDECK's frontend *is* ES-DE, so scraping happens once on
  the server and the Deck consumes the result instead of scraping per-device.

### Importing a downloaded collection into the library

Grabs from Prowlarr and Questarr land in qBittorrent's completed folder, not in
the library — deliberately. The two are different things: `/srv/media/torrents`
is a download area the client still owns, and `/srv/roms` is the curated tree
RomM indexes and Syncthing replicates.

**COPY, never move.** qBittorrent goes on seeding what it downloaded; moving
the files out from under it breaks the torrent and stops the seed.

A worked example — a 174 MB `.7z` grabbed as
`Nintendo for PC (Every NES Rom and Emu EVER)`:

```console
$ 7z l -slt "…/3538 NES ROMS … with ALL Emulators.7z" | grep ^Path | cut -d/ -f2 | sort -u
Emulators          ← Windows .exe / .dll — NOT wanted
Roms               ← 3537 × .nes — this is the part you want
```

Collections routinely bundle Windows emulators alongside the ROMs. Take only
the ROM directory. (`/srv/roms` is `exec=off` anyway, so a bundled `.exe` could
not run from there even if copied — see the dataset note above.)

Run on ernst. Set the four variables at the top and the rest is generic — the
archive's inner path (`*/Roms/*`) and the ROM extension are the only things
that change between collections.

```bash
#!/usr/bin/env bash
set -euo pipefail

SRC="/srv/media/torrents/complete/<torrent folder>"   # what qBittorrent downloaded
INNER='*/Roms/*'                                      # subtree to take; see 7z l below
EXT=nes                                               # ROM extension to keep
PLATFORM=nes                                          # ES-DE's directory name
ROMM_UID=3029

DEST="/srv/roms/roms/${PLATFORM}"
ARCHIVE=$(find "$SRC" -maxdepth 1 \( -name '*.7z' -o -name '*.zip' -o -name '*.rar' \) | head -1)

# Stage on the SAME dataset, so the copy is a rename-speed local copy and a
# half-finished extraction never lands in the library.
STAGE=$(mktemp -d /srv/roms/.import.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT

# 1. Extract ONLY the ROM subtree — not the bundled emulators.
nix shell nixpkgs#p7zip -c 7z x "$ARCHIVE" -o"$STAGE" "$INNER" -bso0 -bsp0

# 2. Look before you copy: confirm the extension and the count.
find "$STAGE" -type f | sed 's/.*\.//' | tr 'A-Z' 'a-z' | sort | uniq -c | sort -rn | head -5

# 3. Copy in. -n so a re-run never overwrites an existing curated file.
install -d -o "$ROMM_UID" -g romm -m 2770 "$DEST"
find "$STAGE" -type f -iname "*.${EXT}" -exec cp -n -t "$DEST" {} +

# 4. Ownership: the setgid bit fixes the group, not the owner.
chown -R "${ROMM_UID}:romm" "$DEST"
```

To find `INNER` for an unfamiliar archive, list its second-level directories
first — this is what tells you the emulators are in there:

```console
$ 7z l -slt "$ARCHIVE" | grep ^Path | cut -d/ -f2 | sort -u
Emulators
Roms
```

Then **Scan** in RomM. Check afterwards:

```bash
find "/srv/roms/roms/${PLATFORM}" -type f | wc -l          # matches step 2's count
find "/srv/roms/roms/${PLATFORM}" -type f -size 0 | wc -l  # must be 0
find /srv/roms/roms -name gamelist.xml                     # ES-DE export produced metadata
```

Do not judge the result by `du -sh` alone: `zdata/roms` is zstd-compressed, so
a real import of 3537 NES ROMs reports **691M apparent / 366M on disk**. Use
the file count and a zero-byte check instead.

and the files appear on birte under `/games/retrodeck/roms/nes/` once Syncthing
catches up.

If the platform shows as **"Unknown"** in RomM, the folder name is not one of
its slugs — add a `system.platforms` mapping in
`/srv/state/romm/config/config.yml` and restart `podman-romm`. Do not rename the
folder: ES-DE reads that name literally and cannot be remapped.

### What about Questarr?

They are not integrated, and should not be:

- **Different content.** Questarr acquires **PC games** through Prowlarr
  indexers and files them into `/srv/games/questarr`. RomM manages **console
  ROMs** for emulation. Neither reads the other's tree.
- **The permission boundary is deliberate.** `/srv/games/questarr` is `0750
  questarr:questarr` precisely so that nothing else has a foothold on the one
  dataset in the pool where files may execute. Pointing RomM at it would
  breach a decision `containers/arr.nix` argues for at length.
- **There is no hand-off to build.** Questarr's output tree is not
  `roms/<platform>/`, so RomM would index it as noise.

The one genuine overlap is **IGDB**: both use it for metadata, so the same IGDB
client ID and secret work in both. That is credential reuse in a UI, not a data
path — nothing in this repo wires it.
