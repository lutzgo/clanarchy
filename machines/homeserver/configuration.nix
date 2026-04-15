{ ... }:
{
  clanarchy.roles.server.enable = true;

  networking.hostName = "homeserver";
  time.timeZone       = "Europe/Berlin";

  # TODO: Add a hostId (generate with: head -c4 /dev/urandom | od -A none -t x4 | tr -d ' ')
  # networking.hostId = "XXXXXXXX";

  # TODO: disko.nix — use modules/disko/with-swap.nix as a template:
  #   imports = [ ../../modules/disko/with-swap.nix { swapSize = "16G"; } ];
  #   then set disko.devices.disk.main.device

  # TODO: Activate users once the machine is ready:
  #   clanarchy.users.admin.enable = true;

  # TODO: microvm services (*arr, Jellyfin, Nextcloud, Immich, Home Assistant)

  system.stateVersion = "26.05";
}
