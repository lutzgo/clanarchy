# Impermanence

Root (`/`) and home (`/home`) are ZFS datasets that roll back to a `@blank` snapshot on every boot. Nothing survives a reboot unless it is explicitly listed in `environment.persistence."/persist"`.

This makes the system self-healing — misconfigured files, leftover state, and stale caches are automatically cleared — at the cost of having to declare everything you want to keep.

---

## How it works

The rollback runs as a oneshot systemd service in the initrd (stage 1), before any filesystems are mounted:

```nix
boot.initrd.systemd.services.rollback = {
  wantedBy = [ "initrd.target" ];
  after    = [ "zfs-import-zroot.service" ];
  before   = [ "sysroot.mount" ];
  script   = ''
    zfs rollback -r zroot/root@blank || true
    zfs rollback -r zroot/home@blank || true
  '';
};
```

The `@blank` snapshots are taken once, immediately after a fresh install, while both datasets are empty.

### Creating the @blank snapshots (post-install ritual)

After `clan machines install` finishes and the machine has booted for the first time:

```bash
# SSH in as root
ssh root@<machine>

# Snapshot the empty root and home (do this before creating any users/state)
zfs snapshot zroot/root@blank
zfs snapshot zroot/home@blank
```

If you forget and the datasets already have state, you can still snapshot — the rollback will just restore to that moment instead of a truly empty state.

---

## Persisted paths

Persist paths are declared in two places:

| Location | What goes there |
|----------|----------------|
| `machines/<name>/impermanence.nix` | System-level paths (`/var/lib/…`, `/etc/machine-id`) |
| `modules/users/<user>.nix` | Per-user paths (`~/.config`, `~/.local/share`, etc.) |

### miralda — system paths

```
/var/lib/nixos       — NixOS uid/gid assignments
/var/lib/sops-nix    — age identity decrypted at activation
/var/log             — systemd journal and other logs
/var/lib/systemd     — random seed, machine-id journal cursor
/var/lib/syncthing   — device DB, peer state, runtime config
/var/lib/fprint      — enrolled fingerprints (fprintd)
/var/lib/flatpak     — installed apps, runtimes, remotes
/etc/machine-id      — stable identity for systemd/journal
```

### biene — system paths

```
/var/lib/nixos
/var/log
/var/lib/systemd
/etc/machine-id
```

### Per-user paths — lgo

```
~/.gnupg             — GPG keyring with YubiKey stubs
~/.claude            — Claude Code credentials + session data
~/.config            — gh auth, helix, zellij, noctalia settings
~/.local/share
~/.cache/noctalia    — shell-state.json (version tracking)
~/.cache/zellij      — compiled WASM + plugin permission cache
~/Pictures           — includes Wallpapers/ for Noctalia
~/Documents, ~/Downloads, ~/Music, ~/Videos, ~/Desktop, ~/Projects, ~/Public
~/.age/yubikey-identity.txt  — PIV-backed age identity
```

### Per-user paths — sabine

```
~/.config, ~/.local/share, ~/.cache
~/Documents, ~/Downloads, ~/Pictures, ~/Music, ~/Videos, ~/Desktop, ~/Public
```

---

## Adding a new persisted path

Add it to the appropriate `environment.persistence."/persist"` block. For system paths, edit `machines/<name>/impermanence.nix`. For user paths, edit `modules/users/<user>.nix`.

```nix
environment.persistence."/persist" = {
  directories = [
    "/var/lib/my-service"   # persists the entire directory
  ];
  files = [
    "/etc/some-config"      # persists a single file
  ];
};
```

For per-user paths inside a user module:

```nix
environment.persistence."/persist".users.<name> = {
  directories = [ ".config/my-app" ];
};
```

After adding a path, deploy the configuration. The bind mount is created on next activation — the path doesn't need to exist beforehand.

!!! warning "Forgotten paths"
    If a service writes to a path that isn't persisted and you reboot, that state is gone. Common symptoms: service re-initialises on every boot, settings reset, credentials lost. Add the path and redeploy.

---

## Troubleshooting

### State lost after reboot

The path is not in the persist list. Find where the service stores state:

```bash
systemctl cat <service> | grep -E "State|Cache|Runtime"
ls /var/lib/<service>
```

Then add it to `impermanence.nix` and redeploy.

### `/persist` not mounted at boot

`fileSystems."/persist".neededForBoot = true` must be set in the machine config. Without it, stage 2 may try to activate users before `/persist` is mounted, causing bind mounts to fail silently.

### `machine-id` changes after rollback

`/etc/machine-id` must be in the `files` list (not `directories`). A changing machine-id breaks the systemd journal, D-Bus, and services that rely on stable identity.

## Snapshots alongside the rollback

The `@blank` rollback discards everything not declared in `environment.persistence`. Automatic snapshots are the complementary half: they let you recover from a *bad write* to data that survived, rather than from an unwanted write to data that didn't.

clan-core enables `services.zfs.autoSnapshot` fleet-wide, but `zfs-auto-snapshot` only acts on datasets carrying the `com.sun:auto-snapshot` property. Machines installed before [#38](https://github.com/lutzgo/clanarchy/pull/38) do not have it set and need a one-off — see [Runbook: ZFS auto-snapshot opt-in](../runbooks/zfs-auto-snapshot-optin.md).
