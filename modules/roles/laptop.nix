{ config, lib, pkgs, ... }:
{
  options.clanarchy.roles.laptop = {
    enable           = lib.mkEnableOption "laptop role";
    framework.enable = lib.mkEnableOption "Framework-specific hardware (fprintd, fwupd, backpack-wake udev rule)";
  };

  config = lib.mkIf config.clanarchy.roles.laptop.enable {

    # GPU / hardware graphics
    hardware.graphics.enable = true;
    hardware.graphics.extraPackages =
      lib.optionals (config.clanarchy.hardware.cpu == "amd") (with pkgs; [
        mesa                    # Rusticl OpenCL via radeonsi driver
        rocmPackages.clr.icd    # ROCm ICD — optional for iGPU testing
      ]) ++
      lib.optionals (config.clanarchy.hardware.cpu == "intel") (with pkgs; [
        intel-media-driver
      ]);

    environment.variables =
      lib.mkIf (config.clanarchy.hardware.cpu == "amd") {
        RUSTICL_ENABLE = "radeonsi";
      };

    environment.systemPackages =
      lib.optionals (config.clanarchy.hardware.cpu == "amd") [ pkgs.clinfo ];

    # Framework-specific hardware — only assert opinions when framework.enable is true.
    # Leaving fwupd unset when framework is off lets desktop modules (e.g. plasma6)
    # set their own mkDefault without a priority conflict.
    services.fprintd.enable = lib.mkIf config.clanarchy.roles.laptop.framework.enable (lib.mkDefault true);
    services.fwupd.enable   = lib.mkIf config.clanarchy.roles.laptop.framework.enable (lib.mkDefault true);

    # Enrolled fingerprints must survive ZFS rollback.
    environment.persistence."/persist".directories =
      lib.mkIf config.clanarchy.roles.laptop.framework.enable [ "/var/lib/fprint" ];

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
