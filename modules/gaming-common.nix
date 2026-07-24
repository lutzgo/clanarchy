{ config, lib, pkgs, ... }:
let
  cfg = config.clanarchy.gaming;
in
{
  options.clanarchy.gaming = {
    enable = lib.mkEnableOption "shared gaming stack (Steam + Proton-GE + gaming-user persistence)";

    user = lib.mkOption {
      type = lib.types.str;
      description = ''
        Login name of the gaming user. Must be declared elsewhere as a
        NixOS user (e.g. birte's `deck.nix`). The paths in
        `persistenceDirectories` are added to
        `environment.persistence."/persist".users.<user>.directories` so
        the Steam library survives ZFS rollback.
      '';
      example = "deck";
    };

    persistenceDirectories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ".steam" ];
      description = ''
        Home-relative directories to persist across ZFS rollback for the
        gaming user. Defaults to `.steam` (Steam runtime bootstrap).
        Generic user paths (.config, .cache, ...) belong in the user
        module, not here.
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    programs.steam = {
      enable              = true;
      extraCompatPackages = with pkgs; [ proton-ge-bin ];
    };

    environment.persistence."/persist".users.${cfg.user} = {
      directories = cfg.persistenceDirectories;
    };
  };
}
