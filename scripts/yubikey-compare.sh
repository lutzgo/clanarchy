#!/usr/bin/env bash
# Compare two YubiKeys feature by feature: which applications are on, PIN
# state, OpenPGP slots + touch policy, PIV slots, OTP slots, OATH accounts.
# Values that MUST differ (serials, key fingerprints, certificate serials) are
# masked, so every line the diff shows is a real difference in setup.
# See docs/guides/yubikey-two-keys.md §6.
#
#   bash scripts/yubikey-compare.sh            # both keys plugged in
#   DEEP=1 bash scripts/yubikey-compare.sh     # also FIDO2 passkeys (asks each FIDO2 PIN)
#
# Read-only: changes nothing on either key.
set -euo pipefail

# SERIALS="a b" overrides detection (testing: the same key twice).
if [ -n "${SERIALS:-}" ]; then read -ra serials <<< "$SERIALS"; else mapfile -t serials < <(ykman list --serials); fi
[ "${#serials[@]}" = 2 ] || { echo "!! plug in both YubiKeys (connected now: ${serials[*]:-none})"; exit 1; }

profile() {
  local s=$1 y="ykman --device $1"
  echo "## device"
  $y info | grep -vE '^(Serial number|Firmware version|Device type|Form factor)'
  echo "## openpgp"
  $y openpgp info | grep -vE '^(OpenPGP version|Application version)' \
    | sed -E 's/(Fingerprint: +).*/\1<set>/'
  echo "## piv"
  $y piv info | grep -vE '^(PIV version|  (Serial|Fingerprint|Not before|Not after|Issuer DN):)'
  echo "## fido2"
  $y fido info | grep -vE '^AAGUID'
  if [ -n "${DEEP:-}" ]; then
    echo "   (FIDO2 PIN of $s:)" > /dev/tty
    $y fido credentials list | awk '{print "passkey: " $0}' | sort
  fi
  echo "## otp"
  $y otp info
  echo "## oath"
  $y oath info | grep -v '^OATH version'
  $y oath info | grep -q 'Password protection: disabled' || echo "   (OATH password of $s:)" > /dev/tty
  $y oath accounts list | sed 's/^/account: /' | sort
}

T=$(mktemp -d -p "/run/user/$(id -u)")
trap 'rm -rf "$T"' EXIT
for s in "${serials[@]}"; do profile "$s" > "$T/$s"; done

a=${serials[0]} b=${serials[1]}
echo "YubiKey $a  ($(ykman --device "$a" info | awk -F': ' '/^Firmware/ {print "fw " $2}'))   vs   YubiKey $b  ($(ykman --device "$b" info | awk -F': ' '/^Firmware/ {print "fw " $2}'))"
echo
if diff -q "$T/$a" "$T/$b" > /dev/null; then
  echo "Identical setup (apart from serials and key material)."
else
  echo "Differences ('<' = $a only, '>' = $b only):"
  diff "$T/$a" "$T/$b" | grep -E '^[<>]' || true
  echo
  echo "Full profiles side by side:"
  diff -y -W 140 "$T/$a" "$T/$b" || true
fi
