# Roles

!!! warning "Auto-generated"
    Do not edit by hand — regenerate with `gendocs` in the devShell.

Machine role modules. Enable exactly the roles that apply to a machine.

| Option | Type | Description |
|--------|------|-------------|
| `clanarchy.roles.laptop.enable` | `boolean` | Whether to enable laptop role. |
| `clanarchy.roles.laptop.framework.enable` | `boolean` | Whether to enable Framework-specific hardware (fprintd, fwupd, backpack-wake udev rule). |
| `clanarchy.roles.rpi.enable` | `boolean` | Whether to enable Raspberry Pi role (headless, no desktop by default). |
| `clanarchy.roles.server.enable` | `boolean` | Whether to enable server role (headless, SSH, no GUI). |
| `clanarchy.roles.vm.enable` | `boolean` | Whether to enable VM role (QEMU/KVM guest, server defaults + optional desktop). |
