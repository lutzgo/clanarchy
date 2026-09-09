# service-modules/pkgs/comfyui/comfy-kitchen.nix
#
# comfy-kitchen — M21.  Comfy-Org's kernel library for ComfyUI: fused
# attention, quantisation and RoPE implementations behind a backend registry.
# Required by ComfyUI 0.35.0's requirements.txt.
#
# Not in nixpkgs (surveyed 2026-09-09).
#
# ── SAME `py3-none-any` CHOICE AS comfy-aimdo.nix, DIFFERENT CONSEQUENCE ───
#
#   Read comfy-aimdo.nix first: it carries the full argument for why the pure
#   wheel is taken over the platform wheels (no sdist on PyPI, so a platform
#   wheel would be an unbuildable binary blob, which is the thing M21's
#   build-it decision exists to avoid).
#
#   What differs is what is lost, and here it is much less.  comfy-aimdo's
#   pure wheel is bindings around a native library that is simply missing.
#   comfy-kitchen's pure wheel is a COMPLETE, WORKING IMPLEMENTATION — the
#   `eager` backend is plain PyTorch, and there are `triton` and `hip` backends
#   beside it (backends/hip/__init__.py, with its own architectures.json).  The
#   platform wheels add nanobind-compiled CUDA kernels on top; the registry
#   selects among whatever is present.
#
#   So on an AMD card the compiled wheel was never the interesting one: its
#   extra is `nvidia-cublas`-shaped (that is literally the only non-dev extra
#   the package declares).  Taking the pure wheel here costs the eager path
#   instead of a fused CUDA path that ernst could not have used anyway.
#
# ── WHICH BACKEND ACTUALLY RUNS, MEASURED RATHER THAN ASSUMED ─────────────
#
#   The `hip` directory in this wheel invites the guess that an AMD card gets
#   fused kernels out of it.  IT DOES NOT.  ComfyUI's own registry, logged at
#   startup from this exact derivation on 2026-09-09:
#
#     Found comfy_kitchen backend hip:    {'available': False,
#       'unavailable_reason': 'HIP extension not built (no _C module in
#       backends/hip)', 'capabilities': []}
#     Found comfy_kitchen backend cuda:   {'available': False,
#       'unavailable_reason': 'Extension file not found: .../cuda/_C.abi3.so'}
#     Found comfy_kitchen backend triton: {'available': True, 'disabled': True}
#     Found comfy_kitchen backend eager:  {'available': True, 'disabled': False,
#       'capabilities': [ ...48 entries... ]}
#
#   So `hip` is a compiled extension the platform wheels carry and this one
#   does not — it is not a runtime JIT that might find hipcc on PATH.  What
#   runs is EAGER, in plain PyTorch, and it advertises the full capability set
#   (adaln, rope, int8/fp8/nvfp4/mxfp8 quantisation, sol_attn, ...).
#
#   That is a correctness-preserving, speed-costing choice, and the size of the
#   cost is NOT established — measure it on the real card before claiming a
#   number.  M19's warning is the one to hold onto while doing so: a plausible
#   result at a bad throughput is a fallback, and only VRAM and wall-clock tell
#   you which path ran.
{
  lib,
  buildPythonPackage,
  fetchurl,
  torch,
}:

buildPythonPackage rec {
  pname = "comfy-kitchen";
  version = "0.2.33";
  format = "wheel";

  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/ed/af/7effaeade6a7edfd73440971b71b014cb940e967b564ce488852a22176d8/comfy_kitchen-0.2.33-py3-none-any.whl";
    hash = "sha256-16/g53LX+1O825WOLN40fR2TVmGTeAxsM37FFAPSugQ=";
  };

  # torch is not in the wheel's declared dependencies — the eager backend
  # imports it anyway.  Named explicitly so this package cannot end up in an
  # environment without one, and so it takes the SAME torch as everything else
  # (default.nix builds one ROCm-enabled python set; two torches on one
  # PYTHONPATH is a failure that presents as an unrelated import error).
  dependencies = [ torch ];

  # ── torch DRAGS IN ninja's SETUP HOOK, AND A WHEEL HAS NOTHING TO BUILD ──
  #
  # Depending on torch propagates ninja, whose setup hook replaces buildPhase
  # with a ninja invocation.  There is no build here — the wheel is unpacked
  # and installed — so the phase runs in a directory with no build.ninja and
  # fails before it even gets that far:
  #
  #   build flags: -j32
  #   .../python3.13-ninja-1.13.2/nix-support/setup-hook: line 19:
  #     ninja: command not found
  #
  # An error about a missing ninja binary, in a package that neither has nor
  # wants one, caused entirely by a dependency edge added for correctness.
  # Turning the hook off is the fix; dropping the torch dependency would also
  # silence it and would be the wrong one — see the note above it.
  dontUseNinjaBuild = true;
  dontUseNinjaInstall = true;
  dontUseNinjaCheck = true;

  doCheck = false;

  pythonImportsCheck = [ "comfy_kitchen" ];

  meta = {
    description = "Kernel library for ComfyUI (pure-Python backends; CUDA kernels not built)";
    homepage = "https://github.com/Comfy-Org/comfy-kitchen";
    license = lib.licenses.asl20;
  };
}
