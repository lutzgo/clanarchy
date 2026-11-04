# @clanarchy/machine-type

Assigns each machine to a hardware/role archetype, applying only the relevant
role module rather than importing all modules everywhere.

## Roles

| Role     | Description |
|----------|-------------|
| `laptop` | GPU drivers, power management, lid-switch. Optional Framework hardware support (`settings.framework.enable`). |
| `server` | SSH hardening, nix store optimisation, weekly GC. |
| `htpc`   | Couch machine: Steam Big Picture, Kodi, the fleet's niri + Noctalia desktop, and optionally Plasma Bigscreen, switchable at runtime. |
| `vm`     | QEMU/KVM guest tools on top of the server baseline. |
| `rpi`    | Raspberry Pi redistributable firmware. Boot loader configured per-machine. |

## HTPC settings

| Setting | Description |
|---------|-------------|
| `user` | The couch user. Owns the session state dir; may restart the display manager. |
| `defaultSession` | `gamescope` \| `kodi` \| `desktop` \| `bigscreen` — where to land before any choice is made. (`plasma`, the desktop arm's old name, is still accepted by the switcher.) |
| `autologin.enable` | Passwordless autologin for the couch user. Also turns on SDDM `Relogin`, so a session that ends is retried instead of leaving a greeter on the TV. |
| `display.gpuPciAddress` | PCI address of the GPU the TV hangs off. Set it: the session then waits for a connected output there before starting a compositor, instead of segfaulting against a TV that is switched off. |
| `bigscreen.enable` | Build the Plasma Bigscreen container. Off — it showed a black screen and the mode is parked (see `modules/desktop/bigscreen.nix`). |
| `bigscreen.gpu.pciAddress` | PCI address of the GPU driving the TV, e.g. `"0000:03:00.0"`. |
| `bigscreen.uid` / `bigscreen.gid` | Numeric ids of the couch user. Must match the host — nspawn does not remap them. |

## Switching sessions

No terminal needed:

| From | Do | Lands in |
|------|----|----------|
| Big Picture | power menu → **Switch to Desktop** | desktop |
| Big Picture | Library → **Media Mode** | Kodi |
| Kodi | power menu → **Exit** | Big Picture |
| Kodi | Favourites → **Gaming Mode** / **Desktop** | Big Picture / desktop |
| desktop | launcher → **Return to Gaming Mode** / **Return to Media Mode** | Big Picture / Kodi |

Over SSH: `clanarchy-session-select gamescope|kodi|desktop`, as the couch user.

The Bigscreen container dates from when Plasma Bigscreen could not run on the
host; see [the HTPC guide](../docs/guides/htpc-bigscreen.md) for that history.

## Usage

```nix
# clan.nix
inventory.instances.machine-type = {
  module.input = "self";
  module.name  = "@clanarchy/machine-type";
  roles.laptop.machines.miralda.settings.framework.enable = true;
  roles.laptop.machines.biene = {};
  roles.server.machines.homeserver = {};
};
```
