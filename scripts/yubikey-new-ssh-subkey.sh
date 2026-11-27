#!/usr/bin/env bash
# Add a new ed25519 SSH (auth) subkey to lgo's offline GPG main key and back it
# up to the USB stick BEFORE it goes anywhere near a card. Touches neither the
# YubiKey nor ~/.gnupg: works in a throwaway GnuPG home in RAM, deleted at the
# end. Step 1 of the rotation in docs/guides/yubikey-two-keys.md.
#
# Prerequisite: the stick's LUKS partition is unlocked and mounted.
# Asks for: the GPG main key passphrase (dialog), and sudo (the 2022 files on
# the stick are root-owned).
set -euo pipefail

STICK=${STICK:-/run/media/lgo/gpg-2022-08-23/gnupg-workspace}
FPR=${FPR:-C3B06FED1C93D951B72FC7BF7BE3C4FBC4BD9026}
D=$(date +%F)

[ -r "$STICK/mastersub.key" ] || { echo "!! $STICK/mastersub.key not readable — is the stick unlocked and mounted?"; exit 1; }
for f in mastersub-$D.key sub-$D.key public-$D.asc; do
  [ ! -e "$STICK/$f" ] || { echo "!! $STICK/$f already exists — not overwriting"; exit 1; }
done

T=$(mktemp -d -p "/run/user/$(id -u)")
export GNUPGHOME=$T
# YK_TEST=1 is for dry runs only: loopback passphrase "test", no dialog.
g() { if [ -n "${YK_TEST:-}" ]; then gpg --batch --pinentry-mode loopback --passphrase test "$@"; else gpg "$@"; fi; }
cleanup() { gpgconf --kill all 2>/dev/null || true; rm -rf "$T"; }
trap cleanup EXIT

echo "== 1/4 importing the backup (may ask for the MAIN KEY passphrase)"
g --quiet --import "$STICK/mastersub.key"

echo "== 2/4 adding an ed25519 auth subkey (asks for the MAIN KEY passphrase)"
g --quiet --quick-add-key "$FPR" ed25519 auth never
NEW=$(g --with-colons --list-keys "$FPR" | awk -F: '$1=="sub" && $4==22 && $12~/a/ {id=$5} END {print id}')
[ -n "$NEW" ] || { echo "!! no ed25519 auth subkey found after adding it"; exit 1; }
echo "   new subkey: $NEW"

echo "== 3/4 exporting the new backup (passphrase may be asked again) and checking it"
O=$T/out
mkdir "$O"
g --armor --export-secret-keys "$FPR"    > "$O/mastersub-$D.key"
g --armor --export-secret-subkeys "$FPR" > "$O/sub-$D.key"
g --armor --export "$FPR"                > "$O/public-$D.asc"
if g --list-packets "$O/mastersub-$D.key" 2>/dev/null \
   | awk '/^:secret sub key packet:/ {s=1; next} s && /keyid:/ {print $2; s=0}' | grep -qx "$NEW"; then
  echo "   OK: mastersub-$D.key contains secret subkey $NEW"
else
  echo "!! mastersub-$D.key does NOT contain secret subkey $NEW — nothing written to the stick"; exit 1
fi

echo "== 4/4 copying to the stick, next to the old files (which stay)"
SUDO=sudo
[ -w "$STICK" ] && SUDO=
$SUDO cp -n "$O/mastersub-$D.key" "$O/sub-$D.key" "$O/public-$D.asc" "$STICK/"
$SUDO chmod 600 "$STICK/mastersub-$D.key" "$STICK/sub-$D.key"
sync
for f in mastersub-$D.key sub-$D.key public-$D.asc; do
  $SUDO cmp -s "$O/$f" "$STICK/$f" || { echo "!! $STICK/$f differs from what was exported"; exit 1; }
done
echo "   OK: written and read back from $STICK"

echo
echo "== new SSH public key — paste this line back to Claude:"
g --export-ssh-key "$NEW!"
echo
echo "Done. The card and ~/.gnupg are unchanged; the throwaway keyring is deleted."
