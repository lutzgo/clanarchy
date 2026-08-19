# Game controllers on the TV

How to get an Xbox pad working on `ernst`'s living-room session, and why the
board's own Bluetooth radio is not the way to do it.

| Path | Status on ernst | Notes |
|------|-----------------|-------|
| **Wired USB** | works, nothing to configure | `xpad` is in-tree; `hardware.steam-hardware` (pulled in by `programs.steam`) ships the udev rules |
| **Onboard Bluetooth** | **does not work** | The board's MT7927 radio has no Bluetooth support on this kernel and no firmware blob — see [below](#the-onboard-radio-cannot-do-bluetooth-yet) |
| **USB Bluetooth dongle** | works | Firmware for the common Realtek and Intel parts is already in the system closure |

`clanarchy.roles.htpc.controller.enable` (on by default) provides the *software*
half — Bluetooth stack plus the xpadneo driver, which is what gives correct
button mapping, rumble and battery reporting for Xbox One S / Series pads over
Bluetooth. It cannot provide a working radio.

## The onboard radio cannot do Bluetooth yet

ernst's WiFi/Bluetooth card is a **MediaTek MT7927** (Filogic 380, WiFi 7):
PCIe `14c3:7927` for the WiFi half, USB `0489:e13a` for the Bluetooth half.
The Bluetooth part is internally an **MT6639**.

What that looks like on the machine:

```console
$ dmesg | grep -i bluetooth
Bluetooth: hci0: Opcode 0x0c03 failed: -16      # HCI_Reset → EBUSY

$ bluetoothctl show
No default controller available
```

`btusb` binds the device by generic Bluetooth device class, then setup fails at
the very first reset, so `hci0` exists at the kernel level (`rfkill list` shows
it, unblocked) but never registers with bluez. Unbinding and rebinding `btusb`
reproduces it exactly; it is not a boot-time wedge.

Two things are missing, both upstream of this repo:

```console
$ uname -r
6.18.43

$ modinfo btmtk | grep ^firmware
firmware:       mediatek/mt7925/BT_RAM_CODE_MT7925_1_1_hdr.bin
firmware:       mediatek/BT_RAM_CODE_MT7961_1_2_hdr.bin
firmware:       mediatek/BT_RAM_CODE_MT7922_1_1_hdr.bin
firmware:       mediatek/mt7668pr2h.bin
firmware:       mediatek/mt7663pr2h.bin
firmware:       mediatek/mt7622pr2h.bin        # ← no MT6639 / MT7927

$ ls /run/current-system/firmware/mediatek/mt7927/
WIFI_MT6639_PATCH_MCU_2_1_hdr.bin.zst
WIFI_RAM_CODE_MT6639_2_1.bin.zst              # ← WiFi only, no BT_RAM_CODE
```

1. **Driver.** `btmtk` on 6.18.43 has no case for hardware variant `0x6639`.
   The fixes landed in mainline around **kernel 7.1** (June 2026).
2. **Firmware.** `mediatek/mt7927/BT_RAM_CODE_MT6639_2_1_hdr.bin` is not in
   linux-firmware. It sits in a **draft** merge request, waiting on MediaTek's
   redistribution sign-off.

The firmware is the real gate: a kernel bump alone will not fix this, and the
blob cannot be shipped until MediaTek signs off. That is why the answer here is
a dongle rather than a `flake.lock` bump.

!!! tip "Re-checking after a flake bump"

    Both halves are one command each. If they ever both come back positive, the
    onboard radio should work with no config change:

    ```bash
    modinfo btmtk | grep -i 6639                       # driver support
    ls /run/current-system/firmware/mediatek/mt7927/    # BT_RAM_CODE_MT6639_*
    ```

## Using a USB dongle

Nothing to configure — `hardware.bluetooth` is already enabled with
`powerOnBoot` by the HTPC role. Because `hci0` never completes setup it never
appears in bluez at all, so a dongle becomes the only controller bluez sees.

Firmware already present in the closure, so these work out of the box:

```console
$ ls /run/current-system/firmware/rtl_bt/ | grep 8761
rtl8761a_config.bin.zst  rtl8761b_config.bin.zst  rtl8761bu_config.bin.zst
rtl8761a_fw.bin.zst      rtl8761b_fw.bin.zst      rtl8761bu_fw.bin.zst

$ ls /run/current-system/firmware/intel/ | grep -c ibt
126
```

That covers the cheap **RTL8761B / 8761BU** sticks and Intel-based adapters.
After plugging one in:

```bash
bluetoothctl list          # expect exactly one controller
```

If more than one ever shows up, pick explicitly with `select <MAC>` inside
`bluetoothctl`.

## Pairing an Xbox pad

From miralda: `ssh root@ernst.skynet.lan` (or `root@10.0.50.10`), then

```bash
bluetoothctl
```

```
power on
agent on
default-agent
scan on
```

Now put the pad in pairing mode: hold the **pair button** — the small one on
top, next to the USB port — for about three seconds, until the Xbox button
flashes rapidly. It will not enter pairing mode while it is still connected to a
console or another host.

A `Device AA:BB:CC:DD:EE:FF Xbox Wireless Controller` line appears. Then:

```
pair AA:BB:CC:DD:EE:FF
trust AA:BB:CC:DD:EE:FF
connect AA:BB:CC:DD:EE:FF
scan off
exit
```

`trust` is the one people skip and then wonder why the pad has to be re-paired:
it is what lets pressing the Xbox button reconnect on its own afterwards.

### Check the right driver took it

```bash
dmesg | grep -i xpadneo          # expect hid-xpadneo binding to the device
ls /dev/input/by-id/ | grep -i xbox
```

xpadneo rather than the in-tree `xpad` is what you want over Bluetooth — rumble
and battery reporting are the visible difference, and both show up in Steam's
controller settings.

### It survives reboots

`/var/lib/bluetooth` is persisted (PR #65), so the pairing outlives ernst's
impermanence rollback. Pair once.

## From the couch, without SSH

Steam's own Bluetooth pairing screen is a SteamOS feature and is not in the
desktop Big Picture build, so pairing is either the SSH route above or Plasma's
Bluetooth applet:

```bash
clanarchy-session-select plasma      # pair, then:
clanarchy-session-select gamescope
```

## References

- [MT7927 Bluetooth: from DKMS to upstream](https://jetm.github.io/blog/posts/mt7927-bluetooth-upstream-submission/)
- [Enabling MediaTek MT7927 Bluetooth on Linux](https://jetm.github.io/blog/posts/enabling-mt7927-bluetooth-on-linux/)
- [linux-firmware MR !946 — MT6639 Bluetooth firmware (draft)](https://gitlab.com/kernel-firmware/linux-firmware/-/merge_requests/946)
- [PATCH bluetooth: btmtk MT7927 / MT6639 firmware loading](https://lists.openwall.net/linux-kernel/2026/02/08/473)
