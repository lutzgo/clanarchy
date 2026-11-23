# machines/ernst/yt-audio-import.sh
#
# Body of `yt-audio-import`.  NOT standalone: yt-audio.nix prepends the path
# constants (STATE, CONF, BOOKS, ABS_ROOT, MUSIC_ROOT) and wraps this in
# writeShellApplication, so the tool cannot drift from the deployment.
#
#   yt-audio-import                    download everything new (what the timer runs)
#   yt-audio-import add-book <library> <playlist-url> <author> <title> [items]
#                                      register a playlist as ONE book, then start a run
#   yt-audio-import books              list the registered books
#   yt-audio-import items <playlist-url>
#                                      a playlist's positions, titles and channels —
#                                      what the [items] of add-book refers to
#
# TWO KINDS OF ENTRY, in two files:
#
# $CONF — inbox playlists, one per line, "<target> <url>":
#
#   audiobooks https://www.youtube.com/playlist?list=PL...   each video → its own book
#   kinder     https://www.youtube.com/playlist?list=PL...   the same, kids' library
#   music      https://www.youtube.com/playlist?list=PL...   each video → a track
#
# $BOOKS — playlists that ARE one book (an album, a Hörspiel in parts),
# tab-separated "<library>\t<url>\t<author>\t<title>\t<items>", written by
# `add-book`.  Every selected video lands in ONE folder <Author>/<Title>/,
# numbered by its playlist position.  Audiobookshelf reads a folder of several
# audio files as a single book with one chapter per file, and plays straight
# through — that IS the concatenation; no re-encode into one file is needed.
# Author and title come from the folder names (Audiobookshelf's default; the
# embedded tags are the channel's and are not consulted).
# <items> is yt-dlp's --playlist-items syntax ("1,2,4-7,9-"), empty for all,
# and is how a stray video in someone else's playlist is left out.
#
# Neither file is in this repo: the repo is public, and an unlisted playlist's
# link is the only thing keeping it unlisted.
#
# Every video is downloaded ONCE per archive: --download-archive records its
# id, so a video left in a playlist is skipped on every later run.

log() { echo "yt-audio-import: $*"; }
die() {
  echo "yt-audio-import: $*" >&2
  exit 1
}

lib_dir() {
  case "$1" in
    audiobooks) echo "$ABS_ROOT/library" ;;
    kinder) echo "$ABS_ROOT/kinder" ;;
    *) return 1 ;;
  esac
}

# Used as a folder name, so: not empty, no slash, no tab (the file's
# separator), not a dot-name.
check_name() {
  case "$2" in
    "" | .* | */* | *$'\t'*) die "$1 must be non-empty, contain no '/' or tab, and not start with '.': '$2'" ;;
  esac
}

cmd_add_book() {
  { [ "$#" -ge 4 ] && [ "$#" -le 5 ]; } ||
    die "usage: yt-audio-import add-book <audiobooks|kinder> <playlist-url> <author> <title> [items]"
  library=$1 url=$2 author=$3 title=$4 items=${5-}
  lib_dir "$library" >/dev/null || die "library must be 'audiobooks' or 'kinder', not '$library'"
  check_name author "$author"
  check_name title "$title"
  case "$items" in *[!0-9,:-]*) die "items must look like '1,2,4-7,9-', not '$items'" ;; esac

  install -d -m 0750 "$STATE"
  if [ -f "$BOOKS" ] && cut -f2 "$BOOKS" | grep -qxF -- "$url"; then
    die "already registered: $url (edit $BOOKS to change it)"
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$library" "$url" "$author" "$title" "$items" >>"$BOOKS"
  log "registered: $library / $author / $title${items:+ (items $items)}"
  systemctl start --no-block yt-audio-import.service
  log "download started — follow it with: journalctl -fu yt-audio-import"
}

cmd_books() {
  [ -s "$BOOKS" ] || {
    echo "no books registered in $BOOKS"
    return 0
  }
  while IFS=$'\t' read -r library url author title items; do
    printf '%-10s %s / %s%s\n           %s\n' "$library" "$author" "$title" "${items:+  [items $items]}" "$url"
  done <"$BOOKS"
}

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
  # Without this --write-thumbnail also writes the PLAYLIST's own thumbnail,
  # as "00 - <playlist title>.jpg" inside the book folder.
  --no-write-playlist-metafiles
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

# Probe the playlist itself first.  The download runs with --ignore-errors, so
# it exits non-zero for a single dead video too — which would turn the unit red
# every day for a video nobody can fix.  A playlist that cannot be read at all
# (typo, or set to Private) is the failure worth a red unit.
probe() {
  if ! yt-dlp --flat-playlist --quiet --no-warnings -J "$1" >/dev/null </dev/null; then
    log "cannot read the playlist $1 — is it set to Unlisted (not Private)?"
    failed=1
    return 1
  fi
}

fetch() { # <archive-name> <url> <args...>
  archive=$1 url=$2
  shift 2
  yt-dlp "${common[@]}" "$@" --download-archive "$STATE/archive-$archive.txt" "$url" </dev/null ||
    log "some videos failed (see above); the rest were downloaded, the failed ones are retried next run"
}

run_inbox() {
  [ -s "$CONF" ] || {
    log "no inbox playlists in $CONF"
    return 0
  }
  while read -r target url _; do
    case "$target" in "" | \#*) continue ;; esac
    [ -n "${url:-}" ] || {
      log "line for '$target' has no URL — skipped"
      failed=1
      continue
    }

    case "$target" in
      audiobooks | kinder)
        # Audiobookshelf's layout: <Author>/<Title>/<files>, with cover.jpg
        # beside the audio.  The channel is the author.
        dir="%(uploader|Unknown)s/%(title)s"
        args=(
          -P "home:$(lib_dir "$target")"
          -o "$dir/%(title)s.%(ext)s"
          --write-thumbnail -o "thumbnail:$dir/cover.%(ext)s"
        )
        ;;
      music)
        # Tags are what Navidrome groups by.  A YouTube Music upload carries
        # real artist/album fields and they are kept; anything else gets the
        # channel as artist and "YouTube" as the album, so a channel's pieces
        # form one album instead of one single per track.
        install -d -m 2770 "$MUSIC_ROOT"
        args=(
          -P "home:$MUSIC_ROOT"
          -o "%(artist,uploader|Unknown)s/%(title)s.%(ext)s"
          --parse-metadata '%(artist,uploader|Unknown)s:%(meta_artist)s'
          --parse-metadata '%(album_artist,artist,uploader|Unknown)s:%(meta_album_artist)s'
          --parse-metadata '%(album|YouTube)s:%(meta_album)s'
        )
        ;;
      *)
        log "unknown target '$target' (expected: audiobooks, kinder, music) — skipped"
        failed=1
        continue
        ;;
    esac

    log "$target: $url"
    probe "$url" || continue
    fetch "$target" "$url" "${args[@]}"
  done <"$CONF"
}

run_books() {
  [ -s "$BOOKS" ] || return 0
  while IFS=$'\t' read -r library url author title items; do
    [ -n "$library" ] || continue
    root=$(lib_dir "$library") || {
      log "book '$title': unknown library '$library' — skipped"
      failed=1
      continue
    }

    log "book: $library / $author / $title"
    probe "$url" || continue

    # Numbered by PLAYLIST POSITION, which is what orders the chapters.  With
    # items left out the numbers have gaps (01, 02, 04, …); the order is
    # still right, and a video added to the playlist later slots in where it
    # belongs instead of at the end.  cover.jpg comes from the first video;
    # later ones find it present and leave it.
    args=(
      -P "home:$root/$author/$title"
      -o "%(playlist_index)02d - %(title)s.%(ext)s"
      --write-thumbnail -o "thumbnail:cover.%(ext)s"
      --parse-metadata '%(playlist_index)s:%(meta_track)s'
    )
    [ -z "$items" ] || args+=(-I "$items")
    # One archive for all books, separate from the inbox ones: a video that
    # is both a standalone piece and a chapter of a book is downloaded once
    # for each.
    fetch books "$url" "${args[@]}"
  done <"$BOOKS"
}

case "${1-}" in
  items)
    [ "$#" -eq 2 ] || die "usage: yt-audio-import items <playlist-url>"
    yt-dlp --flat-playlist --no-warnings \
      --print '%(playlist_index)3s  %(title)s  —  %(channel,uploader|unavailable)s' "$2"
    exit 0
    ;;
  add-book)
    shift
    cmd_add_book "$@"
    exit 0
    ;;
  books)
    cmd_books
    exit 0
    ;;
  "") ;;
  *) die "unknown command '$1' (expected: add-book, books, items, or nothing)" ;;
esac

install -d -m 0750 "$STATE/tmp" "$STATE/cache"
run_inbox
run_books

# A book's 2nd..nth thumbnail cannot be moved (cover.jpg exists, by design)
# and stays behind in the temp tree; MoveFiles also leaves the directories.
# .part files are NOT touched — they are what lets a failed download resume.
find "$STATE/tmp" -type f -name '*.jpg' -delete
find "$STATE/tmp" -mindepth 1 -type d -empty -delete

exit "$failed"
