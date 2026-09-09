# service-modules/pkgs/comfyui/comfyui-frontend-package.nix
#
# comfyui-frontend-package — M21.  ComfyUI's web UI, as upstream publishes it:
# a prebuilt JavaScript bundle inside a pure-Python wheel.
#
# Not in nixpkgs: surveyed against ernst's own pin on the session date
# (2026-09-09).  Neither `comfyui` nor any of its three asset packages exists
# there, which is why this directory exists at all.
#
# ── THE WHEEL IS THE UPSTREAM RELEASE ARTIFACT, AND THAT IS THE RULE ────────
#
#   docs/roadmap.md's packaging section, settled by M12: "take the upstream
#   release artifact when there is one ... build from source only when there is
#   not."  The frontend's source is a separate repository (Comfy-Org/
#   ComfyUI_frontend, a Vue/Vite application), and building it would mean a
#   node_modules lock in this repo for output that upstream already ships,
#   pinned to a version ComfyUI's own requirements.txt names exactly.
#
#   THE VERSION IS NOT FREE TO CHOOSE.  ComfyUI 0.35.0's requirements.txt
#   pins `comfyui-frontend-package==1.51.10`, and ComfyUI checks the installed
#   version against that pin at startup (app/frontend_management.py's
#   check_comfy_packages_versions()).  A mismatch is a warning rather than a
#   failure, but it means the UI and the server disagree about the API they
#   share.  BUMP THIS ONLY TOGETHER WITH default.nix's ComfyUI version.
#
# ── WHY IT IS A PYTHON PACKAGE AND NOT A DATA DERIVATION ───────────────────
#
#   ComfyUI locates the bundle by IMPORTING it — frontend_management.py's
#   default_frontend_path() resolves `comfyui_frontend_package.__file__` and
#   serves the `static/` directory beside it.  So it has to be on PYTHONPATH,
#   not merely on disk somewhere, and a plain `runCommand` copying files would
#   not be found.
{
  lib,
  buildPythonPackage,
  fetchurl,
}:

buildPythonPackage rec {
  pname = "comfyui-frontend-package";
  version = "1.51.10";
  format = "wheel";

  # fetchurl on the wheel URL rather than fetchPypi: fetchPypi's wheel support
  # needs `dist` and `python` attributes that just reconstruct this URL, and
  # the reconstruction is one more thing that can be wrong without saying so.
  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/db/66/0f951eb4a77fff00c093e9796667192812d03dabd836653f6b6295a11a7e/comfyui_frontend_package-1.51.10-py3-none-any.whl";
    hash = "sha256-UufSmfCwYcG2Yhfve2TfuhdjVdnfclKM9Dgcqi2us/s=";
  };

  # A wheel of static assets: there is nothing to test and no test suite in it.
  doCheck = false;

  pythonImportsCheck = [ "comfyui_frontend_package" ];

  meta = {
    description = "Prebuilt web frontend assets for ComfyUI";
    homepage = "https://github.com/Comfy-Org/ComfyUI_frontend";
    license = lib.licenses.gpl3Only;
  };
}
