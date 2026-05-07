# Desktop

!!! warning "Auto-generated"
    Do not edit by hand — regenerate with `gendocs` in the devShell.

Desktop environment modules (Niri, GNOME, KDE). Enable exactly the one that applies to the machine.

| Option | Type | Description |
|--------|------|-------------|
| `clanarchy.desktop.gnome.enable` | `boolean` | Whether to enable GNOME desktop environment. |
| `clanarchy.desktop.gnome.sabine` | `boolean` | Whether to enable Sabine's personal GNOME dconf defaults. |
| `clanarchy.desktop.kde.enable` | `boolean` | Whether to enable KDE Plasma 6 desktop environment. |
| `clanarchy.desktop.kde.fprintd.enable` | `boolean` | Whether to enable fingerprint authentication via fprintd. |
| `clanarchy.desktop.niri.display.resolution.height` | `signed integer` | Vertical resolution of the primary display. |
| `clanarchy.desktop.niri.display.resolution.width` | `signed integer` | Horizontal resolution of the primary display. |
| `clanarchy.desktop.niri.display.scale` | `floating point number` | Output scale factor for the primary display (eDP-1). |
| `clanarchy.desktop.niri.enable` | `boolean` | Whether to enable Niri Wayland compositor with Noctalia. |
| `clanarchy.desktop.niri.fprintd.enable` | `boolean` | Whether to enable fingerprint authentication via fprintd. |
| `clanarchy.desktop.niri.input.pointerSpeed` | `floating point number` | Pointer acceleration speed applied to both touchpad and mouse. Range: -1.0 (slowest) to 1.0 (fastest). 0.0 is libinput's neutral baseline. |
| `clanarchy.desktop.niri.opacity.focused` | `floating point number` | Baseline window opacity for focused windows. |
| `clanarchy.desktop.niri.opacity.unfocused` | `floating point number` | Window opacity for unfocused windows. |
| `clanarchy.desktop.niri.wallpaper.workspaceColors` | `list of string` | Per-workspace accent colors (5 entries for workspaces 1-5). Reserved for future Noctalia workspace theming. |
