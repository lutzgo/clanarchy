{ ... }:
#
# @clanarchy/users — assign user profiles to machines via inventory.
#
# Replaces the previous pattern of importing modules/users/lgo.nix and
# modules/users/sabine.nix into every machine in flake.nix and enabling
# them with clanarchy.users.*.enable options.
#
# admin.nix is NOT managed here — it is imported directly in flake.nix
# because it also wires system-wide HM settings (useGlobalPkgs etc.) that
# must be present on every machine regardless of clan inventory.
#
# Roles:
#   lgo    — power user: Niri, browsers, devtools, YubiKey
#   sabine — personal user: GNOME, LibreOffice, Thunderbird, Firefox
#
{
  _class = "clan.service";
  manifest.name = "@clanarchy/users";
  manifest.description = "Assign user profiles to machines (lgo, sabine).";
  manifest.readme = builtins.readFile ./users.md;

  roles.lgo = {
    description = "lgo power user: Niri desktop, browsers, devtools, YubiKey.";
    perInstance =
      { ... }:
      {
        nixosModule =
          { ... }:
          {
            imports = [ ../modules/users/lgo.nix ];
            clanarchy.users.lgo.enable = true;
          };
      };
  };

  roles.sabine = {
    description = "sabine personal user: GNOME, LibreOffice, Thunderbird, Firefox.";
    perInstance =
      { ... }:
      {
        nixosModule =
          { ... }:
          {
            imports = [ ../modules/users/sabine.nix ];
            clanarchy.users.sabine.enable = true;
          };
      };
  };
}
