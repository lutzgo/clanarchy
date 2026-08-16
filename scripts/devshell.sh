#!/usr/bin/env bash
# shellcheck shell=bash
#
# Developer shell helpers for clanarchy.
#
# Sourced from the devShell's shellHook in flake.nix. It lives here rather than
# inline in flake.nix so shellcheck can actually lint it — inside a Nix string
# it was invisible to every tool, and `''${...}` escaping made it awkward to
# read and edit.
#
# Everything here is defined as a shell function and exported, so it behaves
# exactly as before from the caller's point of view.

# age/SOPS identity — points to the keys.txt that contains both the
# regular age key and the AGE-PLUGIN-YUBIKEY-1... identity stub.
# Required for `clan machines update` and any direct `sops` invocation
# that needs to decrypt secrets encrypted to the YubiKey recipient.
# The file persists across reboots via impermanence (.config is listed
# in the persisted paths).  First-time setup on a new machine:
#   age-plugin-yubikey --identity >> ~/.config/sops/age/keys.txt
export SOPS_AGE_KEY_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/sops/age/keys.txt"

# Update gpg-agent's pinentry TTY to this shell's TTY.
# gpg-agent caches the TTY from the session where it first started;
# entering a new shell (nix develop, new terminal) changes the TTY
# but the agent doesn't know — pinentry then tries the old TTY, fails
# silently, and the agent refuses card-backed SSH signing operations.
echo UPDATESTARTUPTTY | gpg-connect-agent >/dev/null 2>&1 || true

# ── Deploy ──────────────────────────────────────────────────────────────────
#
# Fast deploy: builds locally, pushes result, switches remotely.
# Avoids clan's full inventory evaluation — use for quick iteration.
#
# Use "clan machines update <machine>" when you need secrets/vars to be
# re-evaluated (e.g. after changing sops or clan vars config).
#
# Usage: deploy <machine> [boot|switch] [extra nixos-rebuild args...]
#
# The default target host per machine is listed below and can be overridden
# per invocation with <MACHINE>_HOST, e.g.
#   BIENE_HOST=192.168.1.50 deploy biene boot
deploy() {
  local machine=${1?usage: deploy <machine> [boot|switch] [extra args...]}
  local action=${2:-switch}
  local host

  case "$machine" in
    miralda) host=${MIRALDA_HOST:-miralda.goclan.org} ;;
    biene)   host=${BIENE_HOST:-biene.local} ;;
    birte)   host=${BIRTE_HOST:-birte.local} ;;
    ernst)   host=${ERNST_HOST:-ernst.skynet.lan} ;;
    *)
      echo "deploy: unknown machine '$machine' (expected: miralda, biene, birte, ernst)" >&2
      return 2
      ;;
  esac

  # --no-reexec (never --fast); never --build-host localhost. See CLAUDE.md.
  nixos-rebuild "$action" \
    --flake ".#$machine" \
    --target-host "root@$host" \
    --no-reexec \
    -j auto \
    "${@:3}"
}
export -f deploy

# Per-machine aliases, kept so existing muscle memory and the docs keep
# working. `deploy` without arguments used to mean miralda; it now requires an
# explicit machine, which is why deploy-miralda exists as well.
deploy-miralda() { deploy miralda "$@"; }
deploy-biene()   { deploy biene   "$@"; }
deploy-birte()   { deploy birte   "$@"; }
deploy-ernst()   { deploy ernst   "$@"; }
export -f deploy-miralda deploy-biene deploy-birte deploy-ernst

# ── VM testing ──────────────────────────────────────────────────────────────

# Check out a PR branch and boot it in QEMU. Rebuild the VM (which
# applies the machine's virtualisation.vmVariant overrides in
# modules/vm-variant.nix) and launch it. The reviewer's working
# branch is left on the PR HEAD until they gh pr checkout out.
#
# Usage: test-pr <PR#> [machine]      machine defaults to biene
test-pr() {
  local pr=${1?usage: test-pr <PR#> [machine]}
  local machine=${2:-biene}
  gh pr checkout "$pr" || return 1
  nixos-rebuild build-vm --flake ".#$machine" --no-reexec -j auto || return 1
  exec ./result/bin/run-"$machine"-vm
}
export -f test-pr

# Same as test-pr, but for an already-checked-out branch (or main).
# Usage: test-vm [machine]            machine defaults to biene
test-vm() {
  local machine=${1:-biene}
  nixos-rebuild build-vm --flake ".#$machine" --no-reexec -j auto || return 1
  exec ./result/bin/run-"$machine"-vm
}
export -f test-vm

# ── Git ─────────────────────────────────────────────────────────────────────

# Push using gh's credentials rather than an ambient git identity.
# This exists because ~/.config/git is impermanence-backed: it is
# persisted (zroot/persist), but nothing here should assume a
# hand-configured credential store is present on a fresh rollback.
#
# It used to splice $(gh auth token) straight into the remote URL.
# That leaked the token two ways: into the process arguments, where
# any local user could read it out of `ps`, and into git's own error
# output, which echoes the remote URL on failure — so a failed push
# could print the token to the terminal or a log.
#
# The fix is gh's git credential helper: git asks gh for the
# credential over the credential protocol on stdin, so the token
# never appears in argv or in a URL.
#
# Note `gh auth setup-git` is NOT used, and cannot be: it writes
# `git config --global`, but ~/.config/git/config is a home-manager
# symlink into /nix/store, so it fails with "could not lock config
# file: Read-only file system". That read-only config is also why
# this helper exists at all.
#
# It is also unnecessary — `programs.gh.enable` in
# modules/users/lgo.nix already declares the helper for github.com.
# Passing it with `-c` as well makes the function self-contained on
# a machine where that HM integration is not active, without
# mutating any config.
#
# Usage: push [remote] [branch]
push() {
  local remote=${1:-origin}
  local branch=${2:-main}
  git -c "credential.https://github.com.helper=!gh auth git-credential" \
    push "$remote" "$branch"
}
export -f push

# ── Docs ────────────────────────────────────────────────────────────────────

# Generate option reference docs from live NixOS config, then serve locally.
# Usage: gendocs      — write docs/reference/*.md
#        docs serve   — live-reload preview at http://localhost:8000
gendocs() {
  python3 scripts/gen-options.py
}
export -f gendocs

# Local docs preview. This runs *mkdocs*, not properdocs.
#
# CI (.github/workflows/docs.yml) publishes with properdocs, which
# is a different engine. Standardising both sides on properdocs is
# the goal, but it is not packaged in nixpkgs — absent from both
# top-level and python3Packages as of 26.05 — and pip-installing
# into the devShell would defeat the point of having one.
#
# So the wrapper is named after what it actually runs, rather than
# pretending to be the CI toolchain. It was previously called
# `properdocs`, which read as though local and CI matched when they
# did not. mkdocs-material renders the same site for preview
# purposes; treat CI's output as authoritative.
#
# Lift this once properdocs lands in nixpkgs: add it to `packages`
# in flake.nix and drop this wrapper entirely.
docs() {
  mkdocs "$@"
}
export -f docs
