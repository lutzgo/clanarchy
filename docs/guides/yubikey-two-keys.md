# Two YubiKeys: backup and keeping them in step

There are two keys in the household: **lgo's** (YubiKey 5C NFC, serial
19345499) and **his wife's** (her own identity — not a clone of lgo's).
[yubikey.md](yubikey.md) covers how lgo's key is wired into the fleet. This guide
covers what has to be backed up, and what to do so both keys stay usable.

!!! note "Shell"
    The command blocks are **bash**. lgo's login shell is nushell, so type
    `bash` first and `exit` when done.

---

## 1. The one rule: a YubiKey can't be synced

A key generated on a YubiKey can't be read back off it. So "sync" never means
copying one key to the other. It means one of three things, depending on what
the secret is:

| Secret | Can it go on a 2nd card? | How the keys stay in step | Lives where |
|---|---|---|---|
| lgo's GPG subkeys (sign, encrypt, **SSH auth**) | Yes, **only from the offline backup** | Write the same subkeys to each card from the backup | USB stick, encrypted partition |
| lgo's age key (PIV slot 1) | No — it was generated on the card | Second key = second *recipient*, plus the regular age key as a fallback | Card only. The fallback is `~/.config/sops/age/keys.txt`, which belongs on the stick too |
| TOTP codes (Yubico Authenticator) | Yes, **only at enrolment** | Add the same seed (QR code) to both keys at the same time | KeePassXC entry holds the seed |
| Passkeys / FIDO2 website logins | No | Register each key on each site | A list in KeePassXC (see §5) |
| Touch-for-sudo (pam_u2f) | No | One line per key in the repo — the same line works on every machine | `clanarchy.u2f.credentials` |

So the **sources of truth** are: the **USB stick** (private keys),
**KeePassXC** (TOTP seeds, PINs, recovery codes, the list of sites), and
**this repo** (public halves only). A YubiKey is a copy of something kept
elsewhere, or a thing that can be replaced and re-registered. It is never the
only place a secret exists.

---

## 2. Current state — MEASURED on miralda 2026-11-18

The stick (`sda`, 1.9 GB) has two partitions: `sda1` (LUKS, the secrets) and
`sda2` (ext2, label `gpg-public-2022-`). The public partition holds
`gpg-0x7BE3C4FBC4BD9026-2022-08-23.asc`:

| Key | On the card (19345499) | In the 2022 public export |
|---|---|---|
| Master `0x7BE3C4FBC4BD9026` rsa4096 [C] | — (offline, as it should be) | yes |
| Sign `…C7F06026F01896C4` rsa4096 | yes | yes |
| Encrypt `…14694FF23C252D99` rsa4096 | yes (created 2022-08-23) | yes |
| Auth `…AB99704F6CEEADCE` rsa4096 | **no** — replaced | yes |
| Auth `…9673D4E35E293E5A` **ed25519 — the SSH key in `authorizedKeys`** | yes | **no** |

So the SSH key the fleet trusts (`openpgp:0x5E293E5A`) was added after the
2022 backup. Whether the encrypted partition has it is **not yet checked** —
§3 step 1 finds out. If it doesn't, that subkey exists only on the card, and
§3 step 3 fixes that.

Two things to clean up on the stick:

- `sda2` is **unencrypted** but holds `flores/` and `lombok/`, with
  `ssh_host_*_key` **private** host keys. Neither machine is in the fleet. If
  they are retired, delete the folders. Otherwise move them into the LUKS
  partition.
- The label says 2022. Once §3 has run, the public export's file name should
  carry the new date.

---

## 3. Refresh the USB backup (do this now, then after every key change)

### Step 1 — look at what is on it

```bash
udisksctl unlock -b /dev/sda1          # LUKS passphrase
udisksctl mount -b /dev/dm-<N>         # the device the unlock printed
ls -la /run/media/lgo/<secret-label>/
```

Inspect every secret export without importing it anywhere:

```bash
T=$(mktemp -d)
for f in /run/media/lgo/<secret-label>/*.{key,asc,gpg}; do
  echo "== $f"; gpg --homedir "$T" --import-options show-only --import "$f" 2>/dev/null | grep -E '^(sec|ssb)'
done
rm -rf "$T"
```

The backup is complete when `sec` for `7BE3C4FBC4BD9026` appears **without**
a `#` (`sec#` means only a stub), and there is an `ssb` ed25519 line ending in
`5E293E5A`.

If there is a whole GnuPG home directory on the stick instead of export files,
use `gpg --homedir /run/media/lgo/<secret-label>/<dir> -K`. Don't write into it
— copy it to a temp directory first (step 2).

### Step 2 — work in a throwaway GnuPG home, never in `~/.gnupg`

```bash
export GNUPGHOME=$(mktemp -d)
gpg --import /run/media/lgo/<secret-label>/<secret export>
gpg -K          # sec = master present, ssb = subkeys present
```

Every later step happens in here. The stick stays read-only until step 4, and
`~/.gnupg` on miralda is never touched — it holds card stubs only, and that is
how it should stay.

### Step 3 — only if the ed25519 SSH subkey is missing from the backup

It can't be pulled off the card. Make a new one, **back it up first**, then
put it on the cards:

```bash
gpg --quick-add-key 7BE3C4FBC4BD9026 ed25519 auth 0
gpg --export-ssh-key 7BE3C4FBC4BD9026     # → the new public key
```

Then: step 4 (backup), §4 (write it to the card), and replace the public key in
**both** places the fleet reads it — `clan.nix` (`"lgo-yubikey"` under
`roles.server.settings.authorizedKeys`) and
`machines/miralda/yubikey_ed25519.pub`. Deploy every machine **while the old key
still works**. The `clanarchy_admin` key is the fallback if one is missed.

### Step 4 — write the backup back

```bash
B=/run/media/lgo/<secret-label>; D=$(date +%F)
gpg --armor --export-secret-keys 7BE3C4FBC4BD9026 > "$B/gpg-secret-$D.asc"
gpg --armor --gen-revoke 7BE3C4FBC4BD9026        > "$B/gpg-revoke-$D.asc"   # if none is there yet
cp ~/.config/sops/age/keys.txt                      "$B/age-keys-$D.txt"    # the regular age key — the sops fallback
# public half → the unencrypted partition
udisksctl mount -b /dev/sda2
gpg --armor --export 7BE3C4FBC4BD9026 | sudo tee /run/media/lgo/gpg-public-2022-/gpg-0x7BE3C4FBC4BD9026-$D.asc >/dev/null
```

Keep the old files until you have checked the new ones (step 1 again on the new
file names). Then:

```bash
rm -rf "$GNUPGHOME"; unset GNUPGHOME
sync; udisksctl unmount -b /dev/sda2; udisksctl unmount -b /dev/dm-<N>; udisksctl lock -b /dev/sda1
```

A single stick is a single point of failure. A second stick with the same
contents, kept somewhere else, costs ten minutes, and so does every later
refresh.

---

## 4. Put lgo's GPG subkeys on a card (spare or replacement)

From the throwaway home of §3 step 2, with the target card inserted:

```bash
gpg --edit-key 7BE3C4FBC4BD9026
# gpg> list          note which ssb line is [S], [E], [A]
# gpg> key 1         select ONE subkey (an asterisk marks it)
# gpg> keytocard     slot: 1 = sign, 2 = encrypt, 3 = auth
# gpg> key 1         deselect, then the next one
# … repeat for each subkey …
# gpg> save
```

`save` moves the subkeys out of the **throwaway** home, so for a second card,
start again from §3 step 2. The stick is unaffected.

Back in the real `~/.gnupg`, point the stubs at the card that is plugged in.
This step is needed whenever you switch between two cards that hold the same
keys:

```bash
gpg-connect-agent "scd serialno" "learn --force" /bye
ssh-add -L          # ed25519 … cardno:<serial>
```

A replacement card also needs a **new age key**: "Re-provisioning the PIV slot"
in [yubikey.md](yubikey.md), then add its `age1yubikey1…` to
`sops/users/lgo/key.json` and `sops updatekeys`.

---

## 5. Her key

Her key has its own identity: nothing of lgo's goes on it.

**Once, when she gets it** (any machine with `ykman`, e.g. miralda):

1. Set PINs: `ykman fido access change-pin` (FIDO2) and
   `ykman oath access change-password` (TOTP, optional). Put both in
   KeePassXC.
2. Register it for touch-to-sudo — see below.
3. Enrol her TOTP accounts in Yubico Authenticator, **saving each seed or QR
   code in KeePassXC first**. Then a lost key is a re-enrolment, not an
   account recovery.
4. Register it as a passkey or security key on her own accounts.

**Touch-to-sudo on her laptop.** `modules/hardware/yubikey-u2f.nix` (fleet-wide,
inert until enabled). Accepts a touch instead of the password for `sudo`,
polkit and the Noctalia lock screen. Login at the greeter stays
password-only, because a password-less login leaves gnome-keyring locked.
Without the key, the password works as before. The lock-screen part is reasoned, not measured:
if Noctalia shows no touch prompt, press Enter on an empty field, then touch.
Once her machine is in the fleet:

```bash
nix shell nixpkgs#pam_u2f -c pamu2fcfg -u <her-user> -o pam://clanarchy -i pam://clanarchy
# → <her-user>:<KeyHandle>,<UserKey>,es256,+presence     (touch when it blinks)
```

```nix
# machines/<her-machine>/configuration.nix
clanarchy.u2f = {
  enable = true;
  credentials.<her-user> = [
    "<KeyHandle>,<UserKey>,es256,+presence"   # everything after "<her-user>:"
  ];
};
```

The origin `pam://clanarchy` is fixed fleet-wide. That is what makes the
registration "synced": the same line is valid on every machine that enables
the module. That includes lgo's machines, if lgo adds his own key under his
user. The line is public data (key handle + public key), safe to commit.

---

## 6. Shared accounts (bank, utilities, the household email)

Where both of you log in to one account, register **both** keys on it:

- **TOTP:** scan the QR code into both keys at once, and keep the seed in
  KeePassXC. Most sites show the QR code only once.
- **Passkeys / security keys:** add both keys on the site's security page.
  Keep one KeePassXC entry, *YubiKey registrations*, listing each site and
  which keys are registered there. That list is the only record — a YubiKey
  can't tell you where it is registered (resident passkeys excepted:
  `ykman fido credentials list`).

---

## 7. Checklist — after any change

| You changed… | Then |
|---|---|
| a GPG subkey (new, extended expiry) | §3 step 4 (backup) → §4 for each card that should carry it |
| a TOTP account on a shared login | enrol it on both keys, seed in KeePassXC |
| a passkey on a shared login | register both keys, update the KeePassXC list |
| her or lgo's pam_u2f registration | edit `clanarchy.u2f.credentials`, deploy |
| a PIN | KeePassXC |

Once a year: run §3 step 1 against the stick and compare with
`gpg --card-status`, and check the second stick if there is one.

## Lost key

- **lgo's:** a new card from §4 (GPG) + a new age key (yubikey.md,
  "Re-provisioning the PIV slot"). Remove the old `age1yubikey1…` from
  `sops/users/lgo/key.json`, then `sops updatekeys`. The regular age key in
  `keys.txt` (and on the stick) bridges the gap.
- **Hers:** delete her line in `clanarchy.u2f.credentials` and deploy. Remove the
  key on each site in the KeePassXC list. Re-enrol TOTP from the KeePassXC
  seeds onto the new key.
