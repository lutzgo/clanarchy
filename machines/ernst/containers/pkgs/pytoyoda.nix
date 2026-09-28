# machines/ernst/containers/pkgs/pytoyoda.nix
#
# pytoyoda — the Toyota Connected Services client, and the runtime requirement
# of the `toyota` HACS integration (github.com/pytoyoda/ha_toyota, 3.2.1).
#
# ── WHY THIS FILE EXISTS AND `ps.pytoyoda` DOES NOT ─────────────────────────
#
#   `hacs-deps-check` found the gap and printed the usual remediation —
#
#       services.home-assistant.extraPackages = ps: [ ps.pytoyoda ];
#
#   — and that block CANNOT BE APPLIED: there is no `python3Packages.pytoyoda`
#   in nixpkgs, checked against ernst's own pin.  Pasting it would fail at
#   evaluation, not at runtime.  The checker's own closing paragraph names this
#   case ("a requirement with no nixpkgs packaging"), and this is the first time
#   it has come up, so the shape is worth stating: the printed fix is a
#   TEMPLATE, and the attribute existing is the thing to confirm before pasting.
#   `nix search nixpkgs python3Packages.<name>` is that confirmation.
#
#   The checker suggests packaging the whole integration under ./pkgs and
#   dropping it from HACS.  Not done, deliberately: the integration itself is
#   pure Python with no other gap, so vendoring pytoyoda alone closes it while
#   leaving HACS to keep the integration updated.  Packaging the component too
#   would mean tracking two upstreams to gain nothing this deployment needs.
#
# ── NOTHING ELSE HAD TO BE VENDORED ────────────────────────────────────────
#
#   All eight of pytoyoda 5.2.9's runtime dependencies are already in ernst's
#   package set AND already satisfy its constraints — checked before this file
#   was written, because one miss would have turned a single derivation into a
#   chain of them:
#
#     arrow              1.4.0     >=1.1,<2.0        ok
#     hishel             1.1.10    >=1.1.0,<2.0.0    ok
#     httpx              0.28.1    >=0.28.1,<0.29.0  ok   (at the floor)
#     importlib-metadata 9.0.0     >=9.0.0,<10.0.0   ok   (at the floor)
#     langcodes          3.5.1     >=3.1,<4.0        ok
#     loguru             0.7.3     >=0.7.3,<0.8.0    ok   (at the floor)
#     pydantic           2.12.5    >=2.10.4,<3.0.0   ok
#     pyjwt              2.13.0    >=2.8.0,<3.0.0    ok
#
#   THAT TABLE IS NOT THE WHOLE DEPENDENCY SET, which is the trap this file
#   fell into once already: `hishel[httpx]` is an EXTRA, and Nix does not model
#   extras. See the `anysqlite` note in `dependencies` below — it is a ninth
#   distribution that no requirement string names, and omitting it broke login
#   with a bare "Unexpected error" in the UI.
#
#   THREE OF THOSE SIT EXACTLY ON THEIR LOWER BOUND.  A nixpkgs bump that moves
#   httpx past 0.29, or loguru past 0.8, breaks this at BUILD time via the
#   dependency list below rather than silently at import — which is the reason
#   to name the constraints here rather than just the versions.
#
# ── fetchPypi SDIST, AND WHY THE BUILD BACKEND IS NOT A PROBLEM ────────────
#
#   pyproject.toml declares `build-backend = "poetry_dynamic_versioning.backend"`,
#   which normally derives the version from git tags and therefore fails in a
#   source tree with no `.git`.  It does not here, and the reason was checked in
#   the actual artifact rather than assumed: the PUBLISHED SDIST has the
#   resolved version written into it and the plugin switched off —
#
#       version = "5.2.9"
#       [tool.poetry-dynamic-versioning]
#       enable = false
#
#   — so the backend is a pass-through to poetry-core.  The plugin is still
#   listed in `build-system.requires` and must be importable, which is why it
#   appears in `build-system` below despite doing nothing.
#
#   THE HASH WAS TAKEN FROM PyPI's JSON API, not from a summary of the page.
#   A summarised read of that page reported `d85369ac…` for the sdist, which is
#   not a digest at all — it is the URL path (`…/d8/53/69ac9418…`) run together.
#   The digest below matches both the API's `digests.sha256` and a local
#   `sha256sum` of the downloaded file.
{
  lib,
  buildPythonPackage,
  fetchPypi,
  poetry-core,
  poetry-dynamic-versioning,
  arrow,
  hishel,
  httpx,
  importlib-metadata,
  langcodes,
  loguru,
  pydantic,
  pyjwt,
  anysqlite,
}:

buildPythonPackage rec {
  pname = "pytoyoda";
  version = "5.2.9";
  pyproject = true;

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-Ck1B0iMamqPoSvyYBKGqZrBYvU6KXUCp/HqqYRj5jq0=";
  };

  build-system = [
    poetry-core
    poetry-dynamic-versioning
  ];

  dependencies = [
    arrow
    hishel
    httpx
    importlib-metadata
    langcodes
    loguru
    pydantic
    pyjwt

    # ── anysqlite: NOT IN pytoyoda's REQUIREMENTS, AND STILL REQUIRED ─────
    #
    # pytoyoda asks for `hishel[httpx]`, and that EXTRA pulls two more
    # distributions of its own:
    #
    #   anyio>=4.9.0;      extra == "httpx"
    #   anysqlite>=0.0.5;  extra == "httpx"
    #
    # NIX DOES NOT MODEL PYTHON EXTRAS.  nixpkgs' `hishel` propagates its BASE
    # dependencies only — httpx, msgpack, typing-extensions (checked) — so
    # naming `hishel` here silently buys the unextra'd package.  `anyio` was
    # already in the environment via Home Assistant, which is why it is absent
    # from this list; `anysqlite` was not, and nothing in the requirement
    # metadata says so.
    #
    # THE FAILURE WAS LOUD BUT LATE, and `hacs-deps-check` could not have
    # caught it: that checker resolves the manifest's requirement STRINGS, and
    # `pytoyoda==5.2.9` resolved perfectly. The gap is one level down, inside a
    # satisfied requirement's extra. It surfaced only when the config flow
    # actually logged in:
    #
    #   pytoyoda/controller.py:212 in _get_http_client
    #   ImportError: The 'anysqlite' library is required to use the
    #                `AsyncSqliteStorage` integration.
    #
    # which Home Assistant renders in the UI as a bare "Unexpected error".
    #
    # GENERAL SHAPE, worth keeping: a requirement written `pkg[extra]` is a
    # place where the nixpkgs attribute and the PyPI requirement are NOT the
    # same thing, and the extra's dependencies have to be added by hand.
    anysqlite
  ];

  # The sdist ships LICENSE, PKG-INFO, pyproject.toml, README.md and the
  # package directory — no tests directory, so there is nothing to run and
  # `pythonImportsCheck` is the guard, exactly as in bencoding.nix.
  doCheck = false;

  pythonImportsCheck = [ "pytoyoda" ];

  meta = {
    description = "Python client for Toyota Connected Services";
    homepage = "https://github.com/pytoyoda/pytoyoda";
    license = lib.licenses.mit;
  };
}
