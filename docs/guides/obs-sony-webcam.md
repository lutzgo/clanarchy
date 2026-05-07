# OBS Studio — Sony ILCE-7RM5 as Webcam

This guide covers using the Sony ILCE-7RM5 (a7R V) as a webcam via USB-C in OBS Studio on miralda.

## NixOS configuration

The required kernel module and packages are part of `clanarchy.desktop.niri` and activate automatically when the desktop is enabled.

| What | Where | Details |
|------|-------|---------|
| `v4l2loopback` kernel module | `modules/desktop/niri.nix` | Virtual camera device at `/dev/video10`; loaded on boot |
| `v4l-utils` | `modules/desktop/niri.nix` | `v4l2-ctl` for device diagnostics |
| `obs-studio` + plugins | `machines/miralda/apps.nix` | `programs.obs-studio` with `obs-vaapi` and `obs-backgroundremoval` |

After a fresh deploy, `v4l2loopback` is loaded automatically on boot — no manual `modprobe` needed.

---

## Camera setup (on the Sony)

The camera must be in **Streaming** mode, not PC Remote:

```
Menu → Setup (toolbox icon) → USB → USB Connection → Streaming
```

This setting persists across power cycles.

---

## First-time OBS setup

### 1. Add the camera as a source

1. In **Sources**, click **+** → **Video Capture Device (V4L2)**
2. Name it (e.g. `Sony ICLE 7RM5`) → **OK**
3. In the properties dialog:
   - **Device**: `/dev/video2`
   - **Input format**: `YUY2` (uncompressed; preferred at 1080p on this hardware)
   - Set your desired **Resolution** and **Frame Rate**
4. **OK**

!!! tip
    `/dev/video3` is the metadata/still-image endpoint — use `video2` for live video.
    Run `v4l2-ctl --list-devices` to confirm device paths if they shift after a reboot.

### 2. Fit the source to the canvas

After adding the source the image may appear in the top-left of a black canvas if the source resolution differs from the OBS output resolution. Fix it:

- Click the source in **Sources**, then press **Ctrl+F** (Fit to screen)
- Or right-click the source in the preview → **Scale/Crop** → **Fit to screen**

### 3. Background blur / removal (optional)

The `obs-backgroundremoval` plugin provides AI portrait segmentation.

1. Right-click the Sony source in **Sources** → **Filters**
2. Click **+** → **Effect Filters** → **Background Removal**

#### Choosing a segmentation model

The model is the biggest factor for edge smoothness, especially around hair:

| Model | Quality | CPU cost | Best for |
|-------|---------|----------|----------|
| `Robust Video Matting` | Best — soft, hair-aware edges | High | Stationary setup, best result |
| `MediaPipe` | Very good — clean face/shoulder edges | Medium | Good balance for video calls |
| `Selfie Segmentation` | Decent — can be blocky at edges | Low | Weak hardware only |
| `SINet` | Older, less accurate | Low | Avoid |

**Recommendation**: start with `MediaPipe`. Switch to `Robust Video Matting` if edges around hair look jagged — the AMD CPU handles it at 1080p.

#### Settings for a smooth blur

| Setting | Value | Why |
|---------|-------|-----|
| Effect | `Blur` | Keeps real background visible but defocused |
| Segmentation model | `MediaPipe` or `Robust Video Matting` | See table above |
| Threshold | `0.50–0.55` | Lower = include more of the subject; raise slightly if background bleeds in at edges |
| Mask blur | `5–10` | **Key setting** — feathers the segmentation mask edge so the transition between you and the background is gradual, not a hard cut |
| Blur radius | `20–35` | Background blur strength; higher looks more cinematic, lower is more natural |

!!! tip "Mask blur is the most important knob"
    Without mask blur the plugin draws a hard pixel edge around you. A mask blur of 5–10 creates a soft
    feathered transition that hides segmentation imperfections, especially in hair.

#### Tuning for difficult edges (hair, glasses, loose clothing)

- If hair edges flicker or bleed: lower **Threshold** by 0.05 increments until they stabilise
- If background leaks through loose fabric: raise **Threshold** slightly (0.55–0.65)
- If the transition still looks harsh: raise **Mask blur** to 12–15
- For the most natural result: combine a moderate blur radius (20–25) with a higher mask blur (8–12) rather than a very high blur radius with no feathering

The model runs via ONNX Runtime on CPU. At 1080p/30fps on the AMD hardware, `MediaPipe` uses ~8–12% CPU and `Robust Video Matting` ~18–25%.

---

## Virtual camera (share OBS output with other apps)

The `v4l2loopback` module creates `/dev/video10` as a virtual V4L2 device. OBS writes to it when the virtual camera is active; other apps (Jitsi, Zoom, Meet) read from it.

1. In OBS **Controls** → **Start Virtual Camera**
2. In the other app, select **OBS Virtual Camera** as the camera device

!!! note
    The **Start Virtual Camera** button only appears after `v4l2loopback` is loaded. On a fresh boot after deploying the config it loads automatically. If OBS was started before the module loaded, restart OBS.

---

## Diagnostics

```bash
# List all V4L2 devices (confirm Sony appears)
v4l2-ctl --list-devices

# List supported formats and resolutions for the Sony
v4l2-ctl --device=/dev/video2 --list-formats-ext

# Check v4l2loopback virtual device
v4l2-ctl --device=/dev/video10 --info
```

Expected output from `--list-devices`:

```
Laptop Camera: Laptop Camera (usb-0000:c1:00.4-1):
    /dev/video0
    /dev/video1

ILCE-7RM5 (usb-0000:c3:00.4-1):
    /dev/video2
    /dev/video3

OBS Virtual Camera (platform:v4l2loopback-000):
    /dev/video10
```
