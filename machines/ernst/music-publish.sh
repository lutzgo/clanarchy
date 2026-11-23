# machines/ernst/music-publish.sh
#
# Body of `music-publish`.  NOT standalone: containers/arr/music.nix prepends
# the path constants (ST, LIB, MANIFEST) and wraps this in
# writeShellApplication.  Same arrangement as storyteller-stage.sh.
#
# Publishes beets' staging tree into the music library, ONCE per file.
#
#   DRY=1 (the default by hand) prints the plan; DRY=0 copies.
#   The music-import unit runs it with DRY=0.
#
# ── WHY A LEDGER AND NOT `cp -rn` ──────────────────────────────────────────
#
# Lidarr adopts what lands in the library and RENAMES it into its own
# `Album (Year)/Artist - Album - NN - Title` shape.  MEASURED 2026-11-23:
# 5,825 of 7,525 published files no longer exist at the path they were copied
# to.  A path-based no-clobber copy would therefore re-copy every one of them
# as a duplicate.  $MANIFEST records each staging-relative path already
# published; a listed path is never copied again, whether or not it is still
# where it was put.
#
# ── ARTIST FOLDERS MERGE CASE-INSENSITIVELY ────────────────────────────────
#
# beets files by tag, so `Florence + The Machine` and `Florence + the Machine`
# both occur.  A staged artist folder whose lowercased name matches an
# existing library folder goes into THAT folder, so Navidrome does not split
# the artist.
#
# ── `_/` IS NEVER PUBLISHED ────────────────────────────────────────────────
#
# beets files tagless tracks under `_/`.  They stay in staging for a human:
# tag them or delete them (docs/guides/music-pipeline.md).

DRY=${DRY:-1}
touch "$MANIFEST"

declare -A canon
while IFS= read -r d; do canon["${d,,}"]="$d"; done \
  < <(find "$LIB" -mindepth 1 -maxdepth 1 -type d -printf '%f\n')

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

(cd "$ST" && find . -type f ! -path './_/*' | sed 's|^\./||' | sort) > "$work/all"
sort -u "$MANIFEST" > "$work/done"
comm -23 "$work/all" "$work/done" > "$work/new"

untagged=$(find "$ST/_" -type f 2>/dev/null | wc -l)
echo "staged: $(wc -l < "$work/all")  already published: $(wc -l < "$work/done")  to publish: $(wc -l < "$work/new")  untagged (_/, left alone): $untagged"

[ -s "$work/new" ] || exit 0

marker="$work/marker"
touch "$marker"
merged=0
while IFS= read -r f; do
  d=${f%%/*}
  rest=${f#*/}
  k="${d,,}"
  if [ -n "${canon[$k]+x}" ]; then t="${canon[$k]}"; else t="$d"; canon["$k"]="$d"; fi
  [ "$t" != "$d" ] && merged=$((merged + 1))
  if [ "$DRY" = 0 ]; then
    mkdir -p "$LIB/$t/$(dirname "$rest")"
    cp -n --reflink=auto -- "$ST/$f" "$LIB/$t/$rest"
    printf '%s\n' "$f" >> "$MANIFEST"
  else
    echo "  $f -> $t/$rest"
  fi
done < "$work/new"
echo "into a differently-spelled existing artist folder: $merged"

if [ "$DRY" = 0 ]; then
  # The library convention: :media, 0664 files, 2770 setgid directories —
  # what lets Lidarr (group media) manage what it adopts.  cp applies the
  # caller's umask and keeps root's group, so this is not optional.
  find "$LIB" -newer "$marker" -type f -exec chgrp media {} + -exec chmod 0664 {} +
  find "$LIB" -newer "$marker" -type d -exec chgrp media {} + -exec chmod 2770 {} +
  echo "new files in library: $(find "$LIB" -newer "$marker" -type f | wc -l)"
else
  echo "(dry run — DRY=0 to copy)"
fi
