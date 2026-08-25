{lib, ...}: {
  networking.hostName = "miralda";
  networking.hostId = "ebeed95c";
  # DNS: no global `networking.search` — see modules/networking/resolved.nix
  # for the rationale.  The skynet.lan search suffix + Technitium routing
  # attach to the "home" wifi NM profile in modules/networking/skynet-dns-nm.nix.
  time.timeZone = "Europe/Berlin";

  # Locale: English US everywhere (CLI + Noctalia GUI).
  # compose:ralt → Right Alt becomes Compose key for German Umlauts:
  #   Compose " a → ä   Compose " o → ö   Compose " u → ü   Compose s s → ß
  clanarchy.locale = {
    language = "en_US";
    keyboard.layout = "us";
    keyboard.options = "compose:ralt";
  };

  # machine-type and desktop roles are assigned via inventory.instances in clan.nix.
  # wifi networks are provisioned via the clan wifi service (inventory.instances.wifi).
  clanarchy.hardware.cpu = "amd";
  clanarchy.display.scale = 1.25;

  # ZSA Voyager: udev rules for Oryx / Keymapp, plus Keymapp itself.
  # Oryx's *browser* features (live training, web flashing) need WebHID, which
  # librewolf and firefox do not implement — use chromium for those, or
  # Keymapp, which needs no browser at all. See modules/hardware/zsa.nix.
  clanarchy.hardware.zsa.enable = true;

  clanarchy.users.lgo.enable = true;
  clanarchy.users.admin.enable = true;

  # Hybrid-sleep disabled until a swap partition is added to disko.nix.
  # Re-enable (and set boot.resumeDevice) once the swap partition exists.
  clanarchy.roles.laptop.hybridSleep.enable = false;

  # 26.05: pkgsForSystem's config only reaches clanInternals.machines.<sys>.<name>,
  # NOT nixosConfigurations.<name> (which clan machines update uses). So we still
  # have to set allowUnfree at the NixOS module level for the deploy path.
  nixpkgs.config.allowUnfree = true;

  # App categories — package lists and services live in modules/apps/*.nix.
  clanarchy.apps.graphics.simple.enable = true;
  clanarchy.apps.graphics.power.enable = true;
  clanarchy.apps.media.enable = true;
  clanarchy.apps.communication.enable = true;
  clanarchy.apps.containers.enable = true;
  clanarchy.apps.flatpak.enable = true;
  clanarchy.apps.desktopTools.enable = true;

  # ZFS pool alerts via ntfy.sh — URL prompted at `clan vars generate miralda` time.
  clanarchy.zfs.ntfy.enable = true;

  # clan vars generate runs as root, leaving shared vars root-owned.
  # Re-chown after every activation so lgo can enter devShell without sudo.
  system.activationScripts.clanVarsOwnership.text = ''
    chown -R lgo:users /home/lgo/Projects/clanarchy/vars/shared/zerotier-controller || true
  '';

  # OpenTabletDriver — Huion Kamvas Pro 24 (DP-5)
  hardware.opentabletdriver.enable = true;

  # The NixOS OTD module sets Restart=on-failure with no delay.  If the daemon
  # crashes at graphical-session.target activation time (before the session is
  # fully settled), the default burst limit (5 attempts in 10 s) is exhausted
  # immediately and the service stays dead.
  # Fix: restart regardless of exit code (daemon sometimes exits 0 on init
  # failure), 5 s between attempts, 10 attempts per 2-minute window.
  systemd.user.services.opentabletdriver = {
    serviceConfig = {
      Restart = lib.mkForce "always";
      RestartSec = "5s";
    };
    unitConfig = {
      StartLimitBurst = 10;
      StartLimitIntervalSec = 120;
    };
  };

  # hid_uclogic conflicts with OTD when the tablet is connected at boot.
  # boot.blacklistedKernelModules writes to /etc/modprobe.d (main system only);
  # extraModprobeConfig is also embedded in the initrd so the module is
  # suppressed before udev processes the USB device.
  boot.extraModprobeConfig = ''
    blacklist hid_uclogic
    blacklist wacom
  '';

  # Syncthing — run as lgo so it can write to /home/lgo/Public.
  services.syncthing.user = "lgo";
  # Syncthing state survives ZFS rollback.
  environment.persistence."/persist".directories = ["/var/lib/syncthing"];

  system.stateVersion = "25.11";
}
