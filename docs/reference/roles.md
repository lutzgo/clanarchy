# Roles

!!! info "Regenerate"
    Run `gendocs` in the devShell to populate this page with live option data.

Machine role modules. Enable exactly the roles that apply to a machine.

Source: `modules/roles/`

| Option | Type | Description |
|--------|------|-------------|
| `clanarchy.roles.laptop.enable` | `boolean` | Whether to enable laptop role. |
| `clanarchy.roles.laptop.cpu` | `one of "amd", "intel"` | CPU/GPU vendor for hardware-specific driver and env var tweaks. |
| `clanarchy.roles.laptop.framework.enable` | `boolean` | Whether to enable Framework-specific hardware (fprintd, fwupd, backpack-wake udev rule). |
| `clanarchy.roles.server.enable` | `boolean` | Whether to enable server role (headless, SSH, no GUI). |
| `clanarchy.roles.vm.enable` | `boolean` | Whether to enable VM role (QEMU/KVM guest, server defaults + optional desktop). |
| `clanarchy.roles.rpi.enable` | `boolean` | Whether to enable Raspberry Pi role (headless, no desktop by default). |
