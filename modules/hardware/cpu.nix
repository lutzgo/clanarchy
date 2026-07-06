{ config, lib, ... }:
let
  cfg = config.clanarchy.hardware;
in
{
  options.clanarchy.hardware = {
    cpu = lib.mkOption {
      type        = lib.types.enum [ "amd" "intel" ];
      default     = "amd";
      description = "CPU/GPU vendor — selects hardware-specific drivers and env vars (ROCm vs Intel media).";
    };
  };

  config = {
    hardware.cpu.amd.updateMicrocode   = cfg.cpu == "amd";
    hardware.cpu.intel.updateMicrocode = cfg.cpu == "intel";
  };
}
