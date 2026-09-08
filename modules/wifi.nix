{ config, lib, pkgs, ... }:
let
  # Convert a varName like "wifi-fritzbox" → env var stem "WIFI_FRITZBOX"
  varStem = varName: lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] varName);
in
{
  options.clanarchy.wifi.networks = lib.mkOption {
    type    = lib.types.listOf (lib.types.submodule {
      options = {
        ssid    = lib.mkOption { type = lib.types.str; description = "WiFi SSID."; };
        varName = lib.mkOption { type = lib.types.str; description = "Clan vars generator name for this network's secrets."; };
        auth    = lib.mkOption {
          type        = lib.types.enum [ "psk" "peap" ];
          default     = "psk";
          description = ''
            "psk" = WPA2-Personal (a single shared password).
            "peap" = WPA2-Enterprise, PEAP/MSCHAPv2 — campus/eduroam-style
            networks authenticating with a per-user identity + password.
          '';
        };
        anonymousIdentity = lib.mkOption {
          type        = lib.types.str;
          default     = "anonymous";
          description = "Outer identity sent before the PEAP tunnel is established. Only used when auth = \"peap\".";
        };
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
        prompts = if network.auth == "peap" then {
          identity = {
            description = "EAP identity (username) for '${network.ssid}'";
            type        = "line";
          };
          password = {
            description = "EAP password for '${network.ssid}'";
            type        = "hidden";
          };
        } else {
          psk = {
            description = "WiFi password for '${network.ssid}'";
            type        = "hidden";
          };
        };
        script =
          let stem = varStem network.varName; in
          if network.auth == "peap" then ''
            printf '${stem}_IDENTITY=%s\n' "$(cat "$prompts/identity")" > "$out/env"
            printf '${stem}_PASSWORD=%s\n' "$(cat "$prompts/password")" >> "$out/env"
          '' else ''
            printf '${stem}_PSK=%s\n' "$(cat "$prompts/psk")" > "$out/env"
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
        value =
          let stem = varStem network.varName; in
          {
            connection = { id = network.ssid; type = "wifi"; };
            wifi       = { ssid = network.ssid; mode = "infrastructure"; };
            ipv4.method = "auto";
            ipv6.method = "auto";
          } // (if network.auth == "peap" then {
            wifi-security = { key-mgmt = "wpa-eap"; };
            # No ca-cert set: equivalent to a GUI "no CA certificate required"
            # choice — the server cert isn't validated. Acceptable on a
            # trusted campus AP; add a ca-cert path here if the institution
            # publishes one and stricter validation is wanted.
            "802-1x" = {
              eap                = "peap";
              phase2-auth        = "mschapv2";
              identity           = "$" + stem + "_IDENTITY";
              anonymous-identity = network.anonymousIdentity;
              password           = "$" + stem + "_PASSWORD";
            };
          } else {
            wifi-security = {
              auth-alg = "open";
              key-mgmt = "wpa-psk";
              psk      = "$" + stem + "_PSK";
            };
          });
      }) config.clanarchy.wifi.networks);
    };
  };
}
