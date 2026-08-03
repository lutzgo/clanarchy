# ernst — zroot mirror drive replacement

General guide for replacing a failed disk in ernst's encrypted mirrored
`zroot` pool. Cold-swap procedure in either case (the enclosure does not
support hot-swap).

The two mirror halves are asymmetric — one carries the ESP + swap + zroot
partition, the other holds only a zroot partition — so the procedure
branches on which disk failed:

- **Case A** — the ESP-carrying disk failed (currently `disk.system-a` in
  `machines/ernst/disko.nix`). Pulling this disk removes the only bootable
  ESP, so provisioning happens from an installer USB via a chroot. New ESP
  gets written; bootloader is reinstalled.
- **Case B** — the zroot-only disk failed (currently `disk.system-b`). The
  surviving disk still holds a working ESP, so ernst boots normally after
  the cold swap. Provisioning happens from the running system. No installer
  USB required, no chroot, no bootloader work.

See `machines/ernst/disko.nix` for the current layout — the "ESP-carrying"
role belongs to whichever `disk.system-*` block has an `EF00` partition.

---

## Quick reference — fill in before starting

Derive each value at the point in the runbook where it's needed; noted
here so you can keep them together on a note pad.

| Placeholder | How to derive |
|---|---|
| `<FAILED_WWN>` | `zpool status zroot` — the FAULTED / UNAVAIL / DEGRADED vdev's `wwn-…` name (matches a `disk.system-*.device` in `machines/ernst/disko.nix`) |
| `<FAILED_ROLE>` | Cross-reference `<FAILED_WWN>` against `disko.nix` to determine whether it's `system-a` (ESP + swap + zroot) or `system-b` (zroot only) |
| `<CASE>` | **A** if `<FAILED_ROLE>` is the ESP-carrying disk; **B** if it's the zroot-only disk |
| `<SURVIVOR_WWN>` | `zpool status zroot` — the ONLINE mirror half's `wwn-…` name |
| `<SLOT>` | Physical enclosure slot for the failed drive — see §1 for SES-based derivation |
| `<NEW_DEV>` | After inserting the replacement, kernel-assigned `/dev/sd?` — `lsblk -o NAME,SIZE,SERIAL,WWN` |
| `<NEW_WWN>` | Same `lsblk` output — the drive's `WWN` column |
| `<NEW_MODEL>` | `smartctl -i <NEW_DEV>` → *Model Number* |
| `<NEW_SERIAL>` | `smartctl -i <NEW_DEV>` → *Serial number* |

> **Reminder (Case A only)** — do not reboot ernst until the replacement is
> installed and a bootloader is written to a new ESP. The current running
> kernel is safe; a cold reboot with the ESP-carrying disk absent means no
> bootable EFI partition until §4h. Case B is not affected — the surviving
> ESP remains authoritative throughout.

---

## Contents

0. [Prerequisites](#0-prerequisites)
1. [Identify the failed drive](#1-identify-the-failed-drive)
2. [Prepare the pool (while ernst is still up)](#2-prepare-the-pool-while-ernst-is-still-up)
3. [Cold swap](#3-cold-swap)
4. [Provision the new drive](#4-provision-the-new-drive)
5. [Fix sops if needed and redeploy](#5-fix-sops-if-needed-and-redeploy)
6. [Rollback / troubleshooting](#6-rollback--troubleshooting)
7. [Pre-flight checklist](#pre-flight-checklist)

---

## 0. Prerequisites

### 0a. Working console or SSH access to ernst

Required to run §2 (`zpool detach`) before power-off. In Case B, SSH access
is also required after the swap for §4b onwards. In Case A everything from
§3 onwards happens from the installer USB, not via SSH.

### 0b. Confirm ernst is still up and determine which case applies

```bash
uptime
zpool status zroot
```

- Note `<FAILED_WWN>` from the FAULTED / UNAVAIL / DEGRADED vdev.
- Note `<SURVIVOR_WWN>` from the ONLINE half.
- Cross-reference `<FAILED_WWN>` against `machines/ernst/disko.nix`
  `disk.system-*.device` lines to find `<FAILED_ROLE>`.
- Determine `<CASE>`:
    - **Case A** — `<FAILED_ROLE>` has `EF00` + `8200` + `BF01` partitions
      in disko.nix (ESP-carrying disk).
    - **Case B** — `<FAILED_ROLE>` has only a `BF01` partition
      (zroot-only disk).

### 0c. Build the installer USB — Case A only

Skip entirely for Case B; ernst boots off the surviving ESP after the
swap and there is no chroot step.

The installer must match the flake's `clan-core` rev, otherwise `clan flash`
build/eval will drift from the running config. Same rule as the initial
install (see `CLAUDE.md` §Installing a Machine from Scratch).

```bash
REV=$(nix flake metadata --json . | jq -r '.locks.nodes."clan-core".locked.rev')

# lsblk first to confirm the USB device path — clan flash wipes it entirely.
lsblk

clan flash write \
  --flake "git+https://git.clan.lol/clan/clan-core?ref=$REV" \
  --ssh-pubkey machines/miralda/yubikey_ed25519.pub \
  --disk main /dev/sdX      # X = your USB stick — CONFIRM before running
```

Have the zroot passphrase ready in a password manager — you'll need to type
it in the installer when importing the pool. The initrd-ssh unlock helper
only assists the installed system's stage 1, not the installer.

### 0d. About the sops-nix key

**Not a blocker for this procedure in either case.** In Case A, the
bootloader install in §4h runs `switch-to-configuration boot`, which writes
only the bootloader — it does not run the sops activation scripts. In Case B
nothing touches sops at all until §5c's deploy. If sops is broken, that is
dealt with in §5a *before* the final `deploy-ernst switch`. Do not chase
sops now.

---

## 1. Identify the failed drive

Applies to both cases. Aim: determine which physical enclosure slot the
failed drive occupies, so you pull the right tray in §3.

If the failed drive is currently offline from the SAS bus (dropped and not
re-enumerated), you can't blink its own locator LED. Blink the LEDs of
every OTHER drive instead — the empty/unresponsive slot is the failed one.

```bash
# List enclosure services devices
ls /dev/sg* /dev/bsg/ 2>&1

# Read enclosure element status (serials + slot correspondence)
for sg in /dev/sg*; do
  echo "=== $sg ==="
  sg_ses --page=aes "$sg" 2>/dev/null \
    | grep -E "Element index|SAS addr|slot|serial" | head -20
done

# Blink LOCATE LED on a suspected slot to confirm before pulling
sg_ses --index=<N> --set=locate /dev/sgX

# Turn it off again
sg_ses --index=<N> --clear=locate /dev/sgX
```

Once you've identified `<SLOT>`:

1. Open the chassis.
2. Cross-check the tray in `<SLOT>` — status LED should be dark or amber
   (not the green blink of an active drive).
3. Pull the tray.
4. **Read the label on the drive itself and confirm it's the one you
   intend to remove** (serial number matches what `sg_ses` reported for
   that slot, and does NOT match `<SURVIVOR_WWN>`'s serial).

---

## 2. Prepare the pool (while ernst is still up)

Both cases. Do this from ernst over SSH **before powering off**. It cleanly
removes the failing drive from ZFS's view so nothing tries to reach a
phantom device once the pool re-imports (Case A) or continues running
(Case B).

```bash
# Confirm state
zpool status zroot
# Expected: mirror-0 with one half showing FAULTED / UNAVAIL / DEGRADED

# Detach the failed half so ZFS stops trying to talk to it.
# Pool becomes single-vdev (still ONLINE, no redundancy — expected until §4g).
zpool detach zroot wwn-<FAILED_WWN>-part<N>
# <N> is 3 if the failed disk is system-a (ESP + swap + zfs layout),
# or 1 if the failed disk is system-b (zfs-only layout).

# Verify:
zpool status zroot
# Expected: no mirror-0 wrapper anymore, just wwn-<SURVIVOR_WWN>-part<N> ONLINE.
```

If the failed disk carried swap and it's still referenced, turn it off:

```bash
swapon --show
swapoff /dev/mapper/disk-<FAILED_ROLE>-swap 2>/dev/null || true
```

> **If the running system is already unreachable** — dead getty on every
> VT (console shows only kernel/service spam, no login prompt) *and* SSH
> broken — skip this step entirely. After the pool re-import in §4a
> (Case A), detach the ghost vdev there instead using its GUID from
> `zpool status`:
> ```bash
> zpool detach zroot <GUID>
> ```
> The end state is identical: single-vdev pool ready for §4g's attach.

---

## 3. Cold swap

Both cases: shutdown, swap, power on. Only the boot medium differs.

1. Clean shutdown from ernst:

   ```bash
   systemctl poweroff
   ```

   **If getty is dead on every VT and SSH is broken**, don't reinstall or
   try to bring sshd back up — press **Ctrl+Alt+Del** at the physical
   console. systemd traps the key combo and performs a clean shutdown
   even with getty gone. Then power off at POST. The §2 detach step is
   handled from the installer per that step's fallback note.

2. Wait for full power-off. Verify PSU LED / chassis is quiet.

3. Physically swap the drive in `<SLOT>`:
   - Pull the failing tray (confirmed by serial in §1).
   - Transfer screws to the replacement SSD in the same caddy positions.
   - Insert into `<SLOT>`; push firmly until the latch clicks.

4. Power on:
   - **Case A** — insert the installer USB *before* powering on. Enter the
     boot menu (typically **F11** on ASUS X870E boards) and boot the USB,
     **not** the internal disk.
   - **Case B** — ensure no installer USB is inserted. Boot normally from
     the internal disk (the surviving ESP is untouched).

5. Verify the new drive enumerated:

   - **Case A** — at the installer shell:

     ```bash
     lsblk -o NAME,SIZE,SERIAL,WWN
     ```

   - **Case B** — once ernst is up, from your admin workstation:

     ```bash
     ssh root@ernst.skynet.lan lsblk -o NAME,SIZE,SERIAL,WWN
     ```

   Note `<NEW_DEV>` and `<NEW_WWN>`. Expect both mirror-role drives visible
   plus the data disks. The new drive has an empty/unknown partition table.

---

## 4. Provision the new drive

**Case A** runs §4a–§4i from the installer, with a chroot for the
bootloader step. **Case B** runs §4b–§4e and §4g from the live running
system (as root, over SSH) and skips §4a, §4f, §4h, §4i entirely.

### 4a. Import the existing zpool — Case A only

Case B: the pool is already imported and mounted by the running system.
Skip this section.

```bash
# Import read-write, root-relative to /mnt (installer convention).
# -f is REQUIRED: the pool was last opened by ernst's hostid; the installer
# has a different one, so import without -f fails with
# "pool was previously in use from another system".
zpool import -f -R /mnt zroot

# If §2's detach was skipped (unreachable running system): drop the ghost
# vdev now, by GUID (visible in `zpool status zroot`):
#   zpool detach zroot <GUID>

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

### 4b. Identify the new drive

Both cases. Commands identical.

```bash
lsblk -o NAME,SIZE,SERIAL,WWN

# Set variables:
NEW_DEV=/dev/sdX
NEW_WWN=0x................

# Sanity
smartctl -i "$NEW_DEV" | grep -E "Model|Serial|Capacity"
```

### 4c. Verify sector format (mandatory) and reformat if needed

Both cases. Replacement drives are often different SKUs or OEM channels
than the survivor. Enterprise SAS SSDs sometimes ship formatted 4Kn or
with T10 PI (protection information) enabled — both incompatible with the
pool's existing 512-byte-logical vdevs.

```bash
sg_readcap -l "$NEW_DEV"
```

`sg3_utils` (which provides `sg_readcap` and `sg_format`) is **not** on
the clan flash installer image and isn't in ernst's system PATH by
default. Bring it in ad-hoc via `nix shell` in either case:

```bash
nix shell nixpkgs#sg3_utils -c sg_readcap -l "$NEW_DEV"
nix shell nixpkgs#sg3_utils -c sg_format  --format --size=512 "$NEW_DEV"
```

Required properties in the output:
- **Logical block length: 512**
- **prot_en=0** (no T10 PI)

If either is wrong, reformat before partitioning:

```bash
sg_format --format --size=512 "$NEW_DEV"
```

Takes ~20–30 min on a 960 GB SSD. Runs synchronously; the drive stays busy
throughout. Re-run `sg_readcap -l` afterwards to confirm.

**Notes on cross-model compatibility:**
- Any IDEMA-standard 960 GB SAS drive has an identical LBA count, so
  mixing e.g. PM1643 / PM1643a / PM1653 in the mirror is fine as long as
  sector format matches.
- SAS-24G drives (PM1653 etc.) negotiate down to 12 Gb/s on ernst's SAS
  9300-8i HBA. No config change needed.

### 4d. Wipe any existing partition table

Both cases.

```bash
wipefs -a "$NEW_DEV"
sgdisk -Z  "$NEW_DEV"
```

### 4e. Recreate the disko partition layout

Both cases, layout branches on `<CASE>`. Match
`machines/ernst/disko.nix` → `disk.<FAILED_ROLE>.content.partitions`
exactly.

**Case A** — replacing the ESP-carrying disk: 1 GiB ESP + 16 GiB swap +
remainder ZFS.

```bash
sgdisk \
  -n 1:0:+1G   -t 1:EF00 -c 1:disk-<FAILED_ROLE>-ESP  \
  -n 2:0:+16G  -t 2:8200 -c 2:disk-<FAILED_ROLE>-swap \
  -n 3:0:0     -t 3:BF01 -c 3:disk-<FAILED_ROLE>-zfs  \
  "$NEW_DEV"
```

**Case B** — replacing the zroot-only disk: single ZFS partition spanning
the disk.

```bash
sgdisk \
  -n 1:0:0     -t 1:BF01 -c 1:disk-<FAILED_ROLE>-zfs \
  "$NEW_DEV"
```

Then, either case:

```bash
partprobe   "$NEW_DEV"
udevadm settle

# Verify partlabels exist
ls -l /dev/disk/by-partlabel/ | grep "disk-<FAILED_ROLE>"
```

### 4f. Format and mount the new ESP — Case A only

Case B: skip this section — the surviving disk's ESP is untouched and
authoritative.

```bash
mkfs.vfat -F 32 -n ESP /dev/disk/by-partlabel/disk-<FAILED_ROLE>-ESP

# Mount into the target root's /boot (installer chroot convention)
mount /dev/disk/by-partlabel/disk-<FAILED_ROLE>-ESP /mnt/boot
ls /mnt/boot          # empty; bootloader install fills it
```

Swap needs no manual formatting — disko.nix sets `randomEncryption = true`,
so `systemd-cryptsetup@disk-<FAILED_ROLE>-swap.service` creates a fresh key
and swap header each boot.

### 4g. Attach the new drive to the zroot mirror

Both cases. Command is identical — `zpool attach` works against by-partlabel
device paths in either the installer or the running system.

```bash
zpool attach zroot \
  wwn-<SURVIVOR_WWN>-part<N> \
  /dev/disk/by-partlabel/disk-<FAILED_ROLE>-zfs
```

`<N>` matches the survivor's zfs-partition number (1 for `system-b`, 3 for
`system-a` in the current layout).

Resilver kicks off immediately. On mirrored SAS SSDs with only a few GB
used (zroot typically sits at ~4.5 GB), resilver completes in **seconds**,
not minutes — the mirror is ONLINE and both halves match by the time you
switch terminals. It's safe to overlap Case A's §4h bootloader work with
the resilver window; just re-check `zpool status zroot` before §4i's
`zpool export`.

```bash
watch -n 5 'zpool status zroot | head -20'
# Ctrl-C once "resilver completed" appears and the pool is ONLINE
# with no read/write/checksum errors on either half.
```

### 4h. Install the bootloader from a chroot — Case A only

Case B: skip. The surviving disk's ESP already has a valid bootloader.

Run **both** commands in this order — the first primes the ESP with the
systemd-boot binary; the second wires up the generation entries. Running
only the second (as an obvious first attempt) crashes with a Python
traceback from `bootctl status` because efivars aren't visible from
inside the chroot (`Firmware: n/a`), so the NixOS systemd-boot installer
bails before writing anything.

```bash
# 1. Prime the new ESP with systemd-boot (no NVRAM changes — chroot has
#    no efivars). --no-variables suppresses the efibootmgr call that
#    would otherwise fail.
nixos-enter --root /mnt -c \
  "bootctl --esp-path=/boot install --no-variables"

# 2. Now run the NixOS bootloader activation. This writes generation
#    entries (nixos-generation-*.conf), the loader config, and the
#    initrd/kernel copies.
nixos-enter --root /mnt -c \
  "/run/current-system/bin/switch-to-configuration boot"

# Sanity check — you should see one nixos-generation-*.conf entry.
ls /mnt/boot/loader/entries
```

`switch-to-configuration boot` runs only the bootloader-install step; it
does **not** run sops or user-secret activation. If sops-nix is broken this
step still succeeds.

After first successful boot from the running system, register the NVRAM
entry and tidy the boot order:

```bash
ssh root@ernst.skynet.lan
bootctl install   # creates the "Linux Boot Manager" NVRAM entry now
                  # that efivars are visible

# Inspect current entries and reorder as needed.
nix shell nixpkgs#efibootmgr -c efibootmgr
nix shell nixpkgs#efibootmgr -c efibootmgr -o <hex,hex,...>   # new order
```

The firmware auto-creates a **"UEFI OS"** fallback entry pointing at
`\EFI\BOOT\BOOTX64.EFI`. Harmless — keep it as a last-resort fallback.
"Linux Boot Manager" (systemd-boot) should be first in `BootOrder`.

### 4i. Clean unmount and reboot — Case A only

Case B: skip. Continue to §5 with the system still running.

```bash
umount -R /mnt
zpool export zroot

# Remove USB now, then:
systemctl reboot
```

Stage 1 will prompt for the zroot passphrase. The initrd-ssh host key
lives on `/persist/etc/secrets/initrd/` — which is on a dataset you never
touched during this replacement — so remote unlock still works out of the
box. From miralda:
[`docs/guides/remote-unlock.md`](../guides/remote-unlock.md). No console
needed for the passphrase; no re-generation of the initrd host key.

**On first reboot: enter UEFI setup and verify boot order.** Common failure
mode is "worked in the chroot, won't boot unattended" because the firmware
still ranks a stale EFI entry pointing at the removed drive's ESP above the
new one.

- Enter setup (Del or F2 on ASUS ProArt boards).
- Boot → Boot Priority.
- Confirm the "Linux Boot Manager" entry pointing at the **new** drive is
  first.
- Delete or demote any entry pointing at the removed drive's ESP.
- Save and exit.

---

## 5. Fix sops if needed and redeploy

Both cases converge here. In Case A you just rebooted into the repaired
system; in Case B you never left it.

### 5a. Fix sops-nix key if broken

**Only relevant if the activation error `sops-install-secrets: cannot read
keyfile '/var/lib/sops-nix/key.txt'` appears on the next
`deploy-ernst switch`.** If deploys are clean, skip this section.

First diagnose — the key may exist on the persist mount and only the
impermanence binding be broken:

```bash
ls -la /var/lib/sops-nix/ /persist/var/lib/sops-nix/ 2>&1
mount | grep sops-nix
findmnt /var/lib/sops-nix
```

**Case i — key exists on `/persist` but not visible at `/var/lib/sops-nix`:**
the impermanence mapping is broken. Check the persist entry for
`/var/lib/sops-nix` in the flake (`modules/zfs-impermanence.nix` and any
ernst-specific persist config), fix, redeploy. No key regeneration needed.

**Case ii — key genuinely absent** (empty `/persist/var/lib/sops-nix/`):

1. Generate a new machine age key at the persisted path. `age` is not in
   ernst's system PATH by default; bring it into scope via `nix shell`:
   ```bash
   mkdir -p /persist/var/lib/sops-nix
   nix shell nixpkgs#age -c age-keygen -o /persist/var/lib/sops-nix/key.txt
   chmod 600 /persist/var/lib/sops-nix/key.txt
   nix shell nixpkgs#age -c age-keygen -y /persist/var/lib/sops-nix/key.txt   # print new public key
   ```
2. From miralda, update ernst's machine recipient in the clan sops config
   (`sops/machines/ernst/` or `.sops.yaml` depending on layout) to the new
   public key.
3. Re-encrypt existing vars against the new recipient. For plain sops-managed
   files, `sops updatekeys <path>` on each. For machine-scoped clan vars,
   use `clan vars generate --regenerate ernst` (verified against
   `clan vars --help` at this flake's pinned clan-core rev — the subcommand
   surface is `{keygen,check,fix,list,get,set,generate,upload}`, so any
   older docs mentioning `clan vars regenerate` are stale).
4. Commit the recipient rotation on a `vars/ernst-key-rotation` branch and
   land it via PR.
5. Verify decryption works from miralda before deploying:
   ```bash
   sops -d sops/machines/ernst/<some-secret-file>
   ```
6. On ernst, verify the impermanence bind now shows the key:
   ```bash
   ls -la /var/lib/sops-nix/
   ```

### 5b. Update `disko.nix` on miralda

Edit `machines/ernst/disko.nix` for the replaced disk. Update **both** the
`device` line and the trailing comment (model + serial) so the config
remains self-documenting:

```nix
disk.<FAILED_ROLE> = {
  type = "disk";
  device = "/dev/disk/by-id/wwn-<NEW_WWN>";  # <NEW_MODEL>  <NEW_SERIAL>
  ...
};
```

Commit on a branch and open a PR:

```bash
git switch -c fix/ernst-replace-<FAILED_ROLE>
git add machines/ernst/disko.nix
git commit -m "ernst: replace <FAILED_ROLE> disk (new WWN <NEW_WWN>)"
push origin fix/ernst-replace-<FAILED_ROLE>
gh pr create --title "ernst: replace failed <FAILED_ROLE> SAS SSD" \
  --body "New drive: <NEW_MODEL> <NEW_SERIAL> (WWN <NEW_WWN>)."
```

### 5c. Deploy

```bash
deploy-ernst switch
```

Case A: bootloader install writes to the new ESP; services activate.
Case B: no bootloader change; services activate.

### 5d. Verify boot resilience

Both cases. Reboot once to prove the drive+ESP combo boots unattended:

```bash
ssh root@ernst.skynet.lan 'systemctl reboot'
# wait 60–90 s
ssh root@ernst.skynet.lan '
  uptime
  zpool status zroot
  systemctl --failed --no-pager
'
```

**Green result**: fresh uptime, `zroot` ONLINE with *both* `mirror-0`
halves ONLINE and zero errors, no failed units. Runbook complete.

---

## 6. Rollback / troubleshooting

- **`zpool attach` fails with "device is too small"** — the new drive has
  slightly fewer sectors than the survivor. Any IDEMA-standard 960 GB SAS
  drive should match. If it doesn't (rare cross-vendor case), use
  `zpool attach -f` after confirming the delta is trivial (< 1 MB); if it's
  larger, the drive is undersized and unsuitable.

- **`zpool attach` fails with "block size mismatch"** — sector format
  wasn't caught in §4c. Detach, `sg_format --format --size=512` the new
  drive, retry §4d–4g.

- **New drive also flaps on the SAS bus** — the fault is the backplane,
  cable, or HBA port, not the drive. Move it to a different slot; if the
  problem follows the drive it's the drive, if it stays on the slot it's
  the enclosure hardware.

- **Bootloader install fails in chroot (Case A)** — check
  `mount | grep /mnt/boot` and `ls /mnt/boot`. The ESP must be mounted and
  writable. If `by-partlabel` doesn't resolve, `udevadm trigger && udevadm
  settle` and remount.

- **Pool import fails with "one or more devices is currently unavailable"
  (Case A)** — after the detach in §2, the pool has a single vdev; if the
  survivor itself is now flaking (worst case), `zpool import -F zroot` may
  work as a last resort. Only try this if the survivor is healthy —
  otherwise stop and restore from backup.

- **Resilver very slow or erroring on the survivor** — the survivor is
  degrading too. Stop, `zfs send` critical datasets to an external
  destination, then continue.

- **Machine won't boot after §4i's reboot (Case A only)** — UEFI boot
  order issue: see §4i last paragraph. Enter setup, promote the new "Linux
  Boot Manager" entry, delete stale entries.

- **`deploy-ernst switch` in §5c fails at `setupSecrets`** — sops-nix key
  issue; go to §5a.

---

## Pre-flight checklist

- [ ] Replacement SAS SSD in hand (any IDEMA-standard 960 GB matching the
      current mirror capacity — same model preferred, but PM1643a/PM1653
      are interchangeable)
- [ ] `<FAILED_WWN>` and `<SURVIVOR_WWN>` noted from `zpool status zroot`
- [ ] `<FAILED_ROLE>` and `<CASE>` determined by cross-referencing
      `disko.nix` (§0b)
- [ ] Console or SSH access to ernst working (§0a)
- [ ] Installer USB built against the pinned clan-core rev **(Case A only,
      §0c)**
- [ ] zroot passphrase available in a password manager **(Case A only —
      installer prompts for it; Case B never re-imports)**
- [ ] `<SLOT>` physically located and confirmed (§1)
- [ ] `zpool detach` done (§2)
- [ ] Torx driver for the drive caddy screws
- [ ] ESD strap or grounded surface
- [ ] Terminal open with this runbook and a note pad for `<NEW_WWN>`,
      `<NEW_MODEL>`, `<NEW_SERIAL>`
