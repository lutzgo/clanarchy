#!/usr/bin/env bash
# container-snapshot.sh — dump everything a container's declaration produces,
# so a migration can be diffed instead of reviewed.
#
# Usage:
#   ./scripts/container-snapshot.sh ernst miniflux > before-miniflux.txt
#   …migrate…
#   ./scripts/container-snapshot.sh ernst miniflux > after-miniflux.txt
#   diff -u before-miniflux.txt after-miniflux.txt
#
# WHY THIS AND NOT THE DRV HASH. A migration legitimately changes the
# derivation — generated scripts differ in whitespace from hand-written ones —
# so drv equality is the wrong gate here. What must NOT change is the rendered
# units, the container's own attributes, and the ordering between them. A
# missing entry in the after/requires/before/requiredBy quadruple is invisible
# at eval and produces a container that will not start.
set -uo pipefail

machine="${1:?usage: container-snapshot.sh <machine> <container>}"
name="${2:?usage: container-snapshot.sh <machine> <container>}"

ev() {
  nix eval --no-update-lock-file --json \
    ".#nixosConfigurations.${machine}.config.$1" 2>/dev/null || echo 'null'
}

echo "### container attributes"
# The service's own config is excluded: it is the half a migration does not
# touch, and including it buries the half that matters in thousands of lines.
nix eval --no-update-lock-file --json \
  ".#nixosConfigurations.${machine}.config.containers.${name}" \
  --apply 'c: builtins.removeAttrs c [ "config" "path" "pkgs" "specialArgs" "nixpkgs" ]' 2>/dev/null \
  | jq -S . 2>/dev/null || echo "(container attributes unavailable)"

echo
echo "### host units touching it"
for u in "${name}-dirs" "${name}-secrets" "container@${name}"; do
  echo "--- ${u}.service"
  ev "systemd.units.\"${u}.service\".text" | jq -r '. // "(absent)"' 2>/dev/null
done

echo
echo "### host networkd"
ev "systemd.network.networks.\"60-vb-${name}\"" | jq -S . 2>/dev/null

echo
echo "### in-container networking, firewall and ids"
for a in \
  "containers.${name}.config.systemd.network.networks" \
  "containers.${name}.config.networking.firewall.extraCommands" \
  "containers.${name}.config.networking.firewall.allowedTCPPorts" \
  "containers.${name}.config.systemd.network.wait-online.timeout" \
  "containers.${name}.config.services.resolved.enable" \
  "containers.${name}.config.system.stateVersion"
do
  echo "--- $a"
  ev "$a" | jq -S . 2>/dev/null
done
