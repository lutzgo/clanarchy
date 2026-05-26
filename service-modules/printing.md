# @clanarchy/printing

Enables HP printing and scanning:

- **CUPS** with `hplip` drivers
- **SANE** scanning backend via `hplip`
- Adds `lgo` to `lp` and `scanner` groups

## Usage

```nix
# clan.nix — inventory.instances
printing = {
  module.input = "self";
  module.name  = "@clanarchy/printing";
  roles.default.machines.miralda = { };
};
```
