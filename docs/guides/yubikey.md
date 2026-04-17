# YubiKey

This guide covers how the YubiKey is integrated into clanarchy across three distinct use-cases:

1. **SSH authentication** — via the GnuPG ed25519 auth subkey
2. **Age encryption** — via `age-plugin-yubikey` for clan vars / sops
3. **PIV operations** — `ykman` over SSH sessions

Configuration lives in [`machines/miralda/yubikey.nix`](https://github.com/lutzgo/clanarchy/blob/main/machines/miralda/yubikey.nix).

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
  pinentryPackage = pkgs.pinentry-gnome3;
};
```

### Pinentry on Wayland

`gpg-agent` only forwards `DISPLAY` (X11) to pinentry, not `WAYLAND_DISPLAY`. When an SSH session triggers a PIN prompt, pinentry-gnome3 can't open a dialog because it has no Wayland socket. A small wrapper script injects the right environment:

```bash
uid=$(id -u)
wayland=$(ls /run/user/$uid/wayland-* 2>/dev/null | head -1 | xargs basename)
export WAYLAND_DISPLAY="$wayland"
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
exec pinentry-gnome3 "$@"
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

## Age encryption (clan vars / sops)

The YubiKey PIV applet holds an **age recipient** via `age-plugin-yubikey`. This allows clan vars secrets and sops files to be encrypted to the YubiKey — decryptable only when the key is inserted and the PIN is entered.

### devShell requirement

`age-plugin-yubikey` must be in the devShell for any `clan vars generate` or sops re-encryption operation that targets a YubiKey recipient:

```nix
packages = with pkgs; [
  age-plugin-yubikey
  # ...
];
```

If you run `clan vars generate` without the plugin in `PATH`, the generation succeeds but the secret is not encrypted to the YubiKey recipient.

### Re-encrypting sops files

After rotating the age key or adding a new recipient:

```bash
# From inside nix develop
sops updatekeys sops/<file>.yaml
```

The YubiKey must be inserted and PIN available.

---

## Troubleshooting

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

### PIN prompt doesn't appear (Wayland)

The pinentry wrapper reads `wayland-*` from `/run/user/$uid/`. If the Wayland session hasn't created the socket yet (e.g. prompt fires during greeter), there's nothing to inject. Entering the PIN via the terminal fallback (`pinentry-curses`) is not configured — use the graphical session.

### sops decrypt fails after ZFS rollback

After a rollback, the age identity file path referenced in `.sops.yaml` might not exist until impermanence re-creates the bind mounts. Ensure `/var/lib/sops-nix` is in the persisted paths (it is, in `impermanence.nix`).
