# service-modules/pkgs/comfyui/default.nix
#
# ComfyUI — M21.  Node-graph diffusion image generation, built from source
# against nixpkgs' ROCm PyTorch, spawned by llama-swap as an ordinary child
# process.
#
# Not in nixpkgs: neither `comfyui` nor any of its five unpackaged Python
# dependencies exists there, surveyed against ernst's own pin on the session
# date (2026-09-09).
#
# ══════════════════════════════════════════════════════════════════════════
# WHY THIS IS A DERIVATION AND NOT A PINNED CONTAINER IMAGE
# ══════════════════════════════════════════════════════════════════════════
#
# M19 shipped `roles.imagegen` written for the podman tier against a
# digest-pinned community image, and M21 was framed as choosing which image.
# The survey killed all three candidates and the tier along with them
# (docs/roadmap.md §M21 carries the full record; the short version):
#
#   * AMD's OWN image, docker.io/rocm/comfyui, is built
#     `PYTORCH_ROCM_ARCH=gfx942;gfx950` — Instinct only.  It has no kernels for
#     ernst's gfx1100 at all.  The most first-party option available cannot run
#     on the card.
#   * yanwk/comfyui-boot:rocm (1647 stars, 1.34M pulls — by far the best
#     provenance) copies ComfyUI OUT of the image into a persistent volume on
#     first start with `cp --archive --update=none`, then sources a root-run
#     `pre-start.sh` from that volume with PIP_USER=true.  The digest therefore
#     pins the FIRST INSTALL and nothing that runs afterwards, which is the one
#     property the digest pin was supposed to buy.
#   * selcarpa/comfyui-rocm is the only image that both ships ComfyUI and
#     carries gfx1100 kernels.  It is a one-person auto-build: 1 GitHub star,
#     2703 pulls.
#
# And a mechanism-level blocker underneath all of it: llama-swap MUST own the
# process or eviction cannot free VRAM (it kills the backend on ttl; there is
# no other unload path).  `llama-swap.service` runs as the unprivileged `llama`
# user, and ernst's podman tier is rootful — a non-root process cannot start or
# stop a rootful container.  A container ComfyUI could be reached, but never
# arbitrated, and arbitration is the entire milestone.
#
# Built instead, ComfyUI is a child of llama-swap.service.  It inherits that
# unit's ROCm sandbox — `DeviceAllow=/dev/kfd rw` + `char-drm rw`,
# `MemoryDenyWriteExecute=false` — exactly as llama-server's children do,
# eviction is a plain process kill, and M21 takes no uid, no MAC and no
# address.
#
# ══════════════════════════════════════════════════════════════════════════
# THE COST THIS WAS EXPECTED TO HAVE, AND MEASURED NOT TO
# ══════════════════════════════════════════════════════════════════════════
#
# The roadmap assumed building meant compiling the ROCm PyTorch stack.  It does
# not.  Verified against cache.nixos.org on 2026-09-09, by evaluating the
# override below and asking the cache for the resulting paths:
#
#   python3.13-torch-2.11.0        SUBSTITUTABLE
#   python3.13-torchvision-0.26.0  SUBSTITUTABLE
#   python3.13-torchaudio-2.11.0   SUBSTITUTABLE
#
# ── AND THE EXACT SHAPE OF THE OVERRIDE IS LOAD-BEARING ───────────────────
#
#   `python3Packages.torchvision.override { torch = python3Packages.torchWithRocm; }`
#   is the obvious spelling and it is the WRONG one.  It produces a torchvision
#   that is NOT in the cache (and a torchaudio that is not either), because it
#   changes one input of one package rather than the set those packages agree
#   on.  It also leaves plain `torch` reachable through every other package's
#   propagated inputs, so the environment can end up with TWO torches on
#   PYTHONPATH — which does not fail at build time and presents at runtime as
#   an unrelated import error.
#
#   Overriding the SET is what reproduces the cached paths byte-for-byte and
#   guarantees one torch.  The body must mirror nixpkgs' own `torchWithRocm`
#   (pkgs/top-level/python-packages.nix) exactly, INCLUDING `triton` — and it
#   must take `triton-no-cuda` from `prev`, not `final`: nixpkgs defines
#   torchWithRocm as `self.torch.override { triton = self.triton-no-cuda; ... }`
#   against the base set, and reaching for `final` here is an infinite
#   recursion (torchWithRocm is defined in terms of torch).
#
# ── NO rocmGpuTargets OVERRIDE, DELIBERATELY ──────────────────────────────
#
#   The temptation is to narrow the build to gfx1100 the way the inference role
#   does for llama-cpp.  DO NOT.  llama-cpp is built locally either way, so
#   narrowing it is free; torch is not, and any override of its target list
#   leaves the cache and turns this into a multi-hour compile.  The stock list
#   already contains gfx1100 — checked, not assumed:
#
#     rocmPackages.clr.gpuTargets = [ gfx900 gfx906 gfx908 gfx90a gfx942 gfx950
#       gfx1010 gfx1030 gfx1100 gfx1101 gfx1102 gfx1103 gfx1150 gfx1151
#       gfx1200 gfx1201 ]
#
#   NO HSA_OVERRIDE_GFX_VERSION is set here either, for the reason the
#   inference role states at length: the 7900 XTX is gfx1100 and ROCm supports
#   it natively, so an override makes ROCm select the wrong kernels for a card
#   that already has correct ones.  That override belongs to miralda's gfx1103
#   APU and nowhere near this file.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  makeWrapper,
  python3,
}:

let
  # ── The one ROCm-enabled Python set everything below is built from ───────
  #
  # See the long note above for why this is a set override rather than a
  # per-package one, and why `prev.triton-no-cuda` rather than `final`.
  pythonRocm = python3.override {
    packageOverrides = final: prev: {
      torch = prev.torch.override {
        triton = prev.triton-no-cuda;
        rocmSupport = true;
        cudaSupport = false;
      };
    };
  };

  py = pythonRocm.pkgs;

  # The seven dependencies nixpkgs does not carry.  Each has its own file with
  # its own argument; comfy-aimdo.nix is the one to read first, because it
  # explains the pure-wheel choice the whole build rests on.
  comfyui-frontend-package = py.callPackage ./comfyui-frontend-package.nix { };
  comfyui-workflow-templates-core = py.callPackage ./comfyui-workflow-templates-core.nix { };
  comfyui-workflow-templates-json = py.callPackage ./comfyui-workflow-templates-json.nix { };
  comfyui-workflow-templates = py.callPackage ./comfyui-workflow-templates.nix {
    inherit comfyui-workflow-templates-core comfyui-workflow-templates-json;
  };
  comfyui-embedded-docs = py.callPackage ./comfyui-embedded-docs.nix { };
  comfy-aimdo = py.callPackage ./comfy-aimdo.nix { };
  comfy-kitchen = py.callPackage ./comfy-kitchen.nix { };
  spandrel = py.callPackage ./spandrel.nix { };

  # ── The interpreter ComfyUI actually runs under ──────────────────────────
  #
  # Ordered to match ComfyUI 0.35.0's requirements.txt so the two can be
  # diffed by eye on a version bump, which is the only review that catches a
  # dependency being added upstream.  `comfy-angle` is the one entry
  # deliberately absent — see the note below the derivation.
  pythonEnv = pythonRocm.withPackages (ps: [
    comfyui-frontend-package
    comfyui-workflow-templates
    comfyui-embedded-docs

    ps.torch
    ps.torchsde
    ps.torchvision
    ps.torchaudio
    ps.numpy
    ps.einops
    ps.transformers
    ps.tokenizers
    ps.sentencepiece
    ps.safetensors
    ps.aiohttp
    ps.yarl
    ps.pyyaml
    ps.pillow
    ps.scipy
    ps.tqdm
    ps.psutil
    ps.alembic
    ps.sqlalchemy
    ps.filelock
    ps.av
    comfy-kitchen
    comfy-aimdo
    ps.requests
    ps.simpleeval
    ps.blake3

    # requirements.txt's "#non essential dependencies" block.
    ps.kornia
    spandrel
    ps.pydantic
    ps.pydantic-settings
    ps.pyopengl
  ]);

in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "comfyui";
  version = "0.35.0";

  # ── THE REPOSITORY MOVED, AND THE OLD NAME STILL REDIRECTS ───────────────
  #
  # `comfyanonymous/ComfyUI` is now `Comfy-Org/ComfyUI` (checked 2026-09-09 —
  # the GitHub API answers the old path with a 301 to repository id 589831718).
  # The canonical owner is used here, because a redirect is a thing that works
  # until it does not, and because ComfyUI's OWN cli_args.py still carries
  # `DEFAULT_VERSION_STRING = "comfyanonymous/ComfyUI@latest"` — so the stale
  # name is in the source too, and a reader comparing the two should know which
  # is which.
  src = fetchFromGitHub {
    owner = "Comfy-Org";
    repo = "ComfyUI";
    tag = "v${finalAttrs.version}";
    hash = "sha256-ffT9euBDsxpmq4wzd9R2QUcCgI/YnfQOsvC5HuAekUM=";
  };

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  # ── A SOURCE TREE PLUS A WRAPPER, NOT buildPythonApplication ─────────────
  #
  # ComfyUI is not a Python distribution: it has no setup.py and no
  # pyproject.toml declaring an installable package, and it is run as
  # `python main.py` from its own directory, resolving `comfy/`,
  # `comfy_extras/` and `custom_nodes/` relative to main.py's realpath.
  # buildPythonApplication would have nothing to install.
  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/comfyui
    cp -r . $out/share/comfyui/

    makeWrapper ${pythonEnv}/bin/python $out/bin/comfyui \
      --add-flags $out/share/comfyui/main.py

    runHook postInstall
  '';

  # ── THE STORE COPY IS READ-ONLY, AND ComfyUI EXPECTS TO WRITE ────────────
  #
  # Run bare, ComfyUI writes models/, input/, output/, temp/, user/ and
  # custom_nodes/ next to main.py — i.e. into the store, which fails.
  # `--base-directory <path>` relocates ALL SIX in one flag (comfy/cli_args.py),
  # and the caller is expected to pass it.  service-modules/local-ai.nix does,
  # pointing at the inference role's stateDir on zdata, which is where
  # architecture invariant #7 requires service state to live.
  #
  # It is not defaulted here because there is no honest default: a store path
  # would be wrong, /var/lib would bypass the invariant, and a silent fallback
  # to $PWD is how state ends up somewhere nobody declared.
  passthru = {
    inherit pythonEnv;
    python = pythonRocm;
    # Exposed for the same reason the fetcher and the preset INI share one
    # attrset in the inference role: so a reader can check the dependency set
    # without re-deriving it.
    inherit
      comfyui-frontend-package
      comfyui-workflow-templates
      comfyui-workflow-templates-core
      comfyui-workflow-templates-json
      comfyui-embedded-docs
      comfy-aimdo
      comfy-kitchen
      spandrel
      ;
  };

  meta = {
    description = "Node-graph interface for diffusion models, built against ROCm PyTorch";
    homepage = "https://github.com/Comfy-Org/ComfyUI";
    license = lib.licenses.gpl3Only;
    mainProgram = "comfyui";
    platforms = lib.platforms.linux;
  };
})
# ── WHAT IS DELIBERATELY NOT IN THE ENVIRONMENT ───────────────────────────
#
# `comfy-angle` — redistributable ANGLE (OpenGL-over-Vulkan) libraries, listed
# under requirements.txt's non-essential block.  It is imported by exactly one
# file, comfy_extras/nodes_glsl.py, which ComfyUI loads defensively like every
# other comfy_extras pack: without it that one node pack does not register and
# nothing else changes.  It is a prebuilt binary wheel with no sdist, so
# including it would reintroduce the opaque blob this whole approach exists to
# avoid, for a GLSL shader node on a headless server.
#
# `spandrel_extra_arches` — see spandrel.nix.  Non-commercial licence,
# optional import, not worth accepting into a system closure.
#
# ComfyUI-Manager and the custom-node ecosystem — NOT PACKAGED AND NOT
# INSTALLABLE HERE, which is a property rather than a gap.  Manager installs
# nodes by running `pip install` at runtime into ComfyUI's own directory; with
# the tree in the store that cannot happen, and the failure is loud (a
# read-only filesystem) rather than a silently mutating deployment.  A node
# that is genuinely wanted becomes a derivation and an entry in the environment
# above, reviewed like everything else.
