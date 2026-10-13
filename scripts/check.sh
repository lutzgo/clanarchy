#!/usr/bin/env bash
# check.sh — evaluate machine configurations and report one line each.
#
# The single gate before asking for a deploy, and the same script CI runs
# (.github/workflows/check.yml) so "it passed locally" and "it passed in CI"
# mean the same thing.
#
# Usage:
#   ./scripts/check.sh                 # every machine
#   ./scripts/check.sh miralda jens    # just these
#
# Also available as `check` in the devShell.
#
# WHAT A PASS DOES AND DOES NOT PROVE.  It proves the configuration evaluates:
# missing options, renamed attributes, type mismatches, broken wiring, and every
# `assertions` entry.  It does not prove the system works.  Two known cases pass
# here and fail on the machine: an nspawn container name over 12 characters
# (`vb-<name>` hits IFNAMSIZ, fails at container *start*), and a uid colliding
# with a static one in nixpkgs' ids.nix.  See docs/guides/coding-agent-workflow.md.

set -uo pipefail

ALL_MACHINES=(miralda jens biene birte ernst)

if [ "$#" -gt 0 ]; then
  machines=("$@")
else
  machines=("${ALL_MACHINES[@]}")
fi

# jj snapshots the working copy when a jj command runs, not when a file is
# written — and Nix cannot read a path git does not yet track.  Without this a
# brand-new module fails with "not tracked by Git", naming git rather than jj.
if command -v jj >/dev/null 2>&1 && [ -d .jj ]; then
  jj --ignore-working-copy=false status >/dev/null 2>&1 || true
fi

rc=0
for machine in "${machines[@]}"; do
  printf '%-8s ' "$machine"
  if drv=$(nix eval --no-update-lock-file --raw \
             ".#nixosConfigurations.$machine.config.system.build.toplevel.drvPath" \
             2>/tmp/check-$machine.err); then
    printf 'OK    %s\n' "$drv"
  else
    printf 'FAILED\n'
    sed 's/^/           /' "/tmp/check-$machine.err" >&2
    rc=1
  fi
  rm -f "/tmp/check-$machine.err"
done

# Every machine is evaluated before failing, so one broken machine does not
# hide breakage in the other four.
exit "$rc"
