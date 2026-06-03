# Roles

!!! warning "Auto-generated"
    Do not edit by hand — regenerate with `gendocs` in the devShell.

Machine role modules. Enable exactly the roles that apply to a machine.

| Option | Type | Description |
|--------|------|-------------|
| `clanarchy.roles.laptop.enable` | `boolean` | Whether to enable laptop role. |
| `clanarchy.roles.laptop.framework.enable` | `boolean` | Whether to enable Framework-specific hardware (fprintd, fwupd, backpack-wake udev rule). |
| `clanarchy.roles.laptop.hybridSleep.enable` | `boolean` | Enable hybrid-sleep on lid close (suspends to RAM and writes hibernation image simultaneously). Requires a swap partition sized ≥ RAM and boot.resumeDevice set in the machine's own configuration.nix. Disable for machines without swap until a swap partition is added.  |
