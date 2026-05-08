# @clanarchy/software

Assigns browser and email applications to machines via inventory.
Multiple roles can be combined simultaneously on a single machine.

Each role has a `user` setting (default: `"sabine"`) that controls which
Home Manager user receives the per-user configuration (overrides files,
native-messaging manifests, home packages).

Unfree browsers (`chrome`, `edge`) must be listed in the machine's
`nixpkgs.config.allowUnfreePredicate` (e.g. `machines/miralda/apps.nix`).

## Browser roles

| Role       | What it provides |
|------------|-----------------|
| `librewolf` | System pkg, privacy overrides (`librewolf.overrides.cfg`), KeePassXC native messaging |
| `firefox`   | `programs.firefox.enable`; profile and Stylix theming left to per-machine config |
| `chromium`  | `ungoogled-chromium` system pkg (flags baked in via `clan.nix` overlay) |
| `chrome`    | `google-chrome` system pkg + KeePassXC native messaging (unfree) |
| `edge`      | `microsoft-edge` system pkg (unfree) |

## Email roles

| Role          | What it provides |
|---------------|-----------------|
| `thunderbird` | Thunderbird in `home.packages` |
| `geary`       | Geary in `home.packages` |

## Usage

```nix
# clan.nix
inventory.instances.software = {
  module.input = "self";
  module.name  = "@clanarchy/software";
  # lgo on miralda: all browsers, no email
  roles.librewolf.machines.miralda.settings.user  = "lgo";
  roles.firefox.machines.miralda.settings.user    = "lgo";
  roles.chromium.machines.miralda.settings.user   = "lgo";
  roles.chrome.machines.miralda.settings.user     = "lgo";
  roles.edge.machines.miralda                     = {};
  # sabine on biene: librewolf + edge + both email clients
  roles.librewolf.machines.biene.settings.user    = "sabine";
  roles.edge.machines.biene                       = {};
  roles.thunderbird.machines.biene.settings.user  = "sabine";
  roles.geary.machines.biene.settings.user        = "sabine";
};
```
