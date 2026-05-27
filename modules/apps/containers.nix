{ config, lib, ... }:
let cfg = config.clanarchy.apps.containers;
in {
  options.clanarchy.apps.containers.enable =
    lib.mkEnableOption "container runtime (Podman with Docker compatibility)";

  config = lib.mkIf cfg.enable {
    virtualisation.containers.enable = true;
    virtualisation.podman = {
      enable       = true;
      dockerCompat = true;
    };
  };
}
