# @clanarchy/users

Assigns user profiles to machines via inventory, importing only the relevant
user module for each machine.

`admin` is **not** managed here — it is imported directly in `flake.nix`
because it also sets system-wide Home Manager options (`useGlobalPkgs`,
`useUserPackages`, `mutableUsers = false`) that must be present on every
machine regardless of clan inventory.

## Roles

| Role     | Description |
|----------|-------------|
| `lgo`    | Power user profile: Niri desktop, browsers, devtools, YubiKey tools. |
| `sabine` | Personal user profile: GNOME, LibreOffice, Thunderbird, Firefox. |

## Usage

```nix
# clan.nix
inventory.instances.users = {
  module.input = "self";
  module.name  = "@clanarchy/users";
  roles.lgo.machines.miralda    = {};
  roles.sabine.machines.biene   = {};
};
```
