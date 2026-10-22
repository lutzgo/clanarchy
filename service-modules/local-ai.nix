#
# @clanarchy/local-ai — local AI inference, voice, vision and image generation.
#
# ── ONE BRIDGE GENERATOR, THREE ROLES (M29) ─────────────────────────────────
#
# `mkBridges` below is the whole mechanism by which anything in a container
# reaches a service bound to this host's loopback.  It was inline in
# roles.inference and is now shared, because M29 added two more consumers of
# exactly the same shape (mneme, and the two Wyoming voice servers) and the
# note the inline copy carried — "this is generated from a list because it was
# two hand-written blocks and the second one was never written" — applies with
# more force to a third and fourth.
#
# Each bridge is three things and each is silent when missing:
#   * the socket      — nothing listens, connections time out;
#   * the accept rule — the host firewall drops it, and the proxy logs nothing
#                       because it never sees the packet;
#   * the consumer    — pointed at this address, not at localhost.
#
# A FOURTH THING IS REQUIRED AND IS NOT HERE: the veth itself, declared by the
# consuming container as `extraVeths.<name>`.  M29 learned that the hard way —
# see the `aiVeth` note in roles.webui — and the guard for it lives in
# machines/ernst/networking.nix, because that is the only place that can see
# every container at once.
#
# ── WHAT REPLACED WHAT, AND WHY (M19) ────────────────────────────────────────
#
# This module used to be `roles.ollama` + `roles.opencode`.  Ollama is gone from
# ernst, replaced by llama-swap in front of llama-server in router mode.  The
# migration was measured before it was taken — the full Phase 0 record is in
# ~/.local/share/m19-llamacpp/PHASE0-NOTES.md and summarised in docs/history.md, with M19's PRs linked there.  Three results decided it:
#
#   1. CONTEXT OVERFLOW STOPS BEING SILENT.  This is the whole reason.  Ollama
#      answers an over-long prompt with HTTP 200, truncates to ~num_ctx/2,
#      KEEPS THE TAIL AND DISCARDS THE HEAD — where the system message and the
#      tool definitions live — and sets no flag anywhere.  Measured again on
#      2026-09-08: a 16,694-token prompt became 4,098 tokens and the model
#      INVENTED a placeholder-shaped MAC address rather than declining.
#      llama-server refuses the same request outright:
#
#        HTTP 400  request (16694 tokens) exceeds the available context size
#                  (8192 tokens), try increasing it
#
#      That is standing note SN1's core hazard removed at the mechanism, not
#      documented around.
#
#   2. THE `<tool_call>` DEFECT FOLLOWS THE MODEL, NOT THE PARSER.  M11 found
#      qwen3-coder drops the OPENING <tool_call> tag while emitting its closing
#      partner, and blamed ollama's compiled Go parser only until it looked.
#      llama.cpp parses through the GGUF's own Jinja template — a completely
#      independent implementation — and fails identically: 26/30 dropped-tag
#      failures on the worst condition, and ZERO "tag present but unparsed" in
#      any of eight cells across both servers.  So `toolCallRule` below is NOT
#      deleted by this migration; it is the fix on both, and it is still total
#      (60/60 with it, on each server).
#
#   3. DECODE IS WITHIN NOISE AT f16, AND q8_0 LOST ITS REASON TO EXIST.
#      Interleaved, n=5 cycles, same card, same day:
#
#        llama-server f16  32k   21799 MiB   107.5 tok/s   (-3.1%)
#        llama-server q8_0 32k   20361 MiB    94.6 tok/s   (-14.7%)
#        ollama       q8_0 32k   20163 MiB   110.9 tok/s   (control)
#
#      ernst ran q8_0 only because f16 at 64k SPILLED on ollama.  On llama.cpp
#      f16 at 32768 — the window ernst actually declares — fits with 2761 MiB
#      to spare.  So the fleet default moves back to f16 and q8_0 becomes a
#      per-model opt-in with a price tag written next to it.
#
# ── WHY TWO LAYERS, llama-swap AND llama-server'S OWN ROUTER ─────────────────
#
# The obvious objection is that llama-server's router already swaps models, so
# llama-swap is redundant.  It is not, and this is a measurement rather than a
# preference — two of them:
#
#   (a) THE ROUTER NEVER FREES VRAM WHEN IDLE.  Its only unload path is
#       `unload_lru()`, driven solely by `--models-max` being reached
#       (tools/server/server-models.cpp).  There is no idle timeout anywhere in
#       it; the one `timeout` field on a model is `stop_timeout`, for shutdown.
#       So an idle coder model sits on 21.8 GiB forever and a NON-LLM consumer
#       — ComfyUI, whisper-server — can never displace it, because it is not a
#       router "model" at all.  llama-swap's per-model `ttl` plus an
#       `exclusive` group is exactly the missing mechanism, and it is the only
#       thing on this machine that knows the 30B and ComfyUI cannot coexist in
#       24 GiB.
#
#   (b) THE ROUTER ADVERTISES A PHANTOM MODEL THAT RECURSES.  `/v1/models` on
#       the router lists `default` alongside the declared set — it is built
#       from the router's own argv.  Requesting it makes the router SPAWN A
#       CHILD OF ITSELF IN ROUTER MODE and wait for it forever; the request
#       hangs with no response at all.  Clients that pick the first entry from
#       /v1/models — several do — hang.  llama-swap's /v1/models is its
#       declared map and nothing else, and an undeclared name is a clean 404.
#
# So: llama-server's router handles LLM<->LLM swapping and per-model context,
# llama-swap handles LLM<->non-LLM exclusion and hides (b).  llama.cpp itself
# calls router mode "experimental … not recommended in untrusted environments",
# which is a third reason not to make it the front door.
#
# ── THE PORT IS 11434 ON PURPOSE ─────────────────────────────────────────────
#
# llama-swap takes the port ollama had.  Every existing client keeps working
# unchanged, and — the part that matters for security review — the jens tunnel's
# `permitopen="127.0.0.1:11434"` restriction stays exactly as it was.  Nothing
# about the SSH forward changes.
#
# ── ROLES ────────────────────────────────────────────────────────────────────
#
#   inference — llama-swap + llama-server router.  Loopback only.
#   models    — declarative model set.  Fetched to zdata, hash-verified, and
#               the SAME attrset renders the router's preset INI, so a model
#               cannot exist in one and not the other.
#   opencode  — the CLI agent, pointed at llama-swap (local or tunnelled).
#   speech    — whisper.cpp STT on an OpenAI-shaped endpoint.
#   imagegen  — ComfyUI, BUILT from source and spawned by llama-swap (M21).
#               It was written for the podman tier in M19 and moved off it in
#               M21: no usable image exists for this card, and an unprivileged
#               llama-swap could never have started or stopped a rootful
#               container — which eviction requires.  See the role.
#   webui     — Open WebUI in an nspawn container on VLAN 90.
#   agent     — mneme: the household agent daemon.  Presents the Ollama wire
#               protocol to Home Assistant (whose release has no llama.cpp
#               integration) and plain OpenAI to everything else, injecting the
#               constitution on the way through.  M29.
#   voice     — Wyoming STT and TTS for Home Assistant's Assist pipeline.  M29.
#
# ── THIS FILE IS THE SHELL.  EACH ROLE LIVES IN ./local-ai/ ─────────────────
#
#   The roles were in here, all ten of them, and the file was 5,327 lines —
#   2.6x the 32k window the local coding model serves, so the one agent this
#   repo is meant to be workable by could not read the file it had to edit.
#   Each `roles.<name>` is now an ordinary attrset in ./local-ai/<name>.nix,
#   imported below.  No clan-core mechanism is involved: `roles.<name>` takes a
#   value, and an imported file that evaluates to the same attrset is the same
#   value.  The split is proven by the drv hash, not by review.
#
#   `mkBridges` moved to ./local-ai/bridges.nix and is passed to the three
#   roles that call it — inference, agent and voice.  It is a function of
#   `lib`, so it is applied here once rather than in each role.
{lib, ...}: let
  mkBridges = import ./local-ai/bridges.nix {inherit lib;};

  role = name: extra: import (./local-ai + "/${name}.nix") ({inherit lib;} // extra);
in {
  _class = "clan.service";
  manifest.name = "@clanarchy/local-ai";
  manifest.description = "Local AI: llama.cpp inference, voice, vision and image generation.";
  manifest.readme = builtins.readFile ./local-ai.md;

  roles.inference = role "inference" {inherit mkBridges;};
  roles.models = role "models" {};
  roles.speech = role "speech" {};
  roles.agent = role "agent" {inherit mkBridges;};
  roles.voice = role "voice" {inherit mkBridges;};
  roles.imagegen = role "imagegen" {};
  roles.search = role "search" {};
  roles.webui = role "webui" {};
  roles.ollama = role "ollama" {};
  roles.opencode = role "opencode" {};
}
