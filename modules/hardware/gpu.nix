# modules/hardware/gpu.nix — shared GPU options
#
# Declares vendor-agnostic toggles so machines opt in without spelling out
# package lists or driver wiring:
#
#   clanarchy.hardware.gpu.amd.enable        — amdgpu + mesa + radeonsi Rusticl
#   clanarchy.hardware.gpu.amd.rocm.enable   — full ROCm stack (HIP, OpenCL, rocminfo)
#   clanarchy.hardware.gpu.intel.enable      — intel-media-driver (i965/iHD)
{ config, lib, pkgs, ... }:
let
  cfg = config.clanarchy.hardware.gpu;
in
{
  options.clanarchy.hardware.gpu = {
    amd.enable = lib.mkEnableOption "AMD GPU baseline (amdgpu kernel module + mesa + Rusticl)";
    amd.rocm.enable = lib.mkEnableOption "ROCm compute stack (HIP runtime, OpenCL ICD, rocminfo)";
    intel.enable = lib.mkEnableOption "Intel GPU media driver (intel-media-driver)";
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.amd.enable {
      boot.initrd.kernelModules = [ "amdgpu" ];
      hardware.graphics.enable = true;
      hardware.graphics.extraPackages = with pkgs; [
        mesa
        rocmPackages.clr.icd
      ];
      environment.variables.RUSTICL_ENABLE = "radeonsi";
      environment.systemPackages = [ pkgs.clinfo ];
    })

    (lib.mkIf cfg.amd.rocm.enable {
      hardware.graphics.extraPackages = with pkgs; [
        rocmPackages.clr
      ];
      environment.systemPackages = with pkgs; [
        rocmPackages.rocminfo
      ];
      # Many ROCm utilities hard-code /opt/rocm/hip; mirror the local-ai pattern.
      systemd.tmpfiles.rules = [
        "L+ /opt/rocm/hip - - - - ${pkgs.rocmPackages.clr}"
      ];
    })

    (lib.mkIf cfg.intel.enable {
      hardware.graphics.enable = true;
      hardware.graphics.extraPackages = with pkgs; [
        intel-media-driver
      ];
    })
  ];
}
