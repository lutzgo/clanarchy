# service-modules/pkgs/comfyui/comfyui-workflow-templates-json.nix
#
# comfyui-workflow-templates-json — M21.  The workflow template DEFINITIONS:
# the graphs themselves, as JSON.
#
# Not in nixpkgs (surveyed 2026-09-09).
#
# ── THIS IS THE SUBSTANCE, AND THE MEDIA BUNDLES ARE NOT ───────────────────
#
#   comfyui-workflow-templates splits into seven distributions.  Two carry
#   something a headless server needs and five do not, and the size difference
#   is what makes the split worth taking rather than pulling `[all]`:
#
#     core   74 KB   manifest helpers   REQUIRED — parent imports it
#     json  3.4 MB   the graphs         TAKEN — this file
#     media-api      100 MB  \
#     media-video    104 MB   |  thumbnails and preview clips
#     media-image     89 MB   |  for the template browser
#     media-other     89 MB   |
#     media-assets-01 88 MB  /   = 470 MB, SKIPPED
#
#   Loading a template needs the JSON in here.  The media bundles decorate the
#   picker with previews of what each template produces.  See the note in
#   comfyui-workflow-templates.nix for the `dontCheckRuntimeDeps` that makes
#   leaving them out a deliberate statement rather than an oversight.
{
  lib,
  buildPythonPackage,
  fetchurl,
}:

buildPythonPackage rec {
  pname = "comfyui-workflow-templates-json";
  version = "0.1.72";
  format = "wheel";

  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/dc/b5/6f6b4a83f9e5ebdfa0b9c1ef77d0064396678724867837afbf9d7a310d61/comfyui_workflow_templates_json-0.1.72-py3-none-any.whl";
    hash = "sha256-HT/q61C//0Fk2bGauyITHMzOiAVaqT/UzOoZkYKZ884=";
  };

  doCheck = false;

  pythonImportsCheck = [ "comfyui_workflow_templates_json" ];

  meta = {
    description = "Workflow template JSON definitions for ComfyUI";
    homepage = "https://github.com/Comfy-Org/workflow_templates";
    license = lib.licenses.mit;
  };
}
