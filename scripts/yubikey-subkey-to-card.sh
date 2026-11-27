#!/usr/bin/env bash
# Write one subkey from the offline backup onto lgo's YubiKey, then point
# ~/.gnupg at it. Step 3 of the SSH key rotation in
# docs/guides/yubikey-two-keys.md; also how a replacement card gets its keys.
#
# Prerequisites: the stick's LUKS partition unlocked and mounted, and ONLY the
# target YubiKey plugged in. Asks for: the GPG main key passphrase and the
# card's Admin PIN (dialogs), plus five lines typed into gpg (printed below).
set -euo pipefail

STICK=${STICK:-/run/media/lgo/gpg-2022-08-23/gnupg-workspace}
BACKUP=${BACKUP:-$STICK/mastersub-2026-11-27.key}
FPR=${FPR:-C3B06FED1C93D951B72FC7BF7BE3C4FBC4BD9026}
SUB=${SUB:-59BAD230}          # the subkey to move (short or long id)
SERIAL=${SERIAL:-19345499}    # the card it must go to

# --- the right card, and only it --------------------------------------------
if [ -z "${YK_TEST:-}" ]; then
  mapfile -t serials < <(ykman list --serials)
  if [ "${#serials[@]}" -ne 1 ] || [ "${serials[0]}" != "$SERIAL" ]; then
    echo "!! plug in ONLY YubiKey $SERIAL — connected now: ${serials[*]:-none}"; exit 1
  fi
fi
[ -e "$BACKUP" ] || { echo "!! $BACKUP not found — is the stick unlocked and mounted?"; exit 1; }

T=$(mktemp -d -p "/run/user/$(id -u)")
REAL=${GNUPGHOME:-$HOME/.gnupg}
export GNUPGHOME=$T
# Same card access as the real home (disable-ccid → via pcscd); without it the
# throwaway scdaemon fights pcscd and gets "No such device". The real agent is
# stopped so it does not hold the card; it restarts on demand.
[ -e "$REAL/scdaemon.conf" ] && cp "$REAL/scdaemon.conf" "$T/"
GNUPGHOME=$REAL gpgconf --kill gpg-agent
g() { if [ -n "${YK_TEST:-}" ]; then gpg --batch --pinentry-mode loopback --passphrase test "$@"; else gpg "$@"; fi; }
cleanup() { GNUPGHOME=$T gpgconf --kill all 2>/dev/null || true; rm -rf "$T"; }
trap cleanup EXIT

echo "== 1/5 importing $(basename "$BACKUP") into a throwaway keyring (may ask for the MAIN KEY passphrase)"
# Backups written by yubikey-new-ssh-subkey.sh are root-owned and 0600.
if [ -r "$BACKUP" ]; then cp "$BACKUP" "$T/backup.key"; else sudo cat "$BACKUP" > "$T/backup.key"; fi
g --quiet --import "$T/backup.key"

# --- which `key N` is it, proven by gpg's own selection marker -------------
read -r N LONG SUBFPR GRIP < <(g --with-colons --with-keygrip --list-secret-keys "$FPR" | awk -F: -v w="$SUB" '
  $1=="ssb" {n++; id=$5; want=(substr(id, length(id)-length(w)+1)==toupper(w)); next}
  want && $1=="fpr" {fpr=$10; next}
  want && $1=="grp" {print n, id, fpr, $10; exit}') || true
[ -n "${GRIP:-}" ] || { echo "!! subkey $SUB not found in $BACKUP"; exit 1; }
sel=$(gpg --batch --command-fd 0 --edit-key "$FPR" 2>&1 <<<"key $N
list
quit" | awk '/^ssb\*/ {print $2}' | sort -u)
[ "$sel" = "ed25519/$LONG" ] || { echo "!! 'key $N' selects '$sel', expected ed25519/$LONG — stopping"; exit 1; }
echo "   subkey $LONG is 'key $N' (checked), keygrip $GRIP"

echo "== 2/5 card before:"
if [ -z "${YK_TEST:-}" ]; then g --card-status | grep -E '^(Serial number|Authentication key)'; fi

echo
echo "== 3/5 gpg opens next. Type these five lines, one at a time:"
echo
echo "      key $N          (the line 'ssb* ed25519/$LONG' gets a star)"
echo "      keytocard"
echo "      3               (Authentication key)"
echo "      y               (yes, replace the key on the card)"
echo "      save"
echo
echo "   Dialogs in between: the MAIN KEY passphrase, then the card's ADMIN PIN."
echo "   Anything looks different? Type 'quit' and answer y — nothing is written."
echo
if [ -z "${YK_TEST:-}" ]; then
  read -rp "   Press Enter to open gpg… " _
  gpg --edit-key "$FPR"
fi

echo "== 4/5 checking the card now holds the new key"
if [ -z "${YK_TEST:-}" ]; then
  got=$(g --with-colons --card-status | awk -F: '$1=="fpr" {print $4}')
  [ "$got" = "$SUBFPR" ] || { echo "!! card auth key is '$got', expected $SUBFPR — the card was NOT changed as planned"; exit 1; }
fi
echo "   OK: auth slot = $SUBFPR"

echo "== 5/5 pointing ~/.gnupg (and so ssh) at the card"
GNUPGHOME=$T gpgconf --kill all
export GNUPGHOME=$REAL
grep -q "^$GRIP " "$REAL/sshcontrol" 2>/dev/null || echo "$GRIP 0" >> "$REAL/sshcontrol"
if [ -z "${YK_TEST:-}" ]; then
  gpgconf --kill gpg-agent
  gpg --card-status > /dev/null
  gpg-connect-agent "scd serialno" "learn --force" /bye > /dev/null
  echo
  echo "== ssh-add -L now offers:"
  ssh-add -L
fi
echo
echo "Done. Test with:  ssh root@ernst true"
