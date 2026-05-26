{ ... }:
#
# @clanarchy/printing — assign HP printing and scanning to machines via inventory.
#
# Enables CUPS with hplip drivers, SANE scanning backend, and adds lgo to the
# lp and scanner groups.
#
{
  _class = "clan.service";
  manifest.name        = "@clanarchy/printing";
  manifest.description = "HP printing (CUPS + hplip) and scanning (SANE + hplip).";
  manifest.readme      = builtins.readFile ./printing.md;

  roles.default = {
    description = "CUPS + SANE with hplip drivers.";
    perInstance =
      { ... }:
      {
        nixosModule =
          { ... }:
          {
            imports = [ ../modules/hardware/printing.nix ];
          };
      };
  };
}
