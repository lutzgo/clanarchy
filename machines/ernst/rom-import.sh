# machines/ernst/rom-import.sh
#
# Body of the `rom-import` command.  NOT standalone: containers/romm.nix
# prepends the deployment constants (LIB, ROMM_UID, ROMM_GID, QBT*, CATS) and
# wraps this in writeShellApplication, which supplies the shebang and
# `set -euo pipefail` and runs shellcheck at build time.  Keeping those
# constants on the Nix side is the point — they are the same bindings the
# container is built from, so this tool cannot drift from the deployment.
#
# Under `set -e`, note that `cond && action` at statement level EXITS when cond
# is false.  Every such test below is written as a full `if`.

# Never copied into the library.  /srv/roms is exec=off so a stray .exe could
# not run from there anyway, but these are noise in RomM's scan and pointless
# churn for Syncthing.  Archives are NOT in this list — for some systems a .zip
# is the ROM — so nested archives get a warning instead (see cmd_copy).
JUNK='exe|dll|bat|cmd|com|msi|scr|lnk|url|html|htm|ico'

# Staging sits on the SAME dataset as the library, so the copy out of it is a
# rename-speed local copy, and at the ROOT of /srv/roms — outside roms/ and
# bios/, which are the two Syncthing folders and RomM's scan targets.  A
# half-extracted 8 GB pack must reach neither birte nor the scanner.
STAGING="${LIB}/.staging"

die() { printf 'rom-import: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'USAGE'
rom-import — copy finished downloads into the RomM library.

  rom-import list [-c CATS]            what qBittorrent has, in the ROM categories
  rom-import inspect SRC               what is inside a folder or archive
  rom-import copy [OPTS] PLATFORM SRC  copy/extract it into the library
  rom-import unpack SRC                extract an archive to staging, print the path
  rom-import clean                     delete the staging area
  rom-import verify [PLATFORM]         file counts, zero-byte files, gamelist.xml

copy options
  -e EXT[,EXT...]  keep only these extensions (default: all but exe/dll/…)
  -i GLOB          for archives: extract only this inner path (e.g. '*/Roms/*')
  -f               flatten — drop the archive's directory structure
  -b               destination is bios/PLATFORM, not roms/PLATFORM
  -n               dry run: show what would be copied, copy nothing

PLATFORM is the on-disk folder name, and ES-DE on birte reads it LITERALLY —
use ES-DE's name (nes, snes, gba, n64, genesis, mastersystem, atari2600, n3ds,
switch, …), never RomM's display name.  If RomM then shows the platform as
"Unknown", map it on RomM's side in /srv/state/romm/config/config.yml under
`system.platforms:` — never by renaming the directory.

Sources are COPIED, never moved: qBittorrent goes on seeding what it downloaded.

ONE ARCHIVE, SEVERAL CONSOLES?  Console-set packs routinely bundle two or three
systems — the Mega EverDrive pack carries Genesis, 32X, Master System and
SG-1000 in one file.  Extract it ONCE and copy out per platform; the file
extension is what separates them:

  d=$(rom-import unpack '…/Mega EverDrive Pack v6.2.7z')
  rom-import copy -e md      genesis      "$d"
  rom-import copy -e 32x     sega32x      "$d"
  rom-import copy -e sms     mastersystem "$d"
  rom-import clean
USAGE
}

need_lib() { [ -d "$LIB" ] || die "$LIB not found — run this on ernst"; }

# ── qBittorrent ─────────────────────────────────────────────────────────────
qbt_login() {
  [ -r "$QBT_PWFILE" ] || die "cannot read $QBT_PWFILE — run as root"
  CJ=$(mktemp)
  trap 'rm -f "$CJ"' EXIT
  curl -sf -c "$CJ" \
    --data-urlencode "username=${QBT_USER}" \
    --data-urlencode "password=$(cat "$QBT_PWFILE")" \
    "${QBT}/api/v2/auth/login" >/dev/null || die "qBittorrent login failed"
}

cmd_list() {
  local OPTIND=1 o
  while getopts 'c:' o; do
    case $o in c) CATS=$OPTARG ;; *) usage; exit 1 ;; esac
  done
  qbt_login
  curl -sf -b "$CJ" "${QBT}/api/v2/torrents/info" \
    | jq -r --arg cats "$CATS" '
        ($cats | split(",")) as $c
        | map(select(.category as $x | $c | index($x)))
        | sort_by(.progress, .name) | reverse
        | .[]
        | [ (if .progress == 1 then "DONE" else "\(.progress*100|floor)%" end)
          , ((.size/1073741824*10|round/10|tostring) + "G")
          , .category
          , .content_path ]
        | @tsv' \
    | column -t -s"$(printf '\t')"
}

# ── inspect ─────────────────────────────────────────────────────────────────
is_archive() {
  case "${1,,}" in
    *.7z|*.zip|*.rar|*.tar|*.tar.gz|*.tgz|*.tar.xz) return 0 ;;
    *) return 1 ;;
  esac
}

archive_list() {
  case "${1,,}" in
    *.rar) lsar "$1" ;;
    *)     7z l -slt -- "$1" | sed -n 's/^Path = //p' ;;
  esac
}

# stdin: one path per line → a count per file extension.  This is the single
# most useful thing to look at before copying: it is what tells you the archive
# holds .md AND .32x AND .sms, or that half of it is .exe.
histogram() {
  awk -F/ '{ n = split($NF, a, "."); print (n > 1 ? tolower(a[n]) : "(no extension)") }' \
    | sort | uniq -c | sort -rn | head -12
}

cmd_inspect() {
  local src=${1:?SRC required}
  [ -e "$src" ] || die "no such path: $src"
  if [ -d "$src" ]; then
    echo "== directory =="
    find "$src" -mindepth 1 -maxdepth 1 -printf '%y  %f\n' | sort -k2 | head -40
    echo
    echo "== extensions =="
    find "$src" -type f | histogram
    printf '\ntotal: %s files, %s\n' \
      "$(find "$src" -type f | wc -l)" "$(du -sh --apparent-size "$src" | cut -f1)"
  elif is_archive "$src"; then
    echo "== top level =="
    archive_list "$src" | cut -d/ -f1 | sort -u | head -40
    echo
    echo "== extensions =="
    archive_list "$src" | histogram
  else
    echo "== single file =="
    ls -lh -- "$src"
  fi
}

# ── unpack / clean ──────────────────────────────────────────────────────────
cmd_unpack() {
  local src=${1:?SRC required}
  [ -f "$src" ] || die "not a file: $src"
  is_archive "$src" || die "not an archive: $src"
  need_lib
  local base out
  base=$(basename -- "${src%.*}")
  out="${STAGING}/${base}"
  if [ -d "$out" ]; then
    printf 'already unpacked: %s files\n' "$(find "$out" -type f | wc -l)" >&2
  else
    mkdir -p "$out"
    printf 'extracting %s → %s\n' "$(basename -- "$src")" "$out" >&2
    case "${src,,}" in
      *.rar) unar -q -f -o "$out" -D -- "$src" >&2 ;;
      *)     7z x -o"$out" -bso0 -bsp0 -y -- "$src" >&2 ;;
    esac
    find "$out" -type f | histogram >&2
  fi
  # Only the path goes to stdout, so this is usable as  d=$(rom-import unpack …)
  printf '%s\n' "$out"
}

cmd_clean() {
  need_lib
  local n=0
  for d in "$STAGING" "${LIB}"/.import.*; do
    if [ -d "$d" ]; then
      printf 'removing %s (%s)\n' "$d" "$(du -sh "$d" | cut -f1)"
      rm -rf "${d:?}"
      n=$((n + 1))
    fi
  done
  if [ "$n" = 0 ]; then echo "nothing staged"; fi
}

# ── copy ────────────────────────────────────────────────────────────────────
cmd_copy() {
  local OPTIND=1 o
  local exts='' inner='' flat=0 base=roms dry=0
  while getopts 'e:i:fbn' o; do
    case $o in
      e) exts=$OPTARG ;;
      i) inner=$OPTARG ;;
      f) flat=1 ;;
      b) base=bios ;;
      n) dry=1 ;;
      *) usage; exit 1 ;;
    esac
  done
  shift $((OPTIND - 1))
  local platform=${1:?PLATFORM required} src=${2:?SRC required}
  [ -e "$src" ] || die "no such path: $src"
  need_lib

  local dest="${LIB}/${base}/${platform}"

  local stage
  stage=$(mktemp -d "${LIB}/.import.XXXXXXXX")
  # shellcheck disable=SC2064  # $stage must expand NOW, not when the trap fires
  trap "rm -rf '$stage'" EXIT

  local pick=$stage
  if [ -d "$src" ]; then
    pick=$src
  elif is_archive "$src"; then
    printf 'extracting %s …\n' "$(basename -- "$src")"
    case "${src,,}" in
      *.rar)
        unar -q -f -o "$stage" -D -- "$src"
        ;;
      *)
        local mode=x
        if [ "$flat" = 1 ]; then mode=e; fi
        if [ -n "$inner" ]; then
          7z "$mode" -o"$stage" -bso0 -bsp0 -y -- "$src" "$inner"
        else
          7z "$mode" -o"$stage" -bso0 -bsp0 -y -- "$src"
        fi
        ;;
    esac
  fi

  # Build the file list.  -e restricts to the named extensions; without it
  # everything survives except the junk classes.
  local list
  list=$(mktemp)
  # shellcheck disable=SC2064
  trap "rm -f '$list'" RETURN
  if [ -f "$src" ] && ! is_archive "$src"; then
    printf '%s\n' "$src" > "$list"          # a bare ROM file
  elif [ -n "$exts" ]; then
    find "$pick" -type f -regextype posix-extended \
      -iregex ".*\\.(${exts//,/|})" -print > "$list"
  else
    find "$pick" -type f -regextype posix-extended \
      ! -iregex ".*\\.(${JUNK})" -print > "$list"
  fi

  local n
  n=$(wc -l < "$list")
  [ "$n" -gt 0 ] || die "nothing matched — check -e/-i, or run 'rom-import inspect'"

  printf '\n%s files → %s\n' "$n" "$dest"
  histogram < "$list"

  # A nested archive is nearly always a bundled emulator rather than a ROM, but
  # it cannot simply be blacklisted: for some systems a .zip IS the ROM.  So
  # warn and let -e settle it.  A Switch grab put Ryujinx and Yuzu in the
  # library before this warning existed.
  local nested
  nested=$(grep -Eci '\.(7z|rar|tar\.gz|tgz)$' "$list" || true)
  if [ "$nested" -gt 0 ] && [ -z "$exts" ]; then
    printf '\nWARNING: %s nested archive(s) matched — usually a bundled emulator:\n' "$nested"
    grep -Ei '\.(7z|rar|tar\.gz|tgz)$' "$list" | sed 's|.*/|  |' | head -5
    printf 'Pass -e with the ROM extension to exclude them.\n'
  fi

  if [ "$dry" = 1 ]; then
    printf '\ndry run — nothing copied. Sample:\n'
    head -5 "$list" | sed 's|^|  |'
    return 0
  fi

  local before after copied
  install -d -o "$ROMM_UID" -g "$ROMM_GID" -m 2770 "$dest"
  before=$(find "$dest" -type f | wc -l)
  # -n so a re-run never overwrites a file already curated in the library.
  tr '\n' '\0' < "$list" | xargs -0 -r cp -n -t "$dest" --
  after=$(find "$dest" -type f | wc -l)
  # The setgid bit fixes the GROUP of new files, never the owner.
  chown -R "${ROMM_UID}:${ROMM_GID}" "$dest"

  # The library is flat per platform, so two files with the same basename in
  # different subdirectories of the source collapse into one and `cp -n` keeps
  # whichever it saw first.  That is usually a regional or "unpadded" duplicate
  # and is fine — but it is never silent.
  copied=$((after - before))
  if [ "$copied" -lt "$n" ]; then
    printf 'note: %s of %s matched files were already present or share a basename\n' \
      "$((n - copied))" "$n"
  fi

  printf 'done. '
  cmd_verify "$platform" "$base"
}

# ── verify ──────────────────────────────────────────────────────────────────
cmd_verify() {
  need_lib
  local platform=${1:-} base=${2:-roms} d c
  if [ -z "$platform" ]; then
    for d in "${LIB}"/roms/*/ "${LIB}"/bios/*/; do
      if [ -d "$d" ]; then
        c=$(find "$d" -type f | wc -l)
        if [ "$c" -gt 0 ]; then
          printf '%-16s %6s files  %8s\n' "$(basename "$d")" "$c" \
            "$(du -sh --apparent-size "$d" | cut -f1)"
        fi
      fi
    done
    printf '\ngamelist.xml: %s\n' "$(find "${LIB}/roms" -name gamelist.xml | wc -l)"
    return 0
  fi
  d="${LIB}/${base}/${platform}"
  # Do not judge an import by `du -sh`: zdata/roms is zstd-compressed, so 3537
  # NES ROMs report 691M apparent and 366M on disk.  The file count and the
  # zero-byte count are the honest numbers.
  printf '%s: %s files, %s apparent / %s on disk, %s zero-byte\n' \
    "$d" "$(find "$d" -type f | wc -l)" \
    "$(du -sh --apparent-size "$d" | cut -f1)" \
    "$(du -sh "$d" | cut -f1)" \
    "$(find "$d" -type f -size 0 | wc -l)"
}

case "${1:-}" in
  list)    shift; cmd_list "$@" ;;
  inspect) shift; cmd_inspect "$@" ;;
  unpack)  shift; cmd_unpack "$@" ;;
  clean)   shift; cmd_clean "$@" ;;
  copy)    shift; cmd_copy "$@" ;;
  verify)  shift; cmd_verify "$@" ;;
  ''|-h|--help|help) usage ;;
  *) usage; exit 1 ;;
esac
