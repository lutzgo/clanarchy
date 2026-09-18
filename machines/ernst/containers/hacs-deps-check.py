#!/usr/bin/env python3
# machines/ernst/containers/hacs-deps-check.py
#
# Body of `hacs-deps-check`.  Not standalone: containers/home-assistant.nix
# wraps it with the Python interpreter and PYTHONPATH that home-assistant.service
# itself runs under, so what this script can import is exactly what Home
# Assistant can import.  Running it against any other interpreter answers a
# different question and the answer would be worthless.
#
# ── WHAT IT IS FOR ──────────────────────────────────────────────────────────
#
#   nixpkgs builds Home Assistant with `--skip-pip`, and the consequence is
#   worse than "pip does not run".  Requirement checking is BEHIND THE SAME
#   FLAG:
#
#       # homeassistant/requirements.py:167
#       if not self.hass.config.skip_pip:
#           await self._async_process_integration(integration, done)
#
#   So Home Assistant does not check a downloaded integration's requirements at
#   all, does not raise RequirementsNotFound, and logs nothing about pip.  It
#   loads the integration, the integration does `import pyfoo`, and the first
#   sign of trouble is an ImportError from inside somebody else's code — which,
#   for an integration that imports lazily, may not appear until a device is
#   first used, days after the download.
#
#   There is no upstream signal to wire an alert to.  This script MANUFACTURES
#   one: it reads the manifests, resolves each requirement against the live
#   environment, and exits non-zero if any cannot be satisfied.  The unit that
#   runs it fails, and ernst's container-unit collector turns that into
#   `clanarchy_container_systemd_unit_failed` within a minute (PR #139).
#
# ── WHAT IT DELIBERATELY DOES NOT CHECK ─────────────────────────────────────
#
#   A manifest's `dependencies` — those name other Home Assistant integrations,
#   not Python distributions, and that failure mode is NOT silent: Home
#   Assistant reports a missing integration dependency loudly and by name.  This
#   script exists only for the failure that has no reporting at all.
#
#   Components symlinked in from the store are skipped rather than checked.
#   Their requirements were proven at BUILD time by
#   buildHomeAssistantComponent's manifestRequirementsCheckHook, which fails the
#   derivation on a miss — so re-checking them here could only ever agree, and
#   a disagreement would mean the store path had been edited underneath us.

from __future__ import annotations

import json
import os
import sys
from importlib.metadata import PackageNotFoundError
from importlib.metadata import version as installed_version

from packaging.requirements import InvalidRequirement, Requirement
from packaging.utils import canonicalize_name


def classify(req_string: str) -> tuple[str, str]:
    """Resolve one PEP 508 requirement against this interpreter.

    Returns (status, detail).  Status is one of "ok", "skip", "missing",
    "version" or "unparseable".
    """
    try:
        req = Requirement(req_string)
    except InvalidRequirement as exc:
        return "unparseable", str(exc)

    # An environment marker that does not apply to this platform means the
    # requirement is genuinely not needed here — `; sys_platform == "darwin"`
    # is satisfied by being on Linux, not by installing anything.
    if req.marker is not None and not req.marker.evaluate():
        return "skip", f"marker not applicable: {req.marker}"

    try:
        have = installed_version(req.name)
    except PackageNotFoundError:
        return "missing", f"{req.name} is not installed"

    # `contains` rather than `in`, for prereleases=True: a Nix-packaged
    # prerelease would otherwise be reported as failing a specifier it
    # actually satisfies.
    if req.specifier and not req.specifier.contains(have, prereleases=True):
        return "version", f"{req.name} {have} does not satisfy {req.specifier}"

    return "ok", f"{req.name} {have}"


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {os.path.basename(sys.argv[0])} <custom_components-dir>",
              file=sys.stderr)
        return 2

    root = sys.argv[1]

    # Not an error.  Home Assistant's own preStart creates this directory, so
    # its absence means the hub has not started yet rather than that anything
    # is wrong — and failing here would alert on a cold boot.
    if not os.path.isdir(root):
        print(f"hacs-deps-check: {root} does not exist yet — nothing to check.")
        return 0

    declared: list[str] = []
    problems: dict[str, list[str]] = {}
    checked: list[tuple[str, str, str, str]] = []

    for entry in sorted(os.scandir(root), key=lambda e: e.name):
        if not entry.is_dir():
            continue

        # Store symlinks are Nix-declared and were verified at build time.
        if entry.is_symlink() and os.path.realpath(entry.path).startswith("/nix/store"):
            declared.append(entry.name)
            continue

        manifest_path = os.path.join(entry.path, "manifest.json")
        if not os.path.exists(manifest_path):
            problems.setdefault(entry.name, []).append(
                "no manifest.json — this is not a Home Assistant integration"
            )
            continue

        try:
            with open(manifest_path, encoding="utf-8") as handle:
                manifest = json.load(handle)
        except (OSError, json.JSONDecodeError) as exc:
            problems.setdefault(entry.name, []).append(f"unreadable manifest.json: {exc}")
            continue

        requirements = manifest.get("requirements") or []
        if not requirements:
            checked.append((entry.name, "ok", "", "no requirements"))
            continue

        for req_string in requirements:
            status, detail = classify(req_string)
            checked.append((entry.name, status, req_string, detail))
            if status in ("missing", "version", "unparseable"):
                problems.setdefault(entry.name, []).append(f"{req_string}: {detail}")

    downloaded = {name for name, *_ in checked} | set(problems)

    print(
        f"hacs-deps-check: {len(declared)} declared in Nix, "
        f"{len(downloaded)} downloaded, {len(problems)} with unmet requirements"
    )
    print()

    for name in declared:
        print(f"  DECLARED  {name}  (verified at build time)")

    for name, status, req_string, detail in checked:
        label = {"ok": "OK", "skip": "N/A"}.get(status, status.upper())
        suffix = f"{req_string} -> {detail}" if req_string else detail
        print(f"  {label:<9} {name}  {suffix}")

    if not problems:
        print()
        print("All downloaded integrations have their requirements available.")
        return 0

    # Canonical names, deduplicated and ordered, so the remediation block can be
    # pasted rather than transcribed.  Only "missing" and "version" contribute:
    # an unparseable requirement has no name to offer.
    wanted = sorted(
        {
            canonicalize_name(Requirement(req_string).name)
            for _, status, req_string, _ in checked
            if status in ("missing", "version")
        }
    )

    print()
    print("Home Assistant will NOT report this.  It is built with --skip-pip, and")
    print("requirement checking sits behind that same flag (requirements.py:167),")
    print("so nothing is validated and nothing is logged about pip.  The failure")
    print("surfaces as an ImportError from inside the integration — possibly not")
    print("until the affected device is first used.")
    print()
    print("Fix, in machines/ernst/containers/home-assistant.nix:")
    print()
    print("    services.home-assistant.extraPackages = ps: [")
    for name in wanted:
        print(f"      ps.{name}")
    print("    ];")
    print()
    print("then redeploy.  The nixpkgs attribute usually matches the PyPI name;")
    print("confirm with `nix search nixpkgs python3Packages.<name>`.  A requirement")
    print("with no nixpkgs packaging is the case where the answer is to package the")
    print("integration under ./pkgs and remove it from HACS.")

    return 1


if __name__ == "__main__":
    sys.exit(main())
