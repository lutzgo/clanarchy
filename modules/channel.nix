# Per-machine nixpkgs channel selection.
#
# Every machine in this flake normally builds against clan-core's pinned
# nixpkgs (currently 26.05).  Some machines have to run against
# nixpkgs-unstable instead — birte, for example, follows Jovian-NixOS
# which only supports unstable, and Noctalia/Quickshell need
# unstable-flavoured pkgs too.
#
# Setting `clanarchy.channel = "unstable"` swaps this machine's `pkgs`
# instance to the pkgs-unstable one that `lib/mk-machine.nix` injects
# as a module arg.  Leaving it at the default (`"stable"`) keeps
# clan-core's pin.
#
# The `pkgs-unstable` module arg is provided by
# `lib.mkMachine.mkModuleArgs`; every machine in this flake gets it,
# so the module below can rely on it being present.
#
# ── Priority note ─────────────────────────────────────────────────────
# clan-core's own `machineModules/overridePkgs.nix` sets
# `nixpkgs.pkgs = lib.mkForce <clan-pinned pkgs>` on every machine.
# Two `mkForce` definitions collide on a unique option, so we need a
# stronger priority than mkForce (50) — `mkOverride 25` wins the tie.
{ config, lib, pkgs-unstable, ... }:
{
  options.clanarchy.channel = lib.mkOption {
    type        = lib.types.enum [ "stable" "unstable" ];
    default     = "stable";
    example     = "unstable";
    description = ''
      Which nixpkgs channel this machine builds against.
      - `stable`   — clan-core's pinned nixpkgs (the flake default).
      - `unstable` — nixpkgs-unstable (this repo's `nixpkgs-unstable`
        input; used by birte for Jovian compatibility).
    '';
  };

  config = lib.mkIf (config.clanarchy.channel == "unstable") {
    nixpkgs.pkgs = lib.mkOverride 25 pkgs-unstable;
  };
}
