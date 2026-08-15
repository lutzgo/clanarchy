# `go` — the couch user on ernst.
#
# ernst is primarily a headless NAS / VM host / GPU compute box; the HTPC
# stack is a second role layered on top (see roles.htpc in clan.nix and
# modules/roles/htpc.nix).  This file declares the user that role drives,
# the same way machines/birte/deck.nix declares `deck` for Jovian.
#
# Deliberately NOT in `wheel`: this account exists to sit in front of a TV.
# `roles/server.nix` sets `security.sudo.execWheelOnly`, so keeping `go` out
# of wheel means the living-room session cannot sudo even though the machine
# it runs on fronts the storage array.  The switcher doesn't need it — the
# session state dir is user-owned and the display-manager restart is granted
# by a narrow polkit rule in the role module.
{ config, pkgs, ... }:
{
  users.users.go = {
    isNormalUser = true;
    home = "/home/go";
    shell = pkgs.bashInteractive;
    # video/audio/input for the session; gamemode for gamescope's scheduling
    # hints.  No wheel, no networkmanager (ernst is networkd + wired).
    extraGroups = [ "video" "audio" "input" "gamemode" ];
    hashedPasswordFile =
      config.clan.core.vars.generators.go-password.files."hashed-password".path;
  };

  clan.core.vars.generators.go-password = {
    files."hashed-password" = {
      secret = true;
      neededFor = "users";
    };
    prompts."password" = {
      description = "Password for the go user (local login on the TV)";
      type = "hidden";
    };
    # Pipe via stdin so a leading '-' in the password isn't parsed as a flag.
    script = ''
      ${pkgs.mkpasswd}/bin/mkpasswd -m sha-512 -s < "$prompts/password" > "$out/hashed-password"
    '';
    runtimeInputs = [ pkgs.mkpasswd ];
  };

  # ernst's root rolls back to @blank each boot, but /home is a separate
  # dataset that does not — so Steam's library, Plasma config and HM state
  # under /home/go persist without any impermanence bind-mounts.  This
  # matches the reasoning in machines/birte/deck.nix.
  #
  # The Steam library itself belongs on the bulk pool rather than on zroot:
  # zdata/games already exists for exactly this (see machines/ernst/disko.nix,
  # "future Steam library"), and a mirrored 960 GB system pool is the wrong
  # place for hundreds of GB of games.
  systemd.tmpfiles.rules = [
    "d /srv/games/go 0700 go users - -"
    "L+ /home/go/.local/share/Steam - - - - /srv/games/go"
  ];
}
