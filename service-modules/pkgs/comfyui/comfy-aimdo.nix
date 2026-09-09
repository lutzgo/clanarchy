# service-modules/pkgs/comfyui/comfy-aimdo.nix
#
# comfy-aimdo — M21.  Comfy-Org's "AI Model Dynamic Offloader": a PyTorch VRAM
# allocator that pages model weights back to system RAM when the card comes
# under pressure.  ComfyUI 0.35.0 imports it AT MODULE SCOPE in four places
# (main.py, execution.py, comfy/memory_management.py, comfy/model_patcher.py),
# so it is not optional in the "the node pack fails to load" sense — without it
# ComfyUI does not start.
#
# Not in nixpkgs (surveyed 2026-09-09).
#
# ══ THE `py3-none-any` WHEEL IS TAKEN DELIBERATELY, AND THIS IS THE WHOLE ══
# ══ REASON M21 COULD BE BUILT RATHER THAN PINNED TO SOMEBODY'S IMAGE      ══
#
#   PyPI publishes FIVE wheels for this version.  Four are platform wheels
#   (cp39-abi3 manylinux x86_64/aarch64, win_amd64, win_arm64) carrying a
#   compiled `aimdo.so` / `aimdo_rocm.so`, and PyPI publishes NO sdist — so
#   taking a platform wheel would mean a prebuilt binary blob, from a project
#   with no buildable source on the index, woven into ComfyUI's memory manager.
#   That is precisely the opacity M21's "build it" decision was chosen to
#   avoid, and it would have made that decision incoherent.
#
#   The fifth wheel is `comfy_aimdo-0.5.3-py3-none-any.whl`, 24 KB, and it is
#   NOT a stub.  It is the complete set of Python bindings — control.py,
#   host_buffer.py, malloc_graph.py, model_mmap.py, model_vbar.py, torch.py,
#   vram_buffer.py — with the native library loaded through ctypes.  The
#   library is simply absent from this wheel, and its absence is a SUPPORTED,
#   HANDLED state rather than a crash:
#
#     lib = ctypes.CDLL(str(base_path / f"{impl}.{ext}"), mode=mode)
#     except Exception as e:
#         logging.info(f"comfy-aimdo failed to load: {e}")
#         return False
#
#   ...and main.py branches on that return value (`aimdo_initialized`).  So
#   ComfyUI runs with dynamic offloading DISABLED, which is a real functional
#   difference and is stated here rather than discovered later.
#
# ── WHY LOSING THE OFFLOADER COSTS THIS DEPLOYMENT ALMOST NOTHING ──────────
#
#   AIMDO exists to keep a model working on a card too small to hold it, by
#   faulting weights in and out under pressure.  On ernst the card is not
#   shared at the moment of use: llama-swap's exclusive group EVICTS the 21.8
#   GiB coder model before ComfyUI is spawned, so ComfyUI gets essentially all
#   24560 MiB to itself, and SDXL at 1024x1024 is nowhere near that.  The
#   offloader would have nothing to relieve.
#
#   That reasoning is load-bearing and it EXPIRES.  Declare a checkpoint that
#   genuinely does not fit — a full-fat Flux or an SDXL refiner chain held
#   resident alongside — and this becomes a real limitation rather than a
#   footnote.  The escape hatch is open: comfy-aimdo IS open source
#   (github.com/Comfy-Org/comfy-aimdo, first-party), so building `aimdo_rocm.so`
#   from that repository is a later derivation, not a dead end.
{
  lib,
  buildPythonPackage,
  fetchurl,
}:

buildPythonPackage rec {
  pname = "comfy-aimdo";
  version = "0.5.3";
  format = "wheel";

  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/e4/ef/9a94b88981e51dea163f2fdf98cd28424276fab6a31dc7e22ce89018778f/comfy_aimdo-0.5.3-py3-none-any.whl";
    hash = "sha256-sJQBRDnUGocFEDEjyXtOoqT4WE+uIMsUuVNLa4Ky6Xw=";
  };

  doCheck = false;

  # Importing is the whole guard here, and it is a meaningful one: the modules
  # below are what ComfyUI imports at module scope, and they must import
  # cleanly WITHOUT the native library present.  If a future version moves the
  # ctypes load out of init() and into import time, this check fails at build
  # time rather than at first request.
  pythonImportsCheck = [
    "comfy_aimdo.control"
    "comfy_aimdo.host_buffer"
    "comfy_aimdo.model_vbar"
  ];

  meta = {
    description = "PyTorch VRAM allocator with on-demand weight offloading, for ComfyUI (pure-Python bindings; native offloader not built)";
    homepage = "https://github.com/Comfy-Org/comfy-aimdo";
    license = lib.licenses.gpl3Only;
  };
}
