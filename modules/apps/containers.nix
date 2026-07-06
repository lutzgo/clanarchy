{ config, lib, pkgs, ... }:
let cfg = config.clanarchy.apps.containers;
in {
  options.clanarchy.apps.containers.enable =
    lib.mkEnableOption "container runtime (Podman with Docker compatibility + docker-compose)";

  config = lib.mkIf cfg.enable {
    virtualisation.containers.enable = true;
    virtualisation.podman = {
      enable       = true;
      # `docker` → `podman` binary symlink (transparent CLI replacement).
      dockerCompat = true;
      # Emulate the Docker API on /run/docker.sock so that tools speaking the
      # Docker socket protocol (docker-compose v2, lazydocker, IDE Docker
      # integrations) talk to podman without modification.
      dockerSocket.enable = true;
    };

    # docker-compose v2 (Go binary) connects to /run/docker.sock.
    environment.systemPackages = [ pkgs.docker-compose ];

    # Members of the `podman` group can talk to /run/docker.sock without sudo;
    # the user that needs compose access should be added to it in their
    # per-user config (e.g. users.users.<name>.extraGroups = [ "podman" ]).
  };
}
