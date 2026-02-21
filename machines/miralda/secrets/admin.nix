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
}
