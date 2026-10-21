{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.clanarchy.roles.laptop;
in {
  options.clanarchy.roles.laptop = {
    enable = lib.mkEnableOption "laptop role";
    framework.enable = lib.mkEnableOption "Framework-specific hardware (fprintd, fwupd, backpack-wake udev rule)";

    hybridSleep.enable = lib.mkOption {
      type = lib.types.bool;
      default = config.clanarchy.rootfs == "btrfs";
      description = ''
        Hybrid-sleep on lid close: suspend to RAM and write a hibernation
        image at the same time, so a battery that runs flat during sleep
        costs nothing.

        **ONLY AVAILABLE ON btrfs, AND THAT IS THE POINT** — hibernation with
        a ZFS root is widely documented as unsafe (the pool's in-memory state
        and its on-disk state diverge across the resume), and `clanarchy.rootfs`
        is derived from `clanarchy.channel`, so in practice this is on for an
        unstable-channel laptop and refused on a stable one. Enabling it on ZFS
        is an assertion failure, not a silent risk. This is reasoned from
        upstream's position, not measured here.

        Also requires a swap partition sized >= RAM and `boot.resumeDevice`
        set in the machine's own configuration.nix; both are asserted.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(cfg.hybridSleep.enable && config.clanarchy.rootfs != "btrfs");
        message = ''
          clanarchy.roles.laptop.hybridSleep.enable is on, but this machine's
          root is ${config.clanarchy.rootfs}. Hibernation with a ZFS root is
          not supported here — see the option's description.

          `clanarchy.rootfs` is derived from `clanarchy.channel`
          (modules/rootfs.nix), so the way to make this machine capable of
          hibernating is to move it to the unstable channel, which also moves
          it to btrfs. There is no way to enable just one half.
        '';
      }
      {
        # The two runtime preconditions, which were a doc comment until now.
        # A machine that enables hybrid-sleep with neither simply fails to
        # resume, having already powered off — there is nothing to notice
        # until the state is gone.
        assertion = !(cfg.hybridSleep.enable && config.boot.resumeDevice == "");
        message = ''
          clanarchy.roles.laptop.hybridSleep.enable is on but
          boot.resumeDevice is unset, so the hibernation image could be
          written and never found. Set it to a stable
          /dev/disk/by-partlabel/... path in the machine's configuration.nix.
        '';
      }
      {
        assertion = !(cfg.hybridSleep.enable && config.swapDevices == []);
        message = ''
          clanarchy.roles.laptop.hybridSleep.enable is on but this machine
          declares no swap. Pass `enableSwap = true` (and a `swapSize` of at
          least RAM) to the disko template in the machine's disko.nix, and
          `encryptSwap = false` — a randomly-keyed swap partition loses its
          key across the suspend, which is the one thing hibernation needs it
          to keep.
        '';
      }
    ];

    # GPU / hardware graphics — delegate to shared options
    # (modules/hardware/gpu.nix).  Laptops get the baseline driver for the
    # configured CPU vendor; ROCm/iGPU-only flavour ships clr.icd anyway.
    clanarchy.hardware.gpu.amd.enable = config.clanarchy.hardware.cpu == "amd";
    clanarchy.hardware.gpu.intel.enable = config.clanarchy.hardware.cpu == "intel";

    # Framework-specific hardware: fprintd + udev wake rule.
    services.fprintd.enable = lib.mkIf cfg.framework.enable (lib.mkDefault true);

    # fwupd — enabled for all laptops (Framework and non-Framework).
    # Provides firmware updates via LVFS; see docs/guides/firmware-updates.md.
    services.fwupd.enable = lib.mkDefault true;

    # fwupd-refresh (Type=oneshot, LVFS metadata download) intermittently fails on
    # transient network/DNS/auth blips — e.g. right after boot or when roaming.
    # The bare failure surfaces in `switch-to-configuration`'s failed-units summary
    # and makes `deploy switch` on laptops exit non-zero for no real reason.
    #
    # We can't fix this via Restart=on-failure — switch-to-configuration-ng
    # explicitly flags units in SubState=auto-restart with ExecMainStatus!=0 as
    # failed (see switch-to-configuration-ng src/main.rs, the block guarded by
    # `substate == "auto-restart"`). We also can't narrow SuccessExitStatus:
    # fwupdmgr uses generic exit 1 for every transient error, so widening it
    # would mask real failures.
    #
    # Instead, prefix ExecStart with `-`. systemd records the exit code in the
    # journal but treats the run as successful — no auto-restart, no "failed"
    # state, no propagation to switch-to-configuration. fwupd-refresh.timer
    # fires daily, so a missed metadata refresh self-heals on the next run.
    # Persistent LVFS breakage still surfaces via `journalctl -u fwupd-refresh`,
    # motd (which fwupd-refresh itself updates), and `fwupdmgr get-devices`
    # showing stale metadata.
    #
    # ExecStart= in a drop-in is *additive* by default (systemd.service(5)) —
    # so setting it to a plain string appends a second ExecStart after the
    # vendor's, and for Type=oneshot the vendor's undashed command runs first,
    # fails, and short-circuits ours. The empty first list element resets the
    # list; the dashed command is then the only ExecStart.
    systemd.services.fwupd-refresh.serviceConfig.ExecStart = lib.mkForce [
      ""
      "-${config.services.fwupd.package}/bin/fwupdmgr refresh"
    ];

    # Enrolled fingerprints must survive ZFS rollback.
    environment.persistence."/persist".directories =
      lib.mkIf cfg.framework.enable ["/var/lib/fprint"];

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
      HandleLidSwitch =
        if cfg.hybridSleep.enable
        then "hybrid-sleep"
        else "suspend";
      HandleLidSwitchExternalPower = "suspend";
      KillUserProcesses = false;
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
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
    nix.settings.auto-optimise-store = true;
  };
}
