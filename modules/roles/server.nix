{ config, lib, ... }:
{
  options.clanarchy.roles.server = {
    enable = lib.mkEnableOption "server role (headless, SSH, no GUI)";
  };

  config = lib.mkIf config.clanarchy.roles.server.enable {

    services.openssh = {
      enable   = true;
      settings = {
        PasswordAuthentication = false;
        PermitRootLogin        = "prohibit-password";
      };
    };

    nix.settings.auto-optimise-store = true;

    nix.gc = {
      automatic = true;
      dates     = "weekly";
      options   = "--delete-older-than 30d";
    };

    # ── Headless hardening ────────────────────────────────────────────────
    # Only wheel members may run sudo (a non-wheel user with a granting
    # sudoers rule would otherwise still work).  Server has no interactive
    # non-wheel users by design; this closes the gap explicitly.
    security.sudo.execWheelOnly = true;

    # Restrict who may talk to nix-daemon.  Default is "*" — meaning any
    # local user can build/derive/import store paths.  On a multi-tenant
    # host that quickly becomes a substitution/eval DoS surface.  Only
    # admins ever need to nix-build here; services run their own pinned
    # store paths already resolved by the system closure.
    nix.settings.allowed-users = [ "@wheel" ];

    # NixOS injects a default package set (perl, rsync, strace, …) into
    # every system's PATH via environment.defaultPackages.  On a headless
    # server we want an empty baseline and to opt in explicitly per module
    # (e.g. pciutils / smartmontools in configuration.nix).  mkForce so
    # this beats the nixpkgs default without needing higher priority than
    # any downstream additions (those still layer in via systemPackages).
    environment.defaultPackages = lib.mkForce [ ];
  };
}
