{ config, lib, pkgs, ... }:
{
  options.clanarchy.roles = {
    cpu = lib.mkOption {
      type        = lib.types.enum [ "amd" "intel" ];
      default     = "amd";
      description = "CPU/GPU vendor — selects hardware-specific drivers and env vars (ROCm vs Intel media).";
    };
    laptop = {
      enable           = lib.mkEnableOption "laptop role";
      framework.enable = lib.mkEnableOption "Framework-specific hardware (fprintd, fwupd, backpack-wake udev rule)";
    };
  };

  config = lib.mkIf config.clanarchy.roles.laptop.enable {

    # Activate Niri desktop by default on laptops
    clanarchy.desktop.niri.enable = lib.mkDefault true;
    clanarchy.desktop.niri.fprintd.enable =
      lib.mkDefault config.clanarchy.roles.laptop.framework.enable;
    clanarchy.desktop.niri.input.pointerSpeed = lib.mkDefault 0.4;

    # GPU / hardware graphics
    hardware.graphics.enable = true;
    hardware.graphics.extraPackages =
      lib.optionals (config.clanarchy.roles.cpu == "amd") (with pkgs; [
        mesa                    # Rusticl OpenCL via radeonsi driver
        rocmPackages.clr.icd    # ROCm ICD — optional for iGPU testing
      ]) ++
      lib.optionals (config.clanarchy.roles.cpu == "intel") (with pkgs; [
        intel-media-driver
      ]);

    environment.variables =
      lib.mkIf (config.clanarchy.roles.cpu == "amd") {
        RUSTICL_ENABLE = "radeonsi";
      };

    environment.systemPackages =
      lib.optionals (config.clanarchy.roles.cpu == "amd") [ pkgs.clinfo ];

    # Framework-specific hardware — only assert opinions when framework.enable is true.
    # Leaving fwupd unset when framework is off lets desktop modules (e.g. plasma6)
    # set their own mkDefault without a priority conflict.
    services.fprintd.enable = lib.mkIf config.clanarchy.roles.laptop.framework.enable (lib.mkDefault true);
    services.fwupd.enable   = lib.mkIf config.clanarchy.roles.laptop.framework.enable (lib.mkDefault true);

    # Prevent backpack-wake: disable LID ACPI device as a kernel wakeup source.
    # This stops the lid sensor from generating spurious wakeups when bag pressure
    # flexes the chassis. The input event path (power-switch tag) is intentionally
    # preserved so logind can still see lid-close events and trigger HandleLidSwitch.
    # Trade-off: opening the lid will not wake from suspend by itself; use the power button.
    services.udev.extraRules = lib.mkIf config.clanarchy.roles.laptop.framework.enable ''
      ACTION=="add", SUBSYSTEM=="acpi", KERNEL=="PNP0C0D:*", ATTR{power/wakeup}="disabled"
    '';

    # Power management — power-profiles-daemon (NOT TLP — conflicts with Framework AMD)
    services.power-profiles-daemon.enable = true;

    # Lid close → suspend to RAM (hybrid-sleep requires swap, which this ZFS layout lacks)
    services.logind.settings.Login = {
      HandleLidSwitch   = "suspend";
      KillUserProcesses = false;
    };
  };
}
