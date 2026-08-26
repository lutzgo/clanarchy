# machines/ernst/containers/pkgs/scraparr.nix
#
# Scraparr — M13.  A Prometheus exporter for the *arr suite.  Not in nixpkgs
# (surveyed against ernst's own pin on the session date, 2026-08-26: no
# `scraparr` attribute — the closest match is the unrelated `scraper` — and no
# module).
#
# ── THE EASIEST DERIVATION IN THIS DIRECTORY, AND WORTH SAYING WHY ───────────
#
#   umlautadaptarr.nix and cleanuparr.nix unpack prebuilt .NET publishes and
#   fight autoPatchelf; janitorr.nix builds a Spring Boot application from
#   source with a Gradle dependency lock.  This one is a plain setuptools
#   Python package whose six runtime dependencies — prometheus_client, requests,
#   werkzeug, python-dateutil, pyyaml, python-dotenv — are ALL already in
#   nixpkgs.  There is nothing to vendor, nothing to patch and nothing to pin
#   beyond the source tag.
#
#   That asymmetry is the reason M13 could absorb Scraparr and Jellyseerr even
#   if Janitorr's build had failed: they share a milestone, not a risk.
#
# ── UPSTREAM'S `version` IS NOT THE RELEASE VERSION ──────────────────────────
#
#   pyproject.toml says `version = "1.0.0"` and has said so since the project
#   was renamed; the actual release is the git tag (v3.1.0).  `version` below
#   follows the TAG, because that is the number a human compares against
#   upstream's releases page, and pyproject's is not maintained.
#
#   Nothing reads the pyproject version at run time, so overriding it is
#   cosmetic — but a derivation that reports 1.0.0 while tracking 3.1.0 is a
#   trap for whoever next asks "are we current?".
#
# ── IT NEEDS NO CONFIG FILE, AND THAT IS A DELIBERATE DEPLOYMENT CHOICE ──────
#
#   Scraparr looks for /app/src/scraparr/config/config.yaml (and a deprecated
#   second path), loads it through `load_yaml_config_safe`, and MERGES
#   environment variables over the top.  `_safe` means a missing file yields
#   `{}` rather than an error — verified by reading scraparr.py at v3.1.0, not
#   assumed from the name.
#
#   So the unit in containers/arr.nix ships NO YAML at all and configures the
#   exporter entirely from an EnvironmentFile.  The reason is the API keys: see
#   the scraparr block in that file.
{
  lib,
  python3Packages,
  fetchFromGitHub,
}:

python3Packages.buildPythonApplication rec {
  pname = "scraparr";
  version = "3.1.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "thecfu";
    repo = "scraparr";
    tag = "v${version}";
    hash = "sha256-3VtZJNwjUfOw/nlA4J5NG/RdakYp0Hk84rmY286isWg=";
  };

  build-system = [ python3Packages.setuptools ];

  dependencies = with python3Packages; [
    prometheus-client
    requests
    werkzeug
    python-dateutil
    pyyaml
    python-dotenv
  ];

  # The test suite is not shipped in a way that runs without the repo's uv
  # environment, and this is an exporter whose correctness is observable from
  # its own /metrics output — which the PR test plan checks directly.
  doCheck = false;

  pythonImportsCheck = [ "scraparr" ];

  meta = {
    description = "Prometheus exporter for the *arr suite";
    homepage = "https://github.com/thecfu/scraparr";
    license = lib.licenses.gpl3Only;
    mainProgram = "scraparr";
  };
}
