{ config, pkgs, ... }:
#
# `deck` — the primary user on birte. Jovian wires the Steam gaming session
# to a user named "deck" (see jovian.steam.user in jovian.nix) but does NOT
# declare the underlying NixOS account. This file:
#
#   1. Declares `users.users.deck` with the right home, shell, and groups
#      so Jovian's session can log in.
#   2. Provisions the login password via a clan-vars generator (mirrors
#      admin / sabine).
#   3. Persists the paths that must survive ZFS rollback so HM activation,
#      Plasma settings, and Steam library entries stick.
#   4. Attaches a Home Manager config whose only current purpose is to
#      opt into Stylix's HM auto-enable, so the Plasma 6 desktop and
#      other HM-managed apps pick up the base16 palette declared in
#      stylix.nix.
#
{
  users.users.deck = {
    isNormalUser = true;
    home         = "/home/deck";
    shell        = pkgs.bashInteractive;
    # `gamemode` for Jovian's gamescope-session; the rest are the usual
    # desktop groups so KDE / audio / networking work in Desktop Mode.
    extraGroups  = [ "wheel" "networkmanager" "video" "audio" "input" "gamemode" ];
    hashedPasswordFile =
      config.clan.core.vars.generators.deck-password.files."hashed-password".path;
  };

  # Clan vars: deck password generator
  clan.core.vars.generators.deck-password = {
    files."hashed-password" = {
      secret    = true;
      neededFor = "users";
    };
    prompts."password" = {
      description = "Password for the deck user (sudo + local login in Desktop Mode)";
      type        = "hidden";
    };
    # Pipe via stdin so a leading '-' in the password isn't parsed as a flag.
    script = ''
      ${pkgs.mkpasswd}/bin/mkpasswd -m sha-512 -s < "$prompts/password" > "$out/hashed-password"
    '';
    runtimeInputs = [ pkgs.mkpasswd ];
  };

  # ZFS rolls back to @blank on every boot (see modules/zfs-impermanence.nix).
  # Without these paths, HM state, Plasma dotfiles, and the Steam library
  # would vanish on reboot. The gaming-specific `.steam` entry is added by
  # modules/gaming-common.nix (clanarchy.gaming.enable in configuration.nix).
  environment.persistence."/persist".users.deck = {
    directories = [
      ".config"           # Plasma / KDE config, HM-managed dotfiles
      ".local/share"      # KDE data, Steam's ~/.local/share/Steam library
      ".local/state"      # HM profile symlinks, systemd user state
      ".cache"            # thumbnails, icon cache
    ];
  };

  # Home Manager for `deck`. Stylix's HM auto-enable is the default when the
  # HM integration imports it (see stylix.nix at the NixOS level); autoEnable
  # covers the plasma6/kde, GTK, Qt, cursor, and font targets based on the
  # active base16 scheme.
  home-manager.users.deck = { ... }: {
    home.username      = "deck";
    home.homeDirectory = "/home/deck";
    home.stateVersion  = "25.11";

    stylix.autoEnable = true;
    # Note: stylix.targets.kde is force-disabled for every HM user on birte
    # via home-manager.sharedModules in stylix.nix — see the comment there.
  };
}
