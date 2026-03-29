{ config, ... }:
{
  networking.networkmanager.ensureProfiles = {
    environmentFiles = [ config.clan.core.vars.generators.wifi-home.files."env".path ];
    profiles."skynet" = {
      connection = {
        id = "skynet";
        type = "wifi";
      };
      wifi = {
        ssid = "skynet";
        mode = "infrastructure";
      };
      wifi-security = {
        auth-alg = "open";
        key-mgmt = "wpa-psk";
        psk = "$WIFI_HOME_PSK";
      };
      ipv4.method = "auto";
      ipv6.method = "auto";
    };
  };
}
