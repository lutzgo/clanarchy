{ pkgs, ... }:
{
  clan.core.vars.generators.admin-ssh = {
    files."id_ed25519".secret = true;
    files."id_ed25519.pub".secret = false;

    script = ''
      mkdir -p "$out"
      ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -N "" -f "$out/id_ed25519"
    '';

    runtimeInputs = [ pkgs.openssh ];
  };

  clan.core.vars.generators.admin-password = {
    files."hashed-password" = {
      secret = true;
      neededFor = "users";
    };

    prompts."password" = {
      description = "Password for the admin user (used for sudo and local console login)";
      type = "hidden";
    };

    script = ''
      ${pkgs.mkpasswd}/bin/mkpasswd -m sha-512 "$(cat "$prompts/password")" > "$out/hashed-password"
    '';

    runtimeInputs = [ pkgs.mkpasswd ];
  };
}
