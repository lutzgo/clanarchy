{ config, lib, ... }:
{
  options.clanarchy.roles.rpi = {
    enable = lib.mkEnableOption "Raspberry Pi role (headless, no desktop by default)";
  };

  config = lib.mkIf config.clanarchy.roles.rpi.enable {
    # RPi SoC firmware — non-free blobs required for VideoCore GPU and WiFi chip
    hardware.enableRedistributableFirmware = true;

    # NOTE: Boot loader must be configured per RPi model in the machine's configuration.nix.
    #   RPi 3/4/5 with U-Boot / extlinux:
    #     boot.loader.grub.enable = false;
    #     boot.loader.generic-extlinux-compatible.enable = true;
    #   RPi with systemd-boot is NOT supported (no EFI).
  };
}
