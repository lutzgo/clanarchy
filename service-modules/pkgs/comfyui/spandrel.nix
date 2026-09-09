# service-modules/pkgs/comfyui/spandrel.nix
#
# spandrel — M21.  Architecture auto-detection for PyTorch image models: hand
# it an ESRGAN/SwinIR/HAT/... .pth and it works out which architecture the
# weights belong to and returns a loaded model.  ComfyUI uses it for the
# upscale-model nodes (comfy_extras/nodes_upscale_model.py,
# comfy_extras/chainner_models/model_loading.py).
#
# Not in nixpkgs (surveyed against ernst's own pin, 2026-09-09).
#
# ── SOFTER THAN THE REST OF THE DEPENDENCY SET, AND SHIPPED ANYWAY ─────────
#
#   requirements.txt files this under "#non essential dependencies", and it is
#   genuinely optional in the way the others are not: ComfyUI imports
#   comfy_extras node packs defensively, so a missing spandrel costs the
#   upscale nodes and nothing else — the server starts and generates.
#
#   It is included because the cost is one small pure-Python derivation and the
#   alternative is a UI with nodes that silently are not there.  A workflow
#   copied from anywhere on the internet that ends in an upscale step would
#   fail to load, and the error would name a node, not a missing package.
#
# ── THE SDIST, NOT THE GIT TREE, AND FOR AN UNUSUAL REASON ────────────────
#
#   Upstream (chaiNNer-org/spandrel) is a MONOREPO: the published package is
#   `libs/spandrel/` inside it, and there is a second distribution
#   (`spandrel_extra_arches`, non-commercial licensed) beside it that ComfyUI
#   imports separately and optionally.  fetchFromGitHub would bring both and
#   then need a sourceRoot to point at one of them — and would drag a
#   restrictively-licensed sibling into the store to do it.
#
#   The PyPI sdist is exactly the one distribution, MIT, with the version as
#   part of the artifact's identity.  Same call bencoding.nix makes, for a
#   different reason.
#
#   spandrel_extra_arches is DELIBERATELY NOT PACKAGED.  nodes_upscale_model.py
#   imports it inside a try/except and carries on without it, and its licence
#   forbids commercial use — a term this repo should not casually accept into
#   a system closure for a handful of extra upscaler architectures.
{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  torch,
  torchvision,
  safetensors,
  numpy,
  einops,
  typing-extensions,
}:

buildPythonPackage rec {
  pname = "spandrel";
  version = "0.4.2";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-/vpOqWbGpbdyHc8k8+IGKlqWo5XIvty1cPtVlx/cvMs=";
  };

  build-system = [ setuptools ];

  dependencies = [
    torch
    torchvision
    safetensors
    numpy
    einops
    typing-extensions
  ];

  # The test suite downloads model weights from the internet to exercise the
  # architecture detection — the entire point of the library is that it
  # recognises real checkpoints, so its tests cannot run in a sandbox.
  # pythonImportsCheck is the guard, as it is for the rest of ./pkgs.
  doCheck = false;

  pythonImportsCheck = [ "spandrel" ];

  meta = {
    description = "Auto-detection and loading of PyTorch image model architectures";
    homepage = "https://github.com/chaiNNer-org/spandrel";
    license = lib.licenses.mit;
  };
}
