##############################################################################
# roles.imagegen — ComfyUI, spawned by llama-swap
#
# ── THIS ROLE LEFT THE PODMAN TIER IN M21, AND THAT IS THE MILESTONE ──────
#
# M19 wrote it as a digest-pinned community image on the podman tier, with
# `image`, `uid`, `/dev/kfd` and an assertion refusing any tag.  All of that
# is gone.  Two findings removed it, and both are recorded at length in
# service-modules/pkgs/comfyui/default.nix and M21 (docs/history.md):
#
#   1. NO USABLE IMAGE EXISTS.  AMD's own docker.io/rocm/comfyui is built
#      PYTORCH_ROCM_ARCH=gfx942;gfx950 — Instinct only, no kernels for
#      ernst's gfx1100.  The best-provenance community image (yanwk, 1647
#      stars) copies ComfyUI out of the image into a persistent volume with
#      `cp --update=none` and then runs a root pre-start.sh from that volume,
#      so its digest pins the first install and nothing afterwards.  The only
#      image that both ships ComfyUI and targets gfx1100 has one GitHub star.
#
#   2. llama-swap COULD NEVER HAVE ARBITRATED A CONTAINER.  Eviction is
#      llama-swap killing the backend on ttl — there is no other unload path.
#      llama-swap runs as an unprivileged user and ernst's podman tier is
#      rootful, so it could not have started or stopped the container.  The
#      registration M19 shipped could not even have run: `proxy` with no
#      `cmd` is the "empty command" shape this module already documents.
#
# So ComfyUI is now BUILT (service-modules/pkgs/comfyui) and spawned by
# llama-swap as an ordinary child, exactly as llama-server and whisper-server
# are.  It inherits that unit's ROCm sandbox, eviction is a process kill, and
# M21 takes NO uid, NO MAC and NO ADDRESS — the numbers M19 reserved for it
# (uid 3035, sequence 10, 10.0.90.24) were released back to M20.
##############################################################################
{lib, ...}: {
  description = "ComfyUI image generation, spawned by llama-swap, exclusive with the LLM on the GPU.";

  interface.options = {
    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/srv/state/comfyui";
      description = ''
        ComfyUI's `--base-directory`: outputs, inputs, temp, user settings
        and custom_nodes.  On zdata, per architecture invariant #7.

        NOT the model store.  Weights are declared in roles.models and live
        in the inference role's model directory, which ComfyUI is pointed at
        through a generated extra_model_paths.yaml — one fetcher, one
        hash-verified tree, three consumers.  What lands HERE is only what
        ComfyUI itself writes.

        It is created and owned by the inference role's user, because ComfyUI
        runs as a child of llama-swap.service and has no identity of its own.
      '';
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["--lowvram"];
      description = ''
        Extra arguments appended to ComfyUI's command line, verbatim.

        NOT a tuning knob, and one entry in it is load-bearing.

        ── `--use-split-cross-attention` IS NOT OPTIONAL ON ROCm ─────────

        PyTorch's SDPA cross-attention is SILENTLY WRONG on torch 2.11 +
        ROCm 7.2.3 / gfx1100.  Self-attention is fine, so images come out
        sharp and coherent — and completely unrelated to the prompt, because
        cross-attention is where the text conditioning enters the UNet.
        Bisected on ernst 2026-09-10 against a CPU control that used the
        same derivation and produced the correct image; see the settings in
        clan.nix for the full arm-by-arm record.

        It is set per-machine rather than defaulted here because it is a
        property of a GPU stack, not of the role — but any ROCm consumer
        almost certainly needs it, and a machine that omits it will not
        fail, it will just generate the wrong pictures.

        ── EVERYTHING ELSE ──────────────────────────────────────────────

        The VRAM-pressure flags (`--lowvram`, `--novram`,
        `--disable-smart-memory`) exist for cards that must share, and this
        one does not have to: llama-swap's exclusive group evicts the coder
        model BEFORE ComfyUI is spawned, so ComfyUI gets the whole card.
        Reaching for `--lowvram` here is usually a sign that the exclusion is
        not working and should be diagnosed rather than papered over.

        DO NOT PUT `--listen`, `--port`, `--base-directory` OR
        `--extra-model-paths-config` HERE.  Those are set from this role's
        settings and llama-swap's `${"\${PORT}"}` macro; a second copy would
        win or lose depending on argparse order, which is not a thing to
        discover at runtime.
      '';
    };
  };

  perInstance = {...}: {
    # Deliberately empty — the SAME arrangement roles.speech uses, for the
    # same reason, and the reason is the whole point of both roles.
    #
    # ComfyUI must be SPAWNED BY llama-swap rather than run beside it.  A
    # unit of its own would sit outside the exclusive group, hold VRAM while
    # the coder model wanted it, and could not be killed to give it back —
    # which is precisely the failure the group exists to prevent.  So this
    # role carries settings, and the inference role reads them and builds the
    # backend entry.  A unit here would be a second, competing owner.
    nixosModule = {...}: {};
  };
}
