# machines/ernst/containers/pkgs/hacs.nix
#
# HACS — the Home Assistant Community Store, as a store-resident custom
# component for containers/home-assistant.nix.
#
# HACS is not a store in the app-store sense: it is a DOWNLOADER.  It browses
# GitHub for community integrations, themes and Lovelace cards, and writes what
# you pick into Home Assistant's own `custom_components/` and `www/community/`
# directories at runtime.  This file only installs HACS ITSELF.  What HACS then
# downloads is state, not configuration, and lands on zdata/state alongside
# .storage — see the "WHAT HACS DOWNLOADS IS NOT DECLARATIVE" section of
# containers/home-assistant.nix, which owns that argument.
#
# ── NOT IN nixpkgs, AND NOT AN OVERSIGHT ────────────────────────────────────
#
#   Surveyed against ernst's own pin on the session date (2026-09-17): of the
#   ~110 attributes under `pkgs.home-assistant-custom-components`, `hacs` is not
#   one.  That is consistent rather than missing — nixpkgs' answer to "install a
#   community integration" is `services.home-assistant.customComponents`, which
#   is the option this file is consumed through.  HACS is the imperative tool
#   that option exists to replace, so nobody has packaged the replaced thing.
#
#   It is still worth having: nixpkgs carries roughly a hundred custom
#   components and HACS indexes several thousand, and the FRONTEND half — themes
#   and Lovelace cards, which are pure JavaScript dropped into `www/community/`
#   — has no nixpkgs equivalent at all and no Python to reconcile.  That half
#   works here without a caveat.
#
# ── THE RELEASE ZIP, NOT THE GIT TAG.  THIS ONE IS LOAD-BEARING. ────────────
#
#   `fetchFromGitHub` on tag 2.0.5 builds a HACS whose web panel is a 404.  The
#   compiled frontend (`hacs_frontend/`, ~19 MB of the ~19 MB artifact) is NOT
#   in the repository — it is pulled from the `hacs-frontend` PyPI package and
#   folded into the zip by the release workflow.  Checked: the git tree under
#   custom_components/hacs has 25 entries and no hacs_frontend among them.
#
#   The manifest carries the same tell.  In git it reads `"version": "0.0.0"`,
#   a placeholder the release workflow substitutes; the zip's reads "2.0.5".
#   Home Assistant surfaces that string as the integration's version and HACS
#   compares it against its own releases, so the git tree would also report
#   itself as permanently out of date.
#
#   So the zip is the only artifact that is actually HACS.  `stripRoot = false`
#   because it unpacks FLAT — its members are `manifest.json`, `base.py`,
#   `hacs_frontend/` and so on, with no enclosing directory — which is exactly
#   what buildHomeAssistantComponent's installPhase probes for when it tests
#   `[[ -f ./manifest.json ]]` and relocates the tree to
#   $out/custom_components/hacs.
#
# ── 2.0.5 IS THE CURRENT RELEASE, DESPITE THE DATE ──────────────────────────
#
#   Published 2025-01-28, which reads stale next to a 2026 deploy.  It is not:
#   `gh api repos/hacs/integration/tags` returns 2.0.5 at the top and the
#   repository's main branch was last committed 2026-09-05.  Upstream is alive
#   and has simply not cut a release since 2.0.  Do not go looking for a newer
#   tag on the assumption that one must exist.
#
# ── HACS CANNOT UPDATE ITSELF HERE, AND THAT IS THE TRADE ───────────────────
#
#   HACS ships an `update.hacs` entity that rewrites its own
#   custom_components/hacs directory.  Under this module that directory is a
#   symlink into the store, so pressing Install fails with EROFS.  The entity
#   is left alone rather than suppressed: a visible, failing update button is a
#   truthful description of the situation, and hiding it would just mean the
#   next person rediscovers the constraint from a stack trace.
#
#   Updating HACS is a change to THIS FILE: bump `version`, re-run
#   `nix-prefetch-url --unpack <url>`, convert with `nix hash convert`, deploy.
#   Same for any integration this repo decides to pin rather than let HACS
#   fetch.
#
# ── aiogithubapi IS THE ONE DEPENDENCY, AND IT MUST BE DECLARED ─────────────
#
#   nixpkgs builds Home Assistant with `--skip-pip` (pkgs/servers/
#   home-assistant/default.nix), so the runtime `pip install --target deps` that
#   Home Assistant would normally use to satisfy a custom component's manifest
#   requirements never runs.  A manifest requirement that is not in the Python
#   environment is simply an integration that fails to set up.
#
#   `dependencies` below is what puts it there, and buildHomeAssistantComponent's
#   manifestRequirementsCheckHook proves it at BUILD time: it parses
#   manifest.json, resolves each requirement against the propagated inputs, and
#   fails the derivation on a miss.  So `aiogithubapi>=22.10.1` versus the
#   26.0.0 in ernst's pin is checked here, not discovered in a log.
{
  lib,
  fetchzip,
  buildHomeAssistantComponent,
  aiogithubapi,
}:

buildHomeAssistantComponent rec {
  owner = "hacs";
  domain = "hacs";
  version = "2.0.5";

  src = fetchzip {
    url = "https://github.com/hacs/integration/releases/download/${version}/hacs.zip";
    hash = "sha256-iMomioxH7Iydy+bzJDbZxt6BX31UkCvqhXrxYFQV8Gw=";
    # The archive has no enclosing directory — see the header.
    stripRoot = false;
  };

  dependencies = [
    aiogithubapi
  ];

  # ── THE PHANTOM INTEGRATIONS.  FOUND BY DEPLOYING, NOT BY BUILDING. ───────
  #
  #   First deploy, 2026-09-17.  ${configDir}/custom_components came back with
  #   THREE symlinks where one was expected:
  #
  #       hacs            -> .../custom_components/hacs
  #       frontend_es5    -> .../custom_components/hacs/hacs_frontend/frontend_es5
  #       frontend_latest -> .../custom_components/hacs/hacs_frontend/frontend_latest
  #
  #   and Home Assistant duly tried to load the last two as integrations:
  #
  #       ERROR [homeassistant.loader] Error loading integration: frontend_latest
  #       ERROR [homeassistant.loader] Error loading integration: frontend_es5
  #           ... return self.manifest["domain"]
  #
  #   THE CAUSE IS IN THE NixOS MODULE, NOT HERE.  Its copyCustomComponents runs
  #   `find "$component" -name manifest.json` and symlinks every PARENT
  #   DIRECTORY it finds (home-assistant.nix:947-949) — a bare -name over the
  #   whole tree, with nothing scoping it to a component root.  HACS's webpack
  #   output happens to put a file of that name in each frontend bundle, mapping
  #   `entrypoint.js` to its content-hashed filename, and those two are not
  #   Home Assistant manifests at all: no `domain`, no `version`, no
  #   `__init__.py` beside them.
  #
  #   nixpkgs KNOWS ABOUT THIS FILENAME COLLISION AND FIXED THE OTHER HALF.
  #   Issue #429790 reports it — against HACS, from this same release zip, at
  #   this same hash — and PR #432385 closed it by path-scoping the find in
  #   `manifest-requirements-check-hook.sh`.  That is why THIS DERIVATION BUILDS
  #   CLEANLY and the defect only appears on a running hub: the build-time half
  #   is repaired and the module-side half is not.  Do not read a green build as
  #   evidence that this is fixed upstream.
  #
  #   DELETING THEM IS SAFE, AND THAT WAS CHECKED RATHER THAN ASSUMED.  Nothing
  #   in HACS reads them: the only two Python files mentioning "manifest.json"
  #   are enums.py and repositories/integration.py, both concerned with the
  #   manifests of repositories HACS DOWNLOADS.  The browser never needs them
  #   either, because the hashes the maps contain are already inlined in
  #   hacs_frontend/entrypoint.js, which hardcodes
  #   `/hacsfiles/frontend/frontend_latest/entrypoint.bb9d28f38e9fba76.js` and
  #   its es5 sibling.  The maps are a build artefact that shipped.
  #
  #   THE SECOND HALF IS A TRIPWIRE, and it is the part worth keeping.  Deleting
  #   two known paths would silently stop working if a future HACS put a stray
  #   manifest.json somewhere else — and the failure would again be invisible at
  #   build time and visible only as a phantom integration in a production log.
  #   So anything nested that survives fails the derivation instead.
  postInstall = ''
    find "$out/custom_components/${domain}/hacs_frontend" -name manifest.json -delete

    strays=$(find "$out/custom_components/${domain}" -mindepth 2 -name manifest.json)
    if [ -n "$strays" ]; then
      echo "hacs: nested manifest.json files remain, and the NixOS module will" >&2
      echo "  symlink each one's parent into custom_components/ as an" >&2
      echo "  integration Home Assistant cannot load:" >&2
      echo "$strays" >&2
      exit 1
    fi
  '';

  meta = {
    description = "Home Assistant Community Store — browse and install community integrations, themes and Lovelace cards";
    homepage = "https://hacs.xyz/";
    license = lib.licenses.mit;
  };
}
