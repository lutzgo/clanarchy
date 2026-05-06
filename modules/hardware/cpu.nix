{ lib, ... }:
{
  options.clanarchy.hardware = {
    cpu = lib.mkOption {
      type        = lib.types.enum [ "amd" "intel" ];
      default     = "amd";
      description = "CPU/GPU vendor — selects hardware-specific drivers and env vars (ROCm vs Intel media).";
    };
  };
}
