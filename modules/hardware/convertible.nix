# modules/hardware/convertible.nix — touch-first hardware: 2-in-1s and handhelds.
#
# Declares `clanarchy.hardware.convertible.enable` and guards its whole body on
# it, so importing this fleet-wide is inert on the machines that don't fold.
# The name predates the handheld: birte (a Steam Deck) uses it too, for the
# gestures and the on-screen keyboard, with auto-rotation off.
#
# What a touch-first niri machine needs that a clamshell doesn't:
#
#   1. Auto-rotation (`autoRotate`).  iio-sensor-proxy turns the raw IIO
#      accelerometer into orientation events; iio-niri (nixpkgs,
#      services.iio-niri) turns those into `niri msg output … transform`.  Niri
#      remaps touch and stylus coordinates along with the output, so rotating
#      the output is the whole job.  Only for machines WITH an accelerometer:
#      jens has cros-ec-accel; birte has a light sensor and nothing else.
#   2. Touchscreen gestures (`gestures`).  Stock niri 26.04 has none — touch
#      is delivered to apps and that is all.  niri-tablet
#      (github.com/GGEZUS/niri-tablet, the `niri-tablet` flake input) is a
#      patch series adding multi-finger swipes, taps, hold-swipes and edge
#      swipes, configured by a `gestures { touchscreen-swipe … }` block that
#      stock niri REJECTS.  So enabling this swaps programs.niri.package for
#      the patched build, and modules/desktop/niri-hm.nix both injects the
#      block and validates the config with that same binary.
#   3. An on-screen keyboard, since folding the panel back puts the physical
#      keyboard face-down against the desk.  wvkbd is a layer-shell OSK, which
#      is what niri speaks.  Toggled with Mod+O, and by swiping up from the
#      bottom edge when gestures are on.
#
# Tablet-mode itself needs nothing here: the EC reports SW_TABLET_MODE and
# libinput already disables the internal keyboard and touchpad when it is set.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: let
  cfg = config.clanarchy.hardware.convertible;

  # niri with niri-tablet's patches, applied the way the project's own NixOS
  # instructions do it.  `patch -Np1` in postPatch rather than `patches = …`
  # so a patch that no longer applies fails with its own name in the log.
  # None of the patches touch Cargo.toml/Cargo.lock (checked for v26.04.20),
  # so nixpkgs' cargo vendoring is reused unchanged.
  #
  # This is a from-source build of niri, which is not in any binary cache;
  # the remote builder (ernst) takes it.
  niriTablet = pkgs.niri.overrideAttrs (old: {
    pname = "niri-tablet";
    postPatch =
      (old.postPatch or "")
      + ''
        for p in ${inputs.niri-tablet}/pkg/*.patch; do
          echo "niri-tablet: applying $(basename "$p")"
          patch -Np1 < "$p"
        done
      '';
  });
in {
  options.clanarchy.hardware.convertible = {
    enable = lib.mkEnableOption "touch-first hardware support (2-in-1 or handheld): auto-rotation, touchscreen gestures, on-screen keyboard";

    autoRotate = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Rotate the compositor output to follow the accelerometer, with
          iio-niri. Turn this off on hardware without an accelerometer (a
          Steam Deck has none), or to keep the sensor available to
          applications without anything acting on it automatically.

          Only takes effect on Niri machines — iio-niri drives niri over IPC.
        '';
      };

      output = lib.mkOption {
        type = lib.types.str;
        default = "eDP-1";
        description = "Compositor output name to rotate. The built-in panel on every laptop in this clan.";
      };
    };

    gestures.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Touchscreen gestures in niri, from the niri-tablet patch series: three
        fingers drag to resize the column or scroll workspaces, four fingers
        tap for the overview, edge swipes focus columns or summon the
        on-screen keyboard. The full table is in niri-hm.nix.

        Replaces `programs.niri.package` with a patched niri built from
        source. Only meaningful on a machine with a touchscreen.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Accelerometer / ambient-light daemon. iio-niri reads orientation from
    # it; Noctalia and GTK apps can query it too.
    hardware.sensor.iio.enable = cfg.autoRotate.enable;

    # On-screen keyboard. wvkbd-mobintl is the international layout build;
    # the binds that toggle it live in modules/desktop/niri-hm.nix, guarded
    # on this same option.
    environment.systemPackages = [pkgs.wvkbd];

    # Auto-rotation. nixpkgs' module runs `iio-niri listen` as a user service
    # bound to `niriUnit`. Its default, niri.service, is the unit niri's own
    # session script starts; this fleet starts niri through UWSM instead,
    # whose unit is wayland-wm@niri\x2dsession.service — so bind to the
    # target both reach. UWSM exports NIRI_SOCKET into the user manager
    # before graphical-session.target is up, which is all iio-niri needs.
    #
    # This replaced a shell loop over `monitor-sensor` that did the same with
    # its own orientation table (left-up → 90, right-up → 270); iio-niri's
    # default mapping is the same one. If the image ever ends up sideways
    # against the room, `--transform` in extraArgs remaps it.
    services.iio-niri = lib.mkIf cfg.autoRotate.enable {
      enable = true;
      niriUnit = "graphical-session.target";
      extraArgs = ["--monitor" cfg.autoRotate.output];
    };

    programs.niri.package = lib.mkIf cfg.gestures.enable niriTablet;
  };
}
