{ config, lib, pkgs, ... }:
let
  cfg = config.clanarchy.roles.laptop;
in
{
  options.clanarchy.roles.laptop = {
    enable           = lib.mkEnableOption "laptop role";
    framework.enable = lib.mkEnableOption "Framework-specific hardware (fprintd, fwupd, backpack-wake udev rule)";

    hybridSleep.enable = lib.mkOption {
      type    = lib.types.bool;
      default = true;
      description = ''
        Enable hybrid-sleep on lid close (suspends to RAM and writes hibernation
        image simultaneously). Requires a swap partition sized ≥ RAM and
        boot.resumeDevice set in the machine's own configuration.nix.
        Disable for machines without swap until a swap partition is added.
      '';
    };
  };

  config = lib.mkIf cfg.enable {

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
    services.fprintd.enable = lib.mkIf cfg.framework.enable (lib.mkDefault true);
    services.fwupd.enable   = lib.mkIf cfg.framework.enable (lib.mkDefault true);

    # Enrolled fingerprints must survive ZFS rollback.
    environment.persistence."/persist".directories =
      lib.mkIf cfg.framework.enable [ "/var/lib/fprint" ];

    # Prevent backpack-wake: disable LID ACPI device as a kernel wakeup source.
    # This stops the lid sensor from generating spurious wakeups when bag pressure
    # flexes the chassis. The input event path (power-switch tag) is intentionally
    # preserved so logind can still see lid-close events and trigger HandleLidSwitch.
    # Trade-off: opening the lid will not wake from suspend by itself; use the power button.
    services.udev.extraRules = lib.mkIf cfg.framework.enable ''
      ACTION=="add", SUBSYSTEM=="acpi", KERNEL=="PNP0C0D:*", ATTR{power/wakeup}="disabled"
    '';

    # Power management — power-profiles-daemon (NOT TLP — conflicts with Framework AMD)
    services.power-profiles-daemon.enable = true;

    # Lid-close behaviour:
    #   hybridSleep.enable=true  → hybrid-sleep on battery, suspend on AC
    #   hybridSleep.enable=false → suspend only (use until swap partition exists)
    services.logind.settings.Login = {
      HandleLidSwitch              = if cfg.hybridSleep.enable then "hybrid-sleep" else "suspend";
      HandleLidSwitchExternalPower = "suspend";
      KillUserProcesses            = false;
    };

    # Hibernate via clean shutdown (most compatible across firmwares).
    # Only meaningful when hybridSleep.enable = true.
    systemd.sleep.settings.Sleep = lib.mkIf cfg.hybridSleep.enable {
      HibernateMode = "shutdown";
    };
  };
}
