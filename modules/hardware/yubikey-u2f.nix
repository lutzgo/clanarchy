# Touch a YubiKey instead of typing the password — for sudo, polkit and the
# lock screen. Registrations live in this repo, so one entry works on every
# machine that enables this. See docs/guides/yubikey-two-keys.md.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.clanarchy.u2f;
  # One fixed origin fleet-wide. pam_u2f defaults it to pam://<hostname>, which
  # would make a registration valid on one machine only — changing this string
  # invalidates every registered key.
  origin = "pam://clanarchy";
  users = lib.filterAttrs (_: creds: creds != []) cfg.credentials;
  authfile = pkgs.writeText "u2f-mappings" (lib.concatStrings (lib.mapAttrsToList
    (user: creds: "${user}:${lib.concatStringsSep ":" creds}\n")
    users));
in {
  options.clanarchy.u2f = {
    enable = lib.mkEnableOption "YubiKey touch as an alternative to the password (pam_u2f)";
    credentials = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = {};
      example = {alice = ["<KeyHandle>,<UserKey>,es256,+presence"];};
      description = ''
        Registered keys per user: everything after `user:` in the output of
        `pamu2fcfg -o pam://clanarchy -i pam://clanarchy`, one list entry per
        key (split on `:`). Public data — safe to commit.
      '';
    };
    services = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["sudo" "polkit-1" "noctalia"];
      description = ''
        PAM services where a touch is accepted. greetd is left out on purpose:
        logging in without the password leaves gnome-keyring locked.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    security.pam.u2f = {
      # `sufficient`: a touch lets you in; no key, or a user with no entry,
      # falls through to the password. Never `required` — that locks out
      # anyone whose key is lost.
      control = "sufficient";
      settings = {
        inherit authfile origin;
        appid = origin;
        cue = true;
      };
    };
    # Nothing registered yet → no PAM change at all.
    security.pam.services = lib.mkIf (users != {}) (lib.genAttrs cfg.services (_: {u2f.enable = true;}));

    environment.systemPackages = [pkgs.pam_u2f]; # pamu2fcfg, for registering
  };
}
