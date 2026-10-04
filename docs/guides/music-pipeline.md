# Getting playlist downloads into the music library

From a Spotify/CSV playlist to something Navidrome serves. Four stages, three of them automated.

```
sldl              beets             cp                Navidrome
(VPN guest)   →   music-stage   →   into the      →   indexes by
playlists         Artist/Album/     library           TAGS
```

| Stage | Where | Command |
|---|---|---|
| download | VPN guest, `10.0.90.11` | `sldl <csv> -c …/sldl.conf` |
| organise | `arr` container | `music-stage` |
| publish | ernst host | `cp -rn` + `chmod` (below) |
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

## 2. Organise

```bash
ssh root@ernst.skynet.lan
nixos-container run arr -- music-stage        # defaults to the sldl tree
```

`music-stage` is beets with this deployment's config and `-A -s` baked in. It **copies** rather than moves, so sldl's per-playlist `_index.csv` bookkeeping stays intact and the batch is undisturbed. Re-running is cheap: the catalogue in `/srv/state/beets` makes it incremental.

Output: `/srv/media/staging/music/Artist/Album/Title.ext`.

## 3. Publish into the library

```bash
cp -rn /srv/media/staging/music/. /srv/media/library/music/
find /srv/media/library/music -newermt "-10min" -type f -exec chmod 0664 {} +
find /srv/media/library/music -newermt "-10min" -type d -exec chmod 2770 {} +
```

!!! danger "The chmod is not optional"
    `cp` applies your shell's umask, so files land `0644` — **not** group-writable. The library convention is `0664` files / `2770` setgid directories owned `:media`, which is what lets Lidarr (uid 3017, group `media`) manage anything it later adopts. Skipping this silently creates files Lidarr cannot touch. Verify with:

    ```bash
    find /srv/media/library/music -newermt "-10min" -type f ! -perm -g=w | wc -l   # expect 0
    ```

`-n` (no-clobber) means an existing file always wins. Artists already in the library merge; nothing is overwritten.

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

## Two things that need a human

**Case-variant artist folders.** beets files by the tags it is given, so inconsistent tags produce `Florence + the Machine` *and* `Florence + The Machine`. `cp -rn` then creates a second folder and the artist is split in Navidrome. Check before copying:

```bash
ls -1 /srv/media/library/music > /tmp/lib.txt
ls -1 /srv/media/staging/music > /tmp/stage.txt
join -t'|' <(awk '{print tolower($0)"|"$0}' /tmp/lib.txt   | sort -t'|' -k1,1) \
           <(awk '{print tolower($0)"|"$0}' /tmp/stage.txt | sort -t'|' -k1,1) \
  | awk -F'|' '$2 != $3 {print "  lib: " $2 "   stage: " $3}'
```

Merge any hit into the library's spelling before step 3.

**Files with no tags at all.** beets cannot place them and files them under `_/`. Do not copy that into the library:

```bash
mkdir -p /srv/media/staging/untagged
mv /srv/media/staging/music/_/* /srv/media/staging/untagged/ && rmdir /srv/media/staging/music/_
```

Tag them by hand or delete them. Of the first 239 files, exactly two were in this state.
