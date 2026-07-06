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

    # GPU / hardware graphics — delegate to shared options
    # (modules/hardware/gpu.nix).  Laptops get the baseline driver for the
    # configured CPU vendor; ROCm/iGPU-only flavour ships clr.icd anyway.
    clanarchy.hardware.gpu.amd.enable   = config.clanarchy.hardware.cpu == "amd";
    clanarchy.hardware.gpu.intel.enable = config.clanarchy.hardware.cpu == "intel";

    # Framework-specific hardware: fprintd + udev wake rule.
    services.fprintd.enable = lib.mkIf cfg.framework.enable (lib.mkDefault true);

    # fwupd — enabled for all laptops (Framework and non-Framework).
    # Provides firmware updates via LVFS; see docs/guides/firmware-updates.md.
    services.fwupd.enable = lib.mkDefault true;

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

    # Power management — power-profiles-daemon for both AMD and Intel.
    # AMD: amd_pstate EPP is managed automatically by the kernel + ppd.
    # Intel: intel_pstate HWP/EPP managed by ppd; thermald adds thermal budget control.
    # Do NOT enable TLP — it conflicts with power-profiles-daemon on Framework AMD.
    services.power-profiles-daemon.enable = true;
    services.thermald.enable = config.clanarchy.hardware.cpu == "intel";

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

    # Nix store maintenance — weekly GC (14-day retention) + deduplication.
    # Server role uses 30-day retention; laptops rebuild more frequently.
    nix.gc = {
      automatic = true;
      dates     = "weekly";
      options   = "--delete-older-than 14d";
    };
    nix.settings.auto-optimise-store = true;
  };
}
