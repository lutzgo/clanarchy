# YubiKey

This guide covers how the YubiKey is integrated into clanarchy across three distinct use-cases:

1. **SSH authentication** — via the GnuPG ed25519 auth subkey
2. **Age encryption** — via `age-plugin-yubikey` for clan vars / sops
3. **PIV operations** — `ykman` over SSH sessions

Configuration lives in [`modules/hardware/yubikey.nix`](https://github.com/lutzgo/clanarchy/blob/main/modules/hardware/yubikey.nix), wired to machines via the `@clanarchy/yubikey` service module in `service-modules/yubikey.nix`.

---

## SSH via GnuPG auth subkey

The YubiKey holds an **ed25519 auth subkey** on the OpenPGP applet. `gpg-agent` exposes it as an SSH agent socket, replacing `ssh-agent`.

### How it works

```
ssh client
  → SSH_AUTH_SOCK=/run/user/1000/gnupg/S.gpg-agent.ssh
    → gpg-agent
      → scdaemon
        → pcscd (PC/SC daemon)
          → YubiKey OpenPGP applet
```

`pcscd` must be running before `scdaemon` first tries to connect — otherwise you get a `No such device` race. The config starts it eagerly at boot rather than relying on socket activation:

```nix
services.pcscd.enable = true;
systemd.services.pcscd.wantedBy = [ "multi-user.target" ];
```

`gpg-agent` is enabled with SSH support:

```nix
programs.gnupg.agent = {
  enable = true;
  enableSSHSupport = true;
  pinentryPackage = pkgs.pinentry-qt;
};
```

### Pinentry on Wayland

`gpg-agent` only forwards `DISPLAY` (X11) to pinentry, not `WAYLAND_DISPLAY`. `pinentry-gnome3` was explicitly ruled out: it calls `gcr_system_password_finish` via D-Bus (`org.gnome.keyring.SystemPrompter`), which requires `gnome-keyring-daemon` — absent on Niri. Every PIN prompt fails silently, and gpg-agent returns "agent refused operation".

`pinentry-qt` is used instead: it draws its own Qt dialog directly on Wayland with no GNOME dependency. A wrapper script injects `WAYLAND_DISPLAY` and `QT_QPA_PLATFORM=wayland` so Qt picks the right backend even when called from the gpg-agent context (SSH auth flow, devShell):

```bash
uid=$(id -u)
wayland=$(ls /run/user/$uid/wayland-* 2>/dev/null | head -1 | xargs basename)
export WAYLAND_DISPLAY="$wayland"
export QT_QPA_PLATFORM="wayland"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
exec pinentry-qt "$@"
```

This is set as the `pinentry-program` in `/etc/gnupg/gpg-agent.conf` via `lib.mkForce` (overriding the NixOS module's default).

### SSH sessions and pcscd polkit

pcscd uses PolicyKit and by default only permits **active** (local graphical) logind sessions. SSH sessions are not active. Without a polkit override, `ykman` PIV operations and `scdaemon` fail silently over SSH.

The polkit rule grants unconditional access to the PC/SC interfaces:

```javascript
polkit.addRule(function(action, subject) {
  if (action.id === "org.debian.pcsc-lite.access_pcsc" ||
      action.id === "org.debian.pcsc-lite.access_card") {
    return polkit.Result.YES;
  }
});
```

!!! note
    This uses `security.polkit.extraConfig` (JavaScript rules), **not** `security.polkit.extraRules`. The two use different rule engines.

### HostKeyAlgorithms quirk

gnupg 2.4.x fails to sign with card-backed ed25519 keys when OpenSSH negotiates `publickey-hostbound-v00@openssh.com` (a newer algorithm). To avoid this, the SSH client config for `miralda.goclan.org` forces `HostKeyAlgorithms=ssh-ed25519`, and the host's plain ed25519 key is pinned system-wide:

```nix
programs.ssh.knownHosts."miralda.goclan.org" = {
  publicKey = "ssh-ed25519 AAAA...";
};
```

---

### First-time setup of the auth subkey

Only needed when provisioning a new card or a new master key. Prerequisites: a
YubiKey 5 with the OpenPGP app enabled, an existing GPG master key, and both
PINs (defaults `123456` / `12345678`).

**1. Create a dedicated ed25519 auth subkey.** Do not reuse a Sign or Encrypt
subkey for SSH.

```bash
gpg --quick-add-key <FINGERPRINT> ed25519 auth
gpg -K --with-keygrip          # look for `ssb [A] ed25519`; note its keygrip
```

**2. Move it to the card.**

```bash
gpg --edit-key <FINGERPRINT>
# gpg> key 0        deselect everything
# gpg> list         find the [A] subkey's position N
# gpg> key N        select ONLY that one
# gpg> keytocard    choose slot 3 (Authentication); User PIN, then Admin PIN
# gpg> save
```

`key 1` selects the first *subkey*, which is usually not the auth key — use
`list` and match on `[A]`. Afterwards `gpg -K` shows `ssb>` for it; the `>`
means the private half is on the card.

**3. Export the SSH public key** to `machines/miralda/yubikey_ed25519.pub`:

```bash
gpg --export-ssh-key <FINGERPRINT>    # ssh-ed25519 AAAA… openpgp:0xXXXXXXXX
```

**4. Add the keygrip to `sshcontrol`** — gpg-agent only exposes keys listed
there:

```bash
echo "<KEYGRIP> 0" >> ~/.gnupg/sshcontrol
ssh-add -L                     # should now show the ed25519 key
```

The trailing `0` means "confirm on each use". `.gnupg` is persisted through
impermanence, so this survives reboots.

**5. Authorise it.** The pubkey is read into `openssh.authorizedKeys.keys` by
`modules/users/admin.nix` and `modules/users/lgo.nix`:

```nix
openssh.authorizedKeys.keys = [
  (builtins.readFile ../../machines/miralda/yubikey_ed25519.pub)
];
```

Then deploy. Verify end to end:

```bash
gpg --card-status     # card detected, PIN retry counter 3
ssh-add -L            # key exposed by the agent
ssh root@ernst true   # PIN prompt, then success
```

---

## Age encryption (clan vars / sops)

The YubiKey PIV applet holds an **age recipient** via `age-plugin-yubikey`. This allows clan vars secrets and sops files to be encrypted to the YubiKey — decryptable only when the key is inserted and the PIN is entered.

### Key identities

| Key | Public key | Location |
|-----|-----------|----------|
| lgo regular age key | `age1dja6qmtqlxhul8xdtj3tsgj8qwzc07yasauy767fq9k2knaa2q5sj0wxv8` | `~/.config/sops/age/keys.txt` |
| lgo YubiKey age key | `age1yubikey1qw86lycmkeart5sh5mrhrpcr7qwfceemu7aw22veqclmeu3m2wsqwnqw7zg` | YubiKey Serial 19345499, Slot 1 — identity stub seeded into `keys.txt` automatically by `home.activation.seedYubikeyAgeIdentity` in `modules/users/lgo.nix` |
| miralda machine key | `age1c2982jjusdhrdzua0wrj5c8q8knxz6gja975kt42j3e8rdstwfusr0wse6` | `sops/machines/miralda/key.json` |

### Recipient policy

**Every admin-readable sops secret must have lgo's regular age key as a co-recipient**, in addition to the YubiKey key. This is the single most important rule — without it, a PIV slot reset locks you out of all secrets.

`sops/users/lgo/key.json` controls which keys clan uses when generating new secrets:

```json
[
  { "publickey": "age1dja6...", "type": "age" },
  { "publickey": "age1yubikey1...", "type": "age" }
]
```

Both entries must always be present. Adding the regular key here ensures `clan vars generate` and `clan secrets generate` always include it.

### devShell requirement

`age-plugin-yubikey` must be in the devShell for any `clan vars generate` or sops re-encryption operation that targets a YubiKey recipient:

```nix
packages = with pkgs; [
  age-plugin-yubikey
  # ...
];
```

If you run `clan vars generate` without the plugin in `PATH`, the generation succeeds but the secret is not encrypted to the YubiKey recipient.

### Re-provisioning the PIV slot

If the YubiKey PIV slot is reset or a new key is generated:

```bash
# Generate a new age key on the YubiKey (Slot 1)
age-plugin-yubikey --generate --slot 1

# Get the new identity stub + public key
age-plugin-yubikey --identity
```

Update the stub (`AGE-PLUGIN-YUBIKEY-...` and its comment block) baked into
`home.activation.seedYubikeyAgeIdentity` in `modules/users/lgo.nix` with the
new output, so every machine picks it up on next `clan machines update`. (The
grep-and-append guard there is one-shot per string match, so the *old* stub
line is not automatically removed from an already-seeded `keys.txt` — delete
it by hand on each machine, or just leave it: a stale, deprovisioned stub is
inert, not a security hole.)

Then update `sops/users/lgo/key.json` with the new `age1yubikey1...` public key and re-encrypt all sops secrets:

```bash
# For each sops secret file
nix shell nixpkgs#sops --command sops updatekeys sops/secrets/<machine>-age.key/secret
```

### Re-encrypting sops files

After rotating the age key or adding a new recipient:

```bash
# From inside nix develop
sops updatekeys sops/<file>.yaml
```

The YubiKey must be inserted and PIN available.

---

## Troubleshooting

### SSH signing fails

`sign_and_send_pubkey: signing failed … agent refused operation`, usually with
`smartcard signing failed: General error` in the gpg-agent log. In order:

1. Card inserted? `ykman list`
2. PIN not blocked? `gpg --card-status | grep 'PIN retry'` — a counter of `0`
   needs the Admin PIN to clear:
   ```bash
   gpg --card-edit
   # → admin → passwd → option 2 (Unblock PIN)
   ```
3. Stale scdaemon? `gpgconf --kill gpg-agent && gpg --card-status`
4. Does the host have `HostKeyAlgorithms=ssh-ed25519`? See
   [the quirk](#hostkeyalgorithms-quirk) — and note a *new* `Host` alias does
   not inherit it from a pattern block, so the workaround has to be repeated on
   the alias.

If gpg-agent's log shows the failure *before* pinentry or scdaemon are reached,
it is almost always (4).

### gpg-agent not forwarding SSH key

1. Check `SSH_AUTH_SOCK` points to the gnupg socket:
   ```bash
   echo $SSH_AUTH_SOCK
   # should be /run/user/1000/gnupg/S.gpg-agent.ssh
   ```
2. Check that pcscd is running:
   ```bash
   systemctl status pcscd
   ```
3. Check that the card is visible to gpg:
   ```bash
   gpg --card-status
   ```

### "No such device" on login

pcscd is socket-activated and hasn't fully started before scdaemon connects. Confirm `pcscd.service` is in `multi-user.target` (not just the socket unit):

```bash
systemctl cat pcscd.service | grep WantedBy
```

### "No such device" after pcscd restarts (stale scdaemon state)

pcscd can restart mid-session — e.g., after a `deploy switch` or if the socket was triggered late. scdaemon caches a connection to the old pcscd instance and does not automatically reconnect. `gpg --card-status` then fails with `No such device` even though the card is inserted and pcscd is running.

Fix: kill gpg-agent (which also kills scdaemon), then retry. scdaemon will start fresh and reconnect to the live pcscd:

```bash
gpgconf --kill gpg-agent
gpg --card-status
```

This is the correct first step whenever `gpg --card-status` fails with `No such device` and `systemctl status pcscd` shows the daemon active.

### PIN prompt doesn't appear (Wayland)

The pinentry wrapper reads `wayland-*` from `/run/user/$uid/`. If the Wayland session hasn't created the socket yet (e.g. prompt fires during greeter), there's nothing to inject. Entering the PIN via the terminal fallback (`pinentry-curses`) is not configured — use the graphical session.

### `clan machines update` fails: "no identity matched any of the recipients"

This happens when the YubiKey PIV slot is empty (reset or not yet provisioned) and a sops secret is encrypted only to the YubiKey age key.

**Recovery** — the machine's age private key is deployed to `/var/lib/sops-nix/key.txt` on the running machine. Use it to re-encrypt the secret with proper recipients:

```bash
# 1. Get the plaintext from the running machine
ssh root@miralda.goclan.org "cat /var/lib/sops-nix/key.txt"
# → AGE-SECRET-KEY-1...

# 2. Write plaintext JSON and re-encrypt with both age keys
printf '{"data": "AGE-SECRET-KEY-1..."}' > /tmp/plain.json
nix shell nixpkgs#sops --command sops encrypt \
  --age age1dja6qmtqlxhul8xdtj3tsgj8qwzc07yasauy767fq9k2knaa2q5sj0wxv8,age1yubikey1qw86lycmkeart5sh5mrhrpcr7qwfceemu7aw22veqclmeu3m2wsqwnqw7zg \
  --input-type json --output-type json \
  --output /tmp/enc.json \
  /tmp/plain.json

# 3. Verify decryption works
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt \
  nix shell nixpkgs#sops --command sops decrypt /tmp/enc.json

# 4. Also verify via clan
SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt clan secrets get miralda-age.key

# 5. Replace the sops secret
cp /tmp/enc.json sops/secrets/miralda-age.key/secret
```

Commit the result. Then provision the PIV slot (see Re-provisioning above) and `sops updatekeys` to restore the YubiKey recipient for future decryptions.

### sops decrypt fails after ZFS rollback

After a rollback, the age identity file path referenced in `.sops.yaml` might not exist until impermanence re-creates the bind mounts. Ensure `/var/lib/sops-nix` is in the persisted paths (it is, in `modules/zfs-impermanence.nix`).
