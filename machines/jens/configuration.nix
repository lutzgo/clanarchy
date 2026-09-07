{ lib, ... }: {
  networking.hostName = "jens";
  networking.hostId = "f815e992";
  # DNS: no global `networking.search` — see modules/networking/resolved.nix
  # for the rationale.  The skynet.lan search suffix + Technitium routing
  # attach to the "home" wifi NM profile in modules/networking/skynet-dns-nm.nix.
  time.timeZone = "Europe/Berlin";

  # Locale: English US everywhere (CLI + Noctalia GUI) — same as miralda.
  # compose:ralt → Right Alt becomes Compose key for German Umlauts:
  #   Compose " a → ä   Compose " o → ö   Compose " u → ü   Compose s s → ß
  clanarchy.locale = {
    language = "en_US";
    keyboard.layout = "us";
    keyboard.options = "compose:ralt";
  };

  # machine-type and desktop roles are assigned via inventory.instances in clan.nix.
  # wifi networks are provisioned via the clan wifi service (inventory.instances.wifi).
  #
  # Framework Laptop 12 is Intel (Raptor Lake U) where miralda is AMD.  That
  # single line does more than microcode: modules/roles/laptop.nix reads it to
  # pick the GPU baseline (intel-media-driver rather than amdgpu + Rusticl) and
  # to enable thermald, which is Intel-only.
  clanarchy.hardware.cpu = "intel";

  # 1920×1200 on a 12.2" panel is ~186 PPI — close enough to miralda's 201 that
  # it wants the same treatment: 80×25 boot menu and a ter-v24n console font.
  clanarchy.display.scale = 1.25;

  # Stylix palette + polarity — see modules/themes/palettes.nix for the
  # registry. Stated explicitly rather than left to the option default so the
  # two Niri workstations declare their palettes the same way.
  clanarchy.theme = "selenized-black";

  # 2-in-1: accelerometer + auto-rotation + on-screen keyboard.
  # See modules/hardware/convertible.nix; the Niri bind that summons the OSK
  # (Mod+O) is guarded on this same option in modules/desktop/niri-hm.nix.
  clanarchy.hardware.convertible.enable = true;

  # ZSA Voyager: udev rules for Oryx / Keymapp, plus Keymapp itself.
  # Oryx's *browser* features (live training, web flashing) need WebHID, which
  # librewolf and firefox do not implement — use chromium for those, or
  # Keymapp, which needs no browser at all. See modules/hardware/zsa.nix.
  clanarchy.hardware.zsa.enable = true;

  clanarchy.users.lgo.enable = true;
  clanarchy.users.admin.enable = true;

  # Hybrid-sleep disabled: disko.nix lays down no swap partition, matching
  # miralda.  Re-enable together with `enableSwap` + `boot.resumeDevice` if
  # suspend-to-disk is ever wanted here.
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

  # Mount the ESP by PARTUUID, not by the partlabel disko assigns.
  #
  # Every machine in this clan uses disko's disk name `main`, so every ESP in
  # the fleet is labelled `disk-main-ESP` — including the ones on Clan
  # installer USB sticks, which are flashed with `--disk main`. Plug a stick
  # into this machine and udev resolves
  # /dev/disk/by-partlabel/disk-main-ESP to whichever device it saw last,
  # which is how miralda ended up with the installer's ESP mounted at /boot.
  # A bootloader update in that window writes to the USB stick instead of the
  # internal drive: it corrupts the installer and leaves the real ESP stale,
  # and nothing warns you.
  #
  # PARTUUID is the GPT partition GUID and is unique per partition. It is
  # regenerated if this disk is ever repartitioned, so a reinstall of jens
  # means updating the value below — `lsblk -o NAME,PARTUUID /dev/nvme0n1`.
  # Read off the installed system on 2026-09-01.
  fileSystems."/boot".device =
    lib.mkForce "/dev/disk/by-partuuid/1012baa5-1831-4ca4-8bbc-13eb1b056f88";

  # ZFS pool alerts via ntfy.sh — URL prompted at `clan vars generate jens` time.
  clanarchy.zfs.ntfy.enable = true;

  # Hand big compiles to ernst — 32 cores and 249 GB, versus this machine's
  # 2P+8E cores.  More lopsided here than on miralda, so more worth having.
  clanarchy.remoteBuilder.client.enable = true;

  # OpenTabletDriver — Huion Kamvas Pro 24 (DP-5), same as miralda.  The
  # tablet lives on the desk rather than travelling, so this only does
  # anything when jens is docked there; the daemon is cheap when no tablet
  # is attached.
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
  #
  # DELIBERATELY NARROWER THAN MIRALDA, which also blacklists `wacom`.  That
  # is free on miralda, which has no built-in digitizer — but jens does, and
  # some convertible panels drive their active pen through exactly that
  # module.  Blacklisting it there risks trading a working stylus for a
  # conflict that only `hid_uclogic` actually causes.  If the Huion turns out
  # to misbehave on jens in a way `hid_uclogic` alone does not explain, check
  # `lsmod | grep wacom` with the pen working before adding it.
  boot.extraModprobeConfig = ''
    blacklist hid_uclogic
  '';

  # clan vars generate runs as root, leaving shared vars root-owned.
  # Re-chown after every activation so lgo can enter devShell without sudo.
  system.activationScripts.clanVarsOwnership.text = ''
    chown -R lgo:users /home/lgo/Projects/clanarchy/vars/shared/zerotier-controller || true
  '';

  # Syncthing — run as lgo so it can write to /home/lgo/Public.
  services.syncthing.user = "lgo";
  # Syncthing state survives ZFS rollback.
  environment.persistence."/persist".directories = [ "/var/lib/syncthing" ];

  system.stateVersion = "25.11";
}
