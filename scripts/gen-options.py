#!/usr/bin/env python3
"""
Generate Markdown option reference tables from clanarchy NixOS modules.

Uses `nix eval` on the built nixosConfiguration to extract live option
metadata (descriptions, types) from the `clanarchy.*` namespace, then
writes per-topic markdown files to docs/reference/.

Usage (from repo root, inside nix develop):
    python3 scripts/gen-options.py
    # or via the devShell alias:
    gendocs
"""

import json
import subprocess
import sys
import textwrap
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent
OUTDIR = REPO_ROOT / "docs" / "reference"

# Nix expression: walk the clanarchy options attrset and emit serialisable
# {path: {description, type}} records.  Avoids serialising functions/drv
# values by only touching _type=="option" leaves.
NIX_APPLY = textwrap.dedent("""\
    clanarchy:
      let
        isOpt  = v: builtins.isAttrs v && (v._type or "") == "option";
        getDesc = v:
          let d = v.description or ""; in
          if builtins.isString d then d
          else if builtins.isAttrs d then d.text or d._value or ""
          else "";
        walk = prefix: obj:
          if isOpt obj
          then { "${prefix}" = { description = getDesc obj; type = obj.type.description or "unspecified"; }; }
          else if builtins.isAttrs obj
          then builtins.foldl' (a: b: a // b) {}
                 (builtins.attrValues (builtins.mapAttrs (k: v:
                   walk "${prefix}.${k}" v) obj))
          else {};
      in walk "clanarchy" clanarchy
""")

# Which option path prefixes go into which output file.
PAGES: dict[str, dict] = {
    "roles": {
        "title": "Roles",
        "intro": "Machine role modules. Enable exactly the roles that apply to a machine.",
        "prefixes": ["clanarchy.roles."],
    },
    "desktop": {
        "title": "Desktop (Niri)",
        "intro": "Options for the Niri Wayland compositor and its supporting services.",
        "prefixes": ["clanarchy.desktop."],
    },
    "wifi": {
        "title": "WiFi",
        "intro": "Declarative NetworkManager profile generation via clan vars.",
        "prefixes": ["clanarchy.wifi."],
    },
}


def fetch_options() -> dict[str, dict]:
    """Run nix eval and return {option_path: {description, type}}."""
    cmd = [
        "nix", "eval", "--json",
        ".#nixosConfigurations.miralda.options.clanarchy",
        "--apply", NIX_APPLY,
    ]
    try:
        result = subprocess.run(
            cmd,
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError as e:
        print("nix eval failed:", e.stderr[-2000:], file=sys.stderr)
        sys.exit(1)
    return json.loads(result.stdout)


def render_page(title: str, intro: str, opts: dict[str, dict]) -> str:
    lines = [
        f"# {title}",
        "",
        "!!! warning \"Auto-generated\"",
        "    Do not edit by hand — regenerate with `gendocs` in the devShell.",
        "",
        intro,
        "",
        "| Option | Type | Description |",
        "|--------|------|-------------|",
    ]
    for path in sorted(opts):
        meta = opts[path]
        desc = meta.get("description", "").replace("\n", " ").replace("|", "\\|")
        typ  = meta.get("type", "unspecified").replace("|", "\\|")
        lines.append(f"| `{path}` | `{typ}` | {desc} |")
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    print("Fetching options via nix eval …", flush=True)
    all_opts = fetch_options()
    print(f"  {len(all_opts)} options found")

    OUTDIR.mkdir(parents=True, exist_ok=True)

    for slug, cfg in PAGES.items():
        page_opts = {
            path: meta
            for path, meta in all_opts.items()
            if any(path.startswith(p) for p in cfg["prefixes"])
        }
        out = OUTDIR / f"{slug}.md"
        out.write_text(render_page(cfg["title"], cfg["intro"], page_opts))
        print(f"  wrote {out.relative_to(REPO_ROOT)}  ({len(page_opts)} options)")


if __name__ == "__main__":
    main()
