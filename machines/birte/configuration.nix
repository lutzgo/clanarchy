{ ... }:
{
  networking.hostName = "birte";
  # Regenerate if cloning: head -c4 /dev/urandom | od -A none -t x4 | tr -d ' '
  networking.hostId   = "fe39bcd8";
  # DNS: no global `networking.search` — search + routing attach to the
  # "home" NM profile.  See modules/networking/{resolved,skynet-dns-nm}.nix.

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

  # Build against nixpkgs-unstable — Jovian-NixOS only supports unstable,
  # and Noctalia/Quickshell need unstable-flavoured pkgs too.  See
  # modules/channel.nix for how this swaps the pkgs instance.
  clanarchy.channel = "unstable";

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

  # Machine-agnostic gaming bits (Steam + Proton-GE + `.steam` persistence).
  # Jovian / Deck-hardware wiring lives in jovian.nix and deck.nix.
  clanarchy.gaming = {
    enable = true;
    user   = "deck";
  };

  # birte uses `nixpkgs.pkgs = unstablePkgs` (via clanarchy.channel = "unstable"
  # above) while the module list comes from clan-core/nixpkgs 26.05.  The
  # NixOS option-docs generator (lazy-options.json) walks the module list
  # from 26.05 but sandboxes files from `pkgs.path` — which is
  # nixpkgs-unstable's May 30 pin (see nixpkgs-unstable comment in flake.nix).
  # Newer 26.05 module-list entries such as `programs/tack.nix` don't exist
  # in the older unstable source, causing the docs build to fail.
  #
  # Nobody browses `nixos-help` on a Steam Deck — skip the docs build.  Lift
  # once nixpkgs-unstable can be bumped forward and the two sources agree.
  documentation.nixos.enable = false;

  system.stateVersion = "25.11";
}
