# Noctalia shell profiles

Sabine's `biene` runs the [Noctalia](https://github.com/noctalia-dev/noctalia-shell) desktop shell on top of labwc. Noctalia lets her save a custom layout (panel positions, dock behaviour, widget config) as a **Shell Profile**. This guide covers the save/restore flow so Sabine's layout survives a fresh install.

## After first-time install

When `biene` is first installed via `clan machines install biene`, Noctalia boots with declarative defaults from `modules/desktop/labwc-hm.nix`. Plugins listed in `plugins.json` are declared — Noctalia re-downloads their source files from the plugin store on first run.

Sabine then customises her layout via the Noctalia UI, and saves it:

**Settings → Shell Profiles → Save Profile → name it "Sabine"**

Every subsequent `clan machines update biene` restores that profile automatically via the HM activation hook in `modules/users/sabine.nix`. She only needs to save once.

## Pinning the profile so it survives fresh installs

The activation hook reads a JSON blob from `modules/users/sabine-noctalia-settings.json` (or a sibling file — check what's checked in under `modules/users/sabine-noctalia/`). If that file is not committed, Sabine has to re-save the profile on every fresh install.

To pin her current layout into the repo:

```bash
scp root@biene.local:/home/sabine/.config/noctalia/plugins/shell-profiles/assets/profiles/Sabine/settings.json \
    modules/users/sabine-noctalia-settings.json
```

Then wire it into `modules/users/sabine.nix` under `home-manager.users.sabine`:

```nix
xdg.configFile."noctalia/plugins/shell-profiles/assets/profiles/Sabine/settings.json".source =
  ./sabine-noctalia-settings.json;
```

Commit both files. From that point on, any fresh install of `biene` will boot straight into Sabine's saved layout — no manual re-save needed.

## Adding new Noctalia plugins

Plugins are declared in `xdg.configFile."noctalia/plugins.json"` inside `modules/users/sabine.nix` with `force = true`. Add a new entry to the `states` map and run `clan machines update biene`; Noctalia will pull the plugin from its store on next launch.
