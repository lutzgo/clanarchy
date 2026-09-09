# service-modules/pkgs/comfyui/comfyui-embedded-docs.nix
#
# comfyui-embedded-docs — M21.  Per-node help text, rendered in the UI's
# sidebar.  The third of ComfyUI's three asset wheels; see
# comfyui-frontend-package.nix for the argument that covers all three.
#
# Not in nixpkgs (surveyed 2026-09-09).  Version pinned by ComfyUI 0.35.0's
# requirements.txt and checked at startup, so it moves with default.nix.
{
  lib,
  buildPythonPackage,
  fetchurl,
}:

buildPythonPackage rec {
  pname = "comfyui-embedded-docs";
  version = "0.5.11";
  format = "wheel";

  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/63/0f/f30966d7610571f0c1cb1034d4489b91db8afc5399fc1a4d0b8520689f6f/comfyui_embedded_docs-0.5.11-py3-none-any.whl";
    hash = "sha256-CrPpYlNnbQXK+E1ge4FcQyceUDAvPFHONjyuVHmqaX8=";
  };

  doCheck = false;

  pythonImportsCheck = [ "comfyui_embedded_docs" ];

  meta = {
    description = "Embedded per-node documentation for ComfyUI";
    homepage = "https://github.com/Comfy-Org/embedded-docs";
    license = lib.licenses.gpl3Only;
  };
}
