{ ... }:
{
  networking.hostName = "birte";
  # Regenerate if cloning: head -c4 /dev/urandom | od -A none -t x4 | tr -d ' '
  networking.hostId   = "fe39bcd8";
  networking.search   = [ "skynet.lan" ];

  time.timeZone = "Europe/Berlin";

  # Locale: English US everywhere (matches Steam / gamescope defaults).
  clanarchy.locale = {
    language        = "en_US";
    keyboard.layout = "us";
  };

  # machine-type (laptop, no Framework hw) and desktop (kde) are assigned via
  # inventory.instances in clan.nix. Wifi is provisioned via the clan wifi
  # service (home SSID prompted at `clan vars generate birte` time).
  clanarchy.hardware.cpu       = "amd";   # Van Gogh APU (Zen 2 + RDNA 2 iGPU)
  clanarchy.users.admin.enable = true;

  # Hybrid-sleep: the swap partition (see disko.nix) is the resume device.
  # `clanarchy.roles.laptop.hybridSleep.enable` defaults to true — standard
  # for laptops and handheld consoles across the clan — so no override here.
  # "swap" is set by disko from the partition name in the partitions attrset.
  boot.resumeDevice = "/dev/disk/by-partlabel/disk-main-swap";

  # (Steam / Proton are unfree — `allowUnfree = true` is already baked into
  # the pkgs instance built in lib/mk-machine.nix, so we intentionally do
  # NOT set `nixpkgs.config.allowUnfree` here.  Doing both trips a NixOS
  # assertion because `nixpkgs.config` cannot be set when `nixpkgs.pkgs`
  # is an externally created instance.)

  # App categories — keep minimal on the Deck. Flatpak is useful in Desktop Mode
  # for GUI apps that don't ship on Steam.
  clanarchy.apps.flatpak.enable       = true;
  clanarchy.apps.desktopTools.enable  = true;

  system.stateVersion = "25.11";
}
