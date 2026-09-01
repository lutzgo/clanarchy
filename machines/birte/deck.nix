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

  # deck's home is rolled back to blank on every boot, same as every other
  # machine in the fleet (modules/btrfs-impermanence.nix blanks @root and
  # @home).  Only what is declared here survives, so HM state, Plasma
  # dotfiles and the Steam client's own data must be listed explicitly.
  # `.steam` is contributed separately by modules/gaming-common.nix via
  # clanarchy.gaming.persistenceDirectories.
  environment.persistence."/persist".users.deck = {
    directories = [
      ".config"      # Plasma / KDE config, HM-managed dotfiles
      ".local/share" # KDE data + Steam client data (library is symlinked out)
      ".local/state" # HM profile symlinks, systemd user state
      ".cache"       # shader caches — re-derivable, but recompiling them on
                     # every boot is exactly the stutter a Deck must avoid

      # Flatpak's per-app state.  Every Flatpak app keeps its config, data and
      # cache under ~/.var/app/<app-id>/ and NOTHING else — none of it lands
      # in .config or .local/share, so the four entries above do not cover it.
      # /var/lib/flatpak (persisted by modules/apps/flatpak.nix) keeps the
      # installed *apps* across a rollback; without this line they came back
      # every boot freshly installed and completely unconfigured.
      #
      # RetroDECK is the case that exposed it: its entire configuration,
      # including which data folder it was pointed at, lives in
      # ~/.var/app/net.retrodeck.retrodeck/config/retrodeck/retrodeck.cfg.
      ".var/app"
    ];
  };

  # The game library lives on the @games subvol mounted at /games (see
  # disko.nix), outside the rollback path and outside the impermanence
  # bind-mounts.  A freshly-created btrfs subvolume is root:root 0755, so
  # without the `d` rule Steam can't write to its own library.
  #
  # `L+` forces the symlink each boot, so it is re-established after the
  # rollback regardless of what the persisted .local/share contains.
  systemd.tmpfiles.rules = [
    "d /games 0700 deck ${config.users.users.deck.group} - -"
    "L+ /home/deck/.local/share/Steam - - - - /games"

    # Decky injects its UI into the Steam client through Steam's CEF remote
    # debugger, which Steam only exposes when this marker file exists. Without
    # it decky-loader runs, listens on 1337 and logs
    #   [wsrouter][WARNING]: Dropping message as there is no connected socket
    # while never appearing in the Quick Access Menu — it looks for all the
    # world like Decky is simply not installed.
    #
    # Steam resolves ~/.steam/steam to /games here, so the marker lands on the
    # @games subvol and survives the rollback on its own.
    "f /games/.cef-enable-remote-debugging 0644 deck ${config.users.users.deck.group} - -"

    # RetroDECK's data folder — ROMs, BIOS, saves, states, scraped media.
    # Same reasoning as the Steam library above: it belongs on @games, which
    # is outside the rollback path, outside the impermanence bind-mounts, and
    # carries nodatacow.  A ROM library is exactly the "large files, plenty of
    # them" case that subvolume exists for, and putting it under /persist
    # instead would mix a media library in with system state.
    #
    # The symlink means RetroDECK's first-run wizard can be answered with its
    # default "Internal" option — ~/retrodeck already resolves onto the right
    # subvolume, so there is no custom path to remember or re-enter after a
    # reinstall.  `L+` re-forces it every boot, after the rollback.
    #
    # Layout note: the tree RetroDECK creates here (roms/<system>/, bios/) is
    # deliberately also a valid RomM library root — see the ROM-library
    # section in docs/guides/birte-emulation.md.
    "d /games/retrodeck 0700 deck ${config.users.users.deck.group} - -"
    "L+ /home/deck/retrodeck - - - - /games/retrodeck"
  ];

  # Home Manager for `deck`. Stylix's HM auto-enable is the default when the
  # HM integration imports it (see stylix.nix at the NixOS level); autoEnable
  # covers the plasma6/kde, GTK, Qt, cursor, and font targets based on the
  # active base16 scheme.
  home-manager.users.deck = { config, lib, ... }: {
    home.username      = "deck";
    home.homeDirectory = "/home/deck";
    home.stateVersion  = "25.11";

    stylix.autoEnable = true;

    # ── ~/.gtkrc-2.0: overwrite, never back up ───────────────────────────────
    #
    # Plasma rewrites this file itself.  `kde-gtk-config` regenerates
    # ~/.gtkrc-2.0 during the desktop session so GTK2 apps follow the Plasma
    # theme, which means the file HM manages is replaced, by another program,
    # between one activation and the next.
    #
    # HM's response to finding an unmanaged file where it expects its own is to
    # move it aside using `home-manager.backupFileExtension` (set to "bak" in
    # modules/base.nix).  That works exactly once.  On the next deploy the
    # backup is already there and activation fails outright:
    #
    #   Existing file '/home/deck/.gtkrc-2.0.bak' would be clobbered by
    #   backing up '/home/deck/.gtkrc-2.0'
    #   home-manager-deck.service: Failed with result 'exit-code'
    #
    # which takes the whole user profile down — Stylix theming included — over
    # a file whose contents nobody wanted preserved.  Hit on birte on
    # 2026-09-01; the stale .bak dated from the previous deploy.
    #
    # `force = true` makes HM overwrite instead of backing up, which is the
    # right answer specifically because the file being discarded is generated:
    # Plasma writes it again at the next session start regardless.  It is the
    # remedy HM's own error message suggests.
    #
    # The key is the ABSOLUTE path, not ".gtkrc-2.0" — HM's gtk2 module
    # declares it as `home.file.${cfg2.configLocation}` and configLocation
    # defaults to "${config.home.homeDirectory}/.gtkrc-2.0".  A relative key
    # would silently create a SECOND, unrelated entry and fix nothing.
    #
    # mkForce because that same module sets `force = false` EXPLICITLY rather
    # than leaving it at its default, so a plain `true` is a conflict, not an
    # override:
    #   The option `…force' has conflicting definition values:
    #     - In `machines/birte/deck.nix': true
    #     - In `home-manager/modules/misc/gtk/gtk2.nix': false
    home.file."${config.home.homeDirectory}/.gtkrc-2.0".force = lib.mkForce true;

    # No screen lock. The Deck has no keyboard attached in Desktop Mode, and
    # the deck password only exists as a sha-512 hash in clan vars — nobody
    # can look it up, so a lock screen here is a lockout, not a security
    # boundary. Gaming Mode is the normal session and never locks anyway.
    xdg.configFile."kscreenlockerrc".text = ''
      [Daemon]
      Autolock=false
      LockOnResume=false
    '';
    # Note: stylix.targets.kde is force-disabled for every HM user on birte
    # via home-manager.sharedModules in stylix.nix — see the comment there.
  };
}
