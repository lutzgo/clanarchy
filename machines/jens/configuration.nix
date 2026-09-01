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
  # PARTUUID is the GPT partition GUID and is unique per partition, so it only
  # exists once disko has actually partitioned this disk.  Fill it in after
  # `clan machines install jens`:
  #   ssh root@jens.skynet.lan lsblk -o NAME,PARTUUID /dev/nvme0n1
  # and it must be updated again if jens is ever reinstalled.
  #
  # TODO(install): replace with the real PARTUUID and drop this comment.
  # fileSystems."/boot".device =
  #   lib.mkForce "/dev/disk/by-partuuid/________-____-____-____-____________";

  # ZFS pool alerts via ntfy.sh — URL prompted at `clan vars generate jens` time.
  clanarchy.zfs.ntfy.enable = true;

  # Hand big compiles to ernst — 32 cores and 249 GB, versus this machine's
  # 2P+8E cores.  More lopsided here than on miralda, so more worth having.
  clanarchy.remoteBuilder.client.enable = true;

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
