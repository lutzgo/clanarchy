# YubiKey SSH Setup Guide

This guide documents how to configure a YubiKey for SSH authentication via GnuPG on this NixOS setup, including every non-obvious pitfall encountered during the initial setup.

---

## Overview

SSH authentication is handled by the GnuPG agent, which exposes the YubiKey's OpenPGP Authentication subkey as an SSH key. The flow is:

```
ssh → gpg-agent (SSH socket) → scdaemon → pcscd → YubiKey
```

The NixOS config in `machines/miralda/yubikey.nix` wires this up, but several issues arise in practice. This guide covers the full setup and all known workarounds.

---

## Prerequisites

- YubiKey 5 (any form factor) with OpenPGP app enabled
- An existing GPG master key (or create one: `gpg --full-gen-key`)
- The YubiKey's Admin PIN (default: `12345678`) and User PIN (default: `123456`)
- `gpg`, `pcsc-tools`, `yubikey-manager` — all available in the devShell or installed via `lgo.nix`

---

## Step 1: Create a dedicated ed25519 Authentication subkey

**Do not use an existing Sign or Encrypt subkey for SSH.** Create a dedicated key in the `auth` role.

```bash
# Add ed25519 auth subkey non-interactively
gpg --quick-add-key <FINGERPRINT> ed25519 auth

# Verify it appears (look for ssb [A] ed25519):
gpg -K --with-keygrip
```

Note the keygrip of the new `[A]` subkey — you'll need it in Step 4.

---

## Step 2: Move the auth subkey to the YubiKey

```bash
gpg --edit-key <FINGERPRINT>
```

Inside the interactive prompt:

```
gpg> key 0       # deselect all (if anything is selected)
gpg> key N       # select only the [A] ed25519 subkey (N = its position, check with "list")
gpg> keytocard
# Choose slot: 3 (Authentication)
# Enter User PIN when prompted, then Admin PIN
gpg> save
```

**Common mistake**: `key 1` selects the first _subkey_ (not the auth key). Use `list` to identify the correct position. The auth subkey has `[A]` in its usage column.

After this, `gpg -K` should show `ssb>` for the auth subkey (the `>` means the private key is on the card).

---

## Step 3: Export the SSH public key

```bash
gpg --export-ssh-key <FINGERPRINT>
```

Save this output to `machines/miralda/yubikey_ed25519.pub`. It has the form:

```
ssh-ed25519 AAAA... openpgp:0xXXXXXXXX
```

---

## Step 4: Add the keygrip to sshcontrol

`gpg-agent` only exposes keys listed in `~/.gnupg/sshcontrol`. Add the auth subkey's keygrip:

```bash
gpg -K --with-keygrip   # find the [A] subkey keygrip
echo "<KEYGRIP> 0" >> ~/.gnupg/sshcontrol
```

The `0` means the key requires confirmation (PIN entry) on each use. Use `1` for no confirmation (not recommended).

Verify:
```bash
ssh-add -L   # should show the ed25519 key
```

**This file is persisted** via impermanence (`.gnupg` directory) so it survives reboots.

---

## Step 5: Update authorized_keys in NixOS config

The new public key must be in `openssh.authorizedKeys.keys` for every user that needs SSH access. In this repo it's wired in `modules/users/admin.nix` and `modules/users/lgo.nix` via:

```nix
openssh.authorizedKeys.keys = [
  (builtins.readFile ../../machines/miralda/yubikey_ed25519.pub)
];
```

Deploy after updating.

---

## Known Issues and Workarounds

### Issue 1: pcscd "No such device" after boot

**Symptom:** `gpg --card-status` reports `No such device` even though the YubiKey is inserted.

**Cause:** pcscd is socket-activated by default. scdaemon connects before pcscd has finished enumerating the USB device — a startup race condition.

**Fix (in `yubikey.nix`):**
```nix
services.pcscd.enable = true;
systemd.services.pcscd.wantedBy = [ "multi-user.target" ];
```

This starts pcscd eagerly at boot rather than waiting for a socket connection, ensuring the card is enumerated before scdaemon first asks for it.

**Workaround (without reboot):**
```bash
sudo systemctl stop pcscd.socket pcscd.service
sudo systemctl start pcscd.socket
gpg --card-status
```

---

### Issue 2: pinentry-gnome3 not opening during SSH auth

**Symptom:** SSH authentication via YubiKey silently fails — no PIN dialog appears. The gpg-agent log shows `pinentry-gnome3` was launched but immediately exited.

**Cause:** `gpg-agent` only forwards `DISPLAY` to the pinentry subprocess, not `WAYLAND_DISPLAY` or `DBUS_SESSION_BUS_ADDRESS`. pinentry-gnome3 needs D-Bus to open a dialog and the Wayland compositor socket to render it.

**Fix (in `yubikey.nix`):** A wrapper script injects these env vars before calling `pinentry-gnome3`:

```nix
pinentryWrapper = pkgs.writeShellScript "pinentry-gnome3-wayland" ''
  uid=$(id -u)
  wayland=$(ls /run/user/$uid/wayland-* 2>/dev/null \
            | head -1 | xargs basename 2>/dev/null || true)
  if [ -n "$wayland" ]; then
    export WAYLAND_DISPLAY="$wayland"
  fi
  export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
  exec ${pkgs.pinentry-gnome3}/bin/pinentry-gnome3 "$@"
'';
```

The wrapper detects the Wayland socket by scanning `/run/user/<uid>/wayland-*` rather than relying on an env var, which is not available in the agent's subprocess environment.

---

### Issue 3: SSH fails with card-backed ed25519 key (gnupg 2.4.x bug)

**Symptom:** After all the above fixes, SSH authentication still fails. Debug logs show:

- gpg-agent receives the SSH sign request
- No `SETDATA` or `PKSIGN` is ever sent to scdaemon
- The "encoded hash" logged by gpg-agent contains a SHA-1 DigestInfo prefix (wrong for ed25519)
- ECDSA software keys sign successfully; only the card-backed ed25519 key fails

**Cause:** gnupg 2.4.x has a bug in the code path that handles `publickey-hostbound-v00@openssh.com` — an OpenSSH 8.9+ extension that is activated when the server uses certificate-based host keys. When this extension is active, gnupg incorrectly applies a SHA-1 DigestInfo wrapper to the data before sending to scdaemon, which is invalid for ed25519. The sign operation fails internally before scdaemon is ever contacted.

**Fix:** Force the SSH client to use plain `ssh-ed25519` host key verification for this host. This bypasses the cert-based host key and prevents OpenSSH from activating `publickey-hostbound-v00@openssh.com`.

In `modules/users/lgo.nix` (Home Manager):
```nix
programs.ssh = {
  enable = true;
  matchBlocks."miralda.goclan.org" = {
    extraOptions.HostKeyAlgorithms = "ssh-ed25519";
  };
};
```

The server's plain ed25519 host key is added to `/etc/ssh/ssh_known_hosts` system-wide in `machines/miralda/yubikey.nix`:
```nix
programs.ssh.knownHosts."miralda.goclan.org" = {
  publicKey = "ssh-ed25519 AAAA...";
};
```

Get the plain host key with:
```bash
ssh-keyscan -t ed25519 miralda.goclan.org
```

---

### Issue 4: pcscd polkit access denied over SSH

**Symptom:** `gpg --card-status` works locally but fails during SSH sessions (when deploying). pcscd logs show access denied.

**Cause:** pcscd uses PolicyKit to gate card access. By default it only permits "active" logind sessions (i.e. local graphical sessions). SSH sessions don't have an active logind session.

**Fix (in `yubikey.nix`):**
```nix
security.polkit.extraConfig = ''
  polkit.addRule(function(action, subject) {
    if (action.id === "org.debian.pcsc-lite.access_pcsc" ||
        action.id === "org.debian.pcsc-lite.access_card") {
      return polkit.Result.YES;
    }
  });
'';
```

Note: use `extraConfig` (polkit JavaScript rules), not `extraRules`.

---

## Verifying the setup

After all fixes are applied and the system is deployed:

```bash
# 1. Confirm card is detected
gpg --card-status

# 2. Confirm SSH key is exposed
ssh-add -L   # should show ssh-ed25519 ... openpgp:0xXXXXXXXX

# 3. Test SSH
ssh root@miralda.goclan.org

# 4. On success, run deploy
deploy
```

---

## Resetting stuck state

If things get into a bad state (wrong PIN entered, agent confused, etc.):

```bash
# Kill agent and scdaemon — they restart automatically on next use
gpgconf --kill gpg-agent scdaemon

# Re-detect the card
gpg --card-status

# Re-check SSH key exposure
ssh-add -L
```

If the YubiKey's User PIN counter reaches 0 (3 wrong attempts), the PIN is blocked. Use the Admin PIN to unblock:
```bash
gpg --card-edit
gpg/card> passwd
# Choose option 2 to unblock PIN
```
