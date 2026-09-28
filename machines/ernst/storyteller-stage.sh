# machines/ernst/storyteller-stage.sh
#
# Body of `storyteller-stage`.  NOT standalone: containers/storyteller.nix
# prepends the uid/gid/path constants and wraps this in writeShellApplication,
# so the tool cannot drift from the deployment.  Same arrangement as
# rom-import.sh next door, for the same reason.

usage() {
  cat <<EOF
storyteller-stage — stage an ebook + audiobook pair for Storyteller

  storyteller-stage <name> <ebook> <audiobook-dir>
  storyteller-stage list
  storyteller-stage pairs
  storyteller-stage new

  <name>           subdirectory to create under the watch folder, e.g. consider-phlebas
  <ebook>          path to an EPUB
  <audiobook-dir>  directory of audio files (flac/mp3/m4a/m4b/ogg/opus)

Both halves land in ONE subdirectory, which is what makes Storyteller treat them
as a single item instead of two unmatched ones.

  list    what is currently staged
  pairs   titles that exist in BOTH libraries and could be staged
  new     pairs not yet imported and not yet staged, tab-separated
          (slug, ebook, audiobook). Empty output means no news — this is
          what the weekly ntfy watcher runs.
EOF
}

die() { echo "storyteller-stage: $*" >&2; exit 1; }

# Same-dataset check.  A hardlink is instant and free; a copy of a 4 GB
# audiobook is neither.  `stat -c %d` is the device id — equal means one
# filesystem, which for this host means one ZFS dataset and therefore linkable.
same_dataset() {
  [ "$(stat -c %d "$1")" = "$(stat -c %d "$2")" ]
}

cmd_list() {
  if [ ! -d "$IMPORT" ] || [ -z "$(ls -A "$IMPORT" 2>/dev/null)" ]; then
    echo "nothing staged in $IMPORT"
    return 0
  fi
  for d in "$IMPORT"/*/; do
    [ -d "$d" ] || continue
    n=$(basename "$d")
    ebooks=$(find "$d" -maxdepth 1 -type f -iname '*.epub' | wc -l)
    audio=$(find "$d" -maxdepth 1 -type f \
      \( -iname '*.flac' -o -iname '*.mp3' -o -iname '*.m4a' \
         -o -iname '*.m4b' -o -iname '*.ogg' -o -iname '*.opus' \) | wc -l)
    # Apparent size, not disk usage: the audio is hardlinked, so `du` without
    # --apparent-size reports ~0 and looks like the staging failed.
    size=$(du -sh --apparent-size "$d" 2>/dev/null | cut -f1)
    printf '  %-40s %2s epub  %3s audio  %s\n' "$n" "$ebooks" "$audio" "$size"
  done
}

# Which titles exist in both libraries.  Deliberately crude — it lowercases and
# strips punctuation, then looks for one name inside the other.  The author
# directories are NOT comparable: Audiobookshelf files Banks under
# "Iain M. Banks" and Bindery under "Iain Banks", so an author-level join
# misses real pairs.  Titles are the only thing that lines up.
norm() { tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9 ]//g; s/  */ /g; s/^ //; s/ $//'; }

# The pair join, once, machine-readable: "<ebook>\t<audiobook>" per line.
# cmd_pairs pretty-prints it and cmd_new filters it; neither reimplements it,
# because two copies of this matcher would drift and the matcher IS the
# interesting part.
emit_pairs() {
  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' RETURN

  find "$EBOOKS" -type f -iname '*.epub' -printf '%p\n' 2>/dev/null > "$tmp/ebooks"
  find "$AUDIO" -mindepth 2 -maxdepth 2 -type d -printf '%p\n' 2>/dev/null > "$tmp/audio"

  while IFS= read -r ab; do
    abt=$(basename "$ab" | norm)
    [ -n "$abt" ] || continue
    while IFS= read -r eb; do
      # Strip the " - Author.epub" suffix Bindery's naming template appends.
      ebt=$(basename "$eb" .epub | sed 's/ - [^-]*$//' | norm)
      [ -n "$ebt" ] || continue
      case "$abt" in *"$ebt"*) ;; *) case "$ebt" in *"$abt"*) ;; *) continue ;; esac ;; esac
      printf '%s\t%s\n' "$eb" "$ab"
      break
    done < "$tmp/ebooks"
  done < "$tmp/audio"
}

cmd_pairs() {
  found=0
  while IFS=$(printf '\t') read -r eb ab; do
    echo "  PAIR"
    echo "    ebook:     $eb"
    echo "    audiobook: $ab"
    found=$((found + 1))
  done <<EOF
$(emit_pairs)
EOF

  [ "$found" -eq 0 ] && echo "  no titles present in both libraries"
  echo
  echo "  ($found candidate pair(s); an EPUB is required — azw3/mobi must be converted first)"
}

# Pairs that are NOT already imported and NOT already staged.  This is what the
# weekly ntfy watcher runs; it prints one "<slug>\t<ebook>\t<audiobook>" per
# line and nothing at all when there is no news, so an empty stdout is the
# "say nothing" signal.
#
# Already-imported is decided against Storyteller's OWN database rather than
# against $IMPORT, because the watch folder is a scratch drop box that gets
# cleared — using it as the ledger would re-announce every title every time it
# was emptied.  Read-only open; this runs while the app is live.
cmd_new() {
  titles=""
  if [ -r "$DB" ]; then
    titles=$(sqlite3 -readonly "$DB" 'select title from book;' 2>/dev/null | norm || true)
  fi

  while IFS=$(printf '\t') read -r eb ab; do
    [ -n "$eb" ] || continue
    abt=$(basename "$ab" | norm)

    # Already in Storyteller?  Same substring rule as the library join, since
    # the DB stores "Consider Phlebas" and the audiobook dir is
    # "Consider Phlebas: Culture Series, Book 1".
    known=0
    while IFS= read -r t; do
      [ -n "$t" ] || continue
      case "$abt" in *"$t"*) known=1; break ;; esac
      case "$t" in *"$abt"*) known=1; break ;; esac
    done <<EOF
$titles
EOF
    [ "$known" -eq 1 ] && continue

    slug=$(basename "$ab" | norm | sed 's/ /-/g' | cut -c1-60)
    [ -e "$IMPORT/$slug" ] && continue

    printf '%s\t%s\t%s\n' "$slug" "$eb" "$ab"
  done <<EOF
$(emit_pairs)
EOF
}

cmd_stage() {
  name=$1; ebook=$2; audiodir=$3

  [ -f "$ebook" ] || die "ebook not found: $ebook"
  [ -d "$audiodir" ] || die "audiobook directory not found: $audiodir"

  case "$ebook" in
    *.epub|*.EPUB) ;;
    *) die "Storyteller needs an EPUB; got '$ebook'.
       Convert first — dropping the file into CWA's ingest folder
       ($INGEST) will do it, and the result lands in CWA's library." ;;
  esac

  dest="$IMPORT/$name"
  [ -e "$dest" ] && die "already staged: $dest (remove it first, or pick another name)"

  install -d -o "$UID_" -g "$GID_" -m 2770 "$dest"

  # Audio: hardlink when possible.  The whole reason the staging directory is
  # on zdata/audiobooks is that this is then free — see containers/storyteller.nix.
  n=0
  linked=0
  while IFS= read -r f; do
    if same_dataset "$f" "$dest"; then
      ln "$f" "$dest/" && linked=$((linked + 1))
    else
      cp -- "$f" "$dest/"
    fi
    n=$((n + 1))
  done < <(find "$audiodir" -maxdepth 1 -type f \
    \( -iname '*.flac' -o -iname '*.mp3' -o -iname '*.m4a' \
       -o -iname '*.m4b' -o -iname '*.ogg' -o -iname '*.opus' \) | sort)

  [ "$n" -eq 0 ] && { rm -rf "$dest"; die "no audio files found in $audiodir"; }

  # Ebook: almost always a real copy, because the ebook library is on
  # zdata/media and the staging directory is not.  Kilobytes; not worth solving.
  cp -- "$ebook" "$dest/"

  chown -R "$UID_:$GID_" "$dest"

  echo "staged $name:"
  echo "  $n audio file(s) ($linked hardlinked, $((n - linked)) copied)"
  echo "  1 ebook: $(basename "$ebook")"
  echo
  echo "Storyteller's watcher picks this up within seconds."
  echo "Alignment is CPU-heavy and nice'd — expect hours, not minutes."
}

case "${1-}" in
  list)  cmd_list ;;
  pairs) cmd_pairs ;;
  new)   cmd_new ;;
  ""|-h|--help|help) usage ;;
  *)
    [ "$#" -eq 3 ] || { usage; exit 1; }
    cmd_stage "$1" "$2" "$3"
    ;;
esac
