{ config, lib, pkgs, ... }:
#
# ZSA keyboard support — Oryx web configurator, Keymapp, and the udev rules
# both of them need.  Written for the Voyager; the same rules cover the
# Moonlander, Planck EZ and ErgoDox EZ, which is why the option is not
# Voyager-specific.
#
# Imported unconditionally by commonBase (lib/mk-machine.nix) and guarded on
# `clanarchy.hardware.zsa.enable`, the same shape as modules/channel.nix and
# modules/rootfs.nix: every machine gets the option, nothing gets the config
# until a machine asks for it.
#
# ── WHAT THE ZSA WIKI'S "CREATE A UDEV RULE FILE" STEP MEANS HERE ──────────
#
# https://github.com/zsa/wally/wiki/Linux-install#2-create-a-udev-rule-file
# tells you to write /etc/udev/rules.d/50-zsa.rules by hand and to create a
# `plugdev` group with your user in it.  On NixOS the first half is
# `hardware.keyboard.zsa.enable`, which installs pkgs.zsa-udev-rules into
# services.udev.packages.  Do NOT hand-write the rules alongside it.
#
# THE SECOND HALF — the plugdev group — IS NOT NEEDED, AND ADDING IT WOULD BE
# A MISTAKE.  Read 50-oryx.rules from the package rather than the wiki:
#
#     SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3297", TAG+="uaccess"
#     SUBSYSTEMS=="usb",   ATTRS{idVendor}=="3297", MODE:="0666", \
#                                                   SYMLINK+="ignition_dfu"
#
# `TAG+="uaccess"` hands systemd-logind the job: it puts an ACL on the device
# for whoever holds the ACTIVE LOCAL SEAT SESSION, and revokes it when that
# session goes away.  That is strictly better than a static group — access
# follows who is actually sitting at the machine instead of who was added to a
# group once and never removed.  Creating `plugdev` on top would be a second
# mechanism for one property, which is the thing containers/traefik.nix argues
# against in its own words and which M7 then acted on by deleting the
# ipAllowList rather than stacking it under forward-auth.
#
# 3297 is ZSA's vendor id and covers the Voyager on both interfaces: the
# hidraw one Oryx and Keymapp talk to for live training and keymap upload, and
# the raw USB one the keyboard presents in DFU/bootloader mode when it is
# being flashed.
#
# ── THE FAILURE THIS REPO HAS ALREADY PAID FOR ONCE ────────────────────────
#
# `uaccess` needs an ACTIVE session on a LOCAL SEAT.  An SSH session has
# neither, so flashing or live-training over SSH fails with a permission error
# on a machine where it works perfectly from the desk.  That is the same class
# of problem as pcscd and the YubiKey, which CLAUDE.md records at length:
# "SSH sessions lack an 'active' logind session, so pcscd requires a polkit
# rule".  The fix there was a polkit rule because pcscd is a system daemon;
# there is no equivalent here and none is wanted — a keyboard is flashed by the
# person holding it.  If it ever IS wanted, the honest answer is a group and an
# explicit argument for it, not a quiet MODE=0666 widening.
#
# ── THE THING MOST LIKELY TO LOOK BROKEN: THE BROWSER ──────────────────────
#
# Oryx's in-browser features — live training, and flashing straight from
# configure.zsa.io — are built on WebHID.  FIREFOX AND LIBREWOLF DO NOT
# IMPLEMENT WebHID OR WebUSB, and they do not intend to; Mozilla's published
# position on both is negative.  So on miralda, where lgo has librewolf,
# firefox AND ungoogled-chromium (clan.nix, @clanarchy/software), Oryx's web
# features work in CHROMIUM ONLY.  The page does not explain this — the
# keyboard simply never appears — so it reads as a udev problem and is not.
#
# Keymapp is the way out of that: it is ZSA's native desktop app, it talks to
# the same hidraw device directly, and it is what ZSA points Voyager owners at
# rather than browser flashing.  It is installed by default with this option
# for exactly that reason.
#
{
  options.clanarchy.hardware.zsa = {
    enable = lib.mkEnableOption ''
      ZSA keyboard support (Voyager, Moonlander, Planck EZ, ErgoDox EZ).

      Installs the ZSA udev rules so the Oryx web configurator and Keymapp can
      reach the keyboard for live training and flashing. Access is granted by
      `uaccess` to the active local seat session, so no group membership is
      needed and none is created
    '';

    keymapp.enable = lib.mkOption {
      type    = lib.types.bool;
      default = config.clanarchy.hardware.zsa.enable;
      description = ''
        Install Keymapp, ZSA's native desktop configurator.

        On by default whenever `clanarchy.hardware.zsa.enable` is set, because
        it is the supported path for the Voyager and the only one that does not
        depend on the browser implementing WebHID.

        NOTE: Keymapp is UNFREE. A machine with `nixpkgs.config.allowUnfree`
        left at `false` must set this to `false` explicitly, or evaluation
        fails. It is a separate toggle rather than part of `enable` so that
        turning on a udev rule cannot drag an unfree package onto a machine
        that has not opted into unfree software.
      '';
    };

    wally.enable = lib.mkOption {
      type    = lib.types.bool;
      default = false;
      description = ''
        Install `wally-cli`, ZSA's older command-line flasher (MIT).

        Off by default: for the Voyager, Keymapp supersedes it, and Wally's
        remaining use is flashing a firmware file built outside Oryx — a QMK
        source build rather than a layout downloaded from configure.zsa.io.
        Turn it on if that is what you are doing; it needs no extra udev rules,
        since it flashes through the same `ignition_dfu` device the rules above
        already tag.
      '';
    };
  };

  config = lib.mkIf config.clanarchy.hardware.zsa.enable {
    # The wiki's step 2, declaratively. Installs pkgs.zsa-udev-rules —
    # 50-oryx.rules + 50-wally.rules — into services.udev.packages.
    hardware.keyboard.zsa.enable = true;

    environment.systemPackages =
      lib.optional config.clanarchy.hardware.zsa.keymapp.enable pkgs.keymapp
      ++ lib.optional config.clanarchy.hardware.zsa.wally.enable pkgs.wally-cli;
  };
}
