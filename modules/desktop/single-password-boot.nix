# One passphrase at boot, carried through to an unlocked keyring.
#
# Type it once for the disk, autologin follows, and gnome-keyring opens with
# the same secret — the behaviour Fedora ships. Off by default; machines opt
# in. Only useful where the root pool is actually encrypted.
#
# ── THE TRADE, STATED PLAINLY ──────────────────────────────────────────────
#
# This REMOVES A FACTOR. Today these machines ask twice: the pool passphrase
# in stage 1, then the user password at ReGreet. With this on, one secret
# gets you a live session with ssh keys and GnuPG material available.
#
# A powered-off laptop is exactly as safe as before — the disk is still
# encrypted and nothing on it is readable. A laptop someone watches you
# unlock, or takes while running, is less safe than before. That is the
# bargain, and it was made deliberately.
#
# ── HOW THE SECRET TRAVELS ─────────────────────────────────────────────────
#
# systemd's kernel-keyring hand-off, which is why stage 1 must be systemd
# (it is: nixpkgs removed the scripted initrd entirely).
#
#   1. stage 1 asks for the passphrase with `systemd-ask-password
#      --keyname=cryptsetup`, which CACHES it in the kernel keyring under
#      that well-known name. LUKS gets this free from systemd-cryptsetup;
#      ZFS does not, so the unit below does it by hand.
#   2. the key lives in the @u keyring for ~2.5 minutes, then expires.
#   3. greetd autologins and `pam_systemd_loadkey.so` reads it back in the
#      SESSION phase and hands it to the stack as the auth token.
#   4. `pam_gnome_keyring.so` takes that token and unlocks the login keyring.
#
# Step 3 needs `KeyringMode = "inherit"` on greetd: by default systemd gives
# each service a fresh session keyring, and a fresh keyring cannot see what
# stage 1 cached.
#
# The 2.5-minute expiry is why this is autologin-only. If a human has to type
# a username first, the key is often gone by the time PAM looks.
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
      one-passphrase boot: cache the stage-1 disk passphrase in the kernel
      keyring, autologin, and unlock gnome-keyring with the same secret
    '';

    user = lib.mkOption {
      type = lib.types.str;
      example = "lgo";
      description = ''
        The account to log in automatically. Its password must EQUAL the
        pool passphrase — that equality is the whole mechanism, and nothing
        here can check it. If they differ the login still works and the
        keyring silently stays locked.
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

    zfsDataset = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "zroot";
      description = ''
        Encrypted ZFS dataset to unlock from the cached passphrase. Leave
        null on a LUKS machine: systemd-cryptsetup already caches under
        `cryptsetup` and needs no help.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.zfsDataset != null -> config.clanarchy.rootfs == "zfs";
        message = "clanarchy.singlePasswordBoot.zfsDataset is set but this machine is not on ZFS.";
      }
    ];

    # ZFS half: take the prompt away from the stock module so it is not asked
    # twice, and ask for it ourselves in a way that populates the keyring.
    #
    # `--accept-cached` matters on a machine with more than one encrypted
    # dataset: the second unit reuses the first answer instead of prompting
    # again.
    boot.zfs.requestEncryptionCredentials = lib.mkIf (cfg.zfsDataset != null) (lib.mkForce false);

    boot.initrd.systemd.services."zfs-load-key-${toString cfg.zfsDataset}" = lib.mkIf (cfg.zfsDataset != null) {
      description = "Load the ${cfg.zfsDataset} key, caching it for the session keyring";
      wantedBy = ["initrd.target"];
      after = ["zfs-import-${cfg.zfsDataset}.service"];
      # BEFORE the impermanence rollback, not merely before sysroot.mount.
      # Both units sit between the pool import and the mount, so without
      # this they are unordered relative to each other — and a rollback that
      # wins the race operates on a dataset whose key is not loaded.
      # modules/zfs-impermanence.nix names its unit `rollback`.
      before = ["rollback.service" "sysroot.mount"];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${pkgs.systemd}/bin/systemd-ask-password \
          --keyname=cryptsetup --accept-cached \
          "Enter passphrase for ${cfg.zfsDataset}:" \
          | ${config.boot.zfs.package}/sbin/zfs load-key ${cfg.zfsDataset}
      '';
    };

    # Autologin. greetd skips PAM's auth phase entirely for initial_session,
    # which is precisely why the key has to be re-read in the session phase
    # below rather than arriving through normal authentication.
    services.greetd.settings.initial_session = {
      command = cfg.session;
      user = cfg.user;
    };

    # Give greetd the caller's keyring instead of a fresh one, or
    # pam_systemd_loadkey has nothing to find.
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
