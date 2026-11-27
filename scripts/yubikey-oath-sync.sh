#!/usr/bin/env bash
# KeePassXC is the master copy of every TOTP seed; the YubiKeys are copies.
# This puts each TOTP account from the database onto every plugged-in key,
# and reports accounts on a key that KeePassXC does not have (a seed that
# exists ONLY on that key — lost with it). See docs/guides/yubikey-two-keys.md §6.
#
#   bash scripts/yubikey-oath-sync.sh              # plan only, changes nothing
#   APPLY=1 bash scripts/yubikey-oath-sync.sh      # add the missing accounts
#   ONLY='GitHub|Amazon' bash …                    # restrict to matching names (regex)
#   TOUCH=1 …                                      # added accounts need a touch
#
# Asks for: the database password (once). Seeds stay in memory: the CSV export
# goes through a pipe, never to disk. ykman only ADDS — nothing is deleted or
# overwritten on a key.
set -euo pipefail

KDBX=${KDBX:-$HOME/goclan/Passwords/go.kdbx}
ONLY=${ONLY:-}
[ -f "$KDBX" ] || { echo "!! $KDBX not found (set KDBX=…)"; exit 1; }
if [ -n "${SERIALS:-}" ]; then read -ra serials <<< "$SERIALS"; else mapfile -t serials < <(ykman list --serials); fi
[ "${#serials[@]}" -ge 1 ] || { echo "!! no YubiKey plugged in"; exit 1; }

read -rsp "KeePassXC password for $(basename "$KDBX"): " pw; echo
# name<TAB>uri per TOTP entry; name as ykman shows it (issuer:account).
entries=$(printf '%s\n' "$pw" | keepassxc-cli export -q -f csv "$KDBX" | python3 -I -c '
import csv, sys, urllib.parse as u
seen = set()
for r in csv.DictReader(sys.stdin):
    uri = r.get("TOTP", "")
    if not uri.startswith("otpauth://"): continue
    p = u.urlparse(uri); label = u.unquote(p.path.lstrip("/"))
    issuer = u.parse_qs(p.query).get("issuer", [""])[0]
    if ":" in label: issuer, label = label.split(":", 1)
    name = f"{issuer}:{label}" if issuer else label
    if name in seen: continue
    seen.add(name); print(f"{name}\t{uri}")
') || true
unset pw
[ -n "$entries" ] || { echo "!! no TOTP entries found (wrong password?)"; exit 1; }
if [ -n "$ONLY" ]; then entries=$(grep -E "^[^	]*($ONLY)" <<< "$entries" || true); fi
echo "KeePassXC: $(grep -c . <<< "$entries") TOTP account(s)${ONLY:+ matching '$ONLY'}"

added=0
for s in "${serials[@]}"; do
  y="ykman --device $s"
  op=()
  if ! $y oath info | grep -q 'Password protection: disabled'; then
    read -rsp "OATH password of YubiKey $s: " opw; echo; op=(-p "$opw")
  fi
  have=$($y oath accounts list "${op[@]}")
  echo
  echo "== YubiKey $s: $(grep -c . <<< "$have" || true) account(s)"
  while IFS=$'\t' read -r name uri; do
    grep -qxF "$name" <<< "$have" && continue
    if [ -n "${APPLY:-}" ]; then
      if $y oath accounts uri "${op[@]}" ${TOUCH:+-t} "$uri" < /dev/null > /dev/null 2>&1; then
        echo "   + added    $name"; added=$((added+1))
      else
        echo "   ! failed   $name (already there under another name? add it by hand)"
      fi
    else
      echo "   + would add $name"
    fi
  done <<< "$entries"
  [ -n "$ONLY" ] && continue
  while read -r name; do
    [ -n "$name" ] || continue
    cut -f1 <<< "$entries" | grep -qxF "$name" || echo "   ? only on this key, not in KeePassXC: $name"
  done <<< "$have"
done
echo
if [ -n "${APPLY:-}" ]; then echo "Added $added account(s)."; else echo "Plan only. Run again with APPLY=1 to add."; fi
echo "'? only on this key': save that seed in KeePassXC (re-enrol it at the site) — otherwise it dies with the key."
