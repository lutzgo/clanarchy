{ pkgs, ... }:
{
  networking.hostName = "ernst";
  # Regenerate if cloning: head -c4 /dev/urandom | od -A none -t x4 | tr -d ' '
  networking.hostId   = "e7c97a1f";
  networking.search   = [ "skynet.lan" ];

  time.timeZone = "Europe/Berlin";

  clanarchy.locale = {
    language        = "en_US";
    keyboard.layout = "us";
  };

  # Server role + admin user assigned via inventory.instances in clan.nix.
  clanarchy.hardware.cpu          = "amd";    # 9950X — wires microcode (cpu.nix)
  clanarchy.hardware.gpu.amd.enable      = true;   # RX 7900 XTX baseline
  clanarchy.hardware.gpu.amd.rocm.enable = true;   # ROCm compute stack
  clanarchy.virtualisation.libvirtd.enable = true; # KVM/QEMU + IOMMU
  clanarchy.users.admin.enable           = true;

  # Bulk-storage diagnostics. smartd pulls in smartmontools.
  environment.systemPackages = [ pkgs.pciutils ];
  services.smartd.enable = true;

  # Swap is defined as a partition on system-a in disko.nix; the kernel picks
  # it up automatically. zramSwap intentionally left off — 256 GB RAM is plenty.
  zramSwap.enable = false;

  system.stateVersion = "26.05";
}
