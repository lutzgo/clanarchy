# Reusable machine-composition helpers.
#
# Every clan machine in this repo needs the same `inputs` module arg and the
# same list of shared modules.  Rather than repeating that boilerplate in each
# `clan.machines.<name>` block, flake.nix imports this file once and picks the
# pieces it needs.
#
# This file used to build a SECOND pkgs instance from `nixpkgs-unstable` and
# inject it as `pkgs-unstable`, because birte ran unstable packages under
# 26.05 modules.  That whole arrangement is gone: clan-core tracks `main`, so
# `inputs.nixpkgs` IS unstable and every machine gets one coherent tree.  With
# it went the `stylixKmsconFix` disabledModules entry and the
# `permittedInsecurePackages` that had to live inside the pkgs instance
# because `nixpkgs.config` cannot be set once `nixpkgs.pkgs` is supplied
# externally.
{inputs}: rec {
  # Injects `inputs` as a module arg on every machine, so modules can take
  # `{ inputs, ... }` in their signature.
  mkModuleArgs = {extraArgs ? {}}: {
    _module.args = {inherit inputs;} // extraArgs;
  };

  # Universal modules — imported by every clan machine, headful or headless.
  commonBase = [
    inputs.impermanence.nixosModules.impermanence
    inputs.home-manager.nixosModules.home-manager
    ../modules/base.nix
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
    # Declarative containers for both tiers, plus the checks over whatever a
    # machine declares. Fleet-wide and INERT until a machine declares one —
    # the same shape as hardware/convertible.nix. Host-agnostic by
    # construction: no bridge, VLAN or domain is named in them.
    ../modules/containers/nspawn.nix
    ../modules/containers/podman-netns.nix
    ../modules/containers/assertions.nix
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
  commonHeadful =
    commonBase
    ++ [
      inputs.stylix.nixosModules.stylix
      ../modules/hardware/display.nix
      # One-passphrase boot. Declares `clanarchy.singlePasswordBoot` and
      # guards its body on it, so importing it headful-wide is inert until a
      # machine opts in — and it ASSERTS on btrfs, so it cannot be turned on
      # for a ZFS machine the way it was in #372.
      ../modules/desktop/single-password-boot.nix
      ../modules/networking/skynet-dns-nm.nix
      ../modules/apps
      # M22. The darktable end of the photo pipeline: a watched export folder
      # pushed to Immich on ernst. Imported here and INERT until enabled, the
      # same shape as hardware/convertible.nix in commonBase — it declares
      # `clanarchy.immich.upload` and does nothing at all until a machine turns
      # it on. Consumers: miralda, jens.
      ../modules/immich-upload.nix
    ];
}
