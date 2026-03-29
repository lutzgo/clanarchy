{ pkgs, ... }:
{
  clan.core.vars.generators.lgo-password = {
    files."hashed-password" = {
      secret = true;
      neededFor = "users";
    };

    prompts."password" = {
      description = "Password for the lgo user (used for sudo and local console login)";
      type = "hidden";
    };

    script = ''
      ${pkgs.mkpasswd}/bin/mkpasswd -m sha-512 "$(cat "$prompts/password")" > "$out/hashed-password"
    '';

    runtimeInputs = [ pkgs.mkpasswd ];
  };
}
