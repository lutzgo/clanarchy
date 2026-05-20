#!/usr/bin/env bash
# check-feature.sh — poll upstream Nix/HM sources for features not yet landed
#
# Usage:
#   ./scripts/check-feature.sh [--notify] [feature...]
#
#   --notify   send a desktop notification (notify-send) when a feature is found
#              omit to just print to stdout
#
#   feature    one or more feature IDs to check (default: all)
#              e.g.  ./scripts/check-feature.sh niri-blur
#
# Adding a new feature to watch:
#   1. Add a check_<feature_id>() function below.
#   2. Register it in the FEATURES array at the bottom.
#   Each function must:
#     - print a one-line status to stdout (used in --notify body)
#     - return 0 if the feature has LANDED (notify), non-zero if still absent.
#
# Run manually, or wire to a systemd timer / cron for periodic checks.
# Example one-liner to run daily via systemd user timer:
#   systemd-run --user --on-calendar=daily \
#     --unit=check-feature \
#     bash /path/to/clanarchy/scripts/check-feature.sh --notify

set -euo pipefail

NOTIFY=0
REQUESTED=()

for arg in "$@"; do
  case "$arg" in
    --notify) NOTIFY=1 ;;
    *)        REQUESTED+=("$arg") ;;
  esac
done

# ── helpers ────────────────────────────────────────────────────────────────────

# Fetch a raw file from GitHub (unauthenticated, rate-limited to 60 req/h).
# Args: owner repo ref path
github_raw() {
  curl -fsSL "https://raw.githubusercontent.com/$1/$2/$3/$4"
}

# Emit result: print msg, optionally send desktop notification.
# Args: feature_id msg landed(0=yes/1=no)
emit() {
  local id="$1" msg="$2" landed="$3"
  if [[ "$landed" -eq 0 ]]; then
    echo "[LANDED]  $id — $msg"
    if [[ "$NOTIFY" -eq 1 ]] && command -v notify-send &>/dev/null; then
      notify-send --urgency=normal \
        "clanarchy: upstream feature landed" \
        "$id\n$msg"
    fi
  else
    echo "[waiting] $id — $msg"
  fi
  return "$landed"
}

# ── feature checks ─────────────────────────────────────────────────────────────

# niri-blur: blur{} top-level block support in sodiboo/niri-flake HM module.
#
# Background: niri 25.11 rejects blur{} as an unknown top-level KDL node.
# Once niri ships blur and niri-flake exposes it as programs.niri.settings.blur,
# we can re-add the blur block in modules/desktop/niri-hm.nix.
#
# What to check: the niri-flake HM module (niri-settings.nix) gains a "blur"
# attribute in its options attrset. We grep for 'blur' in that file as a proxy;
# tighten the pattern if false positives appear.
#
# Tracking: https://github.com/sodiboo/niri-flake (watch for niri blur PRs)
#           https://github.com/YaLTeR/niri (upstream niri compositor)
check_niri_blur() {
  local file
  # sodiboo/niri-flake declares all programs.niri.settings.* options in settings.nix.
  # When niri upstream ships a blur{} top-level KDL block and niri-flake exposes it,
  # a "blur" attribute will appear as a Nix option key in that file, e.g.:
  #   blur = { ... };   or   "blur" = mkOption { ... };
  # We grep for that pattern specifically to avoid matching the one existing
  # "blur radius" string in a CSS shadow doc comment.
  file=$(github_raw sodiboo niri-flake main settings.nix 2>/dev/null || true)

  if [[ -z "$file" ]]; then
    echo "[error]   niri-blur — could not fetch niri-flake settings.nix (network/rate-limit?)"
    return 2
  fi

  # Match "blur" or "blur" as a Nix attribute key (followed by = or .)
  # but NOT inside a string literal or comment.
  if echo "$file" | grep -qE '^\s+"?blur"?\s*[.=]'; then
    emit niri-blur \
      "programs.niri.settings.blur option detected in sodiboo/niri-flake — re-add blur{} block in modules/desktop/niri-hm.nix" \
      0
  else
    emit niri-blur \
      "no top-level blur option in niri-flake settings.nix yet" \
      1
  fi
}

# ── dispatch ───────────────────────────────────────────────────────────────────

# Register feature IDs → check functions here.
declare -A FEATURES=(
  [niri-blur]=check_niri_blur
  # [next-feature]=check_next_feature
)

if [[ "${#REQUESTED[@]}" -eq 0 ]]; then
  REQUESTED=("${!FEATURES[@]}")
fi

any_landed=0
for id in "${REQUESTED[@]}"; do
  fn="${FEATURES[$id]:-}"
  if [[ -z "$fn" ]]; then
    echo "[unknown] $id — no check registered for this feature"
    continue
  fi
  if "$fn"; then
    any_landed=1
  fi
done

# Exit 0 if at least one feature landed (useful for scripting: && do_something).
[[ "$any_landed" -eq 1 ]]
