{ config, ... }:
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

  # btrfs rather than the fleet's ZFS.  Out-of-tree OpenZFS gates the
  # kernel, which doesn't work on a machine tracking unstable + a Valve
  # kernel via Jovian (see disko.nix).  This selects the btrfs
  # impermanence backend — modules/btrfs-impermanence.nix — which blanks
  # @root on boot but, unlike the ZFS backend, leaves home persistent:
  # deck's home holds Steam/gamescope state Gaming Mode expects to
  # survive.  The game library lives on its own @games subvol.
  clanarchy.rootfs = "btrfs";

  # TEMPORARY — birte does not boot with the stage-1 rollback unit enabled.
  # It has never once succeeded on this machine: after two installs there are
  # no @root-blank / @home-blank subvolumes, and the second install left the
  # Deck unable to reach any session at all. Turning the unit off gets a
  # usable machine back so the failure can be read out of the journal on
  # @persist instead of guessed at from the source.
  #
  # While this is false, birte's root is MUTABLE: nothing rolls back, and
  # anything written outside /persist survives reboots. That is contrary to
  # the fleet's design and to what docs/guides/impermanence.md claims.
  # clanarchy-impermanence-check does not cover this — it verifies the blank
  # snapshots exist, not that anything rolls back to them.
  clanarchy.impermanence.rollback.enable = false;

  # Hybrid-sleep: the swap partition (see disko.nix) is the resume device.
  # `clanarchy.roles.laptop.hybridSleep.enable` defaults to true — standard
  # for laptops and handheld consoles across the clan — so no override here.
  #
  # Derived from the disko disk name rather than written out, because the two
  # must agree and nothing checks that they do. Hardcoding it as
  # disk-main-swap is what hung birte's first boot on the renamed layout: the
  # device unit for a swap partition that no longer existed sat in a start job
  # with "no limit", so the boot never progressed and never timed out either.
  boot.resumeDevice =
    "/dev/disk/by-partlabel/disk-${
      builtins.head (builtins.attrNames config.disko.devices.disk)
    }-swap";

  # (Steam / Proton are unfree — `allowUnfree = true` is already baked into
  # the pkgs instance built in lib/mk-machine.nix, so we intentionally do
  # NOT set `nixpkgs.config.allowUnfree` here.  Doing both trips a NixOS
  # assertion because `nixpkgs.config` cannot be set when `nixpkgs.pkgs`
  # is an externally created instance.)

  # App categories — keep minimal on the Deck. Flatpak is useful in Desktop Mode
  # for GUI apps that don't ship on Steam.
  clanarchy.apps.flatpak.enable       = true;
  clanarchy.apps.desktopTools.enable  = true;

  # Machine-agnostic gaming bits (Steam + Proton-GE).
  # Jovian / Deck-hardware wiring lives in jovian.nix and deck.nix.
  clanarchy.gaming = {
    enable = true;
    user   = "deck";
    # persistenceDirectories keeps its default ([ ".steam" ]): birte's home
    # is rolled back like the rest of the fleet, so the Steam runtime
    # bootstrap genuinely needs declaring.  The remaining per-user paths are
    # listed in deck.nix.
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
