# Getting playlist downloads into the music library

From a Spotify/CSV playlist to something Navidrome serves. Four stages; only the first — starting an sldl batch — is manual.

```
sldl              beets             music-publish     Navidrome
(VPN guest)   →   music-stage   →   into the      →   indexes by
playlists         Artist/Album/     library           TAGS
```

| Stage | Where | Command |
|---|---|---|
| download | VPN guest, `10.0.90.11` | `sldl <csv> -c …/sldl.conf` |
| organise | ernst host, `music-import.timer` 06:00 | `music-stage` |
| publish | ernst host, same unit | `music-publish` |
| serve | Navidrome | automatic |

## Why Lidarr is not in that diagram

It is tempting, it is already installed, and it does not work for this input. Both of these were measured on 2026-10-04, not inferred:

- **This Lidarr has no Library Import.** That is a Sonarr/Radarr feature. A full scan of the 3.1.0.4875 UI bundle's routes yields `/add/search` and `/unmapped`; `/add/import` is a 404.
- **Lidarr cannot match this corpus in bulk.** `/api/v1/manualimport` against the staged tree returned all 255 files with `"albumReleaseId": 0` and `"tracks": []` — nothing identified, every file needing an artist *and* album chosen by hand.

That is not a misconfiguration. Lidarr models **artists and albums**; a playlist corpus is ~219 artists holding one track each. The shapes do not meet.

**Navidrome indexes by tags, not paths**, which is exactly what this corpus has — 236 of the first 239 files carried artist, title and album. So the library is the destination and Navidrome is the consumer.

### What Lidarr is still for

Artists you want **managed** — monitored, discography tracked, new releases fetched. Add them individually:

**Lidarr → Library → Add New** (`/add/search`), search the artist, pick a Quality and Metadata profile.

Because its root folder is the same `/srv/media/library/music`, Lidarr **adopts the files already there** when you add the artist. Nothing needs re-importing.

!!! warning "Check Monitor when adding an artist"
    The root folder's defaults are `defaultMonitorOption: all` and `defaultNewItemMonitorOption: all`. Adding an artist at those defaults makes Lidarr want their **entire discography**, and Soularr will then feed all of it to slskd. Set **Monitor: None** (or "Future Albums") unless you genuinely want the back catalogue fetched.

Everything you never add stays listed under **`/unmapped`** and is left alone. That page being long is the expected steady state, not a problem to fix.

## 1. Download

See the sldl section of [the VPN runbook](../runbooks/ernst-vpn-microvm-deploy.md). Downloads land in `/srv/media/soulseek/sldl/<playlist>/`.

## 2 + 3. Organise and publish — automatic

`music-import.service` runs daily at 06:00 (before `sldl-playlists` at 06:30):

1. **`music-stage`** — beets with this deployment's config and `-A -s` baked in, over `/srv/media/soulseek/sldl`. It **copies** rather than moves, so sldl's per-playlist `_index.csv` bookkeeping stays intact. Skipped when no finished file is newer than `/srv/state/beets/.last-stage`. Output: `/srv/media/staging/music/Artist/Album/Title.ext`.
2. **`music-publish`** — copies every staged file not yet in the ledger `/srv/state/beets/published.list` into `/srv/media/library/music`, merges artist folders case-insensitively into the library's existing spelling, and sets `:media` `0664`/`2770`. Tagless files under `_/` are never published.

By hand:

```bash
ssh root@ernst.skynet.lan
systemctl start music-import && journalctl -u music-import -n 20
DRY=1 music-publish           # preview the publish alone
```

!!! danger "Do not publish with `cp -rn`"
    Lidarr adopts and **renames** what lands in the library (`Album (Year)/Artist - Album - NN - Title`). Measured 2026-11-23: 5,825 of 7,525 published files are no longer at the path they were copied to. A path-based no-clobber copy re-copies all of them as duplicates. The ledger is what prevents that; `music-publish` is the only publish.

## 4. Navidrome

It rescans on a schedule and on restart. To force one:

```bash
nixos-container run arr -- systemctl restart navidrome
```

Sanity-check that the database caught up:

```bash
find /srv/media/library/music -type f \( -iname '*.flac' -o -iname '*.mp3' -o -iname '*.m4a' -o -iname '*.opus' \) | wc -l
cp /srv/state/navidrome/navidrome.db /tmp/nd.db
nix shell nixpkgs#sqlite -c sqlite3 -readonly /tmp/nd.db 'select count(*) from media_file;'
rm -f /tmp/nd.db
```

The song count can exceed the file count slightly — Navidrome counts some multi-artist entries separately.

## What still needs a human

**Case-variant artist folders** are handled by `music-publish`, which files a staged `Florence + The Machine/` into an existing `Florence + the Machine/`. Variants *inside* staging that have no library folder yet still split; merge them by hand when you notice one.

**Files with no tags at all.** beets cannot place them and files them under `_/`. Do not copy that into the library:

```bash
mkdir -p /srv/media/staging/untagged
mv /srv/media/staging/music/_/* /srv/media/staging/untagged/ && rmdir /srv/media/staging/music/_
```

Tag them by hand or delete them. Of the first 239 files, exactly two were in this state.

## The other Soulseek route: Soularr → Lidarr

Separate from all of the above, and already automatic: `soularr.timer` searches slskd for Lidarr's *wanted* albums, waits for the download, and asks Lidarr to import it from `/srv/media/soulseek/complete/`. A successful import **moves** the folder out, so what remains there is one of:

- **`complete/failed_imports/<Artist - Album (Year)>/`** — Lidarr refused the match (classical releases, deluxe editions, partial downloads). Soularr denylists that release and does not retry it. Import one by hand in **Lidarr → Wanted → Manual Import** (pick the folder, choose the release), or delete it.
- **Any other folder older than a day** — a download Soularr gave up on (often 1–3 files of an album). Safe to delete; Soularr searches the album again.

To see what is waiting:

```bash
ls /srv/media/soulseek/complete/failed_imports | wc -l
find /srv/media/soulseek/complete -mindepth 1 -maxdepth 1 -type d ! -name failed_imports -mtime +1
```
