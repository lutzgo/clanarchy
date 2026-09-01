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

### Where the library should live — not yet decided

RomM is Docker/Compose upstream; on `ernst` it would be another podman
container alongside the existing ones, behind traefik and authelia, with the
library on `zdata`. That part is routine. The part that is a real decision is
**where the authoritative library lives**, because it changes what birte mounts:

| | Library on ernst, birte mounts it | Library mastered on ernst, synced to birte |
|---|---|---|
| **Mechanism** | NFS/SMB export → mounted at `/games/retrodeck/roms` | Syncthing (already in the clan) replicates into `/games/retrodeck` |
| **Deck away from home** | no games | full library offline |
| **Disk on birte** | almost none | a full copy |
| **Saves** | naturally shared | need their own sync decision, and conflict on concurrent play |

For a handheld that leaves the house, the sync option is the one that matches
how the device is actually used; the mount option is simpler and strictly
better for a machine that never moves.

Nothing for RomM is built yet — this section is the design, not a description
of something deployed.
