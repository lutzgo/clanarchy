# ernst — card1 VRAM starvation crash-looped the TV, 2026-10-09 — RESOLVED

**Status: cause confirmed and measured; fixes written and awaiting deploy.**

The living-room session crash-looped for eleven minutes because a language
model took VRAM the compositor needed. Nobody intervened — it ended when the
model's idle timer expired.

Three things were wrong, and the first is the one that matters:

1. **A model was sized against an idle card.** The card is never idle: the
   HTPC session holds a framebuffer on it continuously. The sizing argument
   lived in a comment, where nothing could check it.
2. **Nothing reclaimed the card when a session started.** llama-swap
   arbitrates the claimants it spawns and is blind to everything else; the
   session is not one of its children, so it could not be swapped out — only
   killed.
3. **The consumer that triggered it had no backoff**, and karakeep exposes no
   setting to give it one.

---

## Timeline

All times CEST, from `journalctl` and `coredumpctl` on ernst.

| Time | What happened |
|---|---|
| ~20:10 | karakeep began a tag + summary batch and asked llama-swap for `qwen3.6-35b-a3b` through `llama-bridge-karakeep` |
| 20:10–20:25 | `llama-server` could not load — Crimson Desert held the VRAM. llama-swap answered 500 in ~1.4 s; karakeep retried at **~60 requests/minute for fourteen minutes**, none of which could have succeeded |
| 20:25:20 | The load finally succeeded, which means the card had just been freed: the game had died. `mem_info_vram_used` went to 24 G of 24 G |
| 20:27:46 | First gamescope abort |
| 20:27:46–20:38:15 | **Nine** aborts, SDDM reloging the session in after each. Gaps as short as six seconds |
| ~20:44 | llama-swap's `ttl: 900` expired, the model unloaded, VRAM fell to 901 M, and the loop stopped on its own |

Note the ordering. The game did not lose to the model — the model could not
load *until* the game died. What the model then did was take the card so
completely that the session could never get back on it.

## Failure mode

Kernel, at every abort:

```
amdgpu 0000:03:00.0: amdgpu: [drm] *ERROR* Not enough memory for command submission!
[drm:amdgpu_dm_plane_helper_prepare_fb [amdgpu]] *ERROR* Failed to pin framebuffer with error -12
```

`-12` is `ENOMEM`. Every one of the nine coredumps carries the same stack:

```
abort (libc.so.6 + 0x29350)
gamescope::CDRMBackend::Commit(FrameInfo_t const*)
gamescope::CDRMBackend::Present(FrameInfo_t const*, bool)
paint_all(global_focus_t*, bool)
steamcompmgr_main(int, char**)
```

gamescope answers a failed DRM atomic commit by calling `abort()`. There is no
degraded mode.

**Why the display manager's restart limits did not stop it.** They never saw
it. `display-manager.service` has nixpkgs' defaults — `StartLimitIntervalSec=30`,
`StartLimitBurst=3`, `Restart=always` — but a compositor dying does not take
SDDM down, so the unit never restarted. It stayed `active (running)` throughout.
What was looping was SDDM's own `Relogin=true` restarting the *session*, which
only `clanarchy-session-run` is in a position to observe.

## The numbers

Measured by summing `/sys/kernel/debug/dri/0000:03:00.0/amdgpu_gem_info` per
process, each session idle, nothing else on the card:

| Claimant | VRAM |
|---|---|
| Card total (`mem_info_vram_total`) | 24560 MiB |
| `qwen3.6-35b-a3b` as configured | 23699 MiB |
| Kodi (`kodi.bin --standalone --windowing=gbm`) | 326 MiB |
| Steam Big Picture (gamescope 225 + Xwayland 276 + steamwebhelper 604 + steamwebhelper 215 + steam 31) | ~1350 MiB |

So:

- model + Kodi = 24025 of 24560 — **fits, with 535 MiB to spare**
- model + Big Picture = 25049 of 24560 — **over by 489 MiB**

That is the whole incident. The machine had been running in Kodi, which fit;
the session that could not fit was the gaming one.

## What the repo claimed, and why it was wrong

Two comments asserted this could not happen. Both have been corrected in place.

`clan.nix`, on the shared dGPU:

> A session and ROCm workloads share a GPU without trouble — compute goes
> through the render node, KMS through the card node — so this is a note for
> future readers rather than a conflict.

True about device nodes, and irrelevant. They do not compete for nodes. They
compete for VRAM, and the node argument never addressed that.

`clan.nix`, on the model that replaced the coder model at M29c:

> **THE ONE REAL COST: 460 MiB OF HEADROOM** — 24100 MiB of 24560 resident,
> against 20959 before. That is enough and it is not comfortable.

The arithmetic was right; the baseline was wrong. 460 MiB is what is left on an
idle card. Big Picture needs ~1350.

A third sentence in the same block was *nearly* right and worth reading
carefully:

> ANYTHING ELSE WANTING THE CARD evicts it, as before. ComfyUI still does.

True only for claimants **inside** llama-swap's `exclusive` group. ComfyUI and
whisper are children of `llama-swap.service`, so the group arbitrates them. The
session is not, so it cannot evict — it aborts. The word "anything" was doing
damage.

`docs/roadmap.md`'s M15 close-out had also recorded the problem as
**UNPROVOKED** ("no service claims the render node"). M19 later added a re-open
trigger noting it was provoked and that "something now arbitrates it". That
arbitration is intra-llama-swap only, and the session is exactly the claimant
it does not cover.

## The fixes

Three, because the single root cause has three independent failure surfaces.

### 1. A VRAM reserve the evaluator enforces

The session's idle baseline is now a declared number rather than whatever
happens to be left over:

- `clanarchy.local-ai` inference settings gain `vram.totalMiB` (24560),
  `vram.reserveMiB` (**1600** — the larger measured baseline plus 250 MiB for
  the framebuffer pin during a modeset) and `vram.cardPciAddress`.
- Each model gains `residentVramMiB`, which is **measured, never computed**.
- An assertion refuses any served model where
  `residentVramMiB + reserveMiB > totalMiB`, naming the model, all three
  numbers and the overage. One assertion per model, not one for the largest:
  the group is exclusive, so any member can be the resident one.
- A warning fires for any model left unmeasured, so omission is visible rather
  than silently exempt.

The next person to raise a context window gets a failed eval instead of a
coredump on the television.

### 2. The model was made to fit

Measured on ernst 2026-10-10, one arm at a time, `llama-server` run by hand on
the live card with the Kodi session resident (330 MiB) and subtracted out.
256-token decode, n=1 per arm. Ceiling is 24560 − 1600 = **22960 MiB**.

| arm | resident | decode | vs ceiling |
|---|---|---|---|
| `-c 32768` (as deployed) | 23699 MiB | 94.5 tok/s | **739 over** |
| `-c 16384` | 23381 MiB | 95.8 tok/s | 421 over |
| `-c 16384 --n-cpu-moe 1` | 22916 MiB | 87.0 tok/s | 44 under |
| `-c 16384 --n-cpu-moe 2` | 22353 MiB | 80.1 tok/s | 607 under |
| **`-c 32768 --n-cpu-moe 2`** | **22672 MiB** | **81.5 tok/s** | **288 under** |
| `-c 32768 --n-cpu-moe 3` | 22207 MiB | 76.2 tok/s | 753 under |

**Taken: `-c 32768 --n-cpu-moe 2`**, at −13.8% decode.

Not the faster arm. `-c 16384 --n-cpu-moe 1` holds 87.0 tok/s but halves the
context window — a semantic change for every consumer, and mneme injects a
constitution plus wiki recall on every turn — and clears the ceiling by 44 MiB,
which is the same thin posture that caused this incident.

`--n-cpu-moe N` moves only the expert tensors of the first N layers to system
RAM and leaves attention and the whole KV cache on the GPU. That is why two
layers buy 1027 MiB for 13% rather than for a third of the decode rate. It
needed no new option: `extraArgs` already existed, though its description had
drifted to describing ollama-era INI syntax and has been corrected.

### 3. Reclaim on session start, and a breaker behind it

`clanarchy-gpu-preempt.service` bounces `llama-swap.service` with
`try-restart` just before a session takes the card. Restarting frees the VRAM —
the backends are children of that cgroup — and leaves the swapper up and able
to reload. `try-restart` rather than `restart` so it is a no-op at boot, and
rather than `stop` because llama-swap's `Restart=on-failure` does not cover a
clean stop and every consumer would lose the model.

**On session start only.** The HTPC session is up twenty-four hours a day, so
"stop the compute while a session exists" would mean never running compute at
all. Steady-state coexistence is the reserve's job.

It is wired twice: `before`/`wantedBy` on `display-manager.service` for boot and
for `clanarchy-session-select`, and a `systemctl start` from
`clanarchy-session-run` — because SDDM's relogin never restarts the display
manager, and that is precisely the crash-loop path.

Behind it, a circuit breaker in `clanarchy-session-run` counts session entries
that nobody asked for (a deliberate switch clears the counter) and demotes
through `kodi` then `plasma` rather than letting the relogin run forever. Kodi
first for a measured reason: 326 MiB against Big Picture's 1350, so it is both
navigable with a remote and the mode most likely to survive whatever exhausted
the card. At the end of the chain the session **holds** instead of exiting,
because exiting is what the display manager answers with another relogin.

The counter lives on tmpfs (`/run/clanarchy-session`) so a reboot is a fresh
start.

### 4. karakeep is told to back off

karakeep 0.32.0 has **no** retry or backoff setting. Read from the deployed
store path:

- `apps/workers/dist/logger-DyXDxwmR.js:30-160` is the complete zod env schema;
  thirteen `INFERENCE_*` variables, none retry-related.
- `shared-server-CI-y1v5_.js:2310` creates the queue with a literal
  `numRetries: 3`.
- `queue-liteque-p9Yg_mKq.js:68` re-polls at 1000 ms.
- the bundled OpenAI SDK retries 5xx twice on its own at 0.5 s then 1 s.

Multiplied out, that is the measured ~60 requests/minute.

But the same SDK honours `Retry-After` off the wire (`index.js:8398-8426`), in
seconds or as an HTTP-date, **with no clamp**. So the backoff is the server's to
send. A 503 gate now stands on karakeep's leg whenever the card belongs to
something outside llama-swap's group: same ULA address as the bridge, mutually
exclusive by the bind itself, raised by llama-swap's `ExecStopPost` and lowered
by its `Conflicts`. A 30-second watchdog reads card occupancy and decides which
of the two owns the leg.

Expected: ~2–3 requests per 300 s instead of ~60 per 60.

**Gated for karakeep alone.** A 503 is right for bookmark tagging and wrong for
anything with a person waiting on it, so Open WebUI and Home Assistant are not
gated, and monitoring must keep scraping for the condition to stay visible.

## Traps worth remembering

**A unit that stays `active` while its payload dies nine times.** The instinct
on a crash loop is to reach for `StartLimitBurst`. It was already set, already
correct, and already irrelevant. Check *which* thing is restarting before
limiting it.

**Measuring a model on a card that is not empty.** Measuring the model while the
session is up measures the sum — the quantity the check is supposed to be
*against*, not its input. Every figure in the table above was taken with the
Kodi baseline subtracted, and the option's description says so, because the next
person will be tempted to skip the stop.

**A headroom figure with no stated baseline.** "460 MiB of headroom" was true
and useless. A reserve is only meaningful next to what it is reserved *from*.

**`ExecStopPost` inherits the unit's sandbox.** The line that raises the gate
runs `systemctl`, under a unit with `User=llama`, `NoNewPrivileges` and a
syscall filter — where it cannot talk to PID 1. It needs the `+` prefix to run
as root, and without it the gate would simply never come up, with the only
symptom being consumers hammering a dead port.

**Two measurement runs were lost to the bug itself.** Repeat runs of the chosen
arm died with `failed to load model` because llama-swap had loaded the 35B for a
real karakeep job mid-measurement. The incident reproduced itself, unprompted,
during the investigation into it.

**"Mutually exclusive by the bind" is not a mechanism.** The first deploy of
this fix failed to start the gate:

```
llama-gate-karakeep.socket: Failed to create listening socket
  ([fdca:fe92::1]:11434): Address already in use
```

The gate and the bridge bind the same address, and that was described in the
code as making them mutually exclusive. It does not: the bridge is
`wantedBy = sockets.target` and therefore always up, so the shared bind did not
arbitrate between them — it just failed whichever came second, which was always
the gate. Two units wanting one address need `Conflicts=` naming each other;
the collision is the symptom, not the mechanism. Fixed in #301.

**A `try-restart` inside an activation transaction can be cancelled.** The
preempt unit also failed on that first deploy — `Job for llama-swap.service
canceled` — because activation was already restarting llama-swap and systemd
resolved the duplicate job by dropping one. Ordering the unit `After=` the units
it bounces removes the cause; a `-` prefix on `ExecStart` removes the
consequence, which matters because this unit sits in front of the television
starting and must never be a reason for a dark screen.

## Not fixed

**A game that starts while a model is already resident still loses.** The gate
is load-prevention, not eviction: it stops a model being loaded onto a busy
card, and does not evict one that is already there. That case waits for the
idle ttl or a manual unload. Wiring Steam's launch path to preempt would close
it and is out of scope here.

**The reserve covers the session shell, not a running game.** A game wanting
several GiB will still make a model load fail. That is correct TV-wins
behaviour, and it is the case the gate exists to make survivable rather than
noisy.
