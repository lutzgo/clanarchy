# machines/ernst/yt-audio-import.sh
#
# Body of `yt-audio-import`.  NOT standalone: yt-audio.nix prepends the path
# constants (CONF, STATE, ABS_ROOT, MUSIC_ROOT) and wraps this in
# writeShellApplication, so the tool cannot drift from the deployment.
#
# Reads $CONF, one playlist per line:
#
#   audiobooks https://www.youtube.com/playlist?list=PL...
#   music      https://www.youtube.com/playlist?list=PL...
#
# Blank lines and lines starting with # are ignored.  The file lives on ernst
# and NOT in this repo because the repo is public and an unlisted playlist's
# link is the only thing keeping it unlisted.
#
# Every video is downloaded ONCE per target: yt-dlp's --download-archive
# records its id, so a video left in the playlist is skipped on every later
# run.  Empty the playlist whenever you like; nothing here depends on it.

log() { echo "yt-audio-import: $*"; }

if [ ! -s "$CONF" ]; then
  log "no playlists configured in $CONF — nothing to do (see docs/guides/youtube.md)"
  exit 0
fi

install -d -m 0750 "$STATE/tmp" "$STATE/cache"

common=(
  --yes-playlist
  --ignore-errors # one deleted/private video must not stop the rest
  --no-progress
  --match-filter '!is_live & live_status != is_upcoming'
  # YouTube almost always offers AAC (itag 140) — taken as-is, no re-encode.
  # Only when it does not is the best audio transcoded to m4a.
  -f 'bestaudio[ext=m4a]/bestaudio'
  --extract-audio --audio-format m4a
  --embed-metadata
  --embed-thumbnail --convert-thumbnails jpg
  --trim-filenames 180
  --no-overwrites
  --sleep-requests 1 --sleep-interval 2
  --cache-dir "$STATE/cache"
  # Fragments and post-processing happen here; the finished file is moved into
  # the library only at the very end, so neither Navidrome's nor
  # Audiobookshelf's folder watcher ever sees a half-written file.  This only
  # works because the -o templates below are RELATIVE (to -P home:) — given
  # an absolute -o, yt-dlp ignores --paths entirely and says so.
  -P "temp:$STATE/tmp"
)

failed=0
while read -r target url _; do
  case "$target" in "" | \#*) continue ;; esac
  [ -n "${url:-}" ] || { log "line for '$target' has no URL — skipped"; failed=1; continue; }

  case "$target" in
    audiobooks)
      # Audiobookshelf's layout: <Author>/<Title>/<files>, with cover.jpg
      # beside the audio.  The channel is the author.
      dir="%(uploader|Unknown)s/%(title)s"
      args=(
        -P "home:$ABS_ROOT"
        -o "$dir/%(title)s.%(ext)s"
        --write-thumbnail -o "thumbnail:$dir/cover.%(ext)s"
      )
      ;;
    music)
      # Tags are what Navidrome groups by.  A YouTube Music upload carries real
      # artist/album fields and they are kept; anything else gets the channel
      # as artist and "YouTube" as the album, so a channel's pieces form one
      # album instead of one single per track.
      args=(
        -P "home:$MUSIC_ROOT"
        -o "%(artist,uploader|Unknown)s/%(title)s.%(ext)s"
        --parse-metadata '%(artist,uploader|Unknown)s:%(meta_artist)s'
        --parse-metadata '%(album_artist,artist,uploader|Unknown)s:%(meta_album_artist)s'
        --parse-metadata '%(album|YouTube)s:%(meta_album)s'
      )
      install -d -m 2770 "$MUSIC_ROOT"
      ;;
    *)
      log "unknown target '$target' (expected: audiobooks, music) — skipped"
      failed=1
      continue
      ;;
  esac

  log "$target: $url"

  # Probe the playlist itself first.  The download below runs with
  # --ignore-errors, so it exits non-zero for a single dead video too — which
  # would turn the unit red every day for a video nobody can fix.  A playlist
  # that cannot be read at all (typo, or set to Private) is the failure worth
  # a red unit.
  if ! yt-dlp --flat-playlist --quiet --no-warnings -J "$url" >/dev/null </dev/null; then
    log "$target: cannot read the playlist — is it set to Unlisted (not Private)?"
    failed=1
    continue
  fi

  yt-dlp "${common[@]}" "${args[@]}" \
    --download-archive "$STATE/archive-$target.txt" \
    "$url" </dev/null || log "$target: some videos failed (see above); the rest were downloaded"
done < "$CONF"

# MoveFiles takes the files out of the temp tree but leaves the directories.
find "$STATE/tmp" -mindepth 1 -type d -empty -delete

exit "$failed"
