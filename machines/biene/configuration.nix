{ lib, pkgs, ... }:
{
  networking.hostName = "biene";
  networking.hostId   = "cd9ef50b";
  networking.search   = [ "skynet.lan" ];

  # No targetHost set — clan auto-discovers biene via ZeroTier (same as miralda).
  # For initial deploy or when ZeroTier is unreachable, use:
  #   BIENE_HOST=biene.local deploy-biene
  time.timeZone = "Europe/Berlin";

  # Locale: German everywhere (CLI + GNOME UI).
  # de layout for GDM; GNOME input-sources (in gnome.nix) adds us as secondary.
  clanarchy.locale = {
    language        = "de_DE";
    keyboard.layout = "de";
  };

  # See miralda: pkgsForSystem's config doesn't propagate to nixosConfigurations,
  # which is what clan machines update uses.
  nixpkgs.config.allowUnfree = true;

  # machine-type (laptop, no Framework hw) and desktop (gnome + sabine dconf)
  # are assigned via inventory.instances in clan.nix.
  # Home wifi is provisioned via the clan wifi service (clan.nix).
  # Fritz!Box is biene-specific — managed via the bespoke modules/wifi.nix.
  clanarchy.hardware.cpu              = "intel";
  clanarchy.users.admin.enable        = true;
  clanarchy.desktop.labwc.valent.enable = true;

  # Fritz!Box 7590 MX — biene-specific second wifi network.
  # Run `clan vars generate biene --generator wifi-fritzbox` to store the PSK.
  clanarchy.wifi.networks = [
    { ssid = "Fritz!Box 7590 MX"; varName = "wifi-fritzbox"; }
  ];

  # Syncthing — run as sabine so it can write to /home/sabine/Public.
  services.syncthing.user = "sabine";

  # Lid close → shut down (Sabine's preference), overriding the laptop-role
  # default of hybrid-sleep on battery / suspend on AC. Disabling hybridSleep
  # also drops the now-unused HibernateMode=shutdown sleep setting.
  # Docked behaviour (HandleLidSwitchDocked) keeps the systemd default: ignore.
  clanarchy.roles.laptop.hybridSleep.enable = false;
  services.logind.settings.Login.HandleLidSwitch              = lib.mkForce "poweroff";
  services.logind.settings.Login.HandleLidSwitchExternalPower = lib.mkForce "poweroff";

  # Swap partition is retained for memory pressure only; resumeDevice is left
  # set so re-enabling hibernation later is a one-line change.
  boot.resumeDevice = "/dev/disk/by-partlabel/disk-main-swap";

  # Removable-media filesystem compatibility (USB sticks, SD cards, externals
  # handed over from Windows / Android / older Macs). Adds native kernel
  # drivers; userspace tools are added to systemPackages below.
  boot.supportedFilesystems = [ "ntfs" "exfat" "vfat" "f2fs" "hfsplus" ];

  # Force udisks2 (and every other mount consumer) to route NTFS through
  # ntfs-3g FUSE instead of the in-kernel ntfs3 driver. ntfs3 refuses to
  # mount volumes with a dirty $LogFile (common after Windows fast-startup
  # or an unclean unplug) and udisks2 has no fallback, so Nautilus just
  # errors out. ntfs-3g replays the journal automatically. Trade-off: FUSE
  # is slower than the kernel driver on large sequential I/O — unnoticeable
  # for removable media, worth the graceful recovery.
  services.udev.extraRules = ''
    SUBSYSTEM=="block", ENV{ID_FS_TYPE}=="ntfs", ENV{ID_FS_TYPE}="ntfs-3g"
  '';

  # App categories — package lists and services live in modules/apps/*.nix.
  clanarchy.apps.graphics.simple.enable = true;
  clanarchy.apps.media.enable           = true;
  clanarchy.apps.gnomeCoreApps.enable   = true;
  clanarchy.apps.desktopTools.enable    = true;
  clanarchy.apps.flatpak.enable         = true;

  # GUI applications available to all biene users (file manager, doc viewer).
  # gvfs provides virtual filesystem support for nautilus
  # (network shares, MTP devices, trash, etc.).
  # loupe (image viewer) comes from clanarchy.apps.graphics.simple.
  environment.systemPackages = with pkgs; [
    nautilus
    evince
    # Removable-media filesystem tools (mkfs.*, fsck.*, repair helpers).
    ntfs3g
    exfatprogs
    dosfstools
    mtools
    f2fs-tools
    hfsprogs
  ];
  services.gvfs.enable = true;

  system.stateVersion = "25.11";
}
