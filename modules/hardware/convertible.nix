# modules/hardware/convertible.nix — 2-in-1 / convertible laptop support.
#
# Declares `clanarchy.hardware.convertible.enable` and guards its whole body on
# it, so importing this fleet-wide is inert on the machines that don't fold.
#
# What a convertible needs that a clamshell doesn't:
#
#   1. An accelerometer daemon (iio-sensor-proxy).  The kernel exposes the raw
#      IIO device, but nothing turns "the panel is now on its side" into
#      something a compositor can consume without it.
#   2. Something to act on that.  Niri does not auto-rotate on its own — it has
#      no orientation client — so `clanarchy-autorotate` below reads
#      monitor-sensor's output and drives `niri msg output ... transform`.
#      Niri remaps touch and stylus coordinates along with the output, so
#      rotating the output is the whole job; the input devices follow.
#   3. An on-screen keyboard, since folding the panel back puts the physical
#      keyboard face-down against the desk.  wvkbd is a layer-shell OSK, which
#      is what Niri speaks.
#
# Tablet-mode itself needs nothing here: the EC reports SW_TABLET_MODE and
# libinput already disables the internal keyboard and touchpad when it is set.
{ config, lib, pkgs, ... }:
let
  cfg = config.clanarchy.hardware.convertible;

  # monitor-sensor prints a line per orientation change, e.g.
  #   Accelerometer orientation changed: left-up
  # Map each to the output transform that puts the top of the image back at
  # the top of the world.  The mapping is inverted on purpose: when the panel
  # rotates left-up, the *image* has to rotate the other way to compensate.
  autorotate = pkgs.writeShellApplication {
    name = "clanarchy-autorotate";
    # niri for `niri msg`; iio-sensor-proxy for `monitor-sensor`.
    runtimeInputs = [ pkgs.iio-sensor-proxy pkgs.niri ];
    text = ''
      output=''${CLANARCHY_AUTOROTATE_OUTPUT:-eDP-1}

      # stdbuf-free: monitor-sensor line-buffers when piped to a shell read
      # loop, and `--accel` keeps the gyroscope/ALS chatter out of the stream.
      monitor-sensor --accel | while read -r line; do
        case "$line" in
          *"orientation changed: normal"*)    transform=normal ;;
          *"orientation changed: bottom-up"*) transform=180 ;;
          *"orientation changed: left-up"*)   transform=90 ;;
          *"orientation changed: right-up"*)  transform=270 ;;
          *) continue ;;
        esac
        niri msg output "$output" transform "$transform" || true
      done
    '';
  };
in
{
  options.clanarchy.hardware.convertible = {
    enable = lib.mkEnableOption "convertible / 2-in-1 support (accelerometer, auto-rotation, on-screen keyboard)";

    autoRotate = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Rotate the compositor output to follow the accelerometer. Turn this
          off to keep the sensor available to applications (Noctalia, GNOME
          apps) without anything acting on it automatically.

          Only takes effect on Niri machines — the service drives `niri msg`.
        '';
      };

      output = lib.mkOption {
        type = lib.types.str;
        default = "eDP-1";
        description = "Compositor output name to rotate. The built-in panel on every laptop in this clan.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Accelerometer / ambient-light daemon. Also what lets Noctalia and any
    # GTK app query orientation on their own.
    hardware.sensor.iio.enable = true;

    # On-screen keyboard. wvkbd-mobintl is the international layout build;
    # the Niri bind that toggles it lives in modules/desktop/niri-hm.nix,
    # guarded on this same option.
    environment.systemPackages = [ pkgs.wvkbd ];

    # Auto-rotation. A NixOS-level user service rather than a Home Manager one
    # so it applies to whichever user logs in, and because UWSM imports the
    # session environment (NIRI_SOCKET included) into the systemd user manager
    # before graphical-session.target is reached.
    systemd.user.services.clanarchy-autorotate = lib.mkIf cfg.autoRotate.enable {
      description = "Rotate the display to follow the accelerometer";
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
      wantedBy = [ "graphical-session.target" ];
      environment.CLANARCHY_AUTOROTATE_OUTPUT = cfg.autoRotate.output;
      serviceConfig = {
        ExecStart = lib.getExe autorotate;
        # monitor-sensor exits if iio-sensor-proxy restarts (or if it starts
        # before the daemon is on the bus); come back rather than staying dead.
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
