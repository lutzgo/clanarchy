# One passphrase at boot, carried through to an unlocked keyring.
#
# Type the LUKS passphrase in stage 1; autologin follows and gnome-keyring
# opens with the same secret — the behaviour Fedora ships. Off by default;
# machines opt in.
#
# ── THERE IS NO INITRD UNIT HERE, AND THAT IS THE WHOLE POINT ───────────────
#
# systemd-cryptsetup caches the passphrase it prompted for into the kernel
# keyring under the well-known name `cryptsetup`, by itself, on every LUKS
# machine. Nothing in this module makes that happen — it only reads it back.
#
# An earlier revision of this file tried to do the same thing on ZFS, which
# has no such path, by hand-writing a stage-1 unit to pipe
# `systemd-ask-password --keyname=cryptsetup` into `zfs load-key`. That unit
# referenced a zfs binary absent from `boot.initrd.systemd.storePaths`, so it
# failed, the pool key never loaded, /home and /persist could not mount, and
# jens reached emergency mode with root locked — recoverable only from the
# previous boot generation. #372, reverted #376, removed #377.
#
# Hence the assertion below: this module refuses to enable on anything but
# btrfs, because btrfs here means LUKS and LUKS means the caching is upstream
# behaviour rather than something this repo maintains.
#
# ── THE TRADE, STATED PLAINLY ──────────────────────────────────────────────
#
# This REMOVES A FACTOR. Without it the machine asks twice — disk passphrase,
# then user password at ReGreet. With it, one secret gets you a live session
# with ssh keys and GnuPG material available.
#
# A powered-off laptop is exactly as safe as before: the disk is still LUKS2
# and nothing on it is readable. A laptop taken while running, or watched
# being unlocked, is less safe than before. Both prompts were asking for the
# same string anyway, so the second was theatre — but the bargain is explicit
# now rather than accidental.
#
# ── HOW THE SECRET TRAVELS ─────────────────────────────────────────────────
#
#   1. stage 1  systemd-cryptsetup prompts, unlocks the volume, and caches the
#               passphrase in the kernel keyring as `cryptsetup`.
#   2. ~2.5 min the key expires. This is why the feature is autologin-only: if
#               a human has to type a username first, the key is often gone.
#   3. greetd   autologins via `initial_session`. greetd skips PAM's auth
#               phase entirely on that path, which is why the key is read back
#               in the SESSION phase rather than arriving through auth.
#   4. PAM      pam_systemd_loadkey hands the cached secret to the stack;
#               pam_gnome_keyring takes it as the auth token and unlocks the
#               login keyring.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.clanarchy.singlePasswordBoot;
in {
  options.clanarchy.singlePasswordBoot = {
    enable = lib.mkEnableOption ''
      one-passphrase boot: autologin, and unlock gnome-keyring from the LUKS
      passphrase that systemd-cryptsetup already cached in the kernel keyring.
      Requires a LUKS root — see the header for what happened when this was
      attempted on ZFS
    '';

    user = lib.mkOption {
      type = lib.types.str;
      example = "lgo";
      description = ''
        The account to log in automatically. Its password must EQUAL the LUKS
        passphrase — that equality is the entire mechanism, and nothing here
        can check it. If they differ, login still succeeds and the keyring
        silently stays locked.
      '';
    };

    session = lib.mkOption {
      type = lib.types.str;
      example = "niri-uwsm";
      description = ''
        Session command for greetd's `initial_session`. Must name a session
        the greeter would otherwise offer.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.clanarchy.rootfs == "btrfs";
        message = ''
          clanarchy.singlePasswordBoot requires a LUKS root, which in this
          fleet means clanarchy.rootfs = "btrfs". On ZFS the passphrase is
          never cached in the kernel keyring and faking it needs a stage-1
          unit, which is what put jens in emergency mode (#372).
        '';
      }
    ];

    # Autologin. greetd skips PAM auth for initial_session, so the key has to
    # be re-read in the session phase below.
    services.greetd.settings.initial_session = {
      command = cfg.session;
      user = cfg.user;
    };

    # mkForce: the greetd module sets `KeyringMode = "shared"` itself, which
    # gives the service its own session keyring — and a fresh keyring cannot
    # see what stage 1 cached, which is the whole mechanism.
    systemd.services.greetd.serviceConfig.KeyringMode = lib.mkForce "inherit";

    # Order matters: loadkey must run BEFORE pam_gnome_keyring, because it is
    # what puts the token where gnome-keyring looks for it.
    security.pam.services.greetd.rules.session = {
      systemd_loadkey = {
        order = 11000;
        control = "optional";
        modulePath = "${config.systemd.package}/lib/security/pam_systemd_loadkey.so";
      };
      gnome_keyring = {
        order = 12000;
        control = "optional";
        modulePath = "${pkgs.gnome-keyring}/lib/security/pam_gnome_keyring.so";
        args = ["auto_start"];
      };
    };
  };
}
