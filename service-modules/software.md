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
| `librewolf` | System pkg, privacy overrides (`librewolf.overrides.cfg`), KeePassXC native messaging, policy-installed extensions |
| `firefox`   | `programs.firefox.enable`; profile and Stylix theming left to per-machine config |
| `chromium`  | `ungoogled-chromium` system pkg (flags baked in via `clan.nix` overlay) |
| `chrome`    | `google-chrome` system pkg + KeePassXC native messaging (unfree) |
| `edge`      | `microsoft-edge` system pkg (unfree) |

### LibreWolf extensions

`roles.librewolf.machines.<m>.settings.extensions` installs add-ons through an
`ExtensionSettings` enterprise policy merged into the wrapped package. Empty by
default; setting it rebuilds LibreWolf for that machine.

```nix
roles.librewolf.machines.miralda.settings.extensions = [
  { id = "floccus@handmadeideas.org";
    installUrl = "https://addons.mozilla.org/firefox/downloads/latest/floccus@handmadeideas.org/latest.xpi"; }
];
```

- `id` is the **WebExtension ID** from the add-on's manifest, not the AMO slug.
  A wrong value installs nothing and reports nothing.
- The setting is **machine-wide**, not per-user — a Firefox-family policy lives
  in the package, and `environment.systemPackages` installs one per machine.
- Entries **merge with** LibreWolf's own shipped policies (its uBlock Origin
  entry and the `"*": allowed` rule survive). Verify with `about:policies`.
- The `.xpi` is fetched from `installUrl` at first launch, not pinned in the
  store. Use a `file://` path if that matters. `nixExtensions` would pin it but
  also blocks every manually installed add-on — see the option's description.

Only LibreWolf has this setting. The other three browsers each need a different
mechanism; the table is in the header of
`machines/miralda/home-modules/browsers.nix`.

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
