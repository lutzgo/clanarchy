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

  # NOTE: deck's home is NOT rolled back.  birte uses the btrfs
  # impermanence backend (clanarchy.rootfs = "btrfs"), which blanks only
  # @root — see modules/btrfs-impermanence.nix for why: Gaming Mode expects
  # Steam and gamescope state to survive reboots.
  #
  # So there are deliberately no `environment.persistence.users.deck`
  # entries here.  Under the old ZFS layout this block listed .config,
  # .local/share, .local/state and .cache; with a persistent @home those
  # bind-mounts would now shadow the real home directory with an empty
  # /persist/home/deck tree.  The same reasoning is why
  # `clanarchy.gaming.persistenceDirectories` is emptied in
  # configuration.nix.

  # The @games subvol is mounted at deck's Steam library directory (see
  # disko.nix).  A freshly-created btrfs subvolume is root:root 0755, so
  # without this Steam can't write to its own library on a fresh install.
  # tmpfiles runs after local-fs.target, i.e. after the subvol is mounted.
  systemd.tmpfiles.rules = [
    "d /home/deck/.local/share/Steam 0700 deck ${config.users.users.deck.group} -"
  ];

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
