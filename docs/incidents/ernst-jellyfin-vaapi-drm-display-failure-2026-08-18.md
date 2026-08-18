# ernst — jellyfin VAAPI DRM display failure, 2026-08-18 — ROOT-CAUSED

**Status: root cause found and fixed.**  `/dev/dri` was not present
inside the container.  libva/mesa re-derives canonical
`/dev/dri/renderD*` and `/dev/dri/card*` names from the fd and looks
them up on disk, so radeonsi could never initialise a DRM display no
matter how the render node was bound.  Fixed by binding `/dev/dri`
into the container; see §Root cause below.

This was hypothesis 1 in the original §Working hypothesis, and
follow-up option 2.  The isolation objection recorded against that
option turned out not to apply — see below.

Original note follows.  After the successful Jellyfin container
migration on 2026-08-18 (see §History below), attempts to enable AMD
iGPU VAAPI transcoding failed at the DRM-display initialisation layer.
Software transcoding (libx264) worked and was the active state.

## Current state (post-rollback)

- Container: `container@jellyfin.service` — `active (running)`.
- Playback: CPU transcoding via `libx264` — functional, higher CPU
  and power draw than VAAPI would be.
- `/srv/state/jellyfin/config/encoding.xml`:
  - `HardwareAccelerationType=vaapi` — set by NixOS from PR #20
  - `VaapiDevice=/dev/jellyfin-igpu-render` — set by NixOS from PR #20
  - `EnableHardwareEncoding=false` — **rollback state**; jellyfin
    therefore falls back to `libx264` regardless of the two settings
    above.

## Failure mode

With `EnableHardwareEncoding=true` and `HardwareDecodingCodecs=<h264,
hevc, vp9>` set, playback fails immediately with:

```
Device creation failed: -542398533.
[vist#0:0/h264 @ …] [dec:h264 @ …] No device available for decoder:
    device type vaapi needed for codec h264.
[vist#0:0/h264 @ …] [dec:h264 @ …] Hardware device setup failed for
    decoder: Generic error in an external library
Error opening output files: Generic error in an external library
```

FFmpeg loaded the vaapi module and issued a proper command line
(`-hwaccel vaapi -hwaccel_output_format vaapi -codec:v:0 h264_vaapi …`)
but VAAPI device init returned the "Generic error in an external
library" that libva raises when it can't obtain a working DRM display.

Independently confirmed at the libva layer:

```
$ nixos-container run jellyfin -- vainfo --display drm \
    --device /dev/jellyfin-igpu-render
Trying display: drm
Failed to a DRM display for the given device
```

Also with `LIBVA_DRIVER_NAME=radeonsi` forced — same "Failed to a DRM
display" — so the driver-selection layer is fine; the failure is
below that, at DRM.

## What we ruled out during diagnosis

1. **File-permissions on the render node.**  Inside the container:
   ```
   crw-rw-rw- 1 root render 226, 129 Aug 18 17:15 /dev/jellyfin-igpu-render
   uid=964(jellyfin) gid=964(jellyfin) groups=964(jellyfin),26(video),303(render),3000(media)
   sudo -u jellyfin test -r /dev/jellyfin-igpu-render  →  readable by jellyfin
   ```
2. **Missing VAAPI userspace driver.**  Three copies of
   `radeonsi_drv_video.so` visible in the container's Nix store view
   (`mesa-26.1.5` × 2, `mesa-26.1.1` × 1).  Not a driver-absence issue.
3. **Bind mount not present.**  The colon-free udev symlink from
   PR #45 + #46 is in place; `readlink -f /dev/jellyfin-igpu-render`
   → `/dev/dri/renderD129` on both host and inside the container.

## Root cause (confirmed)

`/dev/dri` does not exist inside the container.  Only the bind-mounted
alias does:

```
$ nixos-container run jellyfin -- ls -l /dev/dri/
ls: cannot access '/dev/dri/': No such file or directory
```

The alias is enough to *open* the device — confirmed, so neither file
permissions nor the device cgroup were ever the problem:

```
$ nixos-container run jellyfin -- sh -c 'exec 3< /dev/jellyfin-igpu-render && echo OPEN_OK'
OPEN_OK
```

but it is not enough for mesa to bring up a DRM display.  Reproduced
A/B in throwaway `systemd-nspawn` containers against the real iGPU:

| Case | Config | Result |
|------|--------|--------|
| A | alias only, no `/dev/dri` — *jellyfin's exact setup* | `Failed to a DRM display for the given device` |
| B | same + `/dev/dri` bound | `va_openDriver() returns 0`, radeonsi loads, full profile list |
| C | `/dev/dri` bound, `DeviceAllow` on **alias only** | works — no cgroup change needed |
| D | as C, probing other nodes | `renderD129` OPEN_OK; `renderD128` DENIED; `card1` DENIED |

Case A reproduces the error string in §Failure mode verbatim.

**The isolation objection against follow-up option 2 does not apply.**
Binding the directory only makes the other nodes *visible*;
`allowedDevices` still gates opening them and is keyed on major:minor,
so the 7900 XTX stays unreachable (case D).  The "expose only the iGPU,
hide the XTX" property is preserved by the cgroup rather than by
absence of the node — which is the stronger guarantee of the two,
since it no longer depends on what happens to be bind-mounted.

Fix applied in `machines/ernst/containers/jellyfin.nix`:

```nix
"/dev/dri" = { hostPath = "/dev/dri"; isReadOnly = false; };
```

`modules/desktop/bigscreen.nix` carried the identical latent bug and
was fixed in the same change: it bound only its colon-free aliases,
while the proof-of-concept that validated it had bound `/dev/dri`
wholesale — which is why KWin came up there and would not have in the
deployed module.

## Working hypothesis (original — hypothesis 1 was correct)

`vainfo`'s "Failed to a DRM display" is emitted by libva's
`va_openDriver()` after `drmGetVersion()` on the fd returns
unexpected data or fails.  In an nspawn container with only the render
node bind-mounted and default nspawn caps, a few things can break the
DRM handshake even though the file is openable:

- Missing `/dev/dri/by-path` / `/dev/dri/card*` alongside the render
  node — some libva paths still enumerate the DRM directory to pair a
  render node with a primary card node before opening the display.
- `CAP_SYS_ADMIN` (or an eBPF DRM ioctl policy) dropped by nspawn in
  a way that blocks the specific `DRM_IOCTL_VERSION` needed for
  `drmGetVersion()`.
- Missing `LIBVA_DRIVERS_PATH` / `LIBVA_DRIVER_NAME` env vars
  inside the container.  Env dump: no LIBVA vars set.

## Follow-up work — options as originally written

**Resolved by option 2.**  Option 1 (LIBVA env vars) proved
unnecessary — driver discovery was never the failure; radeonsi loads
fine once `/dev/dri` exists.  Option 3 remains optional and is still
worth doing to stop the encoding.xml warning quoted under §Loose ends.
Option 4 is unaffected.


1. **Set LIBVA env inside the container config.**  Cheap.  In
   `machines/ernst/containers/jellyfin.nix`, container's `config`
   block:
   ```nix
   systemd.services.jellyfin.serviceConfig.Environment = [
     "LIBVA_DRIVER_NAME=radeonsi"
     "LIBVA_DRIVERS_PATH=${pkgs.mesa}/lib/dri"
   ];
   ```
   If VAAPI still fails after this, the issue is deeper than driver
   discovery.

2. **Bind `/dev/dri` as a whole directory instead of just the render
   node.**  Loses the "expose only the iGPU, hide the XTX" property
   PR #20 was carefully arranged for — the container would see
   `renderD128` (XTX) too.  Would need to compensate by using
   `--property=DeviceAllow=` (or nixos-container `allowedDevices`) to
   permit only the iGPU's major:minor.  More work than option 1 but
   fully preserves the isolation intent.

3. **`services.jellyfin.forceEncodingConfig = true` + fully-templated
   encoding.xml.**  Lets us pin `EnableHardwareEncoding`,
   `HardwareDecodingCodecs`, `AllowHevcEncoding`, tone-mapping, etc.
   without relying on the thin `services.jellyfin.hardwareAcceleration`
   abstraction (which currently only writes `type` / `device`).  Only
   helpful *after* the DRM display issue is resolved — otherwise
   pinning `EnableHardwareEncoding=true` just re-locks in the failure.

4. **Upstream nixpkgs contribution.**  Extend
   `services.jellyfin.hardwareAcceleration` with `enableEncoding`,
   `decodingCodecs`, `allowHevcEncoding`, tone-mapping toggles.  Best
   long-term fix; benefits everyone else running the same setup.

## History (this session)

Order of events on 2026-08-18:

1. **Container migration completed.**  Jellyfin nspawn container came
   up (PR #45 + #46 for the udev-symlink dance, PR #47 for ollama
   permissions — all merged earlier the same day).
2. **DB import.**  Copied the real 288 MB `jellyfin.db` from Home
   Assistant (`/share/jellyfin/`) via a miralda-mediated tar pipe;
   preserves 4 users, ~96k library items across Movies/TV-Shows plus
   audiobook/comic/photo libraries the user plans to remove in the UI.
3. **`/share/jellyfin` paths in XMLs.**  HA had absolute paths hard-
   coded in `system.xml` (CachePath, MetadataPath) and
   `encoding.xml` (TranscodingTempPath); container has no `/share`,
   Jellyfin aborted at boot.  Fixed in place with:
   ```
   sed -i "
     s|/share/jellyfin/cache|/var/cache/jellyfin|g
     s|/share/jellyfin/metadata|/var/lib/jellyfin/metadata|g
     s|/share/jellyfin/|/var/lib/jellyfin/|g
   " /srv/state/jellyfin/config/*.xml
   ```
   Left in place — nothing regenerates these on deploy (see next).
4. **VAAPI enable attempt.**  Sed-flipped `EnableHardwareEncoding`
   to `true` + populated `HardwareDecodingCodecs` in encoding.xml.
   Container restart → immediate playback failure with the
   ffmpeg/vaapi errors quoted above.
5. **Rollback.**  Sed-flipped `EnableHardwareEncoding` back to `false`.
   Container restart → CPU transcoding works.

## Loose ends (unrelated to VAAPI)

- **DB has residual `/share/jellyfin/…` paths in row-level fields.**
  Log shows `Could not find file /share/jellyfin/config/users/go/profile.png`
  and multiple `/share/jellyfin/metadata/People/…` cast portraits.
  Our sed only fixed the config XMLs, not the DB.  Cast-photo gaps
  are cosmetic (jellyfin re-downloads on next metadata refresh).
  User avatar can be re-uploaded in the profile settings, or fixed in
  bulk with:
  ```sql
  UPDATE BaseItems  SET Path = REPLACE(Path, '/share/jellyfin/', '/var/lib/jellyfin/')
    WHERE Path LIKE '/share/jellyfin/%';
  UPDATE ImageInfos SET Path = REPLACE(Path, '/share/jellyfin/', '/var/lib/jellyfin/')
    WHERE Path LIKE '/share/jellyfin/%';
  ```
  Requires container stopped + sqlite3 write access.  Not blocking.

- **NixOS pre-start warning.**  On every restart:
  ```
  WARN: /var/lib/jellyfin/config/encoding.xml already exists and is
        different from the configured settings. transcoding options
        NOT applied.
  WARN: Set config.services.jellyfin.forceEncodingConfig = true to
        override.
  ```
  Expected — jellyfin's own regen of encoding.xml would clobber our
  path fixes and our EnableHardwareEncoding rollback.  Silence by
  setting `forceEncodingConfig = true` and templating the full
  encoding.xml (option 3 in follow-up work above), or leave and treat
  as informational.
