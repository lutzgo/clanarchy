# Plasma Bigscreen on the TV

!!! failure "Bigscreen does not work in the container. It is parked and disabled."

    The `bigscreen` mode builds, deploys and starts — and shows nothing. It
    cannot be made to work inside a container, for a structural reason
    described under [Why it cannot work](#why-it-cannot-work).
    `clanarchy.roles.htpc.bigscreen.enable` is **off on ernst** and should stay
    off; the TV runs the gamescope Steam session with Jellyfin Media Player.

    The container and the session-switching machinery are kept, because both
    are correct and either escape route reuses most of them.

`ernst` carries the `htpc` role, which offers three living-room modes,
switchable at runtime:

| Mode | What it is | Where it runs |
|------|------------|---------------|
| `gamescope` | Steam Big Picture | Host, stock nixpkgs 26.05 — **what ernst runs** |
| `plasma` | KDE Plasma 6.6.6 desktop | Host, stock nixpkgs 26.05 |
| `bigscreen` | Plasma Bigscreen 6.7.4 | nspawn container — **does not work, not built** |

Switch between them from the couch account:

```bash
clanarchy-session-select gamescope    # or: plasma
```

The choice is written to `/var/lib/clanarchy-session/current`, persists across
reboots, and is re-applied at boot by `clanarchy-htpc-boot.service`.

## The TV must be awake for the session to start

A TV that is switched off, or showing another input, drops HPD — its connector
reads `disconnected`, exactly like an unplugged cable. gamescope answers a card
with no connected output by failing backend creation and then segfaulting:

```
drm: opening DRM node '/dev/dri/card1'
drm:   HDMI-A-1 (disconnected)
drm: cannot find any connected connector!
Error drm: Failed to find a primary plane
Failed to create backend.
steam-gamescope: … Segmentation fault (core dumped)
```

So the session waits for a connected output on the GPU named by
`clanarchy.roles.htpc.display.gpuPciAddress` before starting a compositor, and
SDDM is configured with `Relogin=true` so a session that does end is retried
instead of leaving the greeter on screen. Between them: turn the TV on at any
point and Big Picture comes up; nothing needs a keyboard.

Check what the machine can see:

```bash
for c in /sys/class/drm/card*-*/; do
  printf '%s %s\n' "$(basename "$c")" "$(cat "$c/status")"
done
```

On ernst the TV is `card1-HDMI-A-1` (dGPU, `0000:03:00.0`) and the Comet KVM is
`card0-HDMI-A-2` (iGPU). If the TV shows `disconnected` while it is switched on,
that is a cable or input-selection problem, not a NixOS one — and the session
log says so:

```
clanarchy-session: no connected output on … — waiting for the TV
```

(in `/home/go/.local/share/sddm/wayland-session.log`).

## Why it cannot work

Two requirements are mutually exclusive, and a container can satisfy only one:

**Plasma 6.7 needs logind.** `startplasma-wayland` drives the entire session
through systemd *user* units — it starts `plasma-workspace-wayland.target` by
name rather than exec'ing kwin and plasmashell. There is no opt-out; 6.7.4 has
no `PLASMA_USE_SYSTEMD` / `KDE_NO_SYSTEMD_BOOT` knob (checked in the binary and
the libraries). `systemctl --user` needs `user@<uid>.service`, which needs
`user-runtime-dir@<uid>.service`, whose `systemd-user-runtime-dir` asks logind
for the user record and exits 1 without it.

**KWin needs logind gone.** It has no libseat backend and no seatless DRM path.
Given logind but no active *graphical* session it logs:

```
kwin_core: Could not determine the active graphical session
```

and creates zero outputs, which surfaces in every client as:

```
qt.qpa.wayland: There are no outputs - creating placeholder screen
```

A session that runs, holds no display, and draws nothing.

**A container cannot supply the seat.** Seat assignment is done by udev on the
host, and there is no VT inside a container for a graphical session to occupy.
So Plasma needs logind present and KWin needs it effectively absent.

### What was tried

Recorded so it isn't repeated:

| Attempt | Result |
|---|---|
| Bare nspawn proof-of-concept | KWin **did** create a `DrmOutput` on the TV — with no systemd, so neither logind nor Plasma's user units. This is what made the approach look feasible; it proved the compositor could take the card, not that the session could run. |
| Unit `PATH` + system profile | Fixed `plasma-bigscreen-common-env`, `envmanager`, `dbus-run-session` resolution. Necessary, not sufficient. |
| `services.desktopManager.plasma6.enable` in the container | Necessary — without it there were no Plasma user units and no kwin at all. Brought logind with it. |
| `KWIN_DRM_DEVICES` | Reaches kwin (verified via `/proc/<pid>/environ`). Not the problem. |
| Real `/dev/dri/card1` instead of the udev alias | No change. |
| Granting the denied iGPU render node | Cleared that error; output count stayed zero. A red herring. |
| `PAMName=login` | Creates a logind session, but a `pts` one PAM itself labels *"not a graphical session"*. KWin unmoved. |
| Suppressing logind | Breaks `user-runtime-dir`, so the session unit never starts. Strictly worse. Reverted. |

### Routes that would work

Neither taken yet:

- **Plasma 6.7.4 on the host**, replacing 6.6.6. A real seat and VT exist there,
  satisfying both requirements at once. Costs: ernst's desktop tracks floating
  `nixpkgs-unstable` and diverges from the rest of the fleet.
- **A VM with the dGPU passed through.** Real seat, real VT, no fighting. Costs:
  VFIO binds the card exclusively, so ROCm/Ollama loses it whenever the TV
  session runs — the mutually-exclusive outcome `clan.nix` explicitly rejects.

## Why Bigscreen is in a container

This is the question worth answering up front, because "just add
`kdePackages.plasma-bigscreen` to `environment.systemPackages`" is the obvious
move and it does not work.

Plasma Bigscreen is **not in nixpkgs 26.05** — the top-level attribute is a
throwing alias, and `kdePackages.plasma-bigscreen` does not exist. It appears
only on nixpkgs-unstable, at 6.7.4. The fleet's stable machines run Plasma
6.6.6, and the two generations cannot share one system for two reasons:

**1. The session entry point resolves through `PATH`.** The installed
`bin/plasma-bigscreen-wayland` is an unwrapped `/bin/sh` script. Only its
`--exit-with-session=` argument gets store-path substitution; the actual
compositor launch is a bare call:

```sh
startplasma-wayland --xwayland --libinput --exit-with-session=/nix/store/…-plasma-workspace-6.7.4/libexec/startplasma-waylandsession
```

On a 26.05 host, `startplasma-wayland` resolves to plasma-workspace **6.6.6**,
which is then handed Bigscreen's 6.7.4 shell and libplasma.

**2. The systemd user units collide — and this one has no workaround.** Both
generations ship units under identical names:

```
plasma-plasmashell.service   plasma-workspace-wayland.target
plasma-kcminit.service       plasma-krunner.service          …
```

`services.desktopManager.plasma6.enable` (pulled in by the HTPC role via
`modules/desktop/kde.nix`) registers 6.6.6's copies system-wide. 6.7.4's
`startplasma-wayland` starts those targets **by name**, so systemd hands it the
6.6.6 units and launches 6.6.6 binaries. Registering 6.7.4's units alongside
collides on the same names: one generation wins, the other breaks.

A `--prefix PATH` overlay fixes problem 1 and does nothing about problem 2.
**A machine can host Plasma 6.6.6 or 6.7.4, not both.** The container is the
smallest boundary that gives Bigscreen its own store view, its own systemd
user-unit namespace and its own `nixpkgs.pkgs`, while still sharing the host
kernel and GPU.

## How the container gets the GPU

Verified on ernst against the real RX 7900 XTX before the module was written:

- **DRM master crosses the nspawn boundary** — but only with a device-cgroup
  entry. Without `allowedDevices`, `open()` on the card node returns `EPERM`
  inside the container *even as root*, and KWin reports "No suitable DRM
  devices have been found".
- **KWin works because the container has no logind.** KWin has no libseat
  backend and no seatless DRM path. On the host it asks logind for the device
  and gets `EPERM` from any session without a seat. Inside the container
  logind is absent entirely, so KWin falls back to opening the node directly —
  which the cgroup now permits. Running a compositor in a container is easier
  than running one over SSH.
- **`/run/opengl-driver` must exist inside the container**, or gbm device
  creation fails. `hardware.graphics.enable` in the container config provides
  it.
- **There is no VT.** `/dev/tty0` does not exist inside an nspawn container and
  cannot be made to. For a dedicated TV appliance this costs nothing, but it
  does mean this session can never be one arm of a VT-switched multi-seat
  setup.
- **It runs unprivileged.** Verified as uid 1001 with only `video`, `input`
  and `render` supplementary groups: shaders compile on the AMD card and KWin
  holds a `DrmOutput` on the TV connector.

### The kdeconnect QML dependency

`kdeconnect-kde` is in the container's package list deliberately, and removing
it breaks the homescreen. Plasma Bigscreen 6.7.4 ships
`indicators/KdeConnect.qml` and `indicators/PairWindow.qml`, both of which
`import org.kde.kdeconnect`, but the package does not carry kdeconnect-kde in
its closure. Without it the homescreen fails with:

```
module "org.kde.kdeconnect" is not installed
```

The usual suggested fix — an overlay wrapping `plasma-bigscreen-wayland` with a
`QML2_IMPORT_PATH` prefix — targets the wrong process. That QML is loaded by
**plasmashell**, which renders the plasmoid, not by the launcher script. In a
full NixOS container the fix is just to put the package in the system
environment, which is where plasmashell looks. Re-check whether upstream has
fixed it with:

```bash
nix path-info -r <plasma-bigscreen> | grep -c kdeconnect
```

### Why the GPU is pinned by PCI address

ernst has two AMD GPUs, and the card numbering is **inverted** relative to PCI
order:

```
pci-0000:03:00.0-card -> ../card1     # RX 7900 XTX  -> TV        (HDMI-A-1)
pci-0000:7b:00.0-card -> ../card0     # Granite Ridge iGPU -> KVM (HDMI-A-2)
```

Card numbering is enumeration order and can flip on a kernel bump. A flip
would put the TV session on the KVM's head and take the compute card away from
ROCm. So the module takes a PCI address and derives stable aliases from
`ENV{ID_PATH}`.

The aliases are **colon-free** (`/dev/clanarchy-bigscreen-card`) because
nspawn's `--bind=SRC:DST` parser tokenises on `:` and rejects source paths
carrying extra colons — so the natural `/dev/dri/by-path/pci-0000:03:00.0-card`
cannot be used as a bind source. This is the same wall
`machines/ernst/containers/jellyfin.nix` hit for the iGPU, solved the same way.

The dGPU is also Ollama's ROCm card. A kwin session and ROCm workloads coexist
fine — compute goes through the render node, KMS through the card node.

## Enabling it on another machine

The module is machine-agnostic. Import `modules/desktop/bigscreen.nix` and set:

```nix
clanarchy.desktop.bigscreen = {
  enable = true;
  user   = "go";
  uid    = 1001;          # must match the host's — nspawn does not remap ids
  gid    = 100;
  gpu.pciAddress = "0000:03:00.0";
};
```

Find the PCI address with:

```bash
ls -l /dev/dri/by-path/     # map card/render nodes to PCI paths
lspci -nn | grep -i vga     # identify which card is which
```

On a machine that also carries the `htpc` role, set it through the role
instead (`clanarchy.roles.htpc.bigscreen.*`), which wires the couch user
through and teaches the session switcher about the third mode.

`extraPackages` must be drawn from `pkgs-unstable`, not the host's `pkgs` —
otherwise a second, conflicting Qt/KDE closure lands in the session.

## Troubleshooting

```bash
machinectl shell bigscreen                       # get a shell inside
journalctl -M bigscreen -u plasma-bigscreen      # session log
readlink -f /dev/clanarchy-bigscreen-card        # should be the dGPU's node
```

If the container fails to start with "Failed to clone
/dev/clanarchy-bigscreen-card: No such file or directory", the udev rule has
not fired. `clanarchy-bigscreen-drm-symlinks.service` exists to prevent exactly
this, but a manual re-trigger is:

```bash
udevadm trigger --subsystem-match=drm --action=add
```

Both the display manager and the container want KMS on the same card, so only
one may run. `clanarchy-session-select` stops one before starting the other; if
things get out of step, `systemctl stop display-manager` then
`systemctl start container@bigscreen`.
