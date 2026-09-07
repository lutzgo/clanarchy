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
    # Same overlays as the stable instance built by `pkgsForSystem` in
    # clan.nix.  A machine on `clanarchy.channel = "unstable"` takes its
    # whole `pkgs` from here, so leaving them off means package overrides
    # silently apply to some machines and not others.
    overlays = [ (import ./overlays.nix) ];
    config = {
      allowUnfree = true;
      # birte pulls pnpm-9.15.9 transitively (Jovian / KDE tooling).  Since
      # birte uses `nixpkgs.pkgs = unstablePkgs` (via
      # `clanarchy.channel = "unstable"` — see modules/channel.nix),
      # `nixpkgs.config` cannot be layered on at the NixOS level --
      # allowed insecure packages must live inside the pkgs instance.
      permittedInsecurePackages = [ "pnpm-9.15.9" ];
    };
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
    ../modules/channel.nix
    # Root filesystem strategy: rootfs.nix declares `clanarchy.rootfs` and
    # holds the shared persist bits; the two backends below each guard
    # their own body on it, so importing both is inert for the one not
    # selected.
    ../modules/rootfs.nix
    ../modules/zfs-impermanence.nix
    ../modules/btrfs-impermanence.nix
    ../modules/vm-variant.nix
    ../modules/locale.nix
    ../modules/networking/mdns.nix
    ../modules/networking/resolved.nix
    ../modules/networking/initrd-ssh.nix
    # Pins every clan machine's host key on every address it answers on,
    # generated from committed vars. Fleet-wide because any machine may be the
    # one running `clan machines update`, and the address clan picks depends on
    # which path answers first.
    ../modules/networking/clan-known-hosts.nix
    ../modules/hardware/cpu.nix
    ../modules/hardware/gpu.nix
    # ZSA keyboards (Voyager et al). Declares `clanarchy.hardware.zsa` and
    # guards its own body on it, so importing it fleet-wide is inert on the
    # machines that never plug one in.
    ../modules/hardware/zsa.nix
    # Convertible / 2-in-1 hardware (jens). Same pattern as zsa.nix above:
    # declares `clanarchy.hardware.convertible` and guards its body on it, so
    # it is inert on the clamshells. It has to be fleet-wide rather than
    # jens-only because modules/desktop/niri-hm.nix reads the option to decide
    # whether to bind the on-screen keyboard, and that module is shared.
    ../modules/hardware/convertible.nix
    ../modules/virtualisation.nix
    # Distributed Nix builds. Declares `clanarchy.remoteBuilder` with both
    # roles off by default, so importing it fleet-wide is inert until a
    # machine opts into client or server.
    ../modules/nix-remote-builder.nix
    ../modules/users/admin.nix
    ../modules/observability/zfs-ntfy.nix
  ];

  # Headful (workstation) machines: adds stylix + display + apps + NM DNS
  # routing (NM is only enabled on the NM-managed machines — see wifi service).
  # Ernst opts out — headless homelab server, no stylix / no apps / networkd.
  commonHeadful = commonBase ++ [
    inputs.stylix.nixosModules.stylix
    stylixKmsconFix
    ../modules/hardware/display.nix
    ../modules/networking/skynet-dns-nm.nix
    ../modules/apps
  ];
}
