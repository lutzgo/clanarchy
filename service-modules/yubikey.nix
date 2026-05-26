{ ... }:
#
# @clanarchy/yubikey — assign YubiKey hardware support to machines via inventory.
#
# Enables pcscd, GnuPG agent (pinentry-qt Wayland wrapper), YubiKey udev rules,
# polkit rule for SSH PCSC access, and system-wide known_hosts for clan machines.
#
{
  _class = "clan.service";
  manifest.name        = "@clanarchy/yubikey";
  manifest.description = "YubiKey support: pcscd, GnuPG agent, polkit PCSC rule.";
  manifest.readme      = builtins.readFile ./yubikey.md;

  roles.default = {
    description = "Full YubiKey support stack for a machine.";
    perInstance =
      { ... }:
      {
        nixosModule =
          { ... }:
          {
            imports = [ ../modules/hardware/yubikey.nix ];
          };
      };
  };
}
