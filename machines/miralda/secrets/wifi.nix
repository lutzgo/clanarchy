{ pkgs, ... }:
{
  clan.core.vars.generators.wifi-home = {
    files."env" = {
      secret = true;
    };

    prompts."psk" = {
      description = "WiFi password for 'skynet'";
      type = "hidden";
    };

    script = ''
      printf 'WIFI_HOME_PSK=%s\n' "$(cat "$prompts/psk")" > "$out/env"
    '';
  };
}
