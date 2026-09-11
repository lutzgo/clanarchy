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

# ── THE SCRATCH DIRECTORY, AND WHY IT IS NOT `local` ────────────────────────
#
# immich-go reads ./immich-go.yaml if one happens to be in the working
# directory, which would silently override the flags assembled below depending
# on where an operator happened to be standing.  Running from a fresh empty
# directory makes that impossible rather than unlikely.
#
# IT IS A GLOBAL DELIBERATELY.  The first version declared it `local` inside
# cmd_import, with `trap 'rm -rf "$work"' EXIT` beside it.  The trap fires when
# the SCRIPT exits — by which time cmd_import has returned and a local is out
# of scope — so under `set -u` the cleanup itself failed:
#
#     photo-import: line 1: work: unbound variable
#
# Measured 2026-09-11, printed as the last line of a completely successful dry
# run of 18,801 assets.  Harmless, and exactly the kind of harmless that gets
# read as "the import broke at the end".
_workdir=""
cleanup_workdir() { if [ -n "$_workdir" ]; then rm -rf "$_workdir"; fi; }
trap cleanup_workdir EXIT

usage() {
  cat <<'USAGE'
photo-import — import the retired Arch server's photographs into Immich.

  photo-import survey [DIR...]   what is under each tree, by kind and size
  photo-import check             prove the server answers and the key is valid
  photo-import lgo  [-n] [-c] [-j N]    import lgo's trees
  photo-import sgo  [-n] [-c] [-j N]    import Sarinah's trees

options
  -n     dry run — immich-go reports what it would upload and uploads nothing
  -c     continue past errors instead of stopping at the first one
  -j N   concurrent uploads (default 8; immich-go's own default of 32 broke
         the server mid-import on 2026-09-11 — see the comment in the source)

A DRY RUN DOES NOT PROVE A REAL RUN WILL WORK. It never contacts the album or
upload endpoints, so every server-side failure mode — album creation, capacity,
connection resets — is invisible to it. The first real run found 136 errors
after a dry run that reported zero.

Re-running after a failure is the designed recovery, not a workaround: Immich
deduplicates on content hash, so already-uploaded assets are skipped.

THE API KEY SELECTS THE ACCOUNT.  Export the key of the account you are
importing INTO, minted in Immich under Account Settings -> API Keys:

    export IMMICH_API_KEY=...
    photo-import lgo -n        # read the summary before doing it for real
    photo-import lgo

Optionally also export IMMICH_ADMIN_API_KEY (the `admin` account's key, which
is NOT lgo's or sgo's).  It only lets immich-go pause Immich's background
workers during the upload, which is faster; without it they keep running.
It never changes WHERE the photos land — IMMICH_API_KEY decides that.

Every asset is tagged `import/server001`, so a bad run can be found and
removed in the UI as a group rather than hunted for by date.
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
  local dry=0 onerr="stop" jobs=8 opt
  while getopts 'ncj:' opt; do
    case "$opt" in
      n) dry=1 ;;
      c) onerr="continue" ;;
      j) jobs="$OPTARG" ;;
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
    --no-ui

    # NO --api-key HERE.  It goes in a 0600 config file written below, and
    # the reason is not style — see "THE KEYS DO NOT GO IN argv".

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

    # ── CONCURRENCY, AND WHY THE DEFAULT IS 8 AND NOT immich-go's 32 ────────
    #
    # MEASURED ON ERNST 2026-09-11, on the first real run. At immich-go's own
    # default the import uploaded 12,286 of 15,209 assets and then DIED:
    #
    #   14:44-14:50   1-4 errors/min   (album creates only)
    #   14:51            10 errors
    #   14:52             9
    #   14:53           100            <- "server error", "context canceled"
    #   14:54         AssetUpload ... write: connection reset by peer
    #
    # The server degraded under sustained load and then the connection was
    # reset mid-body. Not a bad file, not a timeout (Traefik has no
    # respondingTimeouts set), and NOT CrowdSec — its decision list held only
    # external scanners, no entry for this host. Checked, because a
    # self-inflicted ban was the obvious first suspect.
    #
    # Note what it is NOT: the background queues WERE paused (that is why
    # 19,000 metadataExtraction jobs had piled up waiting by the end). The load
    # came from the ingest path itself — 32 concurrent multipart uploads plus
    # the Postgres writes and storage-template moves each one triggers.
    #
    # 8 is a starting point chosen to be obviously gentler, not a measured
    # optimum. `-j` exists so the next person can find one without editing Nix.
    --concurrent-tasks "$jobs"
  )

  # ── JOB PAUSING IS OFF UNLESS AN ADMIN KEY IS SUPPLIED ────────────────────
  #
  # immich-go pauses Immich's background workers during an upload by default,
  # and THAT IS AN ADMIN OPERATION.  This deployment has a dedicated `admin`
  # account that is nobody's daily login, so `lgo` and `sgo` are ordinary
  # users and their keys cannot do it.  Left at the default, the binary stops
  # with:
  #
  #   can't pause immich background jobs: pass an administrator key with the
  #   flag --admin-api-key or disable the jobs pausing with the flag
  #   --pause-immich-jobs=FALSE
  #
  # (read out of the immich-go 0.31.0 binary, 2026-09-11 — before the first
  # real run rather than after it).
  #
  # So the default here is OFF, because the tool must work with exactly the
  # credential the account being imported into actually owns.  What that costs
  # is real but bounded: thumbnail generation and CPU-only ML run concurrently
  # with the ingest instead of being deferred, so both are slower and the
  # machine is busier.  For a one-off migration that is a fine trade.
  #
  # To get the faster behaviour, export an ADMIN key as well:
  #
  #     export IMMICH_ADMIN_API_KEY=...
  #
  # It is separate from IMMICH_API_KEY on purpose: that one still selects the
  # destination library, and conflating them would silently import into the
  # admin's library instead.
  if [ -n "${IMMICH_ADMIN_API_KEY:-}" ]; then
    args+=(--pause-immich-jobs=TRUE)
    jobs_note="paused via admin key"
  else
    args+=(--pause-immich-jobs=FALSE)
    jobs_note="left running (no IMMICH_ADMIN_API_KEY)"
  fi

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
  printf 'bg jobs:  %s\n' "$jobs_note"
  printf 'sources:\n'
  for d in "${sources[@]}"; do printf '  %s\n' "$d"; done
  printf '\n'

  # Run from an empty directory — see `_workdir` at the top of this file for
  # why it is a global and what the `local` version cost.
  _workdir=$(mktemp -d)
  cd "$_workdir"

  ##########################################################################
  # ── THE KEYS DO NOT GO IN argv ─────────────────────────────────────────
  #
  # The first version of this tool passed `--api-key` and `--admin-api-key`
  # on the command line. That puts both credentials in /proc/<pid>/cmdline,
  # WHICH IS WORLD-READABLE. Found by running `pgrep -a immich-go` during a
  # live import on 2026-09-11 — both keys printed in full, no privilege
  # needed.
  #
  # THAT IS NOT A THEORETICAL EXPOSURE ON THIS MACHINE. ernst carries `go`,
  # the couch account that AUTOLOGINS on the television without a password
  # (see modules/roles/htpc.nix). Any process that account can run could
  # read the admin key out of the process table and then do anything the
  # admin can — including to Sarinah's library, which she has no other way
  # to grant or revoke.
  #
  # It also defeats the reason the keys are kept in root-only files at all:
  # careful storage means nothing if the consumer broadcasts them.
  #
  # immich-go has no environment-variable binding for these (immich-cli
  # does; this is a different program). What it does have is `--config`.
  # So the credentials go in a 0600 file inside this private mktemp
  # directory, which the EXIT trap removes.
  #
  # ── THE SHAPE BELOW IS GENERATED, NOT INFERRED, AND THE FIRST ATTEMPT
  #    WAS INFERRED AND WRONG ────────────────────────────────────────────
  #
  # The first version wrote flat `api_key:` / `admin_api_key:` keys, taken
  # from mapstructure tags found by grepping the binary. immich-go ignored
  # the file completely and died with
  #
  #     missing the parameter --api-key and/or --admin-api-key
  #
  # …which, because this tool had just been "fixed", meant an import that
  # ran zero files while looking like it had run. The real layout is
  # NESTED under `upload:` and HYPHENATED, and the way to learn it is to
  # ask the program rather than to read its strings:
  #
  #     immich-go upload from-folder --api-key X --save-config … .
  #     cat ./immich-go.yaml
  #
  # `upload.from-folder.*` also exists for subcommand options; only the
  # credentials are set here, so every other flag stays on the command line
  # where it is visible in the log line this tool prints.
  #
  # `umask 077` before the redirect, not chmod after: a chmod leaves a
  # window in which the file exists world-readable, which is the same class
  # of mistake as putting the key in argv.
  ##########################################################################
  local cfg="$_workdir/immich-go.yaml"
  ( umask 077
    printf 'upload:\n' > "$cfg"
    printf '    api-key: %s\n' "$IMMICH_API_KEY" >> "$cfg"
    if [ -n "${IMMICH_ADMIN_API_KEY:-}" ]; then
      printf '    admin-api-key: %s\n' "$IMMICH_ADMIN_API_KEY" >> "$cfg"
    fi
  )

  immich-go --config "$cfg" "${args[@]}" "${sources[@]}"
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
