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

  # ernst rolls back BOTH zroot/root and zroot/home to @blank on every boot
  # (modules/zfs-impermanence.nix), so /home/go is wiped each time and only
  # what is declared here survives.  This is the fleet's normal posture and
  # is kept deliberately: the couch account's state stays auditable instead
  # of accumulating whatever Steam and Plasma happen to drop in $HOME.
  #
  # Everything Gaming Mode needs to not re-onboard on every reboot:
  environment.persistence."/persist".users.go = {
    directories = [
      ".config"      # Plasma / KDE config, gamescope + Steam client settings
      ".local/share" # Steam client data (the library itself is symlinked out, below)
      ".local/state" # systemd user state
      # ".steam" is contributed by modules/gaming-common.nix via
      # clanarchy.gaming.persistenceDirectories — not repeated here.
      ".cache"       # shader caches — re-derivable, but recompiling them on
                     # every boot is exactly the stutter this box exists to avoid
    ];
  };

  # The library itself belongs on the bulk pool, not on zroot: zdata/games
  # already exists for exactly this (see machines/ernst/disko.nix, "future
  # Steam library"), and a mirrored 960 GB system pool is the wrong place for
  # hundreds of GB of games.
  #
  # `L+` forces the symlink each boot, so it is re-established after the
  # rollback regardless of what the persisted .local/share contains.
  systemd.tmpfiles.rules = [
    "d /srv/games/go 0700 go users - -"
    "L+ /home/go/.local/share/Steam - - - - /srv/games/go"
  ];
}
