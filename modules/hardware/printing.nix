{ pkgs, ... }:
{
  services.printing = {
    enable  = true;
    drivers = [ pkgs.hplip ];
  };

  hardware.sane = {
    enable        = true;
    extraBackends = [ pkgs.hplip ];
  };

  users.users.lgo.extraGroups = [ "lp" "scanner" ];
}
