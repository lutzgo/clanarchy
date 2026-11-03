{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.clanarchy.apps.communication;
in {
  options.clanarchy.apps.communication.enable =
    lib.mkEnableOption "communication and connectivity apps (Signal, Anytype, Valent/KDE Connect)";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      signal-desktop # messaging (unfree)
      anytype # knowledge base / notes (unfree)
    ];

    # Valent, one systemd-managed instance — see modules/apps/valent.nix.
    clanarchy.apps.valent.enable = true;
  };
}
