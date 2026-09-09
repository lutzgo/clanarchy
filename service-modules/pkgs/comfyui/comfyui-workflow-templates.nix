# service-modules/pkgs/comfyui/comfyui-workflow-templates.nix
#
# comfyui-workflow-templates — M21.  The example workflows ComfyUI offers in
# its "Browse Templates" dialog, shipped by upstream as a pure-Python wheel of
# JSON documents and thumbnails.
#
# Not in nixpkgs (surveyed 2026-09-09).  Same shape and same argument as
# comfyui-frontend-package.nix beside it: an upstream release artifact taken
# rather than rebuilt, found by IMPORT rather than by path, and version-pinned
# by ComfyUI 0.35.0's own requirements.txt.
#
# ── IT IS NOT OPTIONAL, DESPITE BEING "JUST EXAMPLES" ──────────────────────
#
#   ComfyUI's startup version check (app/frontend_management.py's
#   check_comfy_packages_versions()) covers this package too, and the template
#   browser is the only route a first-time user has to a working graph — the
#   default workflow is the one thing standing between "the UI loads" and "an
#   image comes out".  Bump it together with default.nix's ComfyUI version.
{
  lib,
  buildPythonPackage,
  fetchurl,
  comfyui-workflow-templates-core,
  comfyui-workflow-templates-json,
}:

buildPythonPackage rec {
  pname = "comfyui-workflow-templates";
  version = "0.11.57";
  format = "wheel";

  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/1e/df/12106a07f991d05f23d9d87000c9515f3b94b2a106d0f5c013d6d501c92c/comfyui_workflow_templates-0.11.57-py3-none-any.whl";
    hash = "sha256-Uem7MHKU2jiB8SapGxITMOD4ziDur8sqf2NPFGciBrU=";
  };

  # ── IT IS A META-PACKAGE OVER SEVEN DISTRIBUTIONS; TWO ARE TAKEN ─────────
  #
  # This wheel is a shim.  Its entire __init__.py re-exports five helpers from
  # `comfyui_workflow_templates_core` at module scope, and everything of
  # substance lives in siblings it declares as hard dependencies:
  #
  #   core             74 KB   manifest helpers    TAKEN — parent imports it
  #   json            3.4 MB   the workflow graphs TAKEN
  #   media-api       100 MB   \
  #   media-video     104 MB    |  thumbnails and preview clips for the
  #   media-image      89 MB    |  template browser, 470 MB together
  #   media-other      89 MB    |
  #   media-assets-01  88 MB   /   NOT TAKEN
  #
  # Loading and running a template needs `json`; the media bundles only
  # decorate the picker with previews of the output.  So the cost of leaving
  # them out is a template entry with a broken thumbnail that still opens a
  # working graph — which is not worth 470 MB in every system closure on a
  # headless server whose UI is reached through Open WebUI.
  #
  # ── AND THE SPLIT WAS FOUND BY THE BUILD, TWICE, IN TWO DIFFERENT WAYS ──
  #
  # First `pythonRuntimeDepsCheckHook` failed on all seven missing
  # dependencies.  Silencing that with `dontCheckRuntimeDeps` then produced a
  # SECOND, different failure — `pythonImportsCheck` with
  # `ModuleNotFoundError: No module named 'comfyui_workflow_templates_core'`
  # — which is what distinguished the two genuinely-required siblings from the
  # five optional ones.  Neither check is ceremony: without the import check
  # this would have deployed and failed when ComfyUI first started.
  #
  # `dontCheckRuntimeDeps` is therefore scoped to this one package as a
  # statement that FIVE SPECIFIC absences are understood, not a blanket
  # opt-out.  If ComfyUI ever fails to START over a missing media bundle
  # rather than merely rendering an empty thumbnail, this is the line that was
  # wrong.
  dontCheckRuntimeDeps = true;

  dependencies = [
    comfyui-workflow-templates-core
    comfyui-workflow-templates-json
  ];

  doCheck = false;

  pythonImportsCheck = [ "comfyui_workflow_templates" ];

  meta = {
    description = "Example workflow templates bundled with ComfyUI";
    homepage = "https://github.com/Comfy-Org/workflow_templates";
    # MIT, unlike its two sibling asset wheels — checked in the wheel's own
    # METADATA and against the repository, not assumed from the family.
    license = lib.licenses.mit;
  };
}
