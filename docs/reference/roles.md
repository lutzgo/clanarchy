# Roles

!!! warning "Auto-generated"
    Do not edit by hand — regenerate with `gendocs` in the devShell.

Machine role modules. Enable exactly the roles that apply to a machine.

| Option | Type | Description |
|--------|------|-------------|
| `clanarchy.roles.laptop.enable` | `boolean` | Whether to enable laptop role. |
| `clanarchy.roles.laptop.framework.enable` | `boolean` | Whether to enable Framework-specific hardware (fprintd, fwupd, backpack-wake udev rule). |
| `clanarchy.roles.laptop.hybridSleep.enable` | `boolean` | Hybrid-sleep on lid close: suspend to RAM and write a hibernation image at the same time, so a battery that runs flat during sleep costs nothing.  **ONLY AVAILABLE ON btrfs, AND THAT IS THE POINT** — hibernation with a ZFS root is widely documented as unsafe (the pool's in-memory state and its on-disk state diverge across the resume), and `clanarchy.rootfs` is derived from `clanarchy.channel`, so in practice this is on for an unstable-channel laptop and refused on a stable one. Enabling it on ZFS is an assertion failure, not a silent risk. This is reasoned from upstream's position, not measured here.  Also requires a swap partition sized >= RAM and `boot.resumeDevice` set in the machine's own configuration.nix; both are asserted.  |
