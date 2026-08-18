# Plasma Bigscreen on the TV

`ernst` carries the `htpc` role, which offers three living-room modes,
switchable at runtime:

| Mode | What it is | Where it runs |
|------|------------|---------------|
| `gamescope` | Steam Big Picture | Host, stock nixpkgs 26.05 |
| `plasma` | KDE Plasma 6.6.6 desktop | Host, stock nixpkgs 26.05 |
| `bigscreen` | Plasma Bigscreen 6.7.4 | **nspawn container**, nixpkgs-unstable |

Switch between them from the couch account:

```bash
clanarchy-session-select bigscreen    # or: gamescope | plasma
```

The choice is written to `/var/lib/clanarchy-session/current`, persists across
reboots, and is re-applied at boot by `clanarchy-htpc-boot.service`.

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
