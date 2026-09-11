# machines/ernst/photo-import.sh
#
# Body of the `photo-import` command.  NOT standalone: containers/immich.nix
# prepends the deployment constants (SERVER, EXTENSIONS, BAN, SRC_LGO, SRC_SGO,
# LOGDIR) and wraps this in writeShellApplication, which supplies the shebang
# and `set -euo pipefail` and runs shellcheck at build time.  Keeping those
# constants on the Nix side is the point — the source lists are a REVIEWED
# DECISION about whose photographs go where, and they belong in a file that
# goes through a pull request, not in a shell glob.
#
# Under `set -e`, note that `cond && action` at statement level EXITS when cond
# is false.  Every such test below is written as a full `if`.
#
# ── THE API KEY IS NOT A CLAN VAR, AND THAT IS DELIBERATE ───────────────────
#
# It comes from $IMMICH_API_KEY in the environment of whoever runs this, and
# there are two reasons rather than one:
#
#   1. ORDERING.  An Immich API key is minted in the web UI by an account that
#      cannot exist before the server is deployed and running.  A clan var
#      prompted at deploy time would be answered blank, and a blank clan-vars
#      prompt is not an "optional credential": it stores nothing, `.path`
#      becomes /no-such-path, and every later deploy re-prompts.  That took
#      RomM down on 2026-09-07.
#   2. SCOPE.  The key IS the account — immich-go uploads into whichever user
#      minted it.  So this tool needs a DIFFERENT key per run, and a stored
#      one would have to be a stored set.  Exporting the right key for the run
#      makes the account explicit at the moment it matters.
#
# The laptop uploader is the opposite case and gets the opposite answer: it is
# an unattended timer, so its key IS a clan var.  See
# modules/desktop/immich-upload-hm.nix.

die() { printf 'photo-import: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
photo-import — import the retired Arch server's photographs into Immich.

  photo-import survey [DIR...]   what is under each tree, by kind and size
  photo-import check             prove the server answers and the key is valid
  photo-import lgo  [-n] [-c]    import lgo's trees
  photo-import sgo  [-n] [-c]    import Sarinah's trees

options
  -n   dry run — immich-go reports what it would upload and uploads nothing
  -c   continue past errors instead of stopping at the first one

THE API KEY SELECTS THE ACCOUNT.  Export the key of the account you are
importing INTO, minted in Immich under Account Settings -> API Keys:

    export IMMICH_API_KEY=...
    photo-import lgo -n        # read the summary before doing it for real
    photo-import lgo

Every asset is tagged `import/server001`, so a bad run can be found and
removed in the UI as a group rather than hunted for by date.

Re-running is safe: Immich deduplicates on content hash, so an interrupted
import is resumed by running the same command again, not restarted.
USAGE
}

# Build an array from one of the newline-separated Nix constants, into the
# caller-visible `_out`.  A plain word-split would break on `Käthes Geb` and on
# every other path with a space in it, of which the source trees have several.
#
# It takes the VALUE rather than the variable's name.  Indirect expansion
# (`${!_var}`) reads better at the call site and makes shellcheck report every
# constant as unused — SC2034, which writeShellApplication fails the build on,
# and rightly: "assigned and never read" is exactly what a typo'd constant
# looks like too.
lines_to_array() {
  local _line
  _out=()
  while IFS= read -r _line; do
    if [ -n "$_line" ]; then
      _out+=("$_line")
    fi
  done <<<"$1"
}

need_key() {
  if [ -z "${IMMICH_API_KEY:-}" ]; then
    die "IMMICH_API_KEY is not set.  Mint one in Immich (Account Settings ->
  API Keys) for the account you are importing INTO, then:

      export IMMICH_API_KEY=...

  The key selects the account.  lgo's key imports into lgo's library and
  sgo's into Sarinah's; there is no flag that overrides it."
  fi
}

##############################################################################
# survey — what is actually in these trees.
#
# The reason this subcommand exists: /srv/unsorted is a decade-old 26-directory
# tree, and "import the photos" is a triage decision, not a script.  The source
# lists in containers/immich.nix are deliberately CONSERVATIVE — they name the
# unambiguously photographic directories and leave the rest out.  This is how
# you decide whether to add one.
##############################################################################
cmd_survey() {
  local -a dirs
  if [ "$#" -gt 0 ]; then
    dirs=("$@")
  else
    lines_to_array "$SRC_LGO"; dirs=("${_out[@]}")
    lines_to_array "$SRC_SGO"; dirs+=("${_out[@]}")
  fi

  printf '%-52s %8s %8s %8s %10s\n' DIRECTORY IMAGES VIDEOS OTHER SIZE
  local d img vid oth size
  for d in "${dirs[@]}"; do
    if [ ! -d "$d" ]; then
      printf '%-52s %8s\n' "$d" MISSING
      continue
    fi
    img=$(find "$d" -type f \
      \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \
      -o -iname '*.heic' -o -iname '*.heif' -o -iname '*.dng' \
      -o -iname '*.tif' -o -iname '*.tiff' \) -printf . | wc -c)
    vid=$(find "$d" -type f \
      \( -iname '*.mp4' -o -iname '*.mov' -o -iname '*.m4v' \
      -o -iname '*.3gp' -o -iname '*.avi' -o -iname '*.mts' \) -printf . | wc -c)
    oth=$(find "$d" -type f -printf . | wc -c)
    oth=$((oth - img - vid))
    size=$(du -sh "$d" | cut -f1)
    printf '%-52s %8s %8s %8s %10s\n' "$d" "$img" "$vid" "$oth" "$size"
  done

  cat <<'NOTE'

OTHER is what the extension filter will refuse to upload even if the directory
is listed as a source.  A large OTHER count is not a problem — it is the filter
doing its job — but it IS a sign the directory holds something besides
photographs, which is worth knowing before adding it to a source list.
NOTE
}

##############################################################################
# check — prove the chain before moving 150 GB through it.
##############################################################################
cmd_check() {
  need_key
  local out

  printf 'server:  %s\n' "$SERVER"
  if ! out=$(curl -fsS -m 10 "$SERVER/api/server/ping"); then
    die "cannot reach $SERVER.

  This goes through Traefik, not straight to the container — check the
  Technitium record for the hostname first, then the router."
  fi
  printf 'ping:    %s\n' "$out"

  if ! out=$(curl -fsS -m 10 -H "x-api-key: $IMMICH_API_KEY" "$SERVER/api/users/me"); then
    die "the server answered but rejected the key.  A 401 here means
  IMMICH_API_KEY is wrong or was revoked; mint a fresh one in the UI."
  fi
  printf 'account: %s\n' "$out"
  printf '\nTHE ACCOUNT ABOVE IS WHERE THIS IMPORT WILL LAND.  Read it before running.\n'
}

##############################################################################
# The import itself.
##############################################################################
cmd_import() {
  local account=$1; shift
  local dry=0 onerr="stop" opt
  while getopts 'nc' opt; do
    case "$opt" in
      n) dry=1 ;;
      c) onerr="continue" ;;
      *) usage; exit 1 ;;
    esac
  done

  need_key

  local -a sources
  case "$account" in
    lgo) lines_to_array "$SRC_LGO"; sources=("${_out[@]}") ;;
    sgo) lines_to_array "$SRC_SGO"; sources=("${_out[@]}") ;;
    *)   die "unknown account '$account' (expected lgo or sgo)" ;;
  esac

  local d
  for d in "${sources[@]}"; do
    if [ ! -d "$d" ]; then
      die "source directory does not exist: $d
  The source lists live in machines/ernst/containers/immich.nix.  If a tree was
  renamed during triage, fix it there rather than here — this tool is
  regenerated from that file."
    fi
  done

  local -a args=(
    upload from-folder
    --server "$SERVER"
    --api-key "$IMMICH_API_KEY"
    --no-ui

    # THE SECOND FILTER, and the one that does not depend on the source list
    # being right.  Even if a directory holding PDFs, spreadsheets or a job
    # application is listed by mistake, nothing but an image or a video is
    # uploaded.  Sarinah's tree interleaves personal documents with
    # photographs throughout, so this is not a hypothetical.
    --include-extensions "$EXTENSIONS"

    # Albums from the full relative path rather than the leaf, so an album
    # reads `Bilder / 2019` instead of a bare `2019` that collides with every
    # other year directory in the corpus.
    --folder-as-album PATH

    # Provenance, and an undo.  Everything this tool uploads carries one tag,
    # so a run that went wrong is a tag to select and delete in the UI rather
    # than a date range to reconstruct.
    --tag import/server001

    # The DNGs are in scope (lgo's decision: the ~6.1k existing ones are the
    # only copy of those shots) but they are WORKING FILES next to their
    # exports.  Stacking with the JPEG on top means the library shows the
    # finished image and keeps the raw underneath, instead of showing every
    # photograph twice.  Same treatment for the phones' HEIC+JPG pairs.
    --manage-raw-jpeg StackCoverJPG
    --manage-heic-jpeg StackCoverJPG

    --on-errors "$onerr"
  )

  local p
  lines_to_array "$BAN"
  for p in "${_out[@]}"; do
    args+=(--ban-file "$p")
  done

  if [ "$dry" = 1 ]; then
    args+=(--dry-run)
  fi

  mkdir -p "$LOGDIR"
  local stamp log
  stamp=$(date +%Y%m%d-%H%M%S)
  log="$LOGDIR/${account}-${stamp}.log"
  args+=(--log-file "$log")

  printf 'account:  %s\n' "$account"
  printf 'server:   %s\n' "$SERVER"
  if [ "$dry" = 1 ]; then printf 'dry run:  yes\n'; else printf 'dry run:  NO\n'; fi
  printf 'log:      %s\n' "$log"
  printf 'sources:\n'
  for d in "${sources[@]}"; do printf '  %s\n' "$d"; done
  printf '\n'

  # Run from an empty directory.  immich-go reads ./immich-go.yaml if one
  # happens to be in the working directory, which would silently override
  # flags set above depending on where an operator happened to be standing.
  local work
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  cd "$work"

  immich-go "${args[@]}" "${sources[@]}"
}

##############################################################################

if [ "$#" -eq 0 ]; then
  usage
  exit 1
fi

cmd=$1; shift
case "$cmd" in
  survey)      cmd_survey "$@" ;;
  check)       cmd_check "$@" ;;
  lgo|sgo)     cmd_import "$cmd" "$@" ;;
  -h|--help)   usage ;;
  *)           usage; exit 1 ;;
esac
