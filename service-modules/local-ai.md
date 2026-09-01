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
| `ollama` | Enables `services.ollama` with ROCm acceleration for the AMD Radeon 780M iGPU (`gfx1103`); pre-pulls models on service start; persists `/var/lib/ollama` across ZFS rollbacks. Optionally (`remoteClients.enable`) authorises one restricted key so a machine with no usable GPU can forward to it |
| `opencode` | Installs `pkgs.opencode`; writes `~/.config/opencode/config.json` pointing at an Ollama API — the local one by default, or a remote one over an SSH forward (`tunnel.enable`) |

### Reaching a remote ollama (`tunnel.enable`)

`services.ollama` binds loopback and stays that way; `machines/ernst/networking.nix`
records that as deliberate ("M11 changes ernst's attack surface not at all"). So a
client with no usable GPU — `jens`, whose iGPU is Intel and so cannot use the ROCm
stack this role is built around — does not get ollama opened up to it. It gets an
SSH port-forward, which keeps the listener loopback-only at both ends:

```
jens 127.0.0.1:11435  ──ssh -L──▶  ernst 127.0.0.1:11434
```

Three pieces, all declarative:

- **A dedicated keypair**, generated as a shared clan var (`ollama-tunnel-ssh`) by
  the *client* only. It cannot reuse the remote-builder key: that one is authorised
  with `command="nix-daemon --stdio",restrict`, and `restrict` drops port forwarding.
- **`ollama-tunnel.service`** on the client — a system unit, because the private key
  is root-owned `0400` and lgo's own access to ernst authenticates with the YubiKey,
  which needs gpg-agent inside an interactive session. `Restart=always` with no start
  limit, because a laptop loses this link every time it sleeps or roams.
- **One `authorized_keys` line** on the server, from `remoteClients.enable`:
  `restrict,port-forwarding,permitopen="127.0.0.1:11434"`. A forward to that one
  destination and nothing else — no shell, no pty, no agent or X11 forwarding.

`localPort` is **11435, not 11434**, everywhere in the fleet — miralda runs its own
ollama on 11434. Check what you actually reached before trusting an answer:

```bash
curl -s localhost:11435/api/tags | jq -r '.models[].name'
```

Ordering: the server reads the client's public half out of `vars/shared/`, so run
`clan vars generate <client>` before deploying the server. Until then the server
emits a warning and authorises nothing.

### OpenCode config schema

The generated `config.json` uses opencode 1.x's shape:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "ollama/qwen3-coder:30b",
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "options": { "baseURL": "http://127.0.0.1:11435/v1" },
      "models": { "qwen3-coder:30b": {} }
    }
  },
  "instructions": ["/nix/store/…-opencode-tool-call-rule.md"]
}
```

This role previously wrote `providers.ollama.baseUrl` — plural key, camelCase
`baseUrl`, no `npm` driver. That matches no version of the schema, so opencode
ignored the block entirely and fell through to its own defaults. It failed silently,
which is why it went unnoticed. The provider's `models` map is not optional either:
this provider has no catalogue for opencode to discover, so an undeclared tag is not
selectable even when ollama has it pulled.

`instructions` points at the `<tool_call>` reinforcement below, so any machine using
this role sends it by construction rather than by remembering to.

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

## Context window, KV cache, and the `<tool_call>` tag

Three settings interact here in a way that is not guessable from any one of
them, so they are documented together. All numbers were measured on ernst
(RX 7900 XTX, 24560 MiB, ollama 0.32.3, `qwen3-coder:30b`) during M11; the
probes that produced them live in `~/.local/share/m11-bakeoff/probes/` and are
re-runnable.

### Pin `contextLength`, because exceeding it is not an error

Unset, ollama derives the window from the model tag. **Exceeding it returns
HTTP 200.** The prompt is truncated to about `num_ctx/2`, the **tail is kept
and the head discarded**, and the head is where the system message and the tool
definitions live. Measured at `num_ctx=8192` with a 17,083-token prompt: 4,098
tokens survived, tool calling went 0/6, and a question about the discarded head
was answered with an invented, placeholder-shaped MAC address rather than a
refusal.

Reading the config back shows `num_ctx: 8192` and tells you nothing. This is
the same failure shape as the recyclarr duplicate-instance bug — green, exit 0,
doing something other than what was asked.

### `q8_0` is not free, and what it costs is tool calls

The VRAM case for `q8_0` is strong: a 65536 window becomes fully resident at
22482 MiB, where f16 needs 24471 MiB and spills to system RAM, for ~11% of
decode speed. `OLLAMA_FLASH_ATTENTION=1` on its own is a **measured no-op** —
it is the prerequisite, not the saving.

But quantising the KV cache also degrades how reliably the model **formats** a
tool call. Interleaved, n=30 per arm, identical prompt and context:

| KV cache | baseline system prompt | reinforced system prompt |
|---|---|---|
| `f16`  | 83%, 83% | 100% |
| `q8_0` | 40%, 36% | 100% |

So `q8_0` roughly halves tool-call reliability **at a baseline system prompt**,
and the reinforcement below erases the difference entirely. Set `kvCacheType`
only where the clients are known to send that reinforcement.

### The one tag that decides it

Every tool-call failure measured on this fleet — across 88 graded Phase 0
trials and 200+ more since — was the same thing, and it is **not** the model
inventing arguments. Zero invented arguments, zero missing arguments, zero
refusals. The model emits a correct call that is **missing its opening
`<tool_call>` line** while still emitting the closing `</tool_call>`:

```
<function=grep_repo>
<parameter=pattern>
API client
</parameter>
</function>
</tool_call>
```

`ollama/model/parsers/qwen3coder.go` enters tool-collection **only** on the
literal string `<tool_call>` and has no `<function=` fallback, so the whole
block is emitted as prose with `tool_calls: null`.

Two things follow, and both correct a natural first guess:

- **There is no Modelfile template to fix.** `ollama show --modelfile
  qwen3-coder:30b` is `TEMPLATE {{ .Prompt }}` plus `RENDERER qwen3-coder` and
  `PARSER qwen3-coder` — named, compiled Go, not editable template text.
- **The parser and renderer are both correct.** The renderer already injects
  the format spec *and* an `<IMPORTANT>` reminder that the `<function=...>`
  block "must be nested within `<tool_call></tool_call>` XML tags". The model
  ignores an instruction it was already given.

The fix is client-side and cheap — restate that one tag in the system message:

```
CRITICAL OUTPUT RULE: every function call MUST begin with a literal
<tool_call> line and end with a literal </tool_call> line. The opening
<tool_call> tag is mandatory and is the most commonly omitted part. Never
emit <function=...> unless the immediately preceding line is <tool_call>.
```

Measured 80/80 valid calls with it, under both KV cache types, against 5/40 at
baseline on the same conditions. Any agent pointed at this service should send
it.

The `opencode` role now does this automatically: it writes that text to a store
file and names it in the config's `instructions`, so the reinforcement ships with
the role instead of depending on whoever configures the client remembering it.

## Usage

### Inventory (`clan.nix`)

```nix
local-ai = {
  module.input = "self";
  module.name  = "@clanarchy/local-ai";
  roles.ollama.machines.miralda.settings = {
    models        = [ "qwen2.5-coder:7b" ];
    contextLength = 4096;
  };
  roles.ollama.machines.ernst.settings = {
    models        = [ "qwen3-coder:30b" ];
    contextLength = 32768;
    kvCacheType   = "q8_0";
    # Authorise jens's forward (see below).  Does not expose ollama.
    remoteClients.enable = true;
  };
  roles.opencode.machines.miralda.settings.user = "lgo";

  # jens: Intel iGPU, so no local ollama at all — talk to ernst's card
  # over an SSH forward instead.
  roles.opencode.machines.jens.settings = {
    user  = "lgo";
    model = "ollama/qwen3-coder:30b";   # must match ernst's `models`
    tunnel.enable = true;
  };
};
```

(The example here once read `qwen3-coder:8b`. That tag has never existed —
qwen3-coder publishes only 30b and 480b — and it is the reason
`ollama-model-loader.service` sat in a restart loop. Check a tag before
using one; see the `models` option description.)

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
