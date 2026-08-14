# ernst — slot-12 drive drop, 2026-08-11

Incident report. Second drive in a row to fail in the same physical
enclosure slot on ernst's SAS HBA. Documented here so the Monday
on-site diagnostic goes straight to the highest-signal test.

## Summary

- **Machine:** ernst (AM5 / X870E homelab server, headless).
- **What dropped:** the PM1653 (S6M1NN0Y901370, `wwn-0x50025380a5914360`)
  installed on 2026-08-03 in [#23] as `disk.system-a`. It went off the SAS
  bus at 2026-08-11 13:24:09 CEST after 11 days of service.
- **Immediate impact:** zroot mirror `DEGRADED` (single leg on
  `disk.system-b`); `/boot` unmountable (its ESP lives on the dropped
  disk); `deploy-ernst switch` blocked by the systemd-boot
  `check-mountpoints` guard.
- **Data:** no known errors on either pool; zdata `ONLINE`, last scrub
  clean on 2026-08-03.
- **Suspicious pattern:** the previous `disk.system-a` (a used PM1643a)
  also failed and was replaced in [#23] on 2026-08-03. **Both drives lived
  in the same physical slot — enclosure `0x500062b204731180`, slot 12** —
  and both died there. Two independent SAS-SSD failures inside a few
  weeks in the same slot is far less likely than a single slot-side
  fault (cable, backplane connector, HBA channel) that eats whatever is
  plugged into it. Diagnostic tree in §Monday plan optimizes for
  distinguishing drive from slot with the hardware ernst already has.

[#23]: https://github.com/lutzgo/clanarchy/pull/23

## Timeline

| Timestamp (CEST) | Event |
|---|---|
| 2026-08-03 10:53 | Boot after the disk-replacement in [#23]; PM1653 installed in slot 12 as `disk.system-a`. |
| 2026-08-03 17:10 | Scheduled scrub of both pools completes; zero errors. |
| 2026-08-03 → 08-06 | Persistent PCIe AER *correctable* errors on `pcieport 0000:09:05.0` (multiple events per day). See §PCIe context. |
| 2026-08-10 17:14:48 | `igc 0000:0c:00.0 enp12s0: PCIe link lost, device now detached` — Intel I226-V NIC drops off the bus. Uncorrectable **Fatal** AER on `pcieport 0000:09:05.0`. |
| 2026-08-11 13:24:09 | PM1653 in slot 12 produces multiple write errors (`error=5 type=2`), `mpt3sas_cm0: mpt3sas_transport_port_remove: removed sas_addr 0x50025380a5914362, slot 12`, device gone from `/dev/disk/by-id/`. |
| 2026-08-11 13:24:14 | `boot.mount` deactivates (its `disk-system-a-ESP` partition no longer exists). |
| 2026-08-14 (today) | `deploy-ernst switch` fails at systemd-boot's `check-mountpoints` because `/boot` is not a mounted partition. Diagnostic capture taken; this incident opened. |

## PCIe context (why the AER pattern is not the same problem)

Initial concern was that the recurring AER errors and the drive drop
might share a root cause (motherboard, PSU rail). The `lspci -tv`
topology says otherwise:

```
+-01.3-[04]----00.0  Broadcom / LSI SAS3224 PCI-Express Fusion-MPT SAS-3   ← mpt3sas HBA, holds all 8 SAS SSDs
+-02.1-[05-12]----00.0-[06-12]--+-00.0-[07]--
                                +-08.0-[08-10]----00.0-[09-10]--+-...
                                                                +-05.0-[0c]----00.0  Intel Corporation Ethernet Controller I226-V   ← enp12s0
                                                                +-06.0-[0d]----00.0  Aquantia Corp. AQtion AQC113CS 10G                ← enp13s0 (working)
```

- **SAS HBA path:** `00:01.3 → 04:00.0` (LSI SAS3224).
- **AER-noisy bridge:** `0000:09:05.0` — an AMD 600-series chipset
  downstream port, which subordinate is bus `0c` (the Intel I226-V NIC).

The two subsystems share nothing above the CPU root complex. The AER
pattern is a **local-to-enp12s0** signal-integrity issue (bridge is
running at `LnkSta 5GT/s` versus a `Target Link Speed 16GT/s` — link
retrained down). It does not implicate the SAS side.

That gives us a cleaner story for the slot-12 drops: whatever is wrong,
it is contained to the mpt3sas HBA and its connection to slot 12 — not
a global platform issue.

## Current state

Snapshot taken 2026-08-14 (see `docs/incidents/ernst-slot12-drop-2026-08-11/`
for the raw capture logs):

```
zroot                             DEGRADED
  mirror-0                        DEGRADED
    wwn-0x5002538b722787f0-part1  ONLINE      (disk.system-b, PM1643a — survivor)
    wwn-0x50025380a5914360-part3  REMOVED     (disk.system-a, PM1653 — dropped 08-11)

zdata                             ONLINE      (raidz1, 6 × PM1643a)
```

- One more zroot leg loss = pool loss. Do not run risky operations on
  ernst until the mirror is whole again.
- `/boot` is unmounted (its ESP partition no longer exists). No
  bootloader install can proceed; already-installed generations still
  boot fine (until the next reboot which will attempt EFI variable
  handoff — see §Boot-safety note).
- All other pools/services on ernst continue to run.

## Monday plan

Two graduated tests. Do **Option 1** first; do **Option 2** only if
Option 1 doesn't bring the drive back.

### Option 1 — reseat in slot 12 (5 min, zero data risk)

1. Clean shutdown: `systemctl poweroff` (pool is fine to close down).
2. Pull the PM1653 from slot 12. Inspect the SAS connector on the
   drive and on the backplane for bent pins, oxidation, obvious cable
   damage.
3. Reseat firmly.
4. Power on. Verify:
   ```bash
   ssh root@ernst.skynet.lan '
     ls /dev/disk/by-id/ | grep 50025380a5914360
     zpool status zroot
   '
   ```
   - Drive present → `zpool online zroot wwn-0x50025380a5914360-part3`.
     Watch resilver complete (`zpool status zroot -v`). Mount `/boot`
     (`systemctl start boot.mount`) and retry `deploy-ernst switch`.
     Conclusion: seating/dust was the fault. Log and close the incident.
   - Drive absent → Option 2.

### Option 2 — swap PM1653 into a zdata slot (definitive, ~20 min + resilver)

Uses raidz1's redundancy as a temporary "spare slot" to distinguish
drive vs slot 12 without extra hardware.

Pick any physically-accessible zdata slot. The captured `zpool status`
gives you the six candidates:

```
raidz1-0
  wwn-0x5002538b0213bbe0-part1  data-1
  wwn-0x5002538b0213bc20-part1  data-2
  wwn-0x5002538b0213bc30-part1  data-3
  wwn-0x5002538b0213bc80-part1  data-4
  wwn-0x5002538b0214e620-part1  data-5
  wwn-0x5002538b0311c2b0-part1  data-6
```

Steps:

1. `systemctl poweroff` (raidz1 handles the coming absence fine).
2. Physically **label** the chosen zdata drive (call it `slot-X`) and
   pull it. Set it aside.
3. Move the PM1653 from slot 12 into `slot-X`. Leave slot 12 empty.
4. Power on. Verify:
   ```bash
   ssh root@ernst.skynet.lan '
     ls /dev/disk/by-id/ | grep 50025380a5914360
     dmesg -T | grep -iE "50025380a5914360|slot" | tail -20
     zpool status
   '
   ```

Interpret:

- **PM1653 present in slot-X → slot 12 is the fault; drive is fine.**
  - Zdata will show DEGRADED (missing the drive you pulled). Expected.
  - Power off, put the labelled zdata drive back into `slot-X`. Move
    the PM1653 to any slot **other than** slot 12 (or leave slot 12
    empty and defer physical repair).
  - Boot. Zdata resilvers automatically. Bring the PM1653 back into
    zroot with `zpool online zroot wwn-0x50025380a5914360-part3` — it
    will resilver against system-b.
  - **Do not put anything in slot 12** until the cable/backplane is
    replaced or the fault is otherwise localized. Track this as
    hardware-followup.
- **PM1653 absent even in slot-X → drive itself is dead.**
  - Zdata will show DEGRADED (missing the drive you pulled). Expected.
  - Power off, put the labelled zdata drive back into `slot-X`. Do not
    put the PM1653 anywhere; set it aside for RMA.
  - Boot. Zdata resilvers automatically. Zroot stays DEGRADED until a
    new drive arrives — follow
    `docs/runbooks/ernst-zroot-drive-replacement.md` (Case A, since
    `disk.system-a` is the ESP-carrying position).
  - Draft the Samsung RMA for the PM1653. Include: purchase date,
    serial `S6M1NN0Y901370`, and the dmesg extract from
    `docs/incidents/ernst-slot12-drop-2026-08-11/` showing the
    2026-08-11 13:24:09 removal event.

## Boot-safety note

Do **not** power-cycle ernst casually before Monday. The system is
currently up on a running kernel that has zroot imported. A cold reboot
in the current state would attempt to mount `/boot` (its ESP is gone)
and would depend on the EFI firmware still having a valid boot entry
pointing at a working ESP — which it does not, because the only ESP on
this machine lived on the dropped drive. Systemd-boot will not have a
place to write new entries on the next successful `deploy-ernst`, but
the currently-active boot entry may be preserved in NVRAM long enough
for one more boot; do not rely on it.

Follow-up work already tracked in the fleet backlog to make future
incidents of this type non-disruptive:

- **mirroredBoots**: add a second 1G ESP to `disk.system-b`, wire
  `boot.loader.systemd-boot.mirroredBoots` so `/boot` survives a
  slot-12 loss. Blocked on the next ernst reinstall (disko doesn't
  reconcile partitions on running systems); disko declaration to land
  now as future-only work.
- **Fleet ZED alerting**: proactive notification the moment a pool
  goes DEGRADED, rather than discovering it via a failed deploy 3
  days later.

## Raw diagnostic capture

The full `lspci`, `zpool`, `journalctl -k`, and `dmesg` snapshot taken
2026-08-14 lives at:

```
docs/incidents/ernst-slot12-drop-2026-08-11/capture-20260814-110526.log
```

Key excerpts (dmesg, translated timestamps):

```
[Mon Aug 10 17:14:48 2026] igc 0000:0c:00.0 enp12s0: PCIe link lost, device now detached
[Mon Aug 10 17:14:48 2026] pcieport 0000:00:02.1: AER: Uncorrectable (Fatal) error message received from 0000:09:05.0
[Tue Aug 11 13:24:09 2026] zio pool=zroot vdev=/dev/disk/by-id/wwn-0x50025380a5914360-part3 error=5 type=2 offset=43860647936 size=4096 flags=3145856
[Tue Aug 11 13:24:09 2026] zio pool=zroot vdev=/dev/disk/by-id/wwn-0x50025380a5914360-part3 error=5 type=2 offset=43044777984 size=16384 flags=3145856
[Tue Aug 11 13:24:09 2026] sd 0:0:6:0: [sda] Synchronizing SCSI cache
[Tue Aug 11 13:24:09 2026] mpt3sas_cm0: mpt3sas_transport_port_remove: removed: sas_addr(0x50025380a5914362)
[Tue Aug 11 13:24:09 2026] mpt3sas_cm0: removing handle(0x001f), sas_addr(0x50025380a5914362)
[Tue Aug 11 13:24:09 2026] mpt3sas_cm0: enclosure logical id(0x500062b204731180), slot(12)
```

## Related

- Runbook for the actual drive replacement:
  `docs/runbooks/ernst-zroot-drive-replacement.md` (Case A applies here).
- Previous replacement of the same slot: PR [#23] `fix(ernst): replace
  failed system-a disk (PM1643a → PM1653)`.
- Runbook errata from the previous replacement: PR [#26]
  `docs(runbook): ernst Case-A errata`.
