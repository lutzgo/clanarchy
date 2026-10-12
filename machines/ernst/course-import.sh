# machines/ernst/course-import.sh
#
# Body of the `course-import` command.  NOT standalone: courses.nix prepends
# the deployment constants (LIB, INGEST, MANIFESTS, MEDIA_GID) and wraps this
# in writeShellApplication, which supplies the shebang and `set -euo pipefail`
# and runs shellcheck at build time.  Keeping the constants on the Nix side is
# the point — they are the same bindings the Jellyfin bind mount is built from,
# so this tool cannot drift from the deployment.
#
# Under `set -e`, note that `cond && action` at statement level EXITS when cond
# is false.  Every such test below is written as a full `if`.
#
# WHAT THIS EXISTS TO GET RIGHT.  A course is not a TV series, and the three
# things that make it awkward are all handled here rather than by hand:
#
#   1. THE FILE SLUG IS NOT THE TITLE.  Proko's download filenames are the
#      lesson URL slug, and the slug disagrees with the lesson title often
#      enough to matter — `simplify-from-observation-pear-demo` is the lesson
#      "Demo - Simplify Pear from Observation".  There is no rule to derive one
#      from the other, so the manifest states the mapping explicitly and this
#      tool refuses to guess.
#   2. EPISODE ORDER IS NOT FILESYSTEM ORDER.  The number comes from the
#      lesson's position in its chapter in the manifest, never from a sort of
#      the ingest directory.  Adding lesson 3 later must not renumber 4..12.
#   3. SIDECARS HAVE INCONSISTENT SUFFIXES.  Proko ships transcripts as
#      `-transcript-english.txt`, `-transcripts-english.txt` AND
#      `-transcription-english.txt` across lessons in the same chapter, so the
#      transcript is matched by glob, not by a fixed name.
#
# AND THE ONE IT REFUSES TO DO: a lesson whose video has not arrived is left
# entirely alone — no NFO, no subtitle move.  Writing metadata for an absent
# video leaves sidecars orphaned in the library that the real import later has
# to collide with.

die()  { printf 'course-import: %s\n' "$*" >&2; exit 1; }
warn() { printf 'course-import: %s\n' "$*" >&2; }

usage() {
  cat <<'USAGE'
course-import — file downloaded course lessons into the Jellyfin Courses library.

  course-import list                 courses with a manifest, and their progress
  course-import status COURSE        per-lesson table: in library / waiting / missing
  course-import import [-n] COURSE   file everything waiting in ingest into the library
  course-import orphans COURSE       ingest files no manifest entry claims
  course-import prune [-n] COURSE    delete ingest copies already in the library

  -n   dry run: print what it would do, change nothing

Ingest a batch first (from the machine holding the downloads):

  rsync -av --info=progress2 ~/Videos/proko/ root@ernst:INGEST/COURSE/

Then `course-import import COURSE`.  Re-running is safe and is how metadata is
corrected: edit the manifest and run import again.  A changed plot is rewritten
into the .nfo; a changed title additionally renames the episode and all of its
sidecars, because an episode is identified by its SxxExx, not by its title.
USAGE
}

# ─── helpers ────────────────────────────────────────────────────────────────

# XML text escaping.  & MUST be first or it re-escapes the ampersands the later
# rules introduce.  In a sed replacement `\&` is a literal &, not the match.
esc() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# Characters that are legal in a lesson title but not in a filename, plus the
# runs of whitespace that collapsing them leaves behind.
sanitize() {
  printf '%s' "$1" \
    | sed -e 's#[/\\]# - #g' -e 's/:/ -/g' -e 's/[*?"<>|]//g' \
          -e 's/  */ /g' -e 's/^ *//' -e 's/ *$//'
}

manifest_for() {
  local slug=$1 mf="$MANIFESTS/$1.json" have
  if [ ! -f "$mf" ]; then
    have=$(find "$MANIFESTS" -maxdepth 1 -name '*.json' -printf '%f ' | sed 's/\.json//g')
    die "no manifest for '$slug' — have: $have"
  fi
  printf '%s' "$mf"
}

# Runtime in whole minutes, rounded to nearest.  Empty if ffprobe cannot read
# the file — a <runtime/> element is omitted rather than written as 0.
probe_minutes() {
  local d
  d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 -- "$1" 2>/dev/null || true)
  case "$d" in
    ''|N/A) return 0 ;;
  esac
  awk -v d="$d" 'BEGIN { if (d > 0) printf "%d", int((d + 30) / 60) }'
}

# True when any of the glob patterns passed in matched something.
#
# This exists because `compgen -G` DOES NOT WORK HERE, which is only visible on
# the deployed machine: writeShellApplication runs the script under
# `bashNonInteractive`, which nixpkgs builds with --disable-progcomp, so the
# compgen builtin is absent and every call fails with "command not found" —
# under `set -e`, inside an `if`, that reads as "no match" and the test silently
# always goes the same way.  A plain glob expansion is the equivalent that does
# exist.  Call it with the `*` OUTSIDE the quotes so the caller's glob expands:
#
#     glob_exists "$dir/$slug."*".srt"
#
# An unmatched glob expands to the literal pattern, which `-e` then rejects.
glob_exists() {
  local f
  for f in "$@"; do
    if [ -e "$f" ]; then return 0; fi
  done
  return 1
}

# True when a browser is still writing this lesson.  Chromium names a partial
# download `<name>.mp4.crdownload` and renames on completion, so the exact-name
# test in find_video already excludes partials — this exists so that "still
# downloading" is reported as such instead of being indistinguishable from
# "never downloaded", which is the state the user acts on differently.
has_partial() {
  local dir=$1 slug=$2 ext
  for ext in crdownload part partial; do
    if glob_exists "$dir/$slug."*".$ext"; then return 0; fi
  done
  return 1
}

# The video for a lesson, if a COMPLETE one is sitting in ingest.
find_video() {
  local dir=$1 slug=$2 ext
  for ext in mp4 mkv m4v webm; do
    if [ -f "$dir/$slug.$ext" ]; then printf '%s' "$dir/$slug.$ext"; return 0; fi
  done
  return 1
}

# The video of an ALREADY-IMPORTED episode, found by its SxxExx token rather
# than by the filename the current manifest title would produce.
#
# This is what makes correcting a title safe.  Keying on the title instead was
# measured doing the wrong thing: changing `.title` in the manifest changed the
# expected filename, the old file no longer matched, and the lesson was
# reported as "not downloaded" while the correctly-named video sat in the
# library under its old title.  The SxxExx token is the episode's identity;
# the title is just how it is spelled.
find_placed() {
  local dir=$1 sn=$2 ep=$3 f
  for f in "$dir"/*" - S${sn}E${ep} - "*; do
    if [ -f "$f" ]; then
      case "$f" in
        *.mp4|*.mkv|*.m4v|*.webm) printf '%s' "$f"; return 0 ;;
      esac
    fi
  done
  return 1
}

# ─── NFO writers ────────────────────────────────────────────────────────────
#
# <lockdata>true</lockdata> is what stops Jellyfin replacing any of this on a
# later scan.  It matters even with internet metadata disabled on the library,
# because an identification run triggered by hand from the UI ignores the
# library setting but honours the lock.

write_tvshow_nfo() {
  local dir=$1 mf=$2 title plot studio creator url
  title=$(jq -r '.show.title'            "$mf")
  plot=$( jq -r '.show.plot    // ""'    "$mf")
  studio=$(jq -r '.show.studio // ""'    "$mf")
  creator=$(jq -r '.show.creator // ""'  "$mf")
  url=$(jq -r '.show.url      // ""'     "$mf")

  {
    printf '<?xml version="1.0" encoding="utf-8" standalone="yes"?>\n'
    printf '<tvshow>\n'
    printf '  <title>%s</title>\n'     "$(esc "$title")"
    printf '  <sorttitle>%s</sorttitle>\n' "$(esc "$(jq -r '.show.sorttitle // .show.title' "$mf")")"
    if [ -n "$plot" ];    then printf '  <plot>%s</plot>\n'       "$(esc "$plot")"; fi
    if [ -n "$studio" ];  then printf '  <studio>%s</studio>\n'   "$(esc "$studio")"; fi
    jq -r '.show.genres // [] | .[]' "$mf" | while IFS= read -r g; do
      printf '  <genre>%s</genre>\n' "$(esc "$g")"
    done
    if [ -n "$creator" ]; then
      printf '  <director>%s</director>\n' "$(esc "$creator")"
      printf '  <actor>\n    <name>%s</name>\n    <role>Instructor</role>\n  </actor>\n' "$(esc "$creator")"
    fi
    if [ -n "$url" ]; then printf '  <website>%s</website>\n' "$(esc "$url")"; fi
    printf '  <lockdata>true</lockdata>\n'
    printf '</tvshow>\n'
  } > "$dir/tvshow.nfo"
}

write_season_nfo() {
  local dir=$1 season=$2 title=$3
  {
    printf '<?xml version="1.0" encoding="utf-8" standalone="yes"?>\n'
    printf '<season>\n'
    printf '  <title>%s</title>\n'               "$(esc "$title")"
    printf '  <seasonnumber>%s</seasonnumber>\n' "$season"
    printf '  <lockdata>true</lockdata>\n'
    printf '</season>\n'
  } > "$dir/season.nfo"
}

write_episode_nfo() {
  local nfo=$1 show=$2 season=$3 episode=$4 title=$5 plot=$6 video=$7 creator=$8 studio=$9
  local mins
  mins=$(probe_minutes "$video")
  {
    printf '<?xml version="1.0" encoding="utf-8" standalone="yes"?>\n'
    printf '<episodedetails>\n'
    printf '  <title>%s</title>\n'         "$(esc "$title")"
    printf '  <showtitle>%s</showtitle>\n' "$(esc "$show")"
    printf '  <season>%s</season>\n'       "$season"
    printf '  <episode>%s</episode>\n'     "$episode"
    if [ -n "$plot" ];    then printf '  <plot>%s</plot>\n'         "$(esc "$plot")"; fi
    if [ -n "$mins" ];    then printf '  <runtime>%s</runtime>\n'   "$mins"; fi
    if [ -n "$studio" ];  then printf '  <studio>%s</studio>\n'     "$(esc "$studio")"; fi
    if [ -n "$creator" ]; then printf '  <director>%s</director>\n' "$(esc "$creator")"; fi
    printf '  <lockdata>true</lockdata>\n'
    printf '</episodedetails>\n'
  } > "$nfo"
}

# ─── placement ──────────────────────────────────────────────────────────────

# Library convention, matched from containers/jellyfin.nix: directories 2770
# root:media, files 0640 root:media.  This is NOT left to the setgid bit — the
# ingest tree and the library are on the same dataset, so `mv` is a rename, and
# a rename carries the file's ORIGINAL ownership across regardless of setgid on
# the destination directory.  Files rsync'd in as root:root would otherwise
# stay root:root and Jellyfin (uid 964, group media) could not read them.
place_dir() {
  mkdir -p -- "$1"
  chown root:"$MEDIA_GID" -- "$1"
  chmod 2770               -- "$1"
}

place_file() {
  local src=$1 dst=$2
  mv -- "$src" "$dst"
  chown root:"$MEDIA_GID" -- "$dst"
  chmod 0640               -- "$dst"
}

# ─── commands ───────────────────────────────────────────────────────────────

cmd_list() {
  printf '%-18s  %-26s  %7s  %7s  %7s\n' COURSE SHOW LESSONS LIBRARY INGEST
  local mf slug show total ndir ning src
  for mf in "$MANIFESTS"/*.json; do
    slug=$(basename "$mf" .json)
    show=$(jq -r '.show.title' "$mf")
    total=$(jq '[.chapters[].lessons[]] | length' "$mf")
    ndir=0
    if [ -d "$LIB/$show" ]; then
      ndir=$(find "$LIB/$show" -type f \
               \( -name '*.mp4' -o -name '*.mkv' -o -name '*.m4v' -o -name '*.webm' \) \
               | wc -l)
    fi
    ning=0
    src="$INGEST/$slug"
    if [ -d "$src" ]; then
      ning=$(find "$src" -maxdepth 1 -type f \
               \( -name '*.mp4' -o -name '*.mkv' -o -name '*.m4v' -o -name '*.webm' \) \
               | wc -l)
    fi
    printf '%-18s  %-26s  %7s  %7s  %7s\n' "$slug" "$show" "$total" "$ndir" "$ning"
  done
}

cmd_status() {
  local course=$1 mf src show ci nchap season ctitle li nles slug title ep sn base dst state
  mf=$(manifest_for "$course")
  src="$INGEST/$course"
  show=$(jq -r '.show.title' "$mf")

  nchap=$(jq '.chapters | length' "$mf")
  for ((ci = 0; ci < nchap; ci++)); do
    nles=$(jq ".chapters[$ci].lessons | length" "$mf")
    if [ "$nles" -eq 0 ]; then continue; fi
    season=$(jq -r ".chapters[$ci].season" "$mf")
    ctitle=$(jq -r ".chapters[$ci].title"  "$mf")
    sn=$(printf '%02d' "$season")
    printf '\nSeason %s — %s\n' "$sn" "$ctitle"

    for ((li = 0; li < nles; li++)); do
      slug=$( jq -r ".chapters[$ci].lessons[$li].slug"  "$mf")
      title=$(jq -r ".chapters[$ci].lessons[$li].title" "$mf")
      ep=$(printf '%02d' $((li + 1)))
      base="$show - S${sn}E${ep} - $(sanitize "$title")"
      dst="$LIB/$show/Season $sn"

      state="not downloaded"
      if glob_exists "$dst/$base."*; then
        state="in library"
      elif [ ! -d "$src" ]; then
        :
      elif find_video "$src" "$slug" >/dev/null 2>&1; then
        state="waiting in ingest"
      elif has_partial "$src" "$slug"; then
        state="downloading"
      fi
      printf '  S%sE%s  %-18s  %-46s  %s\n' "$sn" "$ep" "$state" "$title" "$slug"
    done
  done
}

cmd_orphans() {
  local course=$1 mf src f known matched
  mf=$(manifest_for "$course")
  src="$INGEST/$course"
  if [ ! -d "$src" ]; then die "nothing ingested for '$course' ($src does not exist)"; fi

  # Every string the manifest can legitimately account for: a lesson slug (any
  # sidecar of which is `<slug>` followed by `.` or `-`), or a named resource
  # file, which does NOT start with a slug and has to be matched literally.
  mapfile -t known < <(jq -r '
    [ .chapters[].lessons[] | .slug ] + [ .chapters[].lessons[].resources // [] | .[] ] | .[]' "$mf")

  # Artwork is claimed by the tool rather than by the manifest, so it has to be
  # excluded here too or every import would report the poster as an orphan.
  known+=(poster folder backdrop fanart banner thumb logo clearlogo)

  local any=0
  while IFS= read -r f; do
    matched=0
    case "$f" in season*-poster.*) matched=1 ;; esac
    if [ "$matched" -eq 0 ]; then
      for k in "${known[@]}"; do
        case "$f" in
          "$k"|"$k".*|"$k"-*) matched=1; break ;;
        esac
      done
    fi
    if [ "$matched" -eq 0 ]; then printf '  %s\n' "$f"; any=1; fi
  done < <(find "$src" -maxdepth 1 -type f -printf '%f\n' | sort)

  if [ "$any" -eq 0 ]; then
    printf 'course-import: no orphans — every file in ingest is claimed by the manifest.\n'
  else
    printf '\ncourse-import: the files above belong to no manifest entry.\n'
    printf '  Usually this means a new chapter needs adding to %s.\n' "$MANIFESTS/$course.json"
  fi
}

cmd_import() {
  local dry=0
  while getopts 'n' opt; do
    case "$opt" in
      n) dry=1 ;;
      *) usage; exit 2 ;;
    esac
  done
  shift $((OPTIND - 1))
  local course=${1:-}
  if [ -z "$course" ]; then usage; exit 2; fi

  local mf src show creator studio showdir
  mf=$(manifest_for "$course")
  src="$INGEST/$course"
  if [ ! -d "$src" ]; then die "nothing ingested for '$course' ($src does not exist)"; fi

  show=$(   jq -r '.show.title'          "$mf")
  creator=$(jq -r '.show.creator // ""'  "$mf")
  studio=$( jq -r '.show.studio  // ""'  "$mf")
  showdir="$LIB/$show"

  local art aext f
  if [ "$dry" -eq 0 ]; then
    place_dir "$showdir"
    write_tvshow_nfo "$showdir" "$mf"

    # Show artwork.  This library has its image fetchers switched off, so the
    # only artwork it will ever have is what is put here by hand: save the
    # course cover image into the INGEST ROOT as poster.jpg (2:3) or
    # backdrop.jpg (16:9) and it is filed on the next import.  Deliberately not
    # committed next to the manifest — it is the vendor's artwork, and the repo
    # is not where that belongs.
    for art in poster folder backdrop fanart banner thumb logo clearlogo; do
      for aext in jpg jpeg png; do
        if [ -f "$src/$art.$aext" ]; then place_file "$src/$art.$aext" "$showdir/$art.$aext"; fi
      done
    done
    # Per-season posters live at the SHOW root as season01-poster.jpg, not
    # inside the season directory.
    for f in "$src"/season*-poster.*; do
      if [ -f "$f" ]; then place_file "$f" "$showdir/$(basename "$f")"; fi
    done
  fi

  local imported=0 refreshed=0 waiting=0 nchap ci nles season ctitle sn dst
  nchap=$(jq '.chapters | length' "$mf")

  for ((ci = 0; ci < nchap; ci++)); do
    nles=$(jq ".chapters[$ci].lessons | length" "$mf")
    if [ "$nles" -eq 0 ]; then continue; fi
    season=$(jq -r ".chapters[$ci].season" "$mf")
    ctitle=$(jq -r ".chapters[$ci].title"  "$mf")
    sn=$(printf '%02d' "$season")
    dst="$showdir/Season $sn"

    # The season directory is created only when at least one of its lessons is
    # actually present, so a manifest listing all eight chapters does not leave
    # seven empty seasons in Jellyfin.
    local seasonmade=0

    local li slug title plot ep base video vext dstvid n res placedvid placedbase
    for ((li = 0; li < nles; li++)); do
      slug=$( jq -r ".chapters[$ci].lessons[$li].slug"       "$mf")
      title=$(jq -r ".chapters[$ci].lessons[$li].title"      "$mf")
      plot=$( jq -r ".chapters[$ci].lessons[$li].plot // \"\"" "$mf")
      ep=$(printf '%02d' $((li + 1)))
      base="$show - S${sn}E${ep} - $(sanitize "$title")"

      # Already in the library?  Then the only work is refreshing the NFO — and,
      # if the manifest title has since been corrected, renaming the episode and
      # every sidecar that shares its basename.  The glob `"$placedbase"*` is
      # deliberately not `"$placedbase".*`: it has to catch the reference images,
      # which are named `<base> - level-1-pear-1.jpg` and so are not separated
      # from the base by a dot.  It cannot over-match a neighbouring episode,
      # because the base it expands from contains that episode's own SxxExx.
      dstvid=""
      if placedvid=$(find_placed "$dst" "$sn" "$ep"); then
        placedbase=${placedvid%.*}
        if [ "$placedbase" = "$dst/$base" ]; then
          dstvid=$placedvid
        elif [ "$dry" -eq 1 ]; then
          printf '  would rename  S%sE%s  -> %s\n' "$sn" "$ep" "$base"
          dstvid=$placedvid
        else
          for f in "$placedbase"*; do
            if [ -f "$f" ]; then mv -- "$f" "$dst/$base${f#"$placedbase"}"; fi
          done
          printf '  renamed   S%sE%s  %s\n' "$sn" "$ep" "$title"
          dstvid="$dst/$base.${placedvid##*.}"
        fi
      fi

      if [ -z "$dstvid" ]; then
        if ! video=$(find_video "$src" "$slug"); then
          if has_partial "$src" "$slug"; then
            warn "S${sn}E${ep} $slug: download still in progress, skipped"
          fi
          waiting=$((waiting + 1))
          continue
        fi
        vext=${video##*.}
        if [ "$dry" -eq 1 ]; then
          printf '  would import  S%sE%s  %s\n' "$sn" "$ep" "$base.$vext"
          imported=$((imported + 1))
          continue
        fi
        if [ "$seasonmade" -eq 0 ]; then
          place_dir "$dst"; write_season_nfo "$dst" "$season" "$ctitle"; seasonmade=1
        fi
        place_file "$video" "$dst/$base.$vext"
        dstvid="$dst/$base.$vext"
        imported=$((imported + 1))
        printf '  imported  S%sE%s  %s\n' "$sn" "$ep" "$title"

        # Subtitles.  Jellyfin reads the language from the `.en.` component, so
        # the track shows as English rather than "Undefined".
        if [ -f "$src/$slug-captions-english.srt" ]; then
          place_file "$src/$slug-captions-english.srt" "$dst/$base.en.srt"
        fi

        # Transcript.  Three different suffixes are in use across one chapter
        # (-transcript-, -transcripts-, -transcription-), hence the glob.
        for f in "$src/$slug"-transcript*.txt "$src/$slug"-transcription*.txt; do
          if [ -f "$f" ]; then place_file "$f" "$dst/$base.txt"; break; fi
        done

        # Reference images named by the manifest.  They keep their original
        # name as a suffix: `<base> - level-1-pear-1.jpg` matches none of
        # Jellyfin's image suffixes (-poster, -fanart, -thumb, -banner, -logo,
        # -clearart, -disc), so none of them is mistaken for episode artwork.
        n=$(jq ".chapters[$ci].lessons[$li].resources // [] | length" "$mf")
        for ((r = 0; r < n; r++)); do
          res=$(jq -r ".chapters[$ci].lessons[$li].resources[$r]" "$mf")
          if [ -f "$src/$res" ]; then place_file "$src/$res" "$dst/$base - $res"; fi
        done
      else
        if [ "$dry" -eq 1 ]; then continue; fi
        if [ "$seasonmade" -eq 0 ]; then
          place_dir "$dst"; write_season_nfo "$dst" "$season" "$ctitle"; seasonmade=1
        fi
        refreshed=$((refreshed + 1))
      fi

      if [ "$dry" -eq 0 ]; then
        write_episode_nfo "$dst/$base.nfo" "$show" "$season" "$((li + 1))" \
                          "$title" "$plot" "$dstvid" "$creator" "$studio"
        chown root:"$MEDIA_GID" -- "$dst/$base.nfo"
        chmod 0640               -- "$dst/$base.nfo"
      fi
    done
  done

  printf '\ncourse-import: %s imported, %s metadata refreshed, %s lessons not downloaded yet.\n' \
         "$imported" "$refreshed" "$waiting"
  if [ "$dry" -eq 0 ]; then
    printf 'Run: course-import orphans %s   — to see anything the manifest does not claim.\n' "$course"
    # The redundant-copy warning.  This is NOT a corner case: the documented
    # workflow is to rsync the whole download folder, and the laptop still holds
    # every lesson it ever downloaded, so a second batch re-uploads the entire
    # first batch.  Those copies are claimed by the manifest, so `orphans` stays
    # silent about them, and `import` cannot move them because the destination
    # already exists — they just sit there.  Measured: 7.8 GB after one re-run.
    prune_report "$course"
  fi
}

# ─── prune ──────────────────────────────────────────────────────────────────
#
# Files in ingest whose lesson is ALREADY in the library.  Reported by `import`
# and deleted only by an explicit `prune`, never automatically: this is the one
# destructive thing the tool does, and a size mismatch means the ingest copy is
# not the file that was imported — a re-download, a different cut — which is a
# question for a human, not something to silently delete.
#
# Emits one TAB-separated "ingest-path<TAB>library-path<TAB>verdict" line per
# candidate on stdout; callers decide what to do with it.
prune_candidates() {
  local course=$1 mf src show showdir
  mf=$(manifest_for "$course")
  src="$INGEST/$course"
  if [ ! -d "$src" ]; then return 0; fi
  show=$(jq -r '.show.title' "$mf")
  showdir="$LIB/$show"

  local nchap ci nles season sn li slug title ep base dst
  local vext f libf isz lsz n r res
  nchap=$(jq '.chapters | length' "$mf")
  for ((ci = 0; ci < nchap; ci++)); do
    nles=$(jq ".chapters[$ci].lessons | length" "$mf")
    if [ "$nles" -eq 0 ]; then continue; fi
    season=$(jq -r ".chapters[$ci].season" "$mf")
    sn=$(printf '%02d' "$season")
    dst="$showdir/Season $sn"
    for ((li = 0; li < nles; li++)); do
      slug=$( jq -r ".chapters[$ci].lessons[$li].slug"  "$mf")
      title=$(jq -r ".chapters[$ci].lessons[$li].title" "$mf")
      ep=$(printf '%02d' $((li + 1)))
      base="$dst/$(printf '%s - S%sE%s - %s' "$show" "$sn" "$ep" "$(sanitize "$title")")"

      # Only a lesson that is actually in the library can have a redundant copy.
      libf=""
      for vext in mp4 mkv m4v webm; do
        if [ -f "$base.$vext" ]; then libf="$base.$vext"; break; fi
      done
      if [ -z "$libf" ]; then continue; fi

      # video
      for vext in mp4 mkv m4v webm; do
        f="$src/$slug.$vext"
        if [ -f "$f" ]; then emit_candidate "$f" "$base.$vext"; fi
      done
      # subtitles
      f="$src/$slug-captions-english.srt"
      if [ -f "$f" ]; then emit_candidate "$f" "$base.en.srt"; fi
      # Transcript (the three suffix spellings).  `break` is load-bearing and
      # not just an optimisation: `-transcript*.txt` ALSO matches
      # `-transcription-english.txt`, so without it that one spelling is emitted
      # by both globs and gets counted — and its bytes totalled — twice.
      # Measured: 35 candidates reported for 34 files on ernst.
      for f in "$src/$slug"-transcript*.txt "$src/$slug"-transcription*.txt; do
        if [ -f "$f" ]; then emit_candidate "$f" "$base.txt"; break; fi
      done
      # named resources
      n=$(jq ".chapters[$ci].lessons[$li].resources // [] | length" "$mf")
      for ((r = 0; r < n; r++)); do
        res=$(jq -r ".chapters[$ci].lessons[$li].resources[$r]" "$mf")
        f="$src/$res"
        if [ -f "$f" ]; then emit_candidate "$f" "$base - $res"; fi
      done
    done
  done
}

emit_candidate() {
  local ing=$1 lib=$2 isz lsz
  if [ ! -f "$lib" ]; then return 0; fi
  isz=$(stat -c %s -- "$ing")
  lsz=$(stat -c %s -- "$lib")
  if [ "$isz" = "$lsz" ]; then
    printf '%s\t%s\tsame\n' "$ing" "$lib"
  else
    printf '%s\t%s\tDIFFERS\n' "$ing" "$lib"
  fi
}

prune_report() {
  local course=$1 n bytes differs
  local out
  out=$(prune_candidates "$course")
  if [ -z "$out" ]; then return 0; fi
  n=$(printf '%s\n' "$out" | grep -c 'same$' || true)
  differs=$(printf '%s\n' "$out" | grep -c 'DIFFERS$' || true)
  if [ "$n" -gt 0 ]; then
    bytes=$(printf '%s\n' "$out" | awk -F'\t' '$3=="same"{print $1}' \
            | tr '\n' '\0' | xargs -0 stat -c %s 2>/dev/null | awk '{s+=$1} END{print s+0}')
    printf 'Note: %s file(s) in ingest (%s) are already in the library.\n' \
           "$n" "$(numfmt --to=iec --suffix=B "$bytes" 2>/dev/null || echo "$bytes bytes")"
    printf '      Run: course-import prune %s   — to delete the redundant copies.\n' "$course"
  fi
  if [ "$differs" -gt 0 ]; then
    printf 'Warning: %s file(s) in ingest share a lesson with the library but DIFFER in size.\n' "$differs"
    printf '         prune will not touch them; inspect them by hand.\n'
  fi
}

cmd_prune() {
  local dry=0
  while getopts 'n' opt; do
    case "$opt" in
      n) dry=1 ;;
      *) usage; exit 2 ;;
    esac
  done
  shift $((OPTIND - 1))
  local course=${1:-}
  if [ -z "$course" ]; then usage; exit 2; fi

  local out n=0 ing lib verdict
  out=$(prune_candidates "$course")
  if [ -z "$out" ]; then
    printf 'course-import: nothing to prune — no ingest file duplicates a library file.\n'
    return 0
  fi

  while IFS=$'\t' read -r ing lib verdict; do
    case "$verdict" in
      same)
        if [ "$dry" -eq 1 ]; then
          printf '  would delete  %s\n' "$(basename "$ing")"
        else
          rm -f -- "$ing"
          printf '  deleted  %s\n' "$(basename "$ing")"
        fi
        n=$((n + 1))
        ;;
      DIFFERS)
        warn "$(basename "$ing"): size differs from the library copy — KEPT"
        ;;
    esac
  done <<< "$out"

  if [ "$dry" -eq 1 ]; then
    printf '\ncourse-import: %s file(s) would be deleted.\n' "$n"
  else
    printf '\ncourse-import: %s redundant file(s) deleted from ingest.\n' "$n"
  fi
}

# ─── dispatch ───────────────────────────────────────────────────────────────

cmd=${1:-}
if [ -n "$cmd" ]; then shift; fi
case "$cmd" in
  list)    cmd_list ;;
  status)  if [ $# -lt 1 ]; then usage; exit 2; fi; cmd_status "$1" ;;
  orphans) if [ $# -lt 1 ]; then usage; exit 2; fi; cmd_orphans "$1" ;;
  import)  cmd_import "$@" ;;
  prune)   cmd_prune "$@" ;;
  ''|-h|--help|help) usage ;;
  *)       die "unknown command '$cmd' (try --help)" ;;
esac
