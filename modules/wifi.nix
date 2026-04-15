{ config, lib, pkgs, ... }:
let
  # Convert a varName like "wifi-home" → env var "WIFI_HOME_PSK"
  varToEnv = varName: lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] varName) + "_PSK";
in
{
  options.clanarchy.wifi.networks = lib.mkOption {
    type    = lib.types.listOf (lib.types.submodule {
      options = {
        ssid    = lib.mkOption { type = lib.types.str; description = "WiFi SSID."; };
        varName = lib.mkOption { type = lib.types.str; description = "Clan vars generator name for this network's PSK."; };
      };
    });
    default     = [];
    description = "List of WiFi networks to configure via NetworkManager and clan vars.";
  };

  config = lib.mkIf (config.clanarchy.wifi.networks != []) {

    # Clan vars generators — one per network
    clan.core.vars.generators = lib.listToAttrs (map (network: {
      name  = network.varName;
      value = {
        files."env".secret = true;
        prompts."psk" = {
          description = "WiFi password for '${network.ssid}'";
          type        = "hidden";
        };
        script = let envVar = varToEnv network.varName; in ''
          printf '${envVar}=%s\n' "$(cat "$prompts/psk")" > "$out/env"
        '';
      };
    }) config.clanarchy.wifi.networks);

    # NetworkManager profiles — one per network
    networking.networkmanager.ensureProfiles = {
      environmentFiles = map
        (n: config.clan.core.vars.generators.${n.varName}.files."env".path)
        config.clanarchy.wifi.networks;

      profiles = lib.listToAttrs (map (network: {
        name  = network.ssid;
        value = {
          connection = { id = network.ssid; type = "wifi"; };
          wifi       = { ssid = network.ssid; mode = "infrastructure"; };
          wifi-security = {
            auth-alg = "open";
            key-mgmt = "wpa-psk";
            psk      = "$" + (varToEnv network.varName);
          };
          ipv4.method = "auto";
          ipv6.method = "auto";
        };
      }) config.clanarchy.wifi.networks);
    };
  };
}
