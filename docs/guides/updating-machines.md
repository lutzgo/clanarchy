# Updating machines

This guide explains how to push a new configuration to an existing machine — both from inside and outside the devShell.

---

## Quick reference

| Command | What it does |
|---------|-------------|
| `clan machines update <name>` | build and activate on that machine |
| `clan machines update <name> --target-host root@host` | same, to a different address |
| `clan vars generate <name>` | (re)generate secrets — run before updating, when they changed |
| `clan machines generations <name>` | what has been deployed there |

---

## Deploying

```bash
nix develop                        # or direnv
clan machines update miralda
clan machines update biene
```

Clan resolves each machine's address from its own deployment configuration, so
nothing needs passing in the normal case. When the configured name isn't
resolving — biene on a foreign network before ZeroTier is up, say — override it
for that invocation:

```bash
# ZeroTier IPv6 (get it from biene: ip -6 addr show altname zerotier)
clan machines update biene --target-host root@<biene-zt-ipv6>

# LAN hostname when on the home network
clan machines update biene --target-host root@biene.skynet.lan
```

See [Networking — biene not reachable from a different network](networking.md#biene-not-reachable-from-a-different-network) for connectivity checks before deploying.

To build somewhere other than where you're deploying — useful for birte, which
is slow — use `--build-host`.

---

## Outside the devShell

```bash
nix develop --command clan machines update miralda
```

Or drive `nixos-rebuild` yourself, which is what to reach for in the one case
clan doesn't cover — staging a change for the next boot without activating it:

```bash
nix --extra-experimental-features 'nix-command flakes' run \
  nixpkgs#nixos-rebuild -- boot \
  --flake .#miralda \
  --target-host root@miralda.goclan.org \
  --no-reexec -j auto
```

Never add `--build-host localhost` or `--fast`.

---

## Vars and the health check

`clan machines update` re-evaluates every var file path before activating, so
changing a generator means regenerating first:

```bash
clan vars generate miralda
clan machines update miralda
```

!!! warning "clan health check"
    `clan machines update` runs a health check across **all** machines before
    proceeding. If any machine has vars needing re-encryption, the update is
    blocked — repair with `clan vars fix <name>`. This used to be listed as a
    reason to fall back to the `deploy` helper; that helper is gone, and
    bypassing the check was never really a fix. Repair the vars.

---

## YubiKey SSH signing

SSH auth to target machines uses the YubiKey's OpenPGP auth subkey via `gpg-agent`. Two things must be true:

1. **The OpenPGP User PIN must not be blocked.** Check with `gpg --card-status` — look for `PIN retry counter : 3 ...`. If it reads `0`, unblock it with the Admin PIN:
   ```bash
   gpg --card-edit
   # → admin → passwd → option 2 (Unblock PIN)
   ```

2. **`HostKeyAlgorithms=ssh-ed25519` must be set for each target host.** This works around a gnupg 2.4.x bug where the `publickey-hostbound-v00@openssh.com` SSH extension causes card-backed signing to silently fail. The SSH config in `modules/users/lgo.nix` already covers `miralda.goclan.org` and `biene.skynet.lan / 10.0.10.105`. Add a new `matchBlocks` entry for every new machine you deploy to.

---

## Troubleshooting

### `sign_and_send_pubkey: signing failed … agent refused operation`

1. Check the card is inserted: `ykman list`
2. Check PIN retry counter: `gpg --card-status | grep 'PIN retry'`
3. Restart scdaemon: `gpgconf --kill scdaemon`
4. Verify the SSH config has `HostKeyAlgorithms=ssh-ed25519` for this host (see above)

### Build succeeds but copy fails (DNS / network)

The build happens locally; only the store closure is copied to the target. If hostname resolution fails, use the IP directly with `--target-host root@<ip>`.
