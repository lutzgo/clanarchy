# Hardware

!!! warning "Auto-generated"
    Do not edit by hand — regenerate with `gendocs` in the devShell.

Hardware-specific options. Set these to match the physical machine.

| Option | Type | Description |
|--------|------|-------------|
| `clanarchy.display.scale` | `floating point number` | Physical display scale hint. Set to 1.0 for standard-DPI panels (e.g. 1366×768 at ~100 PPI), 1.25 for mid-range (e.g. Framework 13 2256×1504 at ~200 PPI), or 2.0 for 4K/5K at ≥ 220 PPI.  This value controls pre-compositor settings (systemd-boot console mode, Linux console font). The compositor output scale is configured separately via clanarchy.desktop.{niri,labwc}.display.scale.  |
| `clanarchy.hardware.cpu` | `one of "amd", "intel"` | CPU/GPU vendor — selects hardware-specific drivers and env vars (ROCm vs Intel media). |
| `clanarchy.locale.keyboard.layout` | `string` | XKB keyboard layout (e.g. "us", "de"). Applied to GDM/X11 sessions and exported as XKB_DEFAULT_LAYOUT. Niri reads this via osConfig in niri-hm.nix.  |
| `clanarchy.locale.keyboard.options` | `null or string` | XKB options, comma-separated. null = no extra options. Example: "compose:ralt" makes Right Alt the Compose key, enabling German Umlaut input on a US keyboard.  |
| `clanarchy.locale.keyboard.variant` | `null or string` | XKB keyboard variant. null = use the layout's default variant. |
| `clanarchy.locale.language` | `one of "en_US", "de_DE"` | System locale and application language. "en_US" → English US for CLI and GUI. "de_DE" → German for CLI and GUI (GNOME displays in German).  |
