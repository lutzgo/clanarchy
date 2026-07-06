# modules/virtualisation.nix — KVM/QEMU + libvirtd toggle
#
#   clanarchy.virtualisation.libvirtd.enable
#       Turn on libvirtd, persist /var/lib/libvirt across ZFS rollback, and
#       set the IOMMU kernel parameters appropriate for the configured CPU
#       vendor (clanarchy.hardware.cpu).  IOMMU is required for PCI device
#       passthrough and harmless on host-only VMs.
{ config, lib, ... }:
let
  cfg = config.clanarchy.virtualisation;
  cpu = config.clanarchy.hardware.cpu;
in
{
  options.clanarchy.virtualisation = {
    libvirtd.enable =
      lib.mkEnableOption "libvirtd (KVM/QEMU) + IOMMU kernel params";
  };

  config = lib.mkIf cfg.libvirtd.enable {
    virtualisation.libvirtd.enable = true;

    boot.kernelParams =
      (if cpu == "amd"
       then [ "amd_iommu=on" ]
       else [ "intel_iommu=on" ])
      ++ [ "iommu=pt" ];

    environment.persistence."/persist".directories = [
      "/var/lib/libvirt"
    ];
  };
}
