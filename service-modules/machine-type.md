# @clanarchy/machine-type

Assigns each machine to a hardware/role archetype, applying only the relevant
role module rather than importing all modules everywhere.

## Roles

| Role     | Description |
|----------|-------------|
| `laptop` | GPU drivers, power management, lid-switch. Optional Framework hardware support (`settings.framework.enable`). |
| `server` | SSH hardening, nix store optimisation, weekly GC. |
| `vm`     | QEMU/KVM guest tools on top of the server baseline. |
| `rpi`    | Raspberry Pi redistributable firmware. Boot loader configured per-machine. |

## Usage

```nix
# clan.nix
inventory.instances.machine-type = {
  module.input = "self";
  module.name  = "@clanarchy/machine-type";
  roles.laptop.machines.miralda.settings.framework.enable = true;
  roles.laptop.machines.biene = {};
  roles.server.machines.homeserver = {};
};
```
