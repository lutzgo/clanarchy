# @clanarchy/desktop

Assigns each machine a desktop environment by importing and enabling only the
relevant desktop module. Replaces the previous pattern of importing all
`modules/desktop/*.nix` into every machine and toggling them via enable flags.

## Roles

| Role    | Description |
|---------|-------------|
| `niri`  | Niri Wayland compositor, UWSM session management, Noctalia shell, regreet greeter. |
| `labwc` | labwc stacking Wayland compositor, UWSM, Noctalia shell, regreet greeter. |
| `gnome` | GNOME desktop with GDM. Optional Sabine dconf defaults (`settings.sabine`). |
| `kde`   | KDE Plasma 6 with SDDM Wayland session. |

## Niri settings

| Setting | Default | Description |
|---------|---------|-------------|
| `display.scale` | `1.25` | Output scale factor for eDP-1 |
| `display.width` | `2256` | Horizontal resolution |
| `display.height` | `1504` | Vertical resolution |
| `input.pointerSpeed` | `0.4` | Touchpad acceleration (-1.0 to 1.0) |

## labwc settings

| Setting | Default | Description |
|---------|---------|-------------|
| `display.scale` | `1.25` | Output scale factor for eDP-1 (via kanshi) |
| `input.pointerSpeed` | `0.4` | Touchpad acceleration (-1.0 to 1.0) |

## Usage

```nix
# clan.nix
inventory.instances.desktop = {
  module.input = "self";
  module.name  = "@clanarchy/desktop";
  roles.niri.machines.miralda = {};
  roles.labwc.machines.biene = {};
};
```
