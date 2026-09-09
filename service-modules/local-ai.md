# @clanarchy/local-ai

Local AI inference, voice, vision and image generation — a fully self-hosted,
offline alternative to Claude Code and the hosted chat clients.

**Nothing here leaves the house.** Every listener is loopback or a
point-to-point veth; the one public hostname is behind Traefik and Authelia on
the LAN only, and no part of this is exposed to the internet.

## Overview

| Component | Package | Role |
|-----------|---------|------|
| [llama-swap](https://github.com/mostlygeek/llama-swap) | `pkgs.llama-swap` | Front door on `127.0.0.1:11434`. Owns GPU arbitration and idle unload |
| [llama.cpp](https://github.com/ggml-org/llama.cpp) | `pkgs.llama-cpp` (ROCm, gfx1100) | `llama-server`, **spawned per model by llama-swap** on an ephemeral loopback port. No router — see below |
| [whisper.cpp](https://github.com/ggml-org/whisper.cpp) | `pkgs.whisper-cpp` | `whisper-server` with an OpenAI-shaped `/v1/audio/transcriptions` |
| [Open WebUI](https://openwebui.com) | `pkgs.open-webui` | Browser client, nspawn container on VLAN 90, behind Traefik + Authelia |
| [ComfyUI](https://github.com/Comfy-Org/ComfyUI) | `service-modules/pkgs/comfyui` (hand-rolled, ROCm) | Image generation, **spawned by llama-swap** like `llama-server`. Built rather than pinned — see below |
| [OpenCode](https://opencode.ai) | `pkgs.opencode` | Terminal coding agent, local or tunnelled |

Everything ships in nixpkgs 26.05 — **no external flake input**.

## Roles

| Role | What it does |
|------|-------------|
| `inference` | llama-swap, loopback only; it spawns `llama-server` per model. Optionally authorises one restricted key for an SSH forward, and one mon0-only metrics listener |
| `models` | Declarative model set: `{ url, hash, contextLength, kvCacheType, subdir }`. Fetched to `/srv/state/local-ai/models` on zdata, hash-verified at every boot |
| `speech` | Whisper STT, registered as a llama-swap backend |
| `imagegen` | ComfyUI, spawned by llama-swap, exclusive with the LLM on the GPU. Settings only — it produces no units, exactly like `speech` |
| `webui` | Open WebUI in an nspawn container on VLAN 90 |
| `opencode` | `pkgs.opencode` + `~/.config/opencode/config.json`, local or over an SSH forward |
| `ollama` | **Legacy. miralda only.** See below |

## Why this replaced Ollama on ernst (M19)

Measured before it was taken; the full record is in
`~/.local/share/m19-llamacpp/PHASE0-NOTES.md` and summarised in
`docs/roadmap.md` §M19. Three results decided it.

### 1. Context overflow stops being silent — this is the whole reason

Ollama answers an over-long prompt with **HTTP 200**, truncates to roughly
`num_ctx/2`, **keeps the tail and discards the head** — which is where the
system message and tool definitions live — and sets no flag anywhere.
Re-measured 2026-09-08 with a 16,694-token prompt at `num_ctx = 8192`:

| server | HTTP | prompt tokens | asked for a fact from the discarded head |
|---|---|---|---|
| ollama | **200** | **4098** | **`00:00:00:00:00:00` — fabricated** |
| llama-server | **400** | — | refused |

llama-server's refusal names both numbers:

```
request (16694 tokens) exceeds the available context size (8192 tokens), try increasing it
```

That is [SN1](../docs/roadmap.md#sn1)'s core hazard removed at the mechanism
rather than documented around. Note the fabrication differs from M11's
(`00:11:22:33:44:55` then) — it is a fresh invention each time, not a memorised
wrong answer.

### 2. The `<tool_call>` defect is the model's, and the fix still ships

M11 found that qwen3-coder drops the **opening** `<tool_call>` tag while still
emitting the closing one, and initially blamed Ollama's compiled Go parser.
llama.cpp parses through the GGUF's own Jinja template — a completely
independent implementation — and fails identically:

| condition | arm | OK | XML_NO_OPEN | XML_OPEN |
|---|---|---|---|---|
| 2 tools, "go find X" | llama.cpp baseline | 4/30 (13%) | 26 | **0** |
| | llama.cpp **+ rule** | **30/30 (100%)** | 0 | 0 |
| | ollama baseline | 4/30 (13%) | 26 | **0** |
| | ollama **+ rule** | **30/30 (100%)** | 0 | 0 |
| 2 tools, "read this file" | llama.cpp baseline | 21/30 (70%) | 9 | **0** |
| | llama.cpp **+ rule** | **30/30 (100%)** | 0 | 0 |
| | ollama baseline | 4/30 (13%) | 26 | **0** |
| | ollama **+ rule** | **30/30 (100%)** | 0 | 0 |

**`XML_OPEN` is zero in all eight cells.** Two unrelated parsers reject exactly
the same malformed output at indistinguishable rates. So the rule below is
**not** deleted by the migration — deleting it takes tool calling from 100% to
13% on the worst condition.

```
CRITICAL OUTPUT RULE: every function call MUST begin with a literal
<tool_call> line and end with a literal </tool_call> line. The opening
<tool_call> tag is mandatory and is the most commonly omitted part. Never
emit <function=...> unless the immediately preceding line is <tool_call>.
```

The `opencode` role writes this to a store file and names it in the config's
`instructions`, so any machine using the role sends it by construction rather
than by somebody remembering to.

### 3. Decode is within noise, and `q8_0` lost its reason to exist

Interleaved, n=5 cycles, same card, same day. Interleaved because a first
sequential pass measured the *same* f16 configuration at 109.8, then 108.1,
then 100.8 tok/s — drift larger than the difference being measured.

| arm | VRAM | of 24560 | decode | vs control |
|---|---|---|---|---|
| **llama-server f16 32k** | 21799 MiB | 88.8% | **107.5 tok/s** | **−3.1%** |
| llama-server q8_0 32k | 20361 MiB | 82.9% | 94.6 tok/s | −14.7% |
| ollama q8_0 32k *(control)* | 20163 MiB | 82.1% | 110.9 tok/s | — |

ernst ran `q8_0` **only** because f16 at 64k spilled on Ollama. On llama.cpp
f16 at 32768 — the window ernst actually declares — fits with 2761 MiB to
spare, so `q8_0` would now cost 14.7% of decode to buy nothing.

**The fleet default is therefore `f16`.** Take `q8_0` when a model genuinely
needs 64k: 21990 MiB at ~95 tok/s, against f16's 24529 MiB which does not fit.

Two more measurements worth not rediscovering:

- **Flash attention is NOT a no-op on llama.cpp.** M11 measured it as one *on
  Ollama* and said so; here `-fa on` saves **1667 MiB** at 32k. Do not carry
  the Ollama-era statement across.
- **Never quantise only K.** `-ctk q8_0` with V at f16 costs **~45% of decode**
  (57.1 tok/s vs ~100) to save 887 MiB. Quantise both or neither — which is why
  `kvCacheType` is one option and not two.

## Why ONE layer — and how that corrected a Phase 0 conclusion

**llama-swap spawns `llama-server` per model. There is no router.** That is a
correction: this module shipped a two-layer design first, and the deployed
system rejected it on the first real request.

### What the two-layer design was, and why it cannot work

The plan was `llama-swap → llama-server --models-preset` in router mode, with
llama-swap owning LLM↔non-LLM exclusion and the router owning LLM↔LLM swapping
and per-model context. llama-swap entries used `proxy` + `useModelName` and no
`cmd`. The first chat request returned:

```
HTTP 500 {"src":"llama-swap","error":"unable to get sanitized command: empty command"}
```

`proxy` is **not** "forward to this external service". llama-swap's own
documentation calls it *"the URL where llama-swap routes API requests"* — where
the process it **starts** will listen — and `cmd` is mandatory
(`internal/config/config.go` returns `empty command` otherwise). There is no
externally-managed-backend mode. The `/v1/models` listing worked, which is why
this survived review: the shape was only wrong on the path that starts a model.

### And the router turned out to be redundant

Once llama-swap spawns `llama-server` itself, each model gets its own `-c`,
`--cache-type-k/v`, `--jinja` and `--mmproj` on the command line, and both of
Phase 0's arguments for the router evaporate:

- **Its lack of an idle unload no longer matters.** The router's only unload
  path is `unload_lru()`, driven solely by `--models-max`; there is no idle
  timeout in it. That was the case for llama-swap's `ttl` *in front of* it —
  now nothing defers to it at all.
- **Its phantom `default` model simply never exists.** In router mode
  `/v1/models` listed `default` alongside the declared set, built from the
  router's own argv, and requesting it made the router **spawn a child of
  itself in router mode** and wait forever — the request hung with no response:

  ```
  srv  ensure_model: waiting until model name=default is fully loaded...
  [34753] srv  main: starting router server, no model will be loaded in this process
  ```

  Confirmed in production before the router was removed: `default` was present
  on the router's port and absent through llama-swap.

llama.cpp's own warning that router mode is *"experimental … not recommended in
untrusted environments"* stops applying too. One layer, not two.

**This is the shape Phase 0 actually proved.** The exclusivity measurement below
used `cmd`-spawned models, not a router — so the evidence was always for the
one-layer design, and the two-layer write-up was reasoning that ran ahead of
what had been tested.

### Proven exclusivity

```
08:06:19  VRAM=  330 MiB  baseline, nothing loaded
08:06:23  VRAM=21797 MiB  after CHAT request  -> qwen3-coder-30b resident
08:06:26  VRAM=19118 MiB  after OTHER request -> coder EVICTED, other resident
08:06:30  VRAM=21797 MiB  after CHAT again    -> coder BACK, other evicted
```

## The port is 11434 on purpose

llama-swap takes the port Ollama had, so every existing client keeps working
**and** the jens tunnel's `permitopen="127.0.0.1:11434"` restriction needs no
edit. Nothing about the SSH forward changed.

```
jens 127.0.0.1:11435  ──ssh -L──▶  ernst 127.0.0.1:11434  (llama-swap)
```

`localPort` is **11435, not 11434**, everywhere in the fleet — miralda runs its
own Ollama on 11434. Check what you actually reached before trusting an answer:

```bash
curl -s localhost:11435/v1/models | jq -r '.data[].id'
```

(`/v1/models`, not `/api/tags` — the far end has no Ollama API any more.
miralda's local Ollama still answers `/api/tags`, which is a second way to tell
the two apart.)

Three pieces, all declarative:

- **A dedicated keypair**, generated as a shared clan var (`ollama-tunnel-ssh`)
  by the *client* only. It cannot reuse the remote-builder key: that one is
  authorised with `command="nix-daemon --stdio",restrict`, and `restrict` drops
  port forwarding.
- **`ollama-tunnel.service`** on the client — a system unit, because the private
  key is root-owned `0400` and lgo's own access to ernst authenticates with the
  YubiKey, which needs gpg-agent inside an interactive session.
  `Restart=always` with no start limit, because a laptop loses this link every
  time it sleeps or roams.
- **One `authorized_keys` line** on the server, from `remoteClients.enable`.

The generator is **still named `ollama-tunnel-ssh`**. Renaming it would rotate
the key on every machine that has one for cosmetic reasons, and clan rejects a
shared generator whose definitions diverge between machines — so a half-finished
rename breaks every deploy in the flake. The name is historical; the thing it
names is correct.

## Models are declared, not pulled

One attrset, two consumers — the fetcher and llama-server's preset INI are both
rendered from it, so a model cannot be downloaded but undeclared, or declared
but never fetched.

```nix
roles.models.machines.ernst.settings.models = {
  qwen3-coder-30b = {
    url  = "https://huggingface.co/unsloth/…/Qwen3-Coder-30B-A3B-Instruct-UD-Q4_K_XL.gguf";
    hash = "sha256-KEGqMU2RZDSGDPuJkDR1KNzf5cNQ28udFGHb7oj/JTM=";
    filename      = "Qwen3-Coder-30B-A3B-Instruct-UD-Q4_K_XL.gguf";
    contextLength = 32768;   # required — no default
    kvCacheType   = "f16";
  };
};
```

**Verify every URL and hash before committing it.** This repo has shipped a
model reference that never existed twice:

```bash
nix store prefetch-file --hash-type sha256 --json <url> | jq -r .hash
```

`contextLength` has **no default**, deliberately. Under Ollama the window was
derived from the model tag and set by one global environment variable, so
editing which model was served silently changed the context for every client.
Here it sits on the model, is required, and moves only when someone edits that
line — which is where [SN1](../docs/roadmap.md#sn1) now lives.

The fetcher is a oneshot, not a fixed-output derivation: these are 18 GiB blobs
and [invariant #7](../docs/roadmap.md#architecture-invariants) puts them on
zdata, whereas the store is on `zroot`. It is idempotent by hash, so a correct
file is skipped on every boot, and a **mismatch is a hard failure that leaves
the existing file alone** — never a silent overwrite, because the thing on the
other side of a wrong model is an agent that sounds fine.

### The fetch is deliberately OFF the deploy path

`llama-models-fetch` is started by a **timer** (`OnBootSec=30s`), not by
`multi-user.target`, and it carries `restartIfChanged = false`.

It was originally `wantedBy = multi-user.target` with `llama-router` requiring
it, and the first real deploy showed why that is wrong: `clan machines update
ernst` sat for **thirteen minutes** with no progress output while a 25 GiB
download completed, which is indistinguishable from a hang. It cost on every
subsequent deploy too — the fetcher re-hashes the whole store each run, roughly
a minute of blocking for a store that has not changed.

**The router does not need the models at startup.** It is a router: it reads the
preset INI, lists the models, and opens no weights until a request names one. A
missing file is a per-request error, not a startup failure. So the dependency is
ordering-only (`after`, no `wants`), and the fetch calls `systemctl try-restart
llama-router` when it finishes so newly-arrived files are picked up.

`restartIfChanged = false` is the other half: without it, **adding a model**
changes the unit's script, `switch-to-configuration` restarts it, and the
download is back on the critical path — the same defect, reintroduced by the one
edit most likely to trigger it.

**The cost, stated:** a deploy that adds a model does not fetch it immediately.
Run `systemctl start llama-models-fetch` (idempotent) or wait for the next boot.
That is the right trade — adding a model is rare and deliberate, deploying is
neither.

## Voice — whisper.cpp, and it runs on the CPU

**Speaches was the intended choice and is not taken.** It is not in nixpkgs at
all (its dependencies are — `faster-whisper`, `ctranslate2`, `kokoro` — but the
server is not), and its STT path runs through CTranslate2, whose GPU backend is
CUDA. On a 7900 XTX that is a CPU path with extra steps.

`pkgs.whisper-cpp` is in nixpkgs and `whisper-server` takes
`--inference-path`, so `--inference-path /v1/audio/transcriptions` makes it
OpenAI-shaped with no wrapper.

**It is CPU-only here, and that is measured.** Built with `rocmSupport = true`
the binary genuinely links `libamdhip64.so.7` — `ldd` alone would tell you it
worked — but the build emits no loadable `libggml-hip.so`, and ggml discovers
backends by loading `libggml-<backend>.so` from its own lib directory. At
runtime:

```
load_backend: loaded CPU backend from …/libggml-cpu-zen4.so
whisper_backend_init_gpu: device 0: CPU (type: 0)
whisper_backend_init_gpu: no GPU found
```

llama-cpp's ROCm build *does* ship `libggml-hip.so`, which is why the same
override works there and not here.

Measured: **5.2 s for 11 s of audio on 8 threads (~2.1× realtime)**, zero VRAM.
That is fine for dictation — and it means **Whisper is deliberately NOT in the
exclusive GPU group**. Putting it there would evict the 18.5 GiB coder model to
run a workload that never touches the card, buying a ~15 s reload for nothing.
If the packaging gap closes, Whisper becomes a real GPU consumer and must then
be added to the group.

### TTS is the browser's

Nothing in nixpkgs serves an OpenAI-shaped `/v1/audio/speech`. Open WebUI's Web
Speech API path costs no VRAM on a card this milestone is already arbitrating,
and needs no additional service. Recorded as a decision, not an oversight —
revisit if a packaged Kokoro or Piper HTTP server appears.

## Image generation — built, not pinned (M21)

M19 wrote `imagegen` for the podman tier against a digest-pinned community
image and left it disabled, pending an image worth pinning. **M21 found none,
and found that the tier could not have worked anyway.**

### Every candidate image failed, for three different reasons

Surveyed with `skopeo` on 2026-09-09:

| Candidate | Provenance | Verdict |
|---|---|---|
| `docker.io/rocm/comfyui` | **AMD's own**, from the ROCm docs | `PYTORCH_ROCM_ARCH=gfx942;gfx950` — **Instinct only, no kernels for gfx1100.** The most first-party option cannot run on this card |
| `docker.io/yanwk/comfyui-boot:rocm` | 1647★, 1.34M pulls — by far the best | Copies ComfyUI out of the image into a persistent volume on first start with `cp --archive --update=none`, then sources a root-run `pre-start.sh` from that volume with `PIP_USER=true`. **The digest pins the first install and nothing that runs after it** |
| `docker.io/selcarpa/comfyui-rocm` | 1★, 2703 pulls, one person | The only image that both ships ComfyUI and carries gfx1100 kernels |

### And llama-swap could never have arbitrated a container

This is the finding that settled it, and it is structural rather than a matter
of taste. **Eviction is llama-swap killing the backend on ttl — there is no
other unload path.** `llama-swap.service` runs as the unprivileged `llama`
user; ernst's podman tier is rootful. A non-root process cannot start or stop a
rootful container, so ComfyUI could have been *reached* but never *arbitrated*
— and arbitration is the entire point.

The registration M19 shipped could not have run either: it set `proxy` with no
`cmd`, which is the same "empty command" shape this module already documents
for the abandoned router arrangement. `doStart()` requires both
(`internal/process/process_command.go:358-364`). Nothing caught it because the
role was never enabled.

### What it is now

A hand-rolled derivation in [`pkgs/comfyui/`](pkgs/comfyui/), spawned by
llama-swap as an ordinary child process exactly as `llama-server` and
`whisper-server` are. It inherits that unit's ROCm sandbox — `/dev/kfd` +
`char-drm`, `MemoryDenyWriteExecute=false` — eviction is a plain process kill,
and **M21 took no uid, no MAC and no address**; uid 3035, sequence 10 and
`10.0.90.24` all went back to M20.

The cost the roadmap expected — compiling the ROCm PyTorch stack — **does not
exist.** Verified against `cache.nixos.org`: `torch`, `torchvision` and
`torchaudio` are all substitutable, and `rocmPackages.clr.gpuTargets` already
contains `gfx1100`. The catch is the *shape* of the override — see
`pkgs/comfyui/default.nix`, which reproduces those cached paths by overriding
the **package set** rather than one package's `torch` argument.

### Weights come from `roles.models`, through a third consumer

Checkpoints are declared like every other model — one fetcher, one
hash-verified tree — with `servedByLlama = false` and a `subdir`. ComfyUI
discovers models by **scanning category directories** rather than being handed
a path, so a generated `extra_model_paths.yaml` maps the store into it, and
that mapping is *derived from the declarations*: a model's `subdir` IS its
ComfyUI category.

`subdir` exists because a flat store is wrong in a subtle way here:
`folder_paths.py`'s `supported_pt_extensions` includes `.bin`, so Whisper's
`ggml-large-v3-turbo-q5_0.bin` would be offered as a diffusion checkpoint while
the GGUFs were correctly ignored. It defaults to `""`, so **no existing model
path moves.**

### Open WebUI reaches it at `/upstream/comfyui`

Open WebUI's ComfyUI client speaks ComfyUI's own API (`POST /prompt`,
`GET /history/<id>`, `GET /view`, and a websocket at `/ws`) — **none of which
carry a model name** for llama-swap to dispatch on.
`/upstream/<model>/<path>` is llama-swap's answer: it proxies any request to
that backend, starting it through the normal swap path first, so the exclusive
group still evicts the LLM (`internal/server/api.go`, registered at
`server.go:230`). The websocket survives it because Open WebUI builds its
socket URL by string-replacing the scheme on the same base
(`utils/images/comfyui.py:190`) and every HTTP call is an `f'{base_url}/…'`
append.

It uses the **same `fdca:fe91::1` bridge** chat and STT already use — no new
listener, no new firewall rule.

### What is deliberately absent

- **`comfy-angle`** — a prebuilt binary wheel with no sdist, imported by one
  optional node pack (`comfy_extras/nodes_glsl.py`). Its absence is a startup
  warning and one unregistered node pack; confirmed by running the built
  package, not assumed.
- **`comfy-aimdo`'s native offloader** — the pure-Python wheel is taken (see
  `pkgs/comfyui/comfy-aimdo.nix`), so dynamic weight offloading is off. It has
  nothing to relieve here: the LLM is evicted before ComfyUI starts, so the
  card is not shared at the moment of use. **That reasoning expires** if a
  checkpoint is ever declared that does not fit alone.
- **`comfy-kitchen`'s compiled kernels** — eager (plain PyTorch) is what runs.
  Measured, not assumed: the `hip` backend reports *"HIP extension not built
  (no _C module in backends/hip)"*, so it is a compiled extension the platform
  wheels carry rather than a runtime JIT.
- **470 MB of template preview media**, and **ComfyUI-Manager**. Custom nodes
  cannot be installed at runtime against a read-only store, which is a property
  rather than a gap: a node that is wanted becomes a derivation.

## Open WebUI

An nspawn container on VLAN 90 (`10.0.90.23`), reachable only through Traefik,
behind the `authelia` middleware **and** speaking OIDC to the same provider.
That is the Grafana arrangement, not CWA's: forward-auth decides whether the
request arrives, OIDC decides whose it is. CWA takes OIDC *instead of*
forward-auth because its Kobo and OPDS clients cannot follow a redirect — do not
merge the two reasonings.

It reaches llama-swap over a point-to-point ULA veth (`fdca:fe91::1`), the same
shape M6 used for monitoring and for the same reason: llama-swap is bound to the
host's loopback and a container cannot reach that.

### `ENABLE_PERSISTENT_CONFIG = "False"` is load-bearing

Open WebUI's "PersistentConfig" writes most settings into its own database **on
first launch**, and thereafter **the database wins**. A changed environment
variable then deploys green and does nothing — the exact failure shape this repo
keeps rediscovering. `False` makes the environment authoritative on every boot,
which is the only way a Nix-rendered config means anything here.

### The licence, so nobody rediscovers it

Open WebUI is **marked unfree in nixpkgs**. It is BSD-3-clause plus a fourth
clause forbidding removal or alteration of "Open WebUI" branding — **except**
where the total number of end users does not exceed **fifty in any rolling
30-day period**. This household is comfortably under that, so the exemption
applies (and the branding is left alone anyway).

ernst does **not** set `allowUnfree`; it carries a narrow
`allowUnfreePredicate` from `modules/roles/htpc.nix` for Steam, and that file
says why. The allowance for Open WebUI therefore lives **inside the container's
own nixpkgs**, so the host's predicate is untouched.

## OpenCode config schema

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "local/qwen3-coder-30b",
  "provider": {
    "local": {
      "npm": "@ai-sdk/openai-compatible",
      "options": { "baseURL": "http://127.0.0.1:11435/v1" },
      "models": { "qwen3-coder-30b": {} }
    }
  },
  "instructions": ["/nix/store/…-opencode-tool-call-rule.md"]
}
```

This role previously wrote `providers.ollama.baseUrl` — plural key, camelCase
`baseUrl`, no `npm` driver. That matches no version of the schema, so opencode
ignored the block entirely and fell through to its own defaults. It failed
silently, which is why it went unnoticed. The provider's `models` map is not
optional either: this provider has no catalogue for opencode to discover, so an
undeclared name is not selectable even when the server has it.

## miralda still runs Ollama, deliberately

`roles.ollama` is kept for exactly one machine. The case M19 measured is a
24 GiB discrete card with a 30B model; miralda is a Phoenix 780M iGPU
(`gfx1103`) running a 7B out of **shared system RAM**, which is a different
problem — the VRAM arbitration that justifies llama-swap does not apply, the
`HSA_OVERRIDE_GFX_VERSION = "11.0.3"` override does, and M11 noted in passing
that the override is not even working there (miralda's Ollama runs at 100% CPU).
Migrating it is a real question with its own measurement, and it was not this
milestone's.

**Everything Ollama-specific therefore still applies on miralda, including the
silent-truncation hazard.** SN1 is live there. Pin `contextLength`.

## Usage

### Inventory (`clan.nix`)

```nix
local-ai = {
  module.input = "self";
  module.name  = "@clanarchy/local-ai";

  roles.inference.machines.ernst.settings = {
    remoteClients.enable = true;
    metricsProxy.enable  = true;
    metricsProxy.address = "fdca:fe90::1";
  };
  roles.models.machines.ernst.settings.models = { /* see above */ };
  roles.speech.machines.ernst.settings.language = "auto";
  roles.webui.machines.ernst.settings = {
    mac = "02:00:00:90:00:0f";
    uid = 3034;
    hostName = "chat.goclan.org";
    oidc.enable = true;
    inferenceAddress = "fdca:fe91::1";
  };

  # miralda: legacy ollama, out of M19's scope
  roles.ollama.machines.miralda.settings = {
    models = [ "qwen2.5-coder:7b" ];
    hsaOverrideGfxVersion = "11.0.3";
    contextLength = 4096;
  };

  roles.opencode.machines.jens.settings = {
    user  = "lgo";
    model = "local/qwen3-coder-30b";
    tunnel.enable = true;
  };
};
```

### Operating it

```bash
# What is actually served:
curl -s localhost:11434/v1/models | jq -r '.data[].id'

# What is resident right now, and on which port:
curl -s localhost:11434/running | jq -c '.running[] | {model, state}'

# VRAM, without rocm-smi (which is not on ernst's PATH):
echo $(( $(cat /sys/class/drm/card1/device/mem_info_vram_used) / 1048576 )) MiB

# Metrics — llama-swap's own. A plain scrape: no parameter, and up whether or
# not a model is resident.
curl -s http://127.0.0.1:11434/metrics | head

# Logs:
journalctl -u llama-swap -f          # includes the spawned llama-server output
journalctl -u llama-models-fetch     # the fetch/verify oneshot
```

### Troubleshooting

**A model 404s that clearly exists on disk** — it is fetched but not declared,
or declared under a different key than the client asks for. `/v1/models` is the
truth.

**`llama-models-fetch` fails with `MISMATCH`** — the file on disk does not match
the declared hash. It is deliberately **not** overwritten. Move it aside by hand
after working out which of the two is wrong.

**A newly added model 404s after a deploy** — expected. The fetch is off the
deploy path (above), so it has not run yet. `systemctl start
llama-models-fetch`; it restarts llama-swap itself when it completes.

**`clan machines update` appears to hang on this machine** — check
`systemctl list-jobs` on ernst before assuming a fault. If
`llama-models-fetch.service` is the running job you are watching a download, not
a hang; `ls -la /srv/state/local-ai/models/*.part` shows progress. This should
no longer happen on deploy, only if the unit was started manually in the same
window.

**Tool calling suddenly at ~13%** — the `<tool_call>` instructions file is no
longer reaching the model. Check `instructions` in
`~/.config/opencode/config.json` points at an existing store path.
