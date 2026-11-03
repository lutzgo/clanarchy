# `config` is taken so the niri appearance block below can read the active
# Stylix palette (config.lib.stylix.colors) instead of hardcoding hex.
{
  config,
  lib,
  ...
}: {
  networking.hostName = "miralda";
  # No networking.hostId: that is a ZFS requirement (it keys pool ownership).

  # btrfs on LVM on LUKS, with the impermanence rollback that goes with it.
  # See machines/miralda/disko.nix. boot.resumeDevice is set by disko, to the
  # swap LV inside the LUKS container.
  clanarchy.rootfs = "btrfs";

  # One passphrase at boot: the LUKS passphrase systemd-cryptsetup cached is
  # reused to unlock gnome-keyring after autologin.
  #
  # Your user password MUST equal the LUKS passphrase. Nothing checks it; a
  # mismatch means login succeeds and the keyring quietly stays locked.
  clanarchy.singlePasswordBoot = {
    enable = true;
    user = "lgo";
    # The .desktop Exec line, not the session name — see the option docs.
    command = "uwsm start -F -- /run/current-system/sw/bin/niri-session";
  };

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

  # Stylix palette + polarity. Valid names are the keys of
  # modules/themes/palettes.nix; "selenized-black" is what this machine ran
  # before, and reverting is this one word.
  clanarchy.theme = "rose-pine";

  # lgo's niri look: an accent-coloured glow instead of a drop shadow (the
  # shadow takes the palette's base0D at alpha 0x50, no offset), no border and
  # no focus ring, stronger blur, 10px corners. jens carries the same block —
  # keep the two in step.
  clanarchy.desktop.niri = {
    shadow = {
      enable = true;
      softness = 15;
      spread = 3;
      offset.y = 0;
      offset.x = 0;
      color = "#${config.lib.stylix.colors.base0D}50";
      unfocused = {
        enable = false;
      };
      bar.enable = true;
    };
    blur = {
      passes = 5;
      offset = 6.5;
      noise = 0.0;
      saturation = 1.5;
    };
    cornerRadius = 10.0;
    border = {
      enable = false;
      width = 0;
    };
    opacity = {
      focused = 0.75;
      unfocused = 0.65;
      terminal = 0.75;
    };
    focusRing.enable = false;
  };

  # ZSA Voyager: udev rules for Oryx / Keymapp, plus Keymapp itself.
  # Oryx's *browser* features (live training, web flashing) need WebHID, which
  # librewolf and firefox do not implement — use chromium for those, or
  # Keymapp, which needs no browser at all. See modules/hardware/zsa.nix.
  clanarchy.hardware.zsa.enable = true;

  clanarchy.users.lgo.enable = true;
  clanarchy.users.admin.enable = true;

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

  # M22 — the darktable end of the photo pipeline.  Finished JPEG exports
  # dropped into ~/Pictures/immich-inbox are pushed to Immich on ernst by a
  # timer; see modules/immich-upload.nix.
  #
  # Enabling this declares the `immich-api-key` generator, whose prompt cannot
  # be answered until Immich is deployed and its accounts exist — a DEADLOCK,
  # not an ordering hazard, because a pending prompt blocks the deploy of every
  # machine in the flake.  That module's header and SN5 own the explanation;
  # the two-step turn-on is `clan vars generate miralda --generator
  # immich-api-key` and then `clan machines update miralda`, in that order,
  # at a TTY, never answered blank.
  clanarchy.immich.upload.enable = true;

  # Mount the ESP by DISK-ID — not by the partlabel disko assigns, and not by
  # PARTUUID.  modules/disko/btrfs.nix owns the partlabel ambiguity
  # (`disk-main-ESP` on every machine in the fleet and on every installer
  # stick) and what it costs.
  #
  # THIS WAS A PARTUUID UNTIL TODAY, AND THAT IS A TRAP ON REINSTALL — the one
  # jens hit on 2026-09-22 and moved off.  PARTUUID is minted afresh by each
  # `mkfs`, so the value goes stale the moment `clan machines install` re-runs
  # disko, and the machine comes up with a /boot device that does not exist.
  # Worse, it is circular: the new PARTUUID can only be read off the installed
  # machine, and updating it needs a deploy the machine must boot to accept.
  #
  # The disk-id path has neither problem: it names model+serial, so it can
  # never resolve to a USB stick, and the partition number is fixed by
  # modules/disko/btrfs.nix (ESP is always partition 1).  Survives reinstalls
  # untouched.  Same device string as machines/miralda/disko.nix, plus `-part1`
  # — verified to resolve to the same /dev/nvme0n1p1 the PARTUUID did.
  fileSystems."/boot".device =
    lib.mkForce "/dev/disk/by-id/nvme-WD_BLACK_SN850X_1000GB_23141B801914-part1";

  # No clanarchy.zfs.ntfy: its zedlet reads ZFS-event variables (ZEVENT_*),
  # and btrfs has no equivalent hook.

  # Hand big compiles (birte's Valve kernel above all) to ernst — 32 cores
  # and 249 GB, versus this machine's 16 cores and frequently <8 GB free.
  clanarchy.remoteBuilder.client.enable = true;

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
      # mkForce since 26.11: upstream now sets RestartSec = 3 itself.
      RestartSec = lib.mkForce "5s";
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
