# Hardware

!!! warning "Auto-generated"
    Do not edit by hand — regenerate with `gendocs` in the devShell.

Hardware-specific options. Set these to match the physical machine.

| Option | Type | Description |
|--------|------|-------------|
| `clanarchy.display.scale` | `floating point number` | Physical display scale hint. Set to 1.0 for standard-DPI panels (e.g. 1366×768 at ~100 PPI), 1.25 for mid-range (e.g. Framework 13 2256×1504 at ~200 PPI), or 2.0 for 4K/5K at ≥ 220 PPI.  This value controls pre-compositor settings (systemd-boot console mode, Linux console font). The compositor output scale is configured separately via clanarchy.desktop.{niri,labwc}.display.scale.  |
| `clanarchy.hardware.cpu` | `one of "amd", "intel"` | CPU/GPU vendor — selects hardware-specific drivers and env vars (ROCm vs Intel media). |
| `clanarchy.hardware.gpu.amd.enable` | `boolean` | Whether to enable AMD GPU baseline (amdgpu kernel module + mesa + Rusticl). |
| `clanarchy.hardware.gpu.amd.rocm.enable` | `boolean` | Whether to enable ROCm compute stack (HIP runtime, OpenCL ICD, rocminfo). |
| `clanarchy.hardware.gpu.intel.enable` | `boolean` | Whether to enable Intel GPU media driver (intel-media-driver). |
| `clanarchy.hardware.zsa.enable` | `boolean` | Whether to enable ZSA keyboard support (Voyager, Moonlander, Planck EZ, ErgoDox EZ).  Installs the ZSA udev rules so the Oryx web configurator and Keymapp can reach the keyboard for live training and flashing. Access is granted by `uaccess` to the active local seat session, so no group membership is needed and none is created . |
| `clanarchy.hardware.zsa.keymapp.enable` | `boolean` | Install Keymapp, ZSA's native desktop configurator.  On by default whenever `clanarchy.hardware.zsa.enable` is set, because it is the supported path for the Voyager and the only one that does not depend on the browser implementing WebHID.  NOTE: Keymapp is UNFREE. A machine with `nixpkgs.config.allowUnfree` left at `false` must set this to `false` explicitly, or evaluation fails. It is a separate toggle rather than part of `enable` so that turning on a udev rule cannot drag an unfree package onto a machine that has not opted into unfree software.  |
| `clanarchy.hardware.zsa.wally.enable` | `boolean` | Install `wally-cli`, ZSA's older command-line flasher (MIT).  Off by default: for the Voyager, Keymapp supersedes it, and Wally's remaining use is flashing a firmware file built outside Oryx — a QMK source build rather than a layout downloaded from configure.zsa.io. Turn it on if that is what you are doing; it needs no extra udev rules, since it flashes through the same `ignition_dfu` device the rules above already tag.  |
| `clanarchy.locale.keyboard.layout` | `string` | XKB keyboard layout (e.g. "us", "de"). Applied to GDM/X11 sessions and exported as XKB_DEFAULT_LAYOUT. Niri reads this via osConfig in niri-hm.nix.  |
| `clanarchy.locale.keyboard.options` | `null or string` | XKB options, comma-separated. null = no extra options. Example: "compose:ralt" makes Right Alt the Compose key, enabling German Umlaut input on a US keyboard.  |
| `clanarchy.locale.keyboard.variant` | `null or string` | XKB keyboard variant. null = use the layout's default variant. |
| `clanarchy.locale.language` | `one of "en_US", "de_DE"` | System locale and application language. "en_US" → English US for CLI and GUI. "de_DE" → German for CLI and GUI (GNOME displays in German).  |
