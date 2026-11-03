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
#   4. PAM      a session-phase step reads the cached passphrase and starts
#               `gnome-keyring-daemon --daemonize --login` as the user with it
#               on stdin — exactly what pam_gnome_keyring itself does when it
#               HAS a password. That unlocks the login keyring, creating it
#               from the passphrase if it does not exist yet.
#
# ── WHY NOT pam_systemd_loadkey + pam_gnome_keyring, AS FEDORA DOES ───────
#
# That pairing works only where the display manager runs PAM's AUTH phase on
# autologin (GDM does). greetd's initial_session calls initiate(…,
# authenticate = false) and skips pam_authenticate, and both halves need it:
# pam_systemd_loadkey implements only pam_sm_authenticate/setcred (in a
# session stack it is skipped — "unable to resolve symbol:
# pam_sm_open_session"), and pam_gnome_keyring's open_session unlocks only
# with the password its OWN auth phase stashed (`gkr_system_authtok`), never
# PAM_AUTHTOK. Read from greetd and gnome-keyring-50.0 source, 2026-11-03.
# Until then this module put loadkey in the session stack, where it did
# nothing; miralda's first boot had no login keyring at all, and the first
# app to want one created an unencrypted "Default keyring".
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.clanarchy.singlePasswordBoot;

  # Runs as root from pam_exec. Never echoes the secret: no `set -x`, and it
  # travels only through a pipe.
  unlockScript = pkgs.writeShellScript "clanarchy-keyring-unlock" ''
    log() { ${pkgs.util-linux}/bin/logger -t clanarchy-keyring-unlock "$*"; }
    [ "''${PAM_SERVICE:-}" = greetd ] || exit 0
    [ "''${PAM_TYPE:-}" = open_session ] || exit 0
    [ "''${PAM_USER:-}" = ${lib.escapeShellArg cfg.user} ] || exit 0

    # systemd-cryptsetup caches into ROOT's user keyring as user:cryptsetup,
    # a NUL-separated list; the last entry is the passphrase that worked.
    id=$(${pkgs.keyutils}/bin/keyctl search @u user cryptsetup 2>/dev/null) || {
      log "no cached LUKS passphrase (expired, or no LUKS prompt this boot)"
      exit 0
    }
    mapfile -d "" -t pws < <(${pkgs.keyutils}/bin/keyctl pipe "$id")
    [ "''${#pws[@]}" -gt 0 ] || exit 0

    uid=$(${pkgs.coreutils}/bin/id -u "$PAM_USER")
    printf '%s' "''${pws[-1]}" |
      ${pkgs.util-linux}/bin/setpriv --reuid="$uid" --regid="$(${pkgs.coreutils}/bin/id -g "$PAM_USER")" --init-groups \
        ${pkgs.coreutils}/bin/env -i \
          HOME="$(${pkgs.getent}/bin/getent passwd "$PAM_USER" | ${pkgs.coreutils}/bin/cut -d: -f6)" \
          USER="$PAM_USER" LOGNAME="$PAM_USER" \
          XDG_RUNTIME_DIR="/run/user/$uid" \
          DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
          ${pkgs.gnome-keyring}/bin/gnome-keyring-daemon --daemonize --login >/dev/null &&
      log "started gnome-keyring for $PAM_USER with the LUKS passphrase" ||
      log "gnome-keyring-daemon --login failed for $PAM_USER"
  '';
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

    command = lib.mkOption {
      type = lib.types.str;
      example = "uwsm start -F -- niri-session";
      description = ''
        A COMMAND LINE for greetd's `initial_session`, not a session name.

        This is the distinction that broke the first attempt: `niri-uwsm` is
        a name in `services.displayManager.sessionData.sessionNames`, and
        greetd tried to execute it, failed, and fell back to the greeter — so
        the password prompt reappeared. Compare `default_session.command`,
        which is a full `dbus-run-session … cage … regreet` invocation.

        Take the value from the session's own .desktop `Exec=` line:
        `/run/current-system/sw/share/wayland-sessions/<name>.desktop`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      (let
        rules = config.security.pam.services.login.rules.session;
        ours = rules.clanarchy_keyring_unlock.order;
      in {
        assertion = rules.gnome_keyring.enable && rules.systemd.order < ours && ours < rules.gnome_keyring.order;
        message = ''
          clanarchy.singlePasswordBoot: the keyring-unlock PAM step must sit
          between pam_systemd (${toString rules.systemd.order}) and
          pam_gnome_keyring (${toString rules.gnome_keyring.order}) in the
          login session stack; it is at ${toString ours}.
        '';
      })
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
    # be picked up in the session phase — see the PAM rule below.
    services.greetd.settings.initial_session = {
      command = cfg.command;
      user = cfg.user;
    };

    # mkForce: the greetd module sets `KeyringMode = "shared"` itself, which
    # gives the service its own session keyring — and a fresh keyring cannot
    # see what stage 1 cached, which is the whole mechanism.
    systemd.services.greetd.serviceConfig.KeyringMode = lib.mkForce "inherit";

    # keyutils, so the verification step in the header is actually runnable:
    # `keyctl show @u` is how you confirm the cryptsetup key was cached, and
    # it is not installed by default. Asking someone to run a command that
    # does not exist is worse than not documenting it.
    environment.systemPackages = [pkgs.keyutils];

    # ORDER: AFTER pam_systemd, BEFORE pam_gnome_keyring — in `login`'s
    # session stack, because greetd includes that whole stack as one rule and
    # nothing can be placed inside it from greetd's side.
    #   after pam_systemd     it creates /run/user/<uid> (the daemon's
    #                         control socket) and starts the user bus.
    #   before gnome_keyring  its auto_start then finds our unlocked daemon;
    #                         after it, a LOCKED daemon would already hold
    #                         the control socket and ours would not start.
    # The script returns at once for any PAM service but greetd, so a tty
    # `login` runs it as a no-op.
    security.pam.services.login.rules.session.clanarchy_keyring_unlock = let
      rules = config.security.pam.services.login.rules.session;
    in {
      order = rules.gnome_keyring.order - 50;
      control = "optional";
      modulePath = "${pkgs.linux-pam}/lib/security/pam_exec.so";
      args = ["quiet" "${unlockScript}"];
    };
  };
}
