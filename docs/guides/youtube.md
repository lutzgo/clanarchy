# YouTube → Jellyfin, Audiobookshelf, Navidrome

Three unlisted YouTube playlists are the inbox. Saving a video to one of them
(one tap in the YouTube app) is all there is to do; ernst downloads it within a
day and files it into the library the playlist stands for.

| Playlist | Downloaded by | Lands in | Shows up in |
|---|---|---|---|
| `ernst Video` | TubeSync, every 24 h | `/srv/media/youtube/video/ernst-video/` | Jellyfin → **YouTube** |
| `ernst Hörspiel` | `yt-audio-import`, daily 05:30 | `/srv/audiobooks/library/<Channel>/<Title>/` | Audiobookshelf |
| `ernst Musik` | `yt-audio-import`, daily 05:30 | `/srv/media/library/music/_youtube/<Artist>/` | Navidrome, album **YouTube** |

Each video is downloaded once. Leaving it in the playlist does nothing further,
and removing it deletes nothing — empty a playlist whenever you like.

The playlists must be **Unlisted**, not Private: ernst has no YouTube login, so
it can read only what anyone with the link can read. And their links are not in
this repository, because it is public and the link is what keeps an unlisted
playlist unlisted.

## One-time setup

### 1. Create the three playlists (browser, youtube.com, signed in)

Do this three times, with the names `ernst Video`, `ernst Hörspiel` and
`ernst Musik`:

1. Open any video you want in that playlist.
2. Under the video click **Save**. If there is no Save button, click **⋯** and
   then **Save**.
3. Click **+ New playlist**.
4. Title: the name above. Visibility: **Unlisted**.
5. Click **Create**.

Then collect the three links:

1. Left sidebar → **You** → **Playlists**.
2. Click the playlist, then **View full playlist**.
3. Copy the address bar. It looks like
   `https://www.youtube.com/playlist?list=PL…`.

### 2. Register the two audio playlists on ernst

One command, with the two links pasted in place of the placeholders:

```
ssh root@ernst.skynet.lan "mkdir -p /srv/state/yt-audio && printf 'audiobooks %s\nmusic %s\n' 'HÖRSPIEL-LINK' 'MUSIK-LINK' > /srv/state/yt-audio/playlists"
```

Then fetch them now instead of at 05:30, and watch:

```
ssh root@ernst.skynet.lan 'systemctl start --no-block yt-audio-import'
ssh root@ernst.skynet.lan 'journalctl -fu yt-audio-import'
```

Ctrl-C ends the `journalctl`; the download carries on. The file format is one
`<target> <link>` per line, target `audiobooks` or `music`; lines starting with
`#` are ignored.

### 3. Add the video playlist to TubeSync

1. Open `https://tubesync.goclan.org` → **Sources** → **Add Source**.
2. Source URL: the `ernst Video` link. Click **Add Source**.
3. On the form that follows, set:
    - **Name**: `ernst-video`
    - **Directory**: `ernst-video`
    - **Index schedule**: Every 24 hours
    - **Source resolution**: 1080p (Full HD)
    - **Copy thumbnails**: ticked
    - everything else as it is
4. Click the button at the bottom of the form.

### 4. Create the YouTube library in Jellyfin

TubeSync's downloads are mounted into Jellyfin at `/media/Server001/YouTube`
(read-only; `containers/jellyfin.nix`). The library itself is UI state:

1. Jellyfin → **Dashboard** → **Libraries** → **Add Media Library**.
2. Content type: **Home Videos and Photos**. Display name: `YouTube`.
3. **Folders** → **+** → type `/media/Server001/YouTube` → **OK**.
4. Click **OK**.

This also makes the channels TubeSync already follows visible — they were
downloaded to a tree Jellyfin never mounted until this library existed.

## Daily use

YouTube app → under the video tap **Save** → tick the playlist.

## When something does not arrive

```
ssh root@ernst.skynet.lan 'journalctl -u yt-audio-import --since yesterday'
```

| Log line | Meaning |
|---|---|
| `cannot read the playlist` | The playlist is Private or the link is wrong. The unit is marked failed. |
| `some videos failed` | One video could not be fetched (deleted, region-locked, or a YouTube `403`). It is not in the download archive, so the next run tries it again. |
| `no playlists configured` | Step 2 has not been done. |

Audiobookshelf and Navidrome both watch their folders, so a new file appears on
its own. If it does not: Audiobookshelf → **Settings** → **Libraries** → the
library's **Scan** button. Navidrome additionally rescans every 12 hours by
itself.

The download archives are `/srv/state/yt-audio/archive-{audiobooks,music}.txt`.
To download a video again, delete its line there.

## Why it is built this way

See the header of [`machines/ernst/yt-audio.nix`](../../machines/ernst/yt-audio.nix):
why a playlist and not a Nextcloud watch folder, why not TubeSync for the audio
as well, and why the music goes to `_youtube/` inside the music library.
