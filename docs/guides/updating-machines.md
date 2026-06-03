# Updating machines

This guide explains how to push a new configuration to an existing machine — both from inside and outside the devShell.

---

## Quick reference

| Command | Where | What it does |
|---------|-------|-------------|
| `deploy [boot\|switch]` | devShell | nixos-rebuild → miralda |
| `deploy-biene [boot\|switch]` | devShell | nixos-rebuild → biene |
| `clan machines update <name>` | devShell | nixos-rebuild via clan (re-evaluates vars/secrets) |
| `nixos-rebuild switch --flake .#<name> ...` | anywhere | full manual form |

---

## Inside the devShell

The devShell (enter with `nix develop` or via direnv) exposes shorthand functions:

```bash
# miralda (Framework 13 laptop, root@miralda.goclan.org)
deploy           # switch — activate immediately
deploy boot      # stage for next boot only

# biene (Framework 13 laptop, root@biene.skynet.lan)
deploy-biene
deploy-biene boot
```

Both functions pass `--no-reexec` and `-j auto`. Never add `--build-host localhost` or `--fast`.

`deploy-biene` targets `biene.local` by default (mDNS over ZeroTier — works from any network as long as ZeroTier is up).
Override the target host with `BIENE_HOST`:

```bash
# Use the ZeroTier IPv6 if biene.local hasn't resolved yet
BIENE_HOST=fdda:106a:123a:d561:1099:93da:ef5d:598c deploy-biene

# Use the LAN hostname when on the home network
BIENE_HOST=biene.skynet.lan deploy-biene

# Use the LAN IP as a last resort
BIENE_HOST=10.0.10.105 deploy-biene
```

See [Networking — biene not reachable from a different network](networking.md#biene-not-reachable-from-a-different-network) for connectivity checks before deploying.

---

## Outside the devShell

Run the full command directly. Nix is available system-wide:

```bash
nix --extra-experimental-features 'nix-command flakes' run \
  nixpkgs#nixos-rebuild -- switch \
  --flake .#miralda \
  --target-host root@miralda.goclan.org \
  --no-reexec -j auto
```

Or enter the devShell one-shot:

```bash
nix develop --command deploy
nix develop --command deploy-biene
```

---

## `deploy` vs `clan machines update`

Use `deploy` / `deploy-biene` for day-to-day config changes — it's faster because it skips clan's inventory evaluation.

Use `clan machines update <name>` when you change **secrets or clan vars** (e.g. after `clan vars generate`, adding a new var generator, or rotating age keys). clan re-evaluates all var file paths before activating.

```bash
# After changing sops or vars config:
clan machines update miralda
clan machines update biene
```

!!! warning "clan health check"
    `clan machines update` runs a health check across **all** machines before proceeding. If any machine has vars that need re-encryption, the update is blocked. Use `clan vars fix <name>` to repair, or fall back to `deploy` to bypass the health check entirely.

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
