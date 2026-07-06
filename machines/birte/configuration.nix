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

  # Deck has zram and no swap partition — keep hybrid-sleep off (matches
  # laptop role default when there's no disko swap / boot.resumeDevice).
  clanarchy.roles.laptop.hybridSleep.enable = false;

  # Steam / Proton are unfree.
  nixpkgs.config.allowUnfree = true;

  # App categories — keep minimal on the Deck. Flatpak is useful in Desktop Mode
  # for GUI apps that don't ship on Steam.
  clanarchy.apps.flatpak.enable       = true;
  clanarchy.apps.desktopTools.enable  = true;

  system.stateVersion = "25.11";
}
