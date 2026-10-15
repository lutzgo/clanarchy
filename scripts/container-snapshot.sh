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
name="${2:?usage: container-snapshot.sh <machine> <container> [flake-ref]}"
# Optional third argument: the flake to read, so a baseline can be taken from
# another revision (a jj workspace at `main`) with the CURRENT script.
flake="${3:-.}"

# `ev` is called inside pipelines and command substitutions, where a shell
# variable set in the subshell is lost — so the flag is a FILE.
failmark=$(mktemp)
trap 'rm -f "$failmark"' EXIT

# A PROBE THAT CANNOT WORK MUST SAY SO. The first version of this printed
# `null` on any eval error, and `null` is also a legitimate value — so the
# host-networkd and in-container-networking sections read `null` for all five
# migrated containers and compared nothing against nothing. Both diffed clean
# while paperless shipped a DUPLICATE [BridgeVLAN]. A failed probe now prints
# a marker and makes the whole snapshot exit non-zero.
ev() {
  local attr="$1"; shift
  local out
  if out=$(nix eval --no-update-lock-file --json \
             "${flake}#nixosConfigurations.${machine}.config.${attr}" "$@" 2>/dev/null); then
    printf '%s' "$out"
  else
    echo "!! EVAL FAILED: ${attr}" >&2
    printf '"!! EVAL FAILED"'
    echo 1 >> "$failmark"
  fi
}

# Forcing a whole `systemd.network.networks.<n>` submodule throws: networkd
# carries `mkRemovedOptionModule` entries (`dhcpConfig`) that fire when the
# attrset is evaluated wholesale, not when the removed option is used. So the
# fields are named one at a time.
netFields() {
  local scope="$1" net="$2" f
  for f in matchConfig networkConfig bridgeVLANs linkConfig address routes \
           dhcpV4Config ipv6AcceptRAConfig; do
    local v
    v=$(nix eval --no-update-lock-file --json \
          "${flake}#nixosConfigurations.${machine}.config.${scope}systemd.network.networks.\"${net}\".${f}" \
          2>/dev/null) || continue
    [ "$v" = "null" ] || [ "$v" = "{}" ] || [ "$v" = "[]" ] || \
      echo "    ${f} = $(printf '%s' "$v" | jq -cS .)"
  done
}

# THE TWO TIERS ARE DIFFERENT SHAPES, so the probes differ. An nspawn service
# is `containers.<name>`; a podman one is a netns unit, a dhcp unit and one or
# more `oci-containers` entries with no `containers.<name>` at all. Detected
# rather than passed in, so the caller does not have to know.
if ev "containers" --apply 'cs: builtins.hasAttr "'"$name"'" cs' | grep -q true; then
  tier=nspawn
else
  tier=podman
fi
echo "### tier: ${tier}"

echo
echo "### container attributes"
if [ "$tier" = nspawn ]; then
  # The service's own config is excluded: it is the half a migration does not
  # touch, and including it buries the half that matters in thousands of lines.
  nix eval --no-update-lock-file --json \
    "${flake}#nixosConfigurations.${machine}.config.containers.${name}" \
    --apply 'c: builtins.removeAttrs c [ "config" "path" "pkgs" "specialArgs" "nixpkgs" ]' 2>/dev/null \
    | jq -S . 2>/dev/null || echo "(container attributes unavailable)"
else
  # Every image in this namespace, and the options that place it there: the
  # netns path, the DNS, and `--user`. A second image sharing the namespace is
  # the whole reason romm's database is unaddressable, so the set matters.
  ev "virtualisation.oci-containers.containers" \
    --apply 'cs: builtins.listToAttrs (map (n: { name = n; value = cs.${n}; })
               (builtins.filter (n: n == "'"$name"'" || builtins.match "'"$name"'-.*" n != null)
                 (builtins.attrNames cs)))' \
    | jq -S 'with_entries(.value |= { image, user, extraOptions, environmentFiles, volumes, ports, dependsOn })' 2>/dev/null
fi

echo
echo "### host units touching it"
# ABSENT IS NOT THE SAME AS UNEVALUABLE. A container with no secrets has no
# `<name>-secrets` unit, and asking for a missing attribute's `.text` is an
# eval error — indistinguishable from a real failure unless existence is
# tested first. jellyfin reported two phantom probe failures that way.
if [ "$tier" = nspawn ]; then
  units="${name}-dirs ${name}-secrets container@${name}"
else
  # The podman tier's skeleton IS these units: the namespace, the DHCP client
  # inside it, the container itself and its optional health poll.
  units="${name}-dirs ${name}-secrets ${name}-netns ${name}-dhcp podman-${name} ${name}-healthy"
fi
for u in $units; do
  echo "--- ${u}.service"
  if ev "systemd.units" --apply 'us: builtins.hasAttr "'"${u}.service"'" us' | grep -q true; then
    ev "systemd.units.\"${u}.service\".text" | jq -r . 2>/dev/null
  else
    echo "(absent)"
  fi
done

echo
echo "### host networkd"
# Every host-side network naming this container: the primary `vb-<name>` leg
# plus any VLAN leg, which is a separate `60-*` file.
#
# A VLAN leg's network is named after the VETH, not the container (`60-iot1`
# is mass's), so the set is derived from the container's own `extraVeths`
# rather than by matching the container's name.
# The podman tier has no `extraVeths` — its one leg is `vb-<name>`, created by
# the netns unit and enslaved by networkd.
if [ "$tier" = nspawn ]; then
  legs=$(ev "containers.${name}.extraVeths" --apply 'builtins.attrNames' \
         | jq -r '.[]? // empty')
else
  legs=""
fi
for iface in "vb-${name}" $legs; do
  net="60-${iface}"
  if ev "systemd.network.networks" --apply 'ns: builtins.hasAttr "'"$net"'" ns' \
     | grep -q true; then
    echo "--- $net"
    netFields "" "$net"
  else
    echo "--- $net (absent)"
  fi
done

echo
if [ "$tier" = nspawn ]; then
  echo "### in-container networking"
  for net in $(ev "containers.${name}.config.systemd.network.networks" \
                 --apply 'builtins.attrNames' 2>/dev/null | jq -r '.[]? // empty' | sort); do
    echo "--- $net"
    netFields "containers.${name}.config." "$net"
  done

  echo
  echo "### in-container firewall and ids"
  for a in \
    "containers.${name}.config.networking.firewall.extraCommands" \
    "containers.${name}.config.networking.firewall.allowedTCPPorts" \
    "containers.${name}.config.systemd.network.wait-online.timeout" \
    "containers.${name}.config.services.resolved.enable" \
    "containers.${name}.config.system.stateVersion"
  do
    echo "--- $a"
    ev "$a" | jq -S . 2>/dev/null
  done
else
  # The podman tier has no in-container NixOS config to probe — the firewall
  # lives in the netns unit's script, which the unit texts above already carry
  # verbatim. What is worth naming separately is the tier-wide switch, because
  # two different backends on one host is the failure storyteller.nix records.
  echo "### podman tier"
  for a in \
    "virtualisation.oci-containers.backend" \
    "virtualisation.podman.enable" \
    "virtualisation.containers.enable"
  do
    echo "--- $a"
    ev "$a" | jq -S . 2>/dev/null
  done
fi

# `ev` runs inside `$(…)` in places, where a flag set in the subshell is lost,
# so the markers in the output are the reliable signal and this is the backstop
# for the direct calls.
if [ -s "$failmark" ]; then
  echo >&2 "container-snapshot: at least one probe could not be evaluated."
  exit 1
fi
