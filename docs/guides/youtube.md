# YouTube → Jellyfin, Audiobookshelf, Navidrome

Four unlisted YouTube playlists are the inbox. Saving a video to one of them
(one tap in the YouTube app) is all there is to do; ernst downloads it within a
day and files it into the library the playlist stands for.

| Playlist | Downloaded by | Lands in | Shows up in |
|---|---|---|---|
| `ernst Video` | TubeSync, every 24 h | `/srv/media/youtube/video/ernst-video/` | Jellyfin → **YouTube** |
| `ernst Hörspiel` | `yt-audio-import`, daily 05:30 | `/srv/audiobooks/library/<Channel>/<Title>/` | Audiobookshelf |
| `ernst Kinder` | `yt-audio-import`, daily 05:30 | `/srv/audiobooks/kinder/<Channel>/<Title>/` | Audiobookshelf, Kinder library |
| `ernst Musik` | `yt-audio-import`, daily 05:30 | `/srv/media/library/music/_youtube/<Artist>/` | Navidrome, album **YouTube** |

Each video is downloaded once. Leaving it in the playlist does nothing further,
and removing it deletes nothing — empty a playlist whenever you like.

Each inbox video becomes its **own** book. For a playlist that *is* one book —
an album, a Hörspiel in parts, someone else's playlist included — see
[A whole playlist as one book](#a-whole-playlist-as-one-book).

The playlists must be **Unlisted**, not Private: ernst has no YouTube login, so
it can read only what anyone with the link can read. And their links are not in
this repository, because it is public and the link is what keeps an unlisted
playlist unlisted.

## One-time setup

### 1. Create the four playlists (browser, youtube.com, signed in, German UI)

Do this four times, with the names `ernst Video`, `ernst Hörspiel`,
`ernst Kinder` and `ernst Musik`:

1. Open any video you want in that playlist.
2. Scroll down to the video's title, directly under the player. Below it, on
   the right, click **⋯** → **Speichern**. (On a wide window **Speichern** is
   in that row itself.) Not the **⋮** in a playlist panel beside the video —
   that one only offers *Herunterladen*. Not **+ Erstellen** at the top — that
   is for uploads.
3. Click **+ Neue Playlist**.
4. **Titel**: the name above. **Sichtbarkeit**: **Nicht gelistet**.
5. Click **Erstellen**.

Then collect the links:

1. **☰** (top left) → **Playlists**.
2. Click the playlist, then **Vollständige Playlist ansehen**.
3. Copy the address bar. It must start with
   `https://www.youtube.com/playlist?list=`. A `watch?v=…&list=…` address is
   the wrong one.

### 2. Register the three audio playlists on ernst

One command, with the three links pasted in place of the placeholders:

```
ssh root@ernst.skynet.lan "mkdir -p /srv/state/yt-audio && printf 'audiobooks %s\nkinder %s\nmusic %s\n' 'HÖRSPIEL-LINK' 'KINDER-LINK' 'MUSIK-LINK' > /srv/state/yt-audio/playlists"
```

This replaces the file, so it is also the command for changing a link later.

Then fetch them now instead of at 05:30, and watch:

```
ssh root@ernst.skynet.lan 'systemctl start --no-block yt-audio-import'
ssh root@ernst.skynet.lan 'journalctl -fu yt-audio-import'
```

Ctrl-C ends the `journalctl`; the download carries on. The file format is one
`<target> <link>` per line, target `audiobooks`, `kinder` or `music`; lines starting with
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

YouTube app → under the video tap **Speichern** → tick the playlist.

## A whole playlist as one book

For a playlist that is a single work — any playlist, yours or someone else's —
register it once:

```
ssh root@ernst.skynet.lan "yt-audio-import add-book kinder 'PLAYLIST-LINK' 'AUTHOR' 'TITLE' 'ITEMS'"
```

| Argument | Meaning |
|---|---|
| `kinder` | The library: `kinder` or `audiobooks`. |
| `PLAYLIST-LINK` | The playlist's `https://www.youtube.com/playlist?list=…` link. |
| `AUTHOR`, `TITLE` | The folder names, `<Author>/<Title>/` — which is what Audiobookshelf shows. No `/`, and no `'` (it would end the quoted argument). |
| `ITEMS` | Which playlist positions to take, e.g. `1,2,4-7,9-` (`9-` = 9 to the end). `''` for all of them. This is how stray videos in someone else's playlist are left out. |

It registers the book and starts the download at once. Every selected video
lands in that one folder as `NN - <title>.m4a`, numbered by its playlist
position; Audiobookshelf plays a folder of several files as **one book with a
chapter per file**, straight through. If the playlist gains videos later, the
daily run adds them to the same book.

Example, used for the first one:

```
ssh root@ernst.skynet.lan "yt-audio-import add-book kinder 'https://www.youtube.com/playlist?list=PLgl-_f-IW3BBUbVChZUByUe1vhtkhs6jU' 'Rolf Zuckowski' 'Rolfs Vogelhochzeit' '1-2,4-7,9-14,16-26'"
```

To see the positions first (3 and 15 there are hour-long videos by other
channels, 8 is unavailable):

```
ssh root@ernst.skynet.lan "yt-audio-import items 'PLAYLIST-LINK'"
```

List the registered books with `ssh root@ernst.skynet.lan 'yt-audio-import books'`.
They live in `/srv/state/yt-audio/books`, one tab-separated line each; delete
a line there to stop following a playlist.

## When something does not arrive

```
ssh root@ernst.skynet.lan 'journalctl -u yt-audio-import --since yesterday'
```

| Log line | Meaning |
|---|---|
| `cannot read the playlist` | The playlist is Private or the link is wrong. The unit is marked failed. |
| `some videos failed` | One video could not be fetched (deleted, region-locked, or a YouTube `403`). It is not in the download archive, so the next run tries it again. |
| `no inbox playlists` | Step 2 has not been done. |

Audiobookshelf and Navidrome both watch their folders, so a new file appears on
its own. If it does not: Audiobookshelf → **Settings** → **Libraries** → the
library's **Scan** button. Navidrome additionally rescans every 12 hours by
itself.

The download archives are `/srv/state/yt-audio/archive-{audiobooks,kinder,music,books}.txt`.
To download a video again, delete its line there.

## Why it is built this way

See the header of [`machines/ernst/yt-audio.nix`](../../machines/ernst/yt-audio.nix):
why a playlist and not a Nextcloud watch folder, why not TubeSync for the audio
as well, and why the music goes to `_youtube/` inside the music library.
