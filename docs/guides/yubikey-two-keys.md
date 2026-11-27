# Two YubiKeys: backup and keeping them in step

There are two keys in the household: **lgo's** (YubiKey 5C NFC, serial
19345499) and **his wife's** (her own identity — not a clone of lgo's).
[yubikey.md](yubikey.md) covers how lgo's key is wired into the fleet. This guide
covers what has to be backed up, and what to do so both keys stay usable.

!!! note "Shell"
    Commands in §3 and §4 are written for nushell, lgo's login shell. Any
    other block is bash: type `bash` first and `exit` when done.

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

## 2. Current state — MEASURED on miralda 2026-11-27

The stick (`sda`, 1.9 GB) has two partitions:

- `sda1`: LUKS, label `gpg-2022-08-23`. It holds `gnupg-workspace/`.
- `sda2`: ext2, label `gpg-public-2022-`. Public keys only.

| Key | On the card (19345499) | On the stick |
|---|---|---|
| Main key `0x7BE3C4FBC4BD9026` rsa4096 [C] | — (offline, as it should be) | `mastersub.key` (2022), `mastersub-2026-11-27.key` |
| Sign `…C7F06026F01896C4` rsa4096, **expired 2023-08-23** | yes | yes |
| Encrypt `…14694FF23C252D99` rsa4096, **expired 2023-08-23** | yes | yes |
| Auth `…AB99704F6CEEADCE` rsa4096, expired, unused | no | yes |
| Auth `…F0BCBDAF59BAD230` **ed25519 — the SSH key, `openpgp:0x59BAD230`** | yes | `mastersub-2026-11-27.key` only |

The SSH key before it, `0x5E293E5A` (2026), was never backed up. It existed
only on the card and was replaced on 2026-11-27 by the steps in §3.

The files written in 2026 are owned by root with mode `0600`, and the folder
belongs to uid 1000. The scripts use `sudo` for both, so expect a sudo prompt.

Open items:

- **The sign and encrypt subkeys expired in 2023.** SSH doesn't care, but
  signing and decrypting with GPG do. Extend them the next time the stick is
  open (`gpg --quick-set-expire <main fpr> 2y <subkey fpr>…` in the throwaway
  home, then export as in `yubikey-new-ssh-subkey.sh` step 3).
- `sda2` is **unencrypted** but holds `flores/` and `lombok/`, with
  `ssh_host_*_key` **private** host keys. Neither machine is in the fleet.
  Delete the folders if the machines are retired; otherwise move them into
  `sda1`.
- There is one stick. A second copy kept somewhere else is the cheapest
  insurance here.

---

## 3. Rotate the SSH key (or refresh the backup)

Use this when the SSH subkey is missing from the backup, or when you want a
new one. Each step leaves a working state behind.

The commands are for **nushell** as written. The scripts are bash and are
started with `bash …`.

**Unlock the stick.** Both scripts need it:

```
udisksctl unlock -b /dev/sda1
udisksctl mount -b /dev/dm-3
```

`unlock` asks for the LUKS passphrase and prints `/dev/dm-N`. Use that N in
the mount line, because it changes between boots. The mount point is
`/run/media/lgo/gpg-2022-08-23`.

**Step 1 — make the key and back it up.** This doesn't touch the card or
`~/.gnupg`:

```
bash /home/lgo/Projects/clanarchy/scripts/yubikey-new-ssh-subkey.sh
```

It asks for the **GPG main key passphrase** (the 2022 one, in KeePassXC) and
`sudo`. It writes `mastersub-<date>.key`, `sub-<date>.key` and
`public-<date>.asc` next to the old files, reads them back to check, and
prints the new `ssh-ed25519 … openpgp:0x…` line.

**Step 2 — authorise it next to the old key, and deploy.** Put the line in a
new `machines/miralda/yubikey_ed25519_<year>.pub`. Read that file wherever
`yubikey_ed25519.pub` is read — `grep -rn yubikey_ed25519 --include=*.nix .`
finds them all, including two that use `../miralda/` and `../../miralda/`
paths. Add it to `clan.nix` next to `lgo-yubikey` too. Then deploy **every**
machine while the old key still works. A machine you skip can only be
reached the old way until it is deployed some other way. Don't put two keys
in one `.pub` file: `authorizedKeys.keys` takes single-line strings, and
evaluation fails.

**Step 3 — move it onto the card.** Plug in only that YubiKey:

```
bash /home/lgo/Projects/clanarchy/scripts/yubikey-subkey-to-card.sh
```

The script refuses to run if any other YubiKey is connected. It works out
which `key N` the subkey is and proves it with gpg's own selection marker.
Then it prints the five lines to type into gpg (`key N`, `keytocard`, `3`,
`y`, `save`). Dialogs ask for the **main key passphrase**, then the card's
**OpenPGP Admin PIN**. That is not the PIN you type for SSH: it is at least 8
characters, and a wrong one costs a try (5 in total). Afterwards the script
checks that the card's auth slot holds the new key, adds its keygrip to
`~/.gnupg/sshcontrol` and shows `ssh-add -L`. Test with `ssh root@ernst true`.

**Step 4 — retire the old key.** Make the new line the only content of
`yubikey_ed25519.pub`, drop the `_<year>` file and its reads, and deploy.

**Lock the stick again:**

```
udisksctl unmount -b /dev/dm-3
udisksctl lock -b /dev/sda1
```

Two traps the scripts handle, in case you ever do this by hand:

- A throwaway `GNUPGHOME` needs `disable-ccid` in its `scdaemon.conf`, like
  `~/.gnupg` has. Without it, its scdaemon fights pcscd for the card and
  reports `No such device`. Stop the real agent first
  (`gpgconf --kill gpg-agent`).
- With two YubiKeys plugged in, gpg silently picks one of them. It may well be
  the wrong one.

---

## 4. Put lgo's keys on a replacement card

For the SSH key, use the same script with the target card as the only one
plugged in:

```
bash /home/lgo/Projects/clanarchy/scripts/yubikey-subkey-to-card.sh
```

The script only handles the SSH key (slot 3) today. For sign (slot 1) and
encrypt (slot 2), extend their expiry first (§2), then follow the same pattern
by hand in the throwaway home.

A replacement card also needs a **new age key**: see "Re-provisioning the PIV
slot" in [yubikey.md](yubikey.md). Then add its `age1yubikey1…` to
`sops/users/lgo/key.json` and run `sops updatekeys`.

To find the Admin PIN among many KeePassXC entries without spending tries
blindly: stop gpg (`gpgconf --kill gpg-agent`), then run
`ykman --device <serial> openpgp keys set-touch aut off`. It asks only for the
Admin PIN, and if the PIN is right it rewrites a setting to the value it
already had. `ykman --device <serial> openpgp info` shows the tries left.

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
| a GPG subkey (new, extended expiry) | new dated backup on the stick (§3 step 1 shows how) → §4 for each card that should carry it |
| a TOTP account on a shared login | enrol it on both keys, seed in KeePassXC |
| a passkey on a shared login | register both keys, update the KeePassXC list |
| her or lgo's pam_u2f registration | edit `clanarchy.u2f.credentials`, deploy |
| a PIN | KeePassXC |

Once a year: unlock the stick and compare `gpg --card-status` with the newest
`mastersub-*.key` (`sudo cat <file> | gpg --list-packets | grep keyid`, since the file is root-owned). Every key on the
card must be in the backup. Check the second stick too, if there is one.

## Lost key

- **lgo's:** a new card from §4 (GPG) + a new age key (yubikey.md,
  "Re-provisioning the PIV slot"). Remove the old `age1yubikey1…` from
  `sops/users/lgo/key.json`, then `sops updatekeys`. The regular age key in
  `keys.txt` (and on the stick) bridges the gap.
- **Hers:** delete her line in `clanarchy.u2f.credentials` and deploy. Remove the
  key on each site in the KeePassXC list. Re-enrol TOTP from the KeePassXC
  seeds onto the new key.
