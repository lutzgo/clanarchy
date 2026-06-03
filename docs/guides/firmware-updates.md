# Firmware Updates

Both machines use [fwupd](https://fwupd.org/) to apply firmware updates distributed through [LVFS](https://fwupd.org/lvfs/devices/) (Linux Vendor Firmware Service).

---

## Quick reference

| Command | What it does |
|---------|-------------|
| `fwupdmgr refresh` | Sync metadata from LVFS |
| `fwupdmgr get-devices` | List devices fwupd can manage |
| `fwupdmgr get-updates` | Show available firmware updates |
| `fwupdmgr update` | Download and apply all pending updates |
| `fwupdmgr get-history` | Show previously applied updates |

---

## Standard workflow

```bash
# 1. Refresh LVFS metadata (run as root or with sudo)
fwupdmgr refresh

# 2. Check what's available
fwupdmgr get-updates

# 3. Apply updates
fwupdmgr update
```

Some updates (e.g. UEFI capsule updates, NVMe firmware) take effect on the **next reboot**. fwupd will tell you if a reboot is required.

---

## Checking device support

```bash
fwupdmgr get-devices
```

Devices with `Update State: up-to-date` are supported and current. Devices with `Update Error: failed to get firmware version` or no LVFS entry are not covered by LVFS for this vendor/model.

For biene (Lenovo), Lenovo ships LVFS updates for most ThinkPad and IdeaPad models. Check https://fwupd.org/lvfs/devices/ with the device vendor/model to confirm coverage.

---

## EFI capsule updates

For UEFI/BIOS updates delivered as EFI capsules:

1. fwupd writes the capsule to the EFI System Partition (`/boot`).
2. Reboot — firmware applies the update during POST.
3. After boot, `fwupdmgr get-history` confirms the update was applied.

!!! warning "Do not power off during reboot"
    The reboot cycle for a UEFI capsule update takes longer than normal. Let the machine complete the POST sequence before interacting with it.

---

## Troubleshooting

### `LVFS: Failed to connect to daemon`

The fwupd service may not be started:

```bash
systemctl start fwupd
```

### `No releases found for device`

The device is supported by fwupd but has no updates available from LVFS, or the device firmware is already at the latest version. Run `fwupdmgr refresh` first to ensure metadata is current.

### After a ZFS rollback

fwupd's database (in `/var/lib/fwupd`) is **not** in the impermanence persist list — it is intentionally ephemeral. After a rollback, fwupd may re-offer updates that were already applied. This is safe: applying the same version again is a no-op.

If you want fwupd history to survive rollbacks, add `/var/lib/fwupd` to `environment.persistence."/persist".directories` in the machine's configuration.nix.
