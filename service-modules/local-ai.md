# @clanarchy/local-ai

Local AI inference and coding agent — a fully FOSS, offline alternative to Claude Code.

## Overview

| Component | Package | Role |
|-----------|---------|------|
| [Ollama](https://ollama.com) | `pkgs.ollama` | Inference server, exposes OpenAI-compatible API on `localhost:11434` |
| [OpenCode](https://opencode.ai) | `pkgs.opencode` | Terminal coding agent (TUI), model-agnostic, ~150K GitHub stars |

Both packages ship in nixpkgs (26.05+) — no external flake input required.

## Roles

| Role | What it does |
|------|-------------|
| `ollama` | Enables `services.ollama` with ROCm acceleration for the AMD Radeon 780M iGPU (`gfx1103`); pre-pulls models on service start; persists `/var/lib/ollama` across ZFS rollbacks |
| `opencode` | Installs `pkgs.opencode`; writes `~/.config/opencode/config.json` pointing at the local Ollama API |

## Hardware note (AMD Radeon 780M / gfx1103)

The Phoenix iGPU (`gfx1103`) is absent from stock ROCm kernel libraries. The `ollama`
role works around this by setting:

```
HSA_OVERRIDE_GFX_VERSION = "11.0.3"   # treat gfx1103 as gfx1100 at runtime
ROCR_VISIBLE_DEVICES     = "0"
```

and creating an `/opt/rocm/hip` symlink via `systemd.tmpfiles`. If GPU inference is
unstable, fall back to CPU by setting `acceleration = null` in the NixOS option
`services.ollama.acceleration` (or remove the role setting and override directly).

Expected throughput on the 780M with Qwen3-Coder 8B: **~24–48 tokens/sec** GPU vs
~16 tok/s CPU-only.

## Model recommendations (Framework 12 — 30 GB RAM)

| Model | RAM needed | Quality | Speed | Use case |
|-------|-----------|---------|-------|----------|
| `qwen3-coder:8b` *(default)* | ~6 GB | ★★★★☆ | Fast | Day-to-day coding |
| `qwen2.5-coder:32b` | ~20 GB | ★★★★★ | Slower | Complex refactors |
| `deepseek-coder:33b` | ~20 GB | ★★★★☆ | Slower | Alternative to above |

Pre-pull a model manually with `ollama pull <model>` or set it in `settings.models`.

## Usage

### Inventory (`clan.nix`)

```nix
local-ai = {
  module.input = "self";
  module.name  = "@clanarchy/local-ai";
  roles.ollama.machines.miralda.settings.models  = [ "qwen3-coder:8b" ];
  roles.opencode.machines.miralda.settings.user  = "lgo";
  # roles.opencode.machines.miralda.settings.model = "ollama/qwen2.5-coder:32b";
};
```

### Running OpenCode

```bash
# In any project directory:
opencode

# OpenCode TUI opens — type your request in natural language.
# It reads your codebase, runs shell commands, edits files, and commits diffs.
```

OpenCode key bindings (inside the TUI):

| Key | Action |
|-----|--------|
| `Enter` | Send message |
| `Ctrl+C` | Cancel / exit |
| `Ctrl+Z` | Undo last change |
| `/` | Command palette |
| `Tab` | Cycle context files |

### Switching models at runtime

```bash
# List available local models:
ollama list

# Pull a new model:
ollama pull qwen2.5-coder:32b

# Override the model for one session:
OPENCODE_MODEL=ollama/qwen2.5-coder:32b opencode
```

### Managing Ollama

```bash
# Service status:
systemctl status ollama

# Server logs:
journalctl -u ollama -f

# Check GPU is being used (look for "library=rocm"):
journalctl -u ollama | grep library
```

### Troubleshooting

**GPU not detected (falls back to CPU)**
```bash
# Verify ROCm sees the iGPU:
/run/current-system/sw/bin/rocminfo 2>/dev/null | grep -A3 "gfx"
# If empty: the gfx1103 workaround may need a reboot after first deploy.
```

**Switching to CPU-only** (if ROCm is unstable)

Override the package in `machines/miralda/configuration.nix`:
```nix
services.ollama.package = pkgs.ollama-cpu;  # or plain pkgs.ollama
```

**Model download fails on first boot**
```bash
# Manually pull (runs as your user, Ollama daemon must be running):
ollama pull qwen3-coder:8b
```

**OpenCode can't connect to Ollama**
```bash
# Verify the local API is up:
curl http://localhost:11434/api/tags
# If the ollama service stopped: sudo systemctl start ollama
```
