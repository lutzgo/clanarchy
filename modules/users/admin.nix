{ config, lib, pkgs, ... }:
{
  options.clanarchy.users.admin.enable =
    lib.mkEnableOption "admin user profile (SSH keys, zsh, minimal tools)";

  config = lib.mkIf config.clanarchy.users.admin.enable {

    # System-wide HM settings — set here since admin is always the first user enabled
    users.mutableUsers = false;
    home-manager.useGlobalPkgs   = true;
    home-manager.useUserPackages = true;

    users.users.admin = {
      isNormalUser = true;
      extraGroups  = [ "wheel" ];
      shell        = pkgs.zsh;
      hashedPasswordFile = config.clan.core.vars.generators.admin-password.files."hashed-password".path;
      openssh.authorizedKeys.keys = [
        (builtins.readFile ../../machines/miralda/clanarchy_admin.pub)
        (builtins.readFile ../../machines/miralda/yubikey_ed25519.pub)
      ];
    };

    users.users.root = {
      openssh.authorizedKeys.keys = [
        (builtins.readFile ../../machines/miralda/clanarchy_admin.pub)
        (builtins.readFile ../../machines/miralda/yubikey_ed25519.pub)
      ];

      # ── ROOT HAS A PASSWORD SO THE EMERGENCY CONSOLE WORKS ────────────────
      #
      # THE SAME hash as admin, not a second secret: one generator, one prompt,
      # one thing to rotate.  A separate root-password generator would be a
      # second credential that must be remembered at exactly the moment nobody
      # is thinking clearly, and `neededFor = "users"` on the existing one
      # already guarantees the file is present when accounts are created.
      #
      # ── WHY THIS EXISTS: ernst, 2026-08-28 ───────────────────────────────
      #
      # A single failed mount (/srv/audiobooks, M14) took local-fs.target down
      # and put ernst into emergency mode.  systemd offered the console, and
      # sulogin refused it:
      #
      #     Cannot open access to console, the root account is locked.
      #     See sulogin(8) man page for more details.
      #
      # With no password on root there is NO console recovery at all — the
      # keyboard works, there is simply nothing to log into.  sshd does not run
      # in emergency mode (multi-user.target is never reached), and initrd SSH
      # is long gone by then, so every remote path is closed simultaneously.
      # Recovery needed the systemd-boot menu and a previous generation, which
      # is a thin margin: it depends on a 5-second window, a working display
      # and a working keyboard, and on the machine in question the out-of-band
      # KVM was ALSO down.
      #
      # ── THE TRADE, STATED PLAINLY ────────────────────────────────────────
      #
      # This makes root password-authenticatable ON THE LOCAL CONSOLE.  It does
      # NOT open a remote path, and the setting that guarantees that is worth
      # naming precisely, because the obvious one is not sufficient:
      #
      #   PasswordAuthentication = false        modules/base.nix — necessary…
      #   KbdInteractiveAuthentication = true   …but NOT sufficient on its own.
      #                                         It is left at its default, and
      #                                         keyboard-interactive reaches
      #                                         PAM, i.e. the same hash.
      #   PermitRootLogin = "prohibit-password" modules/base.nix — THIS is the
      #                                         operative one.  It rejects
      #                                         password AND keyboard-
      #                                         interactive for root
      #                                         specifically, leaving publickey
      #                                         as root's only remote path.
      #
      # Verified against the built config on 2026-08-28, not read off the
      # module source.  If PermitRootLogin is ever loosened, this line becomes
      # a remote password login and the two changes must be considered
      # together.
      #
      # `users.mutableUsers = false` (above) means this hash is the only thing
      # that can authenticate as root at all — no `passwd` drift.
      #
      # The exposure added is "someone at the physical console can enter the
      # admin password" — on machines where that person can already power-cycle
      # the box, hold a boot menu open and boot an arbitrary generation.  That
      # is a materially smaller capability than the one the lockout removed.
      #
      # FLEET-WIDE, deliberately.  This module is in `commonBase`, so miralda,
      # biene, birte and ernst all get it.  The failure mode is not
      # ernst-specific — any machine that fails a mount lands in the same place,
      # and the laptops are the ones most likely to be far from a console.
      hashedPasswordFile = config.clan.core.vars.generators.admin-password.files."hashed-password".path;
    };

    # Clan vars: SSH key + password generators
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
        secret    = true;
        neededFor = "users";
      };
      prompts."password" = {
        description = "Password for the admin user (used for sudo and local console login)";
        type        = "hidden";
      };
      # Pipe password via stdin so getopt doesn't try to parse passwords that
      # start with '-' (e.g. "-8…") as command-line flags.
      script = ''
        ${pkgs.mkpasswd}/bin/mkpasswd -m sha-512 -s < "$prompts/password" > "$out/hashed-password"
      '';
      runtimeInputs = [ pkgs.mkpasswd ];
    };

    # Impermanence paths for admin
    environment.persistence."/persist".users.admin = {
      directories = [
        ".ssh"
        ".gnupg"
        ".config"
        ".local/share"
        ".cache/noctalia"  # shell-state.json (version tracking → no wizard/changelog on rollback)
        ".cache/zellij"    # compiled WASM + plugin permission cache (avoids "Allow?" prompt on boot)
        "Pictures"         # Noctalia wallpaper manager (Wallpapers subdirectory lives here)
      ];
    };

    # Home Manager configuration
    home-manager.users.admin = { pkgs, ... }: {
      home.username      = "admin";
      home.homeDirectory = "/home/admin";
      home.stateVersion  = "25.11";

      programs.git.enable = true;
      programs.zsh.enable = true;

      home.packages = with pkgs; [ htop ripgrep fd ];
    };
  };
}
