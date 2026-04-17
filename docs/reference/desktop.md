# Desktop (Niri)

!!! info "Regenerate"
    Run `gendocs` in the devShell to populate this page with live option data.

Options for the Niri Wayland compositor and its supporting services.

Source: `modules/desktop/niri.nix`

| Option | Type | Description |
|--------|------|-------------|
| `clanarchy.desktop.niri.enable` | `boolean` | Whether to enable Niri Wayland compositor with Noctalia. |
| `clanarchy.desktop.niri.display.scale` | `floating point number` | Output scale factor for the primary display (eDP-1). |
| `clanarchy.desktop.niri.display.resolution.width` | `signed integer` | Horizontal resolution of the primary display. |
| `clanarchy.desktop.niri.display.resolution.height` | `signed integer` | Vertical resolution of the primary display. |
| `clanarchy.desktop.niri.fprintd.enable` | `boolean` | Whether to enable fingerprint authentication via fprintd. |
| `clanarchy.desktop.niri.opacity.focused` | `floating point number` | Baseline window opacity for focused windows. |
| `clanarchy.desktop.niri.opacity.unfocused` | `floating point number` | Window opacity for unfocused windows. |
| `clanarchy.desktop.niri.wallpaper.workspaceColors` | `list of string` | Per-workspace accent colors (5 entries for workspaces 1–5). |
