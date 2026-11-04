{lib, ...}: {
  # All clanarchy machines target x86_64-linux. Machines that have a
  # generated facter.json can still override this (mkDefault → lower priority).
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

  # ── THE FLEET'S OVERLAY, APPLIED WHERE IT ACTUALLY TAKES EFFECT ─────────
  #
  #   clan.nix's `pkgsForSystem` builds an instance with lib/overlays.nix and
  #   much of this repo was written assuming every machine used it ("nixpkgs.
  #   overlays is ignored once pkgsForSystem supplies pkgs").  With clan-core
  #   main that is FALSE: pkgsForSystem reaches only `configsPerSystem` (the
  #   copies vars generators run in, via overridePkgs.nix).  The real
  #   `nixosConfigurations.<name>` — what `clan machines update` deploys —
  #   never set `nixpkgs.pkgs` and evaluated plain nixpkgs.
  #
  #   So the overlay had silently stopped applying anywhere.  Found 2026-11-04
  #   from its most visible casualty: ungoogled-chromium without
  #   `--extension-mime-request-handling=always-prompt-for-install`, which
  #   ignores External Extensions — not one of lgo's eight extensions
  #   installed on jens.  The same miss took the Steam-Runtime wrappers
  #   (chromium, google-chrome, eden on birte), niri's checkPhase skip and the
  #   posthog test fix with it.  allowUnfree had hit the same wall earlier and
  #   was patched per machine; the overlay never was.
  #
  #   Setting it here as well as in pkgsForSystem is not a duplicate that can
  #   double-apply: in configsPerSystem `nixpkgs.pkgs` is forced and these
  #   options are inert; everywhere else these are the only ones in force.
  #   The posthog handler pairs with the overlay's test fix, as in clan.nix.
  nixpkgs.overlays = [(import ../lib/overlays.nix)];
  nixpkgs.config.problems.handlers.posthog.broken = "warn";

  nix.settings.experimental-features = ["nix-command" "flakes"];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.plymouth.enable = true;
  boot.kernelParams = ["quiet" "splash"];

  home-manager.backupFileExtension = "bak";

  # Home Manager 26.11 vs Nixpkgs 26.05 — HM is intentionally ahead of the
  # clan-core-pinned nixpkgs.  Silence the per-profile version-mismatch
  # warning for every HM user in the clan; we track HM upstream manually.
  home-manager.sharedModules = [{home.enableNixpkgsReleaseCheck = false;}];

  # Make zsh available as a valid login shell (/etc/shells) for use as fallback.
  programs.zsh.enable = true;

  # SSH hardening — clan sshd service adds keys; these settings lock down auth.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
    };
  };

  # userborn creates users declaratively instead of NixOS's perl activation
  # script.  It is NOT compatible with impermanence under default settings
  # (https://github.com/nix-community/impermanence/pull/223), and every
  # clanarchy machine is impermanent.
  #
  # 26.05 leaves it off, so this is currently a no-op — it is here to keep a
  # future nixpkgs or clan-core default flip from silently breaking user
  # creation across the whole fleet.  srvos guards the same way, disabling
  # userborn whenever it detects `options.environment ? persistence`; we can
  # state it unconditionally because impermanence is universal here.
  #
  # If this is ever lifted, it must be paired with impermanence's
  # userborn-compatible settings — not simply deleted.
  services.userborn.enable = false;

  # Force /tmp to 1777, because nothing else in the stack actually does.
  #
  # SYSTEMD ALREADY SHIPS A RULE FOR THIS AND IT DOES NOT WORK ON AN EXISTING
  # DIRECTORY. /etc/tmpfiles.d/tmp.conf carries `q /tmp 1777 root root 10d`,
  # and `q` applies its mode when it CREATES the directory — it does not
  # correct one that is already there. Measured on ernst 2026-09-14 by
  # breaking /var/tmp (which carries the identical rule) to 0755 and running
  # `systemd-tmpfiles --create --remove --boot`: it stayed 0755. The same test
  # with `z` restored it to 1777, which is why this is a `z` and not a `d`.
  #
  # `z` adjusts mode and ownership of a path that exists, and does nothing if
  # it does not. NOT `Z` — that is the recursive form, and recursively
  # chmod'ing everything under /tmp on every boot would be both slow and
  # destructive.
  #
  # WHY THIS BITES HERE SPECIFICALLY: modules/disko/base.nix gives /tmp its
  # own ZFS dataset, and a fresh dataset's root inode is 0755. Whether a given
  # machine ends up correct is therefore down to how its pool was created —
  # miralda is 1777, ernst was 0755 — and the ones that are wrong stay wrong
  # forever, because the shipped rule never revisits them.
  #
  # HOW IT PRESENTS, which is the reason this is worth a paragraph: it does
  # not look like a permissions problem. On ernst it looked like a broken
  # Steam session — the display manager came up, gamescope segfaulted, and the
  # TV went black. The actual chain was that no non-root user could create a
  # file in /tmp, so Xwayland could not take an X display lock for any of the
  # first 33 slots, wlroots returned NULL, and gamescope dereferenced it:
  #
  #   Error wlserver: [xwayland/sockets.c:217] No display available in the first 33
  #   .gamescope-wrapped … SIGSEGV
  #
  # A no-op on a machine whose /tmp is already correct, which is most of them.
  systemd.tmpfiles.rules = ["z /tmp 1777 root root -"];
}
