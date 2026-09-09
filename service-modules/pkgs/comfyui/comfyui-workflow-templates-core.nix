# service-modules/pkgs/comfyui/comfyui-workflow-templates-core.nix
#
# comfyui-workflow-templates-core — M21.  The manifest helpers
# (`load_manifest`, `iter_templates`, `get_asset_path`, `resolve_all_assets`,
# `get_template_entry`) that comfyui-workflow-templates re-exports.
#
# Not in nixpkgs (surveyed 2026-09-09).
#
# ── WHY THIS FILE EXISTS SEPARATELY: THE TEMPLATES PACKAGE IS A SHIM ───────
#
#   `comfyui-workflow-templates` used to be one wheel of JSON and media.  It is
#   now a META-PACKAGE over seven distributions, and its whole __init__.py is
#
#     from comfyui_workflow_templates_core import (
#         get_asset_path, get_template_entry, iter_templates,
#         load_manifest, resolve_all_assets,
#     )
#
#   at module scope.  So this is not an optional extra: without it the parent
#   fails to import, and ComfyUI fails to start.  It was found exactly that
#   way — pythonImportsCheck on the parent, ModuleNotFoundError — which is the
#   argument for keeping that check on every package in this directory even
#   where "it is just data".
#
#   74 KB, MIT, no dependencies of its own.
{
  lib,
  buildPythonPackage,
  fetchurl,
}:

buildPythonPackage rec {
  pname = "comfyui-workflow-templates-core";
  version = "0.3.337";
  format = "wheel";

  src = fetchurl {
    url = "https://files.pythonhosted.org/packages/7a/24/489449c3a289411c7fa02af6479675e6621af66ee6dc824107d9eb3e103b/comfyui_workflow_templates_core-0.3.337-py3-none-any.whl";
    hash = "sha256-wBWIjhGjgMwCpxidShk9vzxL8I40khpHRkSysfzO9V8=";
  };

  doCheck = false;

  pythonImportsCheck = [ "comfyui_workflow_templates_core" ];

  meta = {
    description = "Manifest helpers for ComfyUI's workflow templates";
    homepage = "https://github.com/Comfy-Org/workflow_templates";
    license = lib.licenses.mit;
  };
}
