#!/usr/bin/env bash
# Give a YubiKey its OWN GPG identity, set up like lgo's: an offline main key
# [C] that lives only on the stick, and sign / encrypt / auth (SSH) subkeys on
# the card. Built for his wife's key; works for any new person.
# See docs/guides/yubikey-two-keys.md §5.
#
# Order matters and is enforced: the backup is on the stick (and read back)
# BEFORE anything goes onto the card, because keytocard moves, not copies.
#
# Prerequisites: the stick's LUKS partition unlocked and mounted, and ONLY the
# target YubiKey plugged in. Asks for: her name + email, a NEW passphrase for
# her main key (she picks it; into KeePassXC), new User PIN + Admin PIN for the
# card (into KeePassXC), sudo.
set -euo pipefail

STICK=${STICK:-/run/media/lgo/gpg-2022-08-23/gnupg-workspace}
SERIAL=${SERIAL:-42221658}
EXPIRE=${EXPIRE:-2y}       # sign + encrypt; extend with yubikey-extend-subkeys.sh
D=$(date +%F)

# --- the right card, and only it, with an empty OpenPGP app ------------------
if [ -z "${YK_TEST:-}" ]; then
  mapfile -t serials < <(ykman list --serials)
  if [ "${#serials[@]}" -ne 1 ] || [ "${serials[0]}" != "$SERIAL" ]; then
    echo "!! plug in ONLY YubiKey $SERIAL — connected now: ${serials[*]:-none}"; exit 1
  fi
fi
[ -d "$STICK" ] || { echo "!! $STICK not found — is the stick unlocked and mounted?"; exit 1; }

if [ -z "${UID_NAME:-}" ]; then read -rp "Her full name (as it should appear in the key): " UID_NAME; fi
if [ -z "${UID_EMAIL:-}" ]; then read -rp "Her email address: " UID_EMAIL; fi
[ -n "$UID_NAME" ] && [[ "$UID_EMAIL" == *@*.* ]] || { echo "!! need a name and an email"; exit 1; }
USERID="$UID_NAME <$UID_EMAIL>"
LABEL=$(printf '%s' "${UID_NAME%% *}" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
DEST=$STICK/$LABEL
[ ! -e "$DEST/mastersub-$D.key" ] || { echo "!! $DEST/mastersub-$D.key already exists — not overwriting"; exit 1; }

T=$(mktemp -d -p "/run/user/$(id -u)")
REAL=${REAL_GNUPGHOME:-$HOME/.gnupg}
export GNUPGHOME=$T
[ -e "$REAL/scdaemon.conf" ] && cp "$REAL/scdaemon.conf" "$T/"   # disable-ccid, see the rotation script
[ -n "${YK_TEST:-}" ] || GNUPGHOME=$REAL gpgconf --kill gpg-agent  # so it does not hold the card
g() { if [ -n "${YK_TEST:-}" ]; then gpg --batch --pinentry-mode loopback --passphrase test "$@"; else gpg "$@"; fi; }
cleanup() { GNUPGHOME=$T gpgconf --kill all 2>/dev/null || true; rm -rf "$T"; }
trap cleanup EXIT

if [ -z "${YK_TEST:-}" ]; then
  slots=$(g --with-colons --card-status | awk -F: '$1=="fpr" {for (i=2;i<=4;i++) if ($i!="") n++} END {print n+0}')
  [ "$slots" = 0 ] || { echo "!! card $SERIAL already holds $slots OpenPGP key(s) — stopping, nothing changed"; exit 1; }
fi

echo
echo "   Key:    $USERID  (ed25519 main key, never expires; subkeys $EXPIRE)"
echo "   Backup: $DEST/"
echo "   Card:   $SERIAL"
read -rp "   Correct? Enter to go on, Ctrl-C to stop… " _

echo "== 1/6 creating the main key — a dialog asks her to CHOOSE its passphrase"
echo "        (KeePassXC entry: 'GPG main key – $UID_NAME')"
g --quiet --quick-generate-key "$USERID" ed25519 cert never
FPR=$(g --with-colons --list-keys "$USERID" | awk -F: '$1=="fpr" {print $10; exit}')
echo "   main key $FPR"
echo "== 2/6 adding sign, encrypt and auth subkeys (passphrase dialog each time)"
g --quiet --quick-add-key "$FPR" ed25519 sign "$EXPIRE"
g --quiet --quick-add-key "$FPR" cv25519 encr "$EXPIRE"
g --quiet --quick-add-key "$FPR" ed25519 auth never
mapfile -t SUBFPR < <(g --with-colons --list-keys "$FPR" | awk -F: '$1=="sub" {s=1; next} s && $1=="fpr" {print $10; s=0}')
[ "${#SUBFPR[@]}" = 3 ] || { echo "!! expected 3 subkeys, got ${#SUBFPR[@]}"; exit 1; }
g --list-keys "$FPR" | sed 's/^/   /'

echo "== 3/6 backup to the stick, BEFORE the card (passphrase may be asked again)"
O=$T/out
mkdir "$O"
g --armor --export-secret-keys "$FPR"    > "$O/mastersub-$D.key"
g --armor --export-secret-subkeys "$FPR" > "$O/sub-$D.key"
g --armor --export "$FPR"                > "$O/public-$D.asc"
cp "$T/openpgp-revocs.d/$FPR.rev" "$O/revoke-$D.asc"
n=$(g --list-packets "$O/mastersub-$D.key" 2>/dev/null | grep -c '^:secret sub key packet:' || true)
[ "$n" = 3 ] || { echo "!! export holds $n secret subkeys, expected 3 — nothing written"; exit 1; }
SUDO=sudo
[ -w "$STICK" ] && SUDO=
$SUDO mkdir -p "$DEST"
$SUDO cp -n "$O"/* "$DEST/"
$SUDO chmod 600 "$DEST/mastersub-$D.key" "$DEST/sub-$D.key" "$DEST/revoke-$D.asc"
sync
for f in "$O"/*; do
  $SUDO cmp -s "$f" "$DEST/$(basename "$f")" || { echo "!! $DEST/$(basename "$f") differs from what was exported"; exit 1; }
done
echo "   OK: main key + 3 subkeys + revocation certificate written and read back in $DEST"

if [ -n "${YK_TEST:-}" ]; then echo "YK_TEST: stopping before the card"; exit 0; fi

echo "== 4/6 card PINs. The card is factory-new, so the CURRENT values are:"
echo "        User PIN 123456, Admin PIN 12345678. Choose new ones (User ≥6, Admin ≥8)"
echo "        and save both in KeePassXC ('YubiKey $SERIAL OpenPGP PIN / Admin PIN')."
ykman --device "$SERIAL" openpgp access change-pin
ykman --device "$SERIAL" openpgp access change-admin-pin

echo "== 5/6 moving the subkeys onto the card (dialogs: main key passphrase, then the NEW Admin PIN)"
# keytocard per subkey: select it, store it in its slot (1 sign, 2 encrypt,
# 3 auth), deselect. Driven via --command-fd; the result is checked below by
# comparing the card's fingerprints, so a wrong turn cannot pass silently.
gpg --command-fd 0 --edit-key "$FPR" <<EOF
key 1
keytocard
1
key 1
key 2
keytocard
2
key 2
key 3
keytocard
3
key 3
save
EOF
got=$(g --with-colons --card-status | awk -F: '$1=="fpr" {print $2" "$3" "$4}')
want="${SUBFPR[0]} ${SUBFPR[1]} ${SUBFPR[2]}"
[ "$got" = "$want" ] || { echo "!! card holds '$got', expected '$want' — re-run step 5 from the backup"; exit 1; }
echo "   OK: sign, encrypt, auth on the card match the backup"

echo "== 6/6 touch policy like lgo's card: sign + decrypt need a touch, SSH does not (Admin PIN)"
ykman --device "$SERIAL" openpgp keys set-touch sig on -f
ykman --device "$SERIAL" openpgp keys set-touch dec on -f
ykman --device "$SERIAL" openpgp keys set-touch aut off -f
g --card-status | grep -E '^(Serial|Key attributes|PIN retry|UIF|Signature key|Encryption key|Authentication key)'

echo
echo "Done. Her SSH public key (for when her machine joins the fleet):"
g --export-ssh-key "${SUBFPR[2]}!"
echo
echo "Public key (her machine imports this once): $DEST/public-$D.asc"
