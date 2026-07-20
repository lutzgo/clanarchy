# First-time machine install

Use this when the target machine has no NixOS on it yet, or when disko must re-partition (new disk, layout change). The process is a two-step: flash a Clan installer USB, boot the target from it, then run `clan machines install <name>` from an existing clan machine.

For an in-place rebuild on an already-installed machine, use `deploy` / `deploy-<machine>` instead — see [Deploying and testing](deploy.md).

## Step 1 — Create the installer USB

The installer needs an SSH key so that `clan machines install` can log in. Use the YubiKey ed25519 pubkey already stored at `machines/miralda/yubikey_ed25519.pub` — it's authorised on every machine, so `miralda` can then SSH into the installer without extra setup.

From the devShell, with the USB stick identified via `lsblk` (replace `/dev/sda` with the actual device):

```bash
# Get the exact clan-core rev pinned in this flake
CLAN_CORE_REV=$(nix flake metadata --json . | jq -r '.locks.nodes["clan-core"].locked.rev')

clan flash write \
  --flake "github:clan-lol/clan-core/$CLAN_CORE_REV" \
  --ssh-pubkey machines/miralda/yubikey_ed25519.pub \
  --keymap us --language en_US.UTF-8 \
  --disk main /dev/sda \
  flash-installer
```

- `--flake` **must** point to the same clan-core rev this project's `clan` CLI was built from. A mismatch causes `attribute 'vars' missing` at install time. Reading the rev from `flake.lock` (as above) guarantees they match.
- `--ssh-pubkey` takes a **file path**, not key content.
- Machine-specific config is applied later by `clan machines install`. The installer itself is generic.

!!! warning
    `clan flash` wipes the target USB stick entirely. Double-check the device path with `lsblk` before running.

## Step 2 — Boot the target machine

Insert the USB into the target, boot from it (F12 or the machine's BIOS boot menu). The installer brings up a minimal NixOS with SSH on port 22.

Find the installer's IP (your router's leases page, or `arp-scan -l` from another machine on the LAN):

```bash
ssh root@<installer-ip>      # authenticates via the embedded YubiKey pubkey
```

## Step 3 — Install

From the devShell on `miralda`:

```bash
clan machines install <machine> --target-host root@<installer-ip>
```

This runs disko (partitions and formats the disk as declared in `machines/<machine>/disko.nix`) then installs NixOS with all clan vars applied.

After the machine reboots into the new system, switch to the ordinary deploy workflow — see [Deploying and testing](deploy.md).

## Notes per machine

- **`miralda`** — YubiKey-first. After first login, run `age-plugin-yubikey --identity >> ~/.config/sops/age/keys.txt` so sops can decrypt secrets that were encrypted to your PIV recipient.
- **`biene`** — no YubiKey. Noctalia boots with declarative defaults; Sabine saves her layout as a Shell Profile the first time she logs in (see [Noctalia profiles](noctalia-profiles.md)).
- **`birte`** — Steam Deck. Boot with the installer USB via a USB-C hub. Jovian-NixOS provisions the `deck` user; Steam Gaming Mode starts on login. Use "Switch to Desktop" for the KDE Plasma 6 session.
- **`ernst`** — headless. Configure the installer over serial or a temporary display; the running system has no compositor. Deploys are SSH-only. Also hits [`yubikey-ssh-setup.md` Issue 3](yubikey-ssh-setup.md#issue-3-ssh-fails-with-card-backed-ed25519-key-gnupg-24x-bug) (card-backed ed25519 SSH auth fails against ernst's cert host key); miralda's `lgo` HM ssh settings apply the `PubkeyAuthentication=unbound` workaround to `ernst`/`ernst.skynet.lan`/`10.0.50.10`/its ZeroTier IPv6 so plain `ssh root@ernst.skynet.lan` and `deploy-ernst` both work.
