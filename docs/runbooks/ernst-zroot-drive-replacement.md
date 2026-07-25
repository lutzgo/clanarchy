# ernst — zroot mirror drive replacement

Runbook for replacing the failing PM1643a in `system-a`. Assumes ernst is
currently running the previous generation; the failing drive has been offline
from the SAS bus since 2026-07-25 02:46 CEST.

**Path: cold-swap** (enclosure does not support hot-swap). This means power off
→ physical swap → boot from installer USB → provision new ESP + attach mirror
half from a chroot → reboot into installed system.

---

## Quick reference — drive identities

| Role | Detail |
|---|---|
| **REMOVE** (broken, slot 12) | Serial `S5G1NC0T602213`, WWN `0x5002538b7263f800`, SAS addr `0x5002538b7263f802`, model `SAMSUNG MZILT960HBHQ` (PM1643a 960 GB) |
| **KEEP** (survivor, system-b) | Serial `S5G1NC0T203063`, WWN `0x5002538b722787f0`, model `SAMSUNG MZILT960HBHQ` |
| Enclosure | Logical ID `0x500062b204731180`, slot `12` |
| Replacement to order | Samsung PM1643a 960 GB SAS 12 Gb/s, MPN `MZILT960HBHQ` (SKU commonly `MZILT960HBHQ-00007`) |

> **Reminder** — do not reboot ernst until either the replacement drive is
> installed and the bootloader written to the new ESP, or an alternative ESP
> has been provisioned. The current running kernel is safe; a cold reboot with
> system-a absent means no bootable EFI partition.

---

## Contents

0. [Prerequisites](#0-prerequisites-before-touching-hardware)
1. [Identify the broken drive physically](#1-identify-the-broken-drive-physically)
2. [Prepare the pool (while ernst is still up)](#2-prepare-the-pool-while-ernst-is-still-up)
3. [Cold swap](#3-cold-swap)
4. [Provision the new drive from the installer](#4-provision-the-new-drive-from-the-installer)
5. [Update flake and re-deploy](#5-update-flake-and-re-deploy)
6. [Rollback / troubleshooting](#6-rollback--troubleshooting)
7. [Pre-flight checklist](#pre-flight-checklist)

---

## 0. Prerequisites before touching hardware

### 0a. Build the installer USB (from miralda)

The installer must match the flake's `clan-core` rev, otherwise `clan flash`
build/eval will drift from the running config. Same rule as the initial install
(see `CLAUDE.md` §Installing a Machine from Scratch).

```bash
REV=$(nix flake metadata --json . | jq -r '.locks.nodes."clan-core".locked.rev')

# lsblk first to confirm the USB device path — clan flash wipes it entirely.
lsblk

clan flash write \
  --flake "git+https://git.clan.lol/clan/clan-core?ref=$REV" \
  --ssh-pubkey machines/miralda/yubikey_ed25519.pub \
  --disk main /dev/sdX      # X = your USB stick — CONFIRM before running
```

You'll need the zroot passphrase when the installer imports the pool. Have it
ready (password manager entry; NOT relying on initrd-ssh, which only helps on
the installed system's stage 1).

### 0b. Restore SSH access to ernst

If SSH is still refused, log in physically on the ernst console as `admin` and:

```bash
sudo systemctl restart sshd
sudo journalctl -u sshd -n 30 --no-pager
```

Most likely a missing host key path from the failed sops activation. Try a
plain restart first before chasing sops.

### 0c. Fix `/var/lib/sops-nix/key.txt`

Diagnostic — run once SSH is back:

```bash
ls -la /var/lib/sops-nix/ /persist/var/lib/sops-nix/ 2>&1
mount | grep sops-nix
```

If the persist dir is empty, the age private key needs regenerating via
`clan vars generate ernst` from miralda and copying over. **Do not proceed to
drive replacement until deploys work again** — you need a working deploy to
bless the new drive layout.

### 0d. Confirm ernst has not been rebooted

```bash
uptime
zpool status zroot
```

Uptime should be counted from before the 2026-07-24 15:01 dropout; zroot should
show `wwn-0x5002538b7263f800-part3 FAULTED` under `mirror-0`.

---

## 1. Identify the broken drive physically

1. Open the enclosure/chassis.
2. Look at the tray in **slot 12** — activity/status LED should be dark or
   amber. Neighbours will have green blinks on I/O.
3. Pull that tray.
4. Read the label on the drive itself. **Confirm serial `S5G1NC0T602213`
   before removing it from the chassis.**
5. If the serial doesn't match: **stop**. Slot numbering on some backplanes
   doesn't match mpt3sas enumeration. Use the SES procedure below.

### If unsure which slot is which

Since the broken drive isn't on the bus right now, you can't blink its
locator. Blink each OTHER drive in turn — the one that doesn't respond is
the failed one.

```bash
# List enclosure services devices
ls /dev/sg* /dev/bsg/ 2>&1

# Read enclosure element status (serials + slot correspondence)
for sg in /dev/sg*; do
  echo "=== $sg ==="
  sg_ses --page=aes "$sg" 2>/dev/null \
    | grep -E "Element index|SAS addr|slot|serial" | head -20
done

# Blink LOCATE LED on a suspected slot
sg_ses --index=<N> --set=locate /dev/sgX

# Turn it off again
sg_ses --index=<N> --clear=locate /dev/sgX
```

---

## 2. Prepare the pool (while ernst is still up)

Do this from ernst over SSH **before powering off**. It cleanly removes the
failing drive from ZFS's view so the imported pool in the installer doesn't
try to reach it.

```bash
# Confirm state
zpool status zroot
# Expected: mirror-0 with the FAULTED half named wwn-0x5002538b7263f800-part3

# Detach the failed half so ZFS stops trying to talk to it.
# Pool becomes single-vdev (still ONLINE, no redundancy — expected until §4).
zpool detach zroot wwn-0x5002538b7263f800-part3

# Verify:
zpool status zroot
# Expected: no mirror-0 wrapper anymore, just wwn-0x5002538b722787f0-part1 ONLINE.
```

If the swap partition is still referenced, turn it off:

```bash
swapon --show
swapoff /dev/mapper/disk-system-a-swap 2>/dev/null || true
```

---

## 3. Cold swap

1. Clean shutdown from ernst:

   ```bash
   systemctl poweroff
   ```

2. Wait for full power-off. Verify PSU LED / chassis is quiet.

3. Physically swap the drive in slot 12:
   - Pull the failing tray (confirmed by serial in §1).
   - Transfer screws to the replacement PM1643a in the same caddy positions.
   - Insert into slot 12; push firmly until the latch clicks.

4. Insert the installer USB. Power on. Enter the boot menu (typically **F11**
   on ASUS X870E boards) and boot the USB — **not** the internal disk.

5. Once at the installer shell, verify the new drive enumerated:

   ```bash
   lsblk -o NAME,SIZE,SERIAL,WWN
   ```

   Expect both PM1643a 960 GB drives visible (survivor + new), plus the six
   15.36 TB data disks. The new drive has an empty/unknown partition table.

---

## 4. Provision the new drive from the installer

### 4a. Import the existing zpool

```bash
# Import read-write, root-relative to /mnt (installer convention)
zpool import -f -R /mnt zroot

# Unlock the encrypted pool
zfs load-key zroot     # prompt: zroot passphrase

# Mount legacy datasets — matches machines/ernst/disko.nix zpool.zroot.datasets
mount -t zfs zroot/root    /mnt
mount -t zfs zroot/nix     /mnt/nix
mkdir -p /mnt/home /mnt/persist /mnt/tmp
mount -t zfs zroot/home    /mnt/home
mount -t zfs zroot/persist /mnt/persist
mount -t zfs zroot/tmp     /mnt/tmp
```

### 4b. Identify the new drive's stable identifiers

```bash
# The new drive is the only 960 GB SAS SSD that isn't wwn-0x5002538b722787f0
lsblk -o NAME,SIZE,SERIAL,WWN

# Set variables (replace X and the WWN):
NEW_DEV=/dev/sdX
NEW_WWN=0x5002538b......      # copy from the lsblk output

# Sanity
smartctl -i "$NEW_DEV" | grep -E "Model|Serial|Capacity"
```

### 4c. Wipe any existing partition table

```bash
wipefs -a "$NEW_DEV"
sgdisk -Z  "$NEW_DEV"
```

### 4d. Recreate the disko partition layout

Matches `machines/ernst/disko.nix` → `disk.system-a`: 1 GiB ESP, 16 GiB swap,
remainder ZFS.

```bash
sgdisk \
  -n 1:0:+1G   -t 1:EF00 -c 1:disk-system-a-ESP  \
  -n 2:0:+16G  -t 2:8200 -c 2:disk-system-a-swap \
  -n 3:0:0     -t 3:BF01 -c 3:disk-system-a-zfs  \
  "$NEW_DEV"

partprobe   "$NEW_DEV"
udevadm settle

# Verify partlabels exist
ls -l /dev/disk/by-partlabel/ | grep disk-system-a
```

### 4e. Format and mount the new ESP

```bash
mkfs.vfat -F 32 -n ESP /dev/disk/by-partlabel/disk-system-a-ESP

# Mount it into the target root's /boot
mount /dev/disk/by-partlabel/disk-system-a-ESP /mnt/boot
ls /mnt/boot          # empty; bootloader install fills it
```

Swap needs no manual formatting — `randomEncryption = true` in disko.nix
means `systemd-cryptsetup@disk-system-a-swap.service` creates a fresh key +
swap header each boot.

### 4f. Attach the new drive to the zroot mirror

```bash
zpool attach zroot \
  wwn-0x5002538b722787f0-part1 \
  /dev/disk/by-partlabel/disk-system-a-zfs
```

Resilver kicks off immediately. On mirrored SSDs of ~15 GB of used space
this takes minutes, not hours. Wait for it to finish before rebooting:

```bash
watch -n 5 'zpool status zroot | head -20'
# Ctrl-C once "resilver completed" appears and the pool is ONLINE
# with no read/write/checksum errors on either half.
```

### 4g. Install the bootloader from a chroot

```bash
nixos-enter --root /mnt

# Inside the chroot — write systemd-boot to the new ESP
/run/current-system/bin/switch-to-configuration boot

# Sanity check
ls /boot/loader/entries
exit
```

### 4h. Clean unmount and reboot

```bash
umount -R /mnt
zpool export zroot

# Remove USB now, then:
systemctl reboot
```

Enter the UEFI boot menu (F8/F11 on ASUS) and select the internal disk. If
the firmware still prefers a stale EFI entry pointing at the old drive,
temporarily boot via the new drive's UEFI entry — you'll clean this up in §5.

---

## 5. Update flake and re-deploy

### 5a. Update `disko.nix` on miralda

Edit `machines/ernst/disko.nix` around line 33 to reference the new drive:

```nix
disk.system-a = {
  type = "disk";
  device = "/dev/disk/by-id/wwn-<NEW_WWN>"; # PM1643a 960G  <NEW_SERIAL>
  ...
};
```

Commit on a branch and open a PR:

```bash
git switch -c fix/ernst-replace-system-a
git add machines/ernst/disko.nix
git commit -m "ernst: replace system-a disk (new WWN <NEW_WWN>)"
push origin fix/ernst-replace-system-a
gh pr create --title "ernst: replace failed system-a SAS SSD" \
  --body "Replaces the flapping PM1643a in slot 12. New WWN: <NEW_WWN>."
```

### 5b. Deploy

Bootloader install will now succeed against the correct WWN, and clean up
any UEFI entry drift:

```bash
deploy-ernst switch
```

### 5c. Verify boot resilience

```bash
ssh root@ernst.skynet.lan 'systemctl reboot'
# wait 60–90 s
ssh root@ernst.skynet.lan '
  uptime
  zpool status zroot
  systemctl status container@jellyfin --no-pager | head -5
'
```

**Green result**: fresh uptime, `zroot` ONLINE with *both* `mirror-0` halves
ONLINE and zero errors, jellyfin container active. Runbook complete.

---

## 6. Rollback / troubleshooting

- **`zpool attach` fails with "device is too small"** — new drive has slightly
  fewer sectors than the survivor. Same-model PM1643a should match exactly.
  If it doesn't, use `zpool attach -f` after confirming the delta is trivial
  (< 1 MB), or check the SKU.

- **New drive also flaps** — it's the backplane/HBA, not the drive. Move it
  to a different slot; if the problem follows the drive it's the drive, if
  it stays on the slot it's the backplane / cable.

- **Bootloader install fails in chroot** — check `mount | grep /mnt/boot`
  and `ls /mnt/boot`. The ESP must be mounted and writable. If
  `by-partlabel` doesn't resolve, `udevadm trigger && udevadm settle` and
  remount.

- **Pool import fails with "one or more devices is currently unavailable"**
  — after the detach in §2, the pool has a single vdev; if the survivor
  itself is now flaking (worst case), `zpool import -F zroot` may work as a
  last resort. Only try this if the survivor is healthy — otherwise stop
  and restore from backup.

- **Resilver very slow or erroring on the survivor** — the survivor is
  degrading too. Stop, `zfs send` critical datasets to an external
  destination, then continue.

- **Machine won't boot after reboot in 5c** — EFI boot order may still
  prefer the missing drive's entry. Enter UEFI setup → Boot Order → make
  sure the new drive's EFI entry is first, or add a NixOS boot entry
  pointing at `\EFI\systemd\systemd-bootx64.efi` on the new ESP.

---

## Pre-flight checklist

- [ ] Replacement Samsung PM1643a 960 GB (`MZILT960HBHQ`) in hand
- [ ] Installer USB built against the pinned clan-core rev (§0a)
- [ ] zroot passphrase available (not just via initrd-ssh)
- [ ] SSH access to ernst restored (§0b)
- [ ] `/var/lib/sops-nix/key.txt` present or plan to recover (§0c)
- [ ] ernst still on original uptime, zroot still shows FAULTED vdev (§0d)
- [ ] `zpool detach` done (§2)
- [ ] Torx driver for the drive caddy screws
- [ ] ESD strap or grounded surface
- [ ] Terminal open with this runbook and a note pad for the new drive's
      WWN + serial

---

*Machine facts current as of 2026-07-25.*
