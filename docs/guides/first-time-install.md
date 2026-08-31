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
  --flake "git+https://git.clan.lol/clan/clan-core?rev=$CLAN_CORE_REV" \
  --ssh-pubkey machines/miralda/yubikey_ed25519.pub \
  --keymap us --language en_US.UTF-8 \
  --disk main /dev/sda \
  flash-installer
```

- `--flake` **must** point to the same clan-core rev this project's `clan` CLI was built from. A mismatch causes `attribute 'vars' missing` at install time. Reading the rev from `flake.lock` (as above) guarantees they match. Note the ref is `git+https://git.clan.lol/...` — clan-core is not on GitHub, so `github:clan-lol/clan-core/<rev>` returns HTTP 404.
- `--ssh-pubkey` takes a **file path**, not key content.
- Machine-specific config is applied later by `clan machines install`. The installer itself is generic.

!!! warning
    `clan flash` wipes the target USB stick entirely. Double-check the device path with `lsblk` before running.

### If the USB stick has been used before

`clan flash` / `disko-install` only zeroes the first 440 bytes (MBR boot code) and clears disk-level headers before re-partitioning. Residual filesystem signatures deeper into the stick (e.g. from a previous NixOS ISO or install) can survive the wipe. On the next re-partition, `blkid` matches those stale signatures and disko **skips `mkfs`** on the affected partition — the subsequent mount then fails with `fsconfig() failed: Structure needs cleaning`.

Pre-wipe the stick before flashing:

```bash
# Unmount any auto-mounts (udisks, GNOME Files, etc.)
sudo umount /run/media/$USER/* 2>/dev/null || true

# Zero the first 200 MB (kills FS signatures in that range)
sudo dd if=/dev/zero of=/dev/sda bs=1M count=200 status=progress conv=fsync

# If the stick was previously partitioned by disko, also clear signatures
# on each existing partition (wipefs on /dev/sda alone only touches disk-level
# headers, not per-partition superblocks past the 200 MB dd range).
sudo wipefs -af /dev/sda?* 2>/dev/null || true
sudo wipefs -af /dev/sda

# Force the kernel to drop its cached partition table
sudo blockdev --rereadpt /dev/sda

# Confirm no residual signatures
sudo blkid /dev/sda*   # should print nothing
```

!!! danger "If `clan flash` fails mid-run, check `/boot` immediately"
    `disko-install` mounts the target's ESP under `/mnt/disko-install-root/boot` while running `nixos-install`. If the run crashes, this mount can leak into the host namespace and take over the host's `/boot` — a subsequent kernel/bootloader update would then write to the USB stick instead of the host's real ESP, potentially bricking boot on next reboot.

    After any failed `clan flash`, run:

    ```bash
    findmnt /boot          # must show the host's real ESP (e.g. /dev/nvme0n1p1)
    ```

    If it shows `/dev/sda*` instead:

    ```bash
    sudo umount /boot
    sudo mount /dev/nvme0n1p1 /boot   # or whichever is the host's real ESP
    findmnt /boot                     # verify
    ```

    Only after `/boot` is restored, clean up disko's leftover mounts and retry:

    ```bash
    sudo umount -R /mnt/disko-install-root 2>/dev/null || true
    sudo rm -rf /mnt/disko-install-root
    ```

!!! note "`rmdir: Directory not empty` at the end means success"
    `clan flash` currently returns exit code 1 whenever the final `rmdir /mnt/disko-install-root` fails, even when `disko-install succeeded` and the boot loader installed cleanly. Scroll up in the output — if you see `disko-install succeeded` and `Installation finished. No error reported.`, the stick is good. Clean up the leftover directory afterwards:

    ```bash
    sudo umount -R /mnt/disko-install-root 2>/dev/null || true
    sudo rm -rf /mnt/disko-install-root
    ```

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

### Step 3a — `ernst`-only: install-time chicken-and-egg fixes

Two secrets that ernst's config assumes exist on `/persist` are not generated by `clan machines install`. Both fail loudly, but at inconvenient moments — the first blocks the install from completing; the second lets it complete but drops the first boot into emergency mode. Handle both from the installer session before considering the box "installed".

**Fix 1 — initrd SSH host key (before the bootloader install completes)**

`clanarchy.initrdSsh.enable = true` in `machines/ernst/networking.nix` makes the initrd cpio depend on `/persist/etc/secrets/initrd/ssh_host_ed25519_key`. Without it, `switch-to-configuration boot` aborts with `cp: cannot stat '/persist/etc/secrets/initrd/ssh_host_ed25519_key': No such file or directory` and no loader entry is written.

`clan machines install ernst ...` will run to that point and fail. **Do not re-run install** — disko would wipe `/persist` again and re-hit the same wall. Instead, drop the key onto the installer-mounted `/mnt/persist` and re-run only the bootloader step from a chroot:

```bash
ssh root@<installer-ip> 'mkdir -p /mnt/persist/etc/secrets/initrd'
ssh root@<installer-ip> 'ssh-keygen -t ed25519 -N "" -C ernst-initrd -f /mnt/persist/etc/secrets/initrd/ssh_host_ed25519_key'
ssh root@<installer-ip> 'chmod 400 /mnt/persist/etc/secrets/initrd/ssh_host_ed25519_key'
ssh root@<installer-ip> 'NIXOS_INSTALL_BOOTLOADER=1 nixos-enter --root /mnt -- /nix/var/nix/profiles/system/bin/switch-to-configuration boot'
```

The last command should end with `Updated EFI boot entry "Linux Boot Manager"` (or `Created ...` on truly fresh hardware) and no `cp` error.

**Fix 2 — rekey `zdata` from passphrase to keyfile (before first real boot)**

Disko provisions `zdata` with `keyformat=passphrase, keylocation=prompt` (matching what disko.nix declares at install time). At runtime `boot.zfs.extraPools = [ "zdata" ]` expects to load the key non-interactively from `/persist/zdata.key`. If you reboot before rekeying, `zfs-import-zdata.service` waits for a passphrase no one is entering, `srv-{media,state,games}.mount` timeout, `local-fs.target` fails, and systemd falls to emergency — where `sulogin` refuses to give a shell because ernst's `root` account has no password (only `admin` does).

Prevent all of that from the same installer session. Note that `/persist` is mounted at the real path `/persist` (not under `/mnt`) so the URI baked into the pool metadata resolves at the time of `change-key`:

```bash
ssh root@<installer-ip>

# Reachable-from-real-root mount of /persist
umount -R /mnt 2>/dev/null || true
zpool export zroot 2>/dev/null || true
zpool import -f zroot
zfs load-key zroot            # enter zroot passphrase
mkdir -p /persist
mount -t zfs zroot/persist /persist

# Import zdata with its install-time passphrase
zpool import -f zdata
zfs load-key zdata            # enter the zdata passphrase you set during install

# Generate raw key and rekey the pool
umask 077
dd if=/dev/urandom of=/persist/zdata.key bs=32 count=1 status=none
chmod 400 /persist/zdata.key
zfs change-key -o keyformat=raw -o keylocation=file:///persist/zdata.key zdata

# Confirm and clean up
zfs get keyformat,keylocation zdata
# expected: keyformat=raw, keylocation=file:///persist/zdata.key
zpool export zdata
umount /persist
zpool export zroot
reboot
```

Pull the USB during POST. First boot should prompt for the zroot passphrase in stage 1 (TV or `ssh -p 2222 root@ernst.skynet.lan` — the initrd-ssh key from Fix 1 authenticates that connection) and then silently import zdata in stage 2.

Verify from miralda:

```bash
ssh-keygen -R ernst.skynet.lan
ssh root@ernst.skynet.lan 'zpool status; mount | grep -E "on /(boot|srv|var/lib/sops)"; systemctl --failed --no-pager'
```

Both pools ONLINE, five expected mounts present, zero failed units.

## Notes per machine

- **`miralda`** — YubiKey-first. After first login, run `age-plugin-yubikey --identity >> ~/.config/sops/age/keys.txt` so sops can decrypt secrets that were encrypted to your PIV recipient.
- **`biene`** — no YubiKey. Noctalia boots with declarative defaults; Sabine saves her layout as a Shell Profile the first time she logs in (see [Noctalia profiles](noctalia-profiles.md)).
- **`birte`** — Steam Deck. Boot with the installer USB via a USB-C hub. Jovian-NixOS provisions the `deck` user; Steam Gaming Mode starts on login. Use "Switch to Desktop" for the KDE Plasma 6 session. Unlike the rest of the fleet birte is **btrfs, not ZFS** (`clanarchy.rootfs = "btrfs"`) — out-of-tree OpenZFS would gate the Valve kernel Jovian ships. Two consequences at install time: there is **no blank-snapshot step to run by hand** (the stage-1 rollback service seeds `@root-blank` from the pristine `@root` on first boot), and **`deck`'s home is persistent** — only `/` is rolled back, so Steam and gamescope state survive reboots. The game library sits on its own `@games` subvol mounted at `/games`, and is symlinked into `~deck/.local/share/Steam` by a tmpfiles `L+` rule in `deck.nix`. It is deliberately *not* mounted at that path directly: `.local/share` is restored as an impermanence bind-mount, which would shadow anything mounted underneath it. The same rule re-forces the symlink after every rollback, and a `d` rule fixes ownership — a fresh subvolume is `root:root`.
- **`ernst`** — headless. Configure the installer over serial or a temporary display; the running system has no compositor. Deploys are SSH-only. **Before treating install as done, work through [Step 3a](#step-3a-ernst-only-install-time-chicken-and-egg-fixes)** — the initrd-ssh host key and the `zdata` keyfile both need to be placed manually on `/persist` from the installer session; the first breaks the bootloader install, the second drops the first boot into emergency mode. Also hits [`yubikey-ssh-setup.md` Issue 3](yubikey-ssh-setup.md#issue-3-ssh-fails-with-card-backed-ed25519-key-gnupg-24x-bug) (card-backed ed25519 SSH auth fails against ernst's cert host key); miralda's `lgo` HM ssh settings apply the `PubkeyAuthentication=unbound` workaround to `ernst`/`ernst.skynet.lan`/`10.0.50.10`/its ZeroTier IPv6 so plain `ssh root@ernst.skynet.lan` and `clan machines update ernst` both work.
