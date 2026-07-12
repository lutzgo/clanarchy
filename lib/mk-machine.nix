# Reusable machine-composition helpers.
#
# Every clan machine in this repo needs the same _module.args injection
# (pkgs-unstable + inputs), the same stylix kmscon workaround, and the
# same 10-item list of shared modules.  Rather than repeating all that
# boilerplate in each `clan.machines.<name>` block, flake.nix imports
# this file once and picks the pieces it needs.
{ inputs }:
let
  unstablePkgs = import inputs.nixpkgs-unstable {
    system = "x86_64-linux";
    config.allowUnfree = true;
  };
in
rec {
  # Injects pkgs-unstable + inputs as module args on every machine.
  # Modules can then take `{ pkgs-unstable, inputs, ... }` in their signature.
  mkModuleArgs = { extraArgs ? { } }: {
    _module.args = {
      pkgs-unstable = unstablePkgs;
      inherit inputs;
    } // extraArgs;
  };

  # Force `nixpkgs.pkgs` to the unstable channel — used by birte, which must
  # follow Jovian-NixOS's nixos-unstable pin.  Overrides clan.nix's
  # pkgsForSystem, which otherwise force-sets nixpkgs to clan-core/nixpkgs.
  #
  # Priority note: clan-core's own `machineModules/overridePkgs.nix` sets
  # `nixpkgs.pkgs = lib.mkForce <clan-pinned pkgs>` on every machine.  Two
  # `mkForce` definitions collide on a unique option, so we need a stronger
  # priority than mkForce (50) — mkOverride 25 wins the tie for birte.
  forceUnstablePkgs = { lib, ... }: {
    nixpkgs.pkgs = lib.mkOverride 25 unstablePkgs;
  };

  # nixpkgs 26.05 restructured services.kmscon; stylix's kmscon target still
  # writes services.kmscon.config which no longer exists.  Bundled into
  # commonHeadful so machines using stylix don't have to think about it.
  stylixKmsconFix = {
    disabledModules = [ "${inputs.stylix}/modules/kmscon/nixos.nix" ];
  };

  # Universal modules — imported by every clan machine, headful or headless.
  commonBase = [
    inputs.impermanence.nixosModules.impermanence
    inputs.home-manager.nixosModules.home-manager
    ../modules/base.nix
    ../modules/zfs-impermanence.nix
    ../modules/vm-variant.nix
    ../modules/locale.nix
    ../modules/networking.nix
    ../modules/hardware/cpu.nix
    ../modules/hardware/gpu.nix
    ../modules/virtualisation.nix
    ../modules/users/admin.nix
  ];

  # Headful (workstation) machines: adds stylix + display + apps.
  # Ernst opts out — it's a headless homelab server.
  commonHeadful = commonBase ++ [
    inputs.stylix.nixosModules.stylix
    stylixKmsconFix
    ../modules/hardware/display.nix
    ../modules/apps
  ];
}
