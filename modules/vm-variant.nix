{ lib, ... }:
{
  # `virtualisation.vmVariant` is a NixOS option: any config set here only
  # applies to the QEMU VM output (`config.system.build.vm`), never to the
  # real deploy. `nixos-rebuild build-vm --flake .#<machine>` produces a
  # runnable `./result/bin/run-<host>-vm` that boots this variant.
  #
  # Purpose: let a reviewer boot a PR branch in QEMU without wiping disks,
  # without needing a real YubiKey, and without depending on ZFS pools or
  # impermanence rollback semantics that only make sense on bare metal.
  virtualisation.vmVariant = {
    # Give the VM a plain rootfs on /dev/vda; the qemu-vm NixOS module
    # provisions the disk image automatically. disko's fileSystems + swap
    # entries reference /dev/disk/by-id/... which does not exist inside
    # the VM, so we disable disko's config emission here.
    disko.enableConfig = lib.mkForce false;

    virtualisation = {
      memorySize = 4096;
      cores      = 4;
      diskSize   = 8192;
      graphics   = true;
      qemu.options = [ "-vga virtio" ];
    };

    # No ZFS pool in the VM — drop the zpool import and the blank-rollback
    # unit from modules/zfs-impermanence.nix so stage 1 doesn't wait forever
    # on a `zroot` that will never appear.
    boot.supportedFilesystems         = lib.mkForce [ "ext4" "vfat" ];
    boot.zfs.forceImportRoot          = lib.mkForce false;
    boot.initrd.systemd.services.rollback.enable = lib.mkForce false;

    # biene sets boot.resumeDevice to a /dev/disk/by-partlabel/... path for
    # hybrid-sleep; in the VM that partition doesn't exist and systemd
    # sits in a ~90 s timeout waiting on it. Clear swapDevices too as a
    # safety net in case disko leaks any residuals past enableConfig=false.
    boot.resumeDevice = lib.mkForce "";
    swapDevices       = lib.mkForce [];

    # Impermanence's `environment.persistence` bind-mounts /persist/* onto
    # the live root. Without a real /persist dataset this fails at
    # activation — clear the persist declarations for the VM.
    environment.persistence = lib.mkForce {};

    # Convenience: single-user autologin so the reviewer lands on a shell
    # (or the compositor's greeter) without hunting for a password.
    services.getty.autologinUser = lib.mkForce "root";
    users.users.root.hashedPassword = lib.mkForce "";

    # Syncthing wants to write to a persisted home dir; nothing to sync in
    # a throwaway VM. Turn it off so it doesn't spam the boot log.
    services.syncthing.enable = lib.mkForce false;
  };
}
