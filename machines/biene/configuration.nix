{ lib, ... }:
{
  networking.hostName = "biene";
  networking.hostId   = "cd9ef50b";
  networking.search   = [ "skynet.lan" ];

  # No targetHost set — clan auto-discovers biene via ZeroTier (same as miralda).
  # For initial deploy or when ZeroTier is unreachable, use:
  #   BIENE_HOST=biene.local deploy-biene
  time.timeZone = "Europe/Berlin";

  # Locale: German everywhere (CLI + GNOME UI).
  # de layout for GDM; GNOME input-sources (in gnome.nix) adds us as secondary.
  clanarchy.locale = {
    language        = "de_DE";
    keyboard.layout = "de";
  };

  # Unfree packages used on biene (microsoft-edge via @clanarchy/software edge role).
  # pkgsForSystem sets allowUnfree = true but the NixOS nixpkgs.config layer
  # overrides that back to false unless an explicit predicate is declared here.
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [ "microsoft-edge" ];

  # machine-type (laptop, no Framework hw) and desktop (gnome + sabine dconf)
  # are assigned via inventory.instances in clan.nix.
  # Home wifi is provisioned via the clan wifi service (clan.nix).
  # Fritz!Box is biene-specific — managed via the bespoke modules/wifi.nix.
  clanarchy.hardware.cpu       = "intel";
  clanarchy.users.admin.enable = true;

  # Fritz!Box 7590 MX — biene-specific second wifi network.
  # Run `clan vars generate biene --generator wifi-fritzbox` to store the PSK.
  clanarchy.wifi.networks = [
    { ssid = "Fritz!Box 7590 MX"; varName = "wifi-fritzbox"; }
  ];

  # Syncthing — run as sabine so it can write to /home/sabine/Public.
  services.syncthing.user = "sabine";

  system.stateVersion = "25.11";
}
