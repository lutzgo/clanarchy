#!/usr/bin/env bash
# Extend the expiry of a GPG key's sign + encrypt subkeys from the offline
# backup, write a new dated backup to the stick, and give ~/.gnupg the updated
# PUBLIC key (so the card can sign/decrypt again). The card is NOT touched:
# an expiry date lives in the public key's self-signatures, not on the card.
# See docs/guides/yubikey-two-keys.md §3a.
#
# Prerequisite: the stick's LUKS partition unlocked and mounted.
# Asks for: sudo, and the main key passphrase (dialog).
set -euo pipefail

STICK=${STICK:-/run/media/lgo/gpg-2022-08-23/gnupg-workspace}
BACKUP=${BACKUP:-$STICK/mastersub-2026-11-27.key}
FPR=${FPR:-C3B06FED1C93D951B72FC7BF7BE3C4FBC4BD9026}
EXPIRE=${EXPIRE:-2y}
OUTDIR=${OUTDIR:-$STICK}
D=$(date +%F)-extended

[ -e "$BACKUP" ] || { echo "!! $BACKUP not found — is the stick unlocked and mounted?"; exit 1; }
for f in mastersub-$D.key sub-$D.key public-$D.asc; do
  [ ! -e "$OUTDIR/$f" ] || { echo "!! $OUTDIR/$f already exists — not overwriting"; exit 1; }
done

T=$(mktemp -d -p "/run/user/$(id -u)")
REAL=${REAL_GNUPGHOME:-$HOME/.gnupg}
export GNUPGHOME=$T
g() { if [ -n "${YK_TEST:-}" ]; then gpg --batch --pinentry-mode loopback --passphrase test "$@"; else gpg "$@"; fi; }
cleanup() { GNUPGHOME=$T gpgconf --kill all 2>/dev/null || true; rm -rf "$T"; }
trap cleanup EXIT

echo "== 1/4 importing $(basename "$BACKUP") into a throwaway keyring"
if [ -r "$BACKUP" ]; then cp "$BACKUP" "$T/backup.key"; else sudo cat "$BACKUP" > "$T/backup.key"; fi
g --quiet --import "$T/backup.key"

# Sign and encrypt subkeys (capability field 12 contains s or e).
mapfile -t SUBS < <(g --with-colons --list-keys "$FPR" | awk -F: '
  $1=="sub" {want=($12 ~ /[se]/); next}
  want && $1=="fpr" {print $10; want=0}')
[ "${#SUBS[@]}" -gt 0 ] || { echo "!! no sign/encrypt subkeys found"; exit 1; }
echo "   extending to $EXPIRE: ${SUBS[*]}"

echo "== 2/4 setting the new expiry (asks for the MAIN KEY passphrase)"
g --quiet --quick-set-expire "$FPR" "$EXPIRE" "${SUBS[@]}"
# The main key too, if it has an expiry at all.
if [ -n "$(g --with-colons --list-keys "$FPR" | awk -F: '$1=="pub" {print $7}')" ]; then
  g --quiet --quick-set-expire "$FPR" "$EXPIRE"
fi
g --list-keys "$FPR" | sed 's/^/   /'
left=$(g --with-colons --list-keys "$FPR" | awk -F: '$1=="sub" && $12 ~ /[se]/ && $2=="e" {bad++} END {print bad+0}')
[ "$left" = 0 ] || { echo "!! $left sign/encrypt subkey(s) still expired — nothing written"; exit 1; }

echo "== 3/4 exporting and checking the new backup (passphrase may be asked again)"
O=$T/out
mkdir "$O"
g --armor --export-secret-keys "$FPR"    > "$O/mastersub-$D.key"
g --armor --export-secret-subkeys "$FPR" > "$O/sub-$D.key"
g --armor --export "$FPR"                > "$O/public-$D.asc"
n=$(g --list-packets "$O/mastersub-$D.key" 2>/dev/null | grep -c '^:secret sub key packet:' || true)
have=$(g --with-colons --list-secret-keys "$FPR" | grep -c '^ssb' || true)
[ "$n" = "$have" ] || { echo "!! export holds $n secret subkeys, keyring has $have — nothing written"; exit 1; }
echo "   OK: mastersub-$D.key holds the main key + $n secret subkeys"

echo "== 4/4 copying to the stick, next to the old files (which stay)"
SUDO=sudo
[ -w "$OUTDIR" ] && SUDO=
$SUDO cp -n "$O/mastersub-$D.key" "$O/sub-$D.key" "$O/public-$D.asc" "$OUTDIR/"
$SUDO chmod 600 "$OUTDIR/mastersub-$D.key" "$OUTDIR/sub-$D.key"
sync
for f in mastersub-$D.key sub-$D.key public-$D.asc; do
  $SUDO cmp -s "$O/$f" "$OUTDIR/$f" || { echo "!! $OUTDIR/$f differs from what was exported"; exit 1; }
done
echo "   OK: written and read back from $OUTDIR"

echo "== ~/.gnupg gets the updated PUBLIC key (secrets stay on the card)"
GNUPGHOME=$REAL gpg --quiet --import "$O/public-$D.asc"
echo "$FPR:6:" | GNUPGHOME=$REAL gpg --quiet --import-ownertrust
[ -n "${YK_TEST:-}" ] || GNUPGHOME=$REAL gpg --card-status > /dev/null   # links the card's keys
GNUPGHOME=$REAL gpg --list-keys "$FPR" | sed 's/^/   /'
echo
echo "Done. New backup: $OUTDIR/mastersub-$D.key. The card was not changed."
echo "Public key for others (keyserver, GitHub, her machine): $OUTDIR/public-$D.asc"
