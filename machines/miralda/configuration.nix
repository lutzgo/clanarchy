{ lib, ... }:
{
  networking.hostName = "miralda";
  networking.hostId  = "ebeed95c";
  networking.search  = [ "skynet.lan" ];
  time.timeZone      = "Europe/Berlin";

  # Locale: English US everywhere (CLI + Noctalia GUI).
  # compose:ralt → Right Alt becomes Compose key for German Umlauts:
  #   Compose " a → ä   Compose " o → ö   Compose " u → ü   Compose s s → ß
  clanarchy.locale = {
    language         = "en_US";
    keyboard.layout  = "us";
    keyboard.options = "compose:ralt";
  };

  # machine-type and desktop roles are assigned via inventory.instances in clan.nix.
  # wifi networks are provisioned via the clan wifi service (inventory.instances.wifi).
  clanarchy.hardware.cpu       = "amd";
  clanarchy.users.lgo.enable   = true;
  clanarchy.users.admin.enable = true;

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
      Restart    = lib.mkForce "always";
      RestartSec = "5s";
    };
    unitConfig = {
      StartLimitBurst       = 10;
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
  environment.persistence."/persist".directories = [ "/var/lib/syncthing" ];

  system.stateVersion = "25.11";
}
