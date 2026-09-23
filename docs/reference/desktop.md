# Desktop

!!! warning "Auto-generated"
    Do not edit by hand — regenerate with `gendocs` in the devShell.

Desktop environment modules (Niri, GNOME, KDE). Enable exactly the one that applies to the machine.

| Option | Type | Description |
|--------|------|-------------|
| `clanarchy.desktop.labwc.display.scale` | `floating point number` | Output scale factor for the primary display (eDP-1). |
| `clanarchy.desktop.labwc.enable` | `boolean` | Whether to enable labwc Wayland compositor with Noctalia. |
| `clanarchy.desktop.labwc.input.pointerSpeed` | `floating point number` | Touchpad acceleration speed. Range: -1.0 (slowest) to 1.0 (fastest). |
| `clanarchy.desktop.labwc.keepassxc.enable` | `boolean` | Whether to enable autostart KeePassXC password manager. |
| `clanarchy.desktop.labwc.nextcloud.enable` | `boolean` | Whether to enable autostart Nextcloud desktop sync client. |
| `clanarchy.desktop.labwc.valent.enable` | `boolean` | Whether to enable Valent KDE Connect daemon (for Noctalia valent-connect plugin). |
| `clanarchy.desktop.niri.blur.enable` | `boolean` | Whether to enable background blur behind translucent windows and Noctalia layer surfaces. |
| `clanarchy.desktop.niri.blur.noise` | `floating point number` | Film grain mixed into the blurred backdrop, 0.0 to 1.0. Masks the banding a blurred gradient otherwise shows. |
| `clanarchy.desktop.niri.blur.offset` | `floating point number` | Sampling offset per pass, in pixels. Widens the blur more cheaply than another pass does, at the cost of banding once it outruns the sample count. |
| `clanarchy.desktop.niri.blur.passes` | `integer between 1 and 10 (both inclusive)` | Number of dual-Kawase blur passes. Each pass widens the blur and costs a further GPU round-trip over the whole blurred region. |
| `clanarchy.desktop.niri.blur.saturation` | `floating point number` | Saturation of the blurred backdrop. 1.0 leaves colors as sampled; above 1.0 compensates for the wash-out that averaging the wallpaper causes. |
| `clanarchy.desktop.niri.border.activeColor` | `null or string` | Border colour of the focused window, as #RRGGBB or #RRGGBBAA. Null keeps niri's own default. |
| `clanarchy.desktop.niri.border.enable` | `boolean` | Whether to enable a border drawn around every window. |
| `clanarchy.desktop.niri.border.inactiveColor` | `null or string` | Border colour of unfocused windows. Null keeps niri's own default. |
| `clanarchy.desktop.niri.border.width` | `integer between 0 and 32 (both inclusive)` | Window border thickness in logical pixels. Drawn outside the window, so raising it eats into the gaps rather than into the window. |
| `clanarchy.desktop.niri.cornerRadius` | `floating point number` | Rounded-corner radius for windows, in logical pixels. 0.0 gives square corners. Applied to all four corners together and paired with clip-to-geometry, so window content is clipped to the rounding instead of poking through it. |
| `clanarchy.desktop.niri.display.resolution.height` | `signed integer` | Vertical resolution of the primary display. |
| `clanarchy.desktop.niri.display.resolution.width` | `signed integer` | Horizontal resolution of the primary display. |
| `clanarchy.desktop.niri.display.scale` | `floating point number` | Output scale factor for the primary display (eDP-1). |
| `clanarchy.desktop.niri.enable` | `boolean` | Whether to enable Niri Wayland compositor with Noctalia. |
| `clanarchy.desktop.niri.focusRing.activeColor` | `null or string` | Focus-ring colour on the focused window, as #RRGGBB or #RRGGBBAA. Null keeps niri's own default, which is a light blue and reads as cyan against most palettes. |
| `clanarchy.desktop.niri.focusRing.enable` | `boolean` | Whether to enable a ring drawn around the focused window, outside its border. |
| `clanarchy.desktop.niri.focusRing.inactiveColor` | `null or string` | Focus-ring colour on unfocused windows — visible only on the active window of an unfocused monitor. Null keeps niri's own default. |
| `clanarchy.desktop.niri.focusRing.width` | `integer between 0 and 32 (both inclusive)` | Focus-ring thickness in logical pixels. |
| `clanarchy.desktop.niri.fprintd.enable` | `boolean` | Whether to enable fingerprint authentication via fprintd. |
| `clanarchy.desktop.niri.input.pointerSpeed` | `floating point number` | Pointer acceleration speed applied to both touchpad and mouse. Range: -1.0 (slowest) to 1.0 (fastest). 0.0 is libinput's neutral baseline. |
| `clanarchy.desktop.niri.opacity.extraOpaqueApps` | `list of string` | app-id regexes appended to `opaqueApps`. Use this rather than `opaqueApps` when a machine needs one more entry, so it keeps picking up changes to the shared default. |
| `clanarchy.desktop.niri.opacity.focused` | `floating point number` | Baseline window opacity for focused windows. |
| `clanarchy.desktop.niri.opacity.opaqueApps` | `list of string` | app-id regexes held at full opacity while focused. These are the apps that render their own chrome and become unreadable when translucent. Unfocused they fall through to `unfocused` and get blurred like anything else. Note that a focused window not on this list gets no blur either — blur is applied to foot and to unfocused windows only — so an app missing from here looks transparent *and* unblurred. Setting this replaces the list; to keep the defaults and add to them, use `extraOpaqueApps`. Check an app's real app-id with `niri msg windows`. |
| `clanarchy.desktop.niri.opacity.terminal` | `floating point number` | Opacity of focused foot terminals, overriding `focused` for them alone — terminals want to stay readable where other windows can afford to be translucent. This is a later window-rule than the `focused` baseline, so for a foot window `focused` has no effect at all; change this instead. Unfocused foot windows still take `unfocused`. |
| `clanarchy.desktop.niri.opacity.unfocused` | `floating point number` | Window opacity for unfocused windows — the fleet's inactive-dim setting. The gap between this and `focused` is the dim; setting them equal removes it. |
| `clanarchy.desktop.niri.shadow.color` | `string` | Shadow color of the focused window, as #RRGGBBAA. The alpha channel is the shadow's strength; niri's default is 70/255. |
| `clanarchy.desktop.niri.shadow.drawBehindWindow` | `boolean` | Draw the shadow behind the window rather than only around it. niri cannot know a client-side-decorated window's corner radius and assumes square corners, which leaves shadow artifacts inside the rounded corners of CSD windows; this fixes them. Keep it false while windows are translucent — every window here is, via clanarchy.desktop.niri.opacity — because a shadow drawn behind a window is visible through it. |
| `clanarchy.desktop.niri.shadow.enable` | `boolean` | Whether to enable drop shadows behind windows. |
| `clanarchy.desktop.niri.shadow.inactiveColor` | `null or string` | Shadow color for unfocused windows, as #RRGGBBAA. Null keeps niri's own behaviour, which already draws inactive windows with a more transparent version of `color` — set this only to override how far it fades. This is the colour-only path; for a differently *shaped* shadow on unfocused windows, use `shadow.unfocused` below. |
| `clanarchy.desktop.niri.shadow.offset.x` | `integer or floating point number between -64 and 64 (both inclusive)` | Horizontal shadow displacement in logical pixels. Positive moves it right. |
| `clanarchy.desktop.niri.shadow.offset.y` | `integer or floating point number between -64 and 64 (both inclusive)` | Vertical shadow displacement in logical pixels. Positive moves it down, which is what makes the window read as lifted. |
| `clanarchy.desktop.niri.shadow.softness` | `nonnegative integer or floating point number, meaning >=0` | Blur radius of the shadow, in logical pixels. This is the soft falloff at the edge; 0 gives a hard-edged slab. |
| `clanarchy.desktop.niri.shadow.spread` | `integer or floating point number between -64 and 64 (both inclusive)` | How far the shadow extends past the window before the falloff starts, in logical pixels. Negative values pull it inside the window's footprint. |
| `clanarchy.desktop.niri.shadow.unfocused.color` | `null or string` | Shadow colour for unfocused windows. Null inherits `shadow.color`. Set here rather than in `shadow.inactiveColor` when you are already using this block — the window-rule is evaluated after the layout node, so this wins. |
| `clanarchy.desktop.niri.shadow.unfocused.enable` | `boolean` | Whether to enable a separately shaped shadow for unfocused windows, emitted as an is-focused=false window-rule. |
| `clanarchy.desktop.niri.shadow.unfocused.offset.x` | `null or integer or floating point number between -64 and 64 (both inclusive)` | Horizontal shadow offset for unfocused windows. Null inherits `shadow.offset.x`. |
| `clanarchy.desktop.niri.shadow.unfocused.offset.y` | `null or integer or floating point number between -64 and 64 (both inclusive)` | Vertical shadow offset for unfocused windows. Null inherits `shadow.offset.y`. |
| `clanarchy.desktop.niri.shadow.unfocused.softness` | `null or (nonnegative integer or floating point number, meaning >=0)` | Shadow softness for unfocused windows. Null inherits `shadow.softness`. |
| `clanarchy.desktop.niri.shadow.unfocused.spread` | `null or integer or floating point number between -64 and 64 (both inclusive)` | Shadow spread for unfocused windows. Null inherits `shadow.spread`. |
| `clanarchy.desktop.niri.wallpaper.workspaceColors` | `list of string` | Per-workspace accent colors (5 entries for workspaces 1-5). Reserved for future Noctalia workspace theming. |
| `clanarchy.desktop.niri.xwayland.enable` | `boolean` | Whether to enable Xwayland for X11-only applications, via xwayland-satellite. |
| `clanarchy.iconTheme.name` | `string` | GTK icon theme name applied to all graphical users. Must match the Name field in the theme package's index.theme.  |
| `clanarchy.iconTheme.package` | `package` | Icon theme package.  The default builds a Stylix-recolored Papirus-Dark: folder icons are tinted with the Stylix base0D accent color. Set to pkgs.papirus-icon-theme (and name to "Papirus-Dark") to opt out of the color customization.  |
