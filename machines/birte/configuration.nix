{config, ...}: {
  networking.hostName = "birte";
  # Regenerate if cloning: head -c4 /dev/urandom | od -A none -t x4 | tr -d ' '
  networking.hostId = "fe39bcd8";
  # DNS: no global `networking.search` — search + routing attach to the
  # "home" NM profile.  See modules/networking/{resolved,skynet-dns-nm}.nix.

  time.timeZone = "Europe/Berlin";

  # Locale: English US everywhere (matches Steam / gamescope defaults).
  clanarchy.locale = {
    language = "en_US";
    keyboard.layout = "us";
  };

  # machine-type (laptop, no Framework hw) and desktop (kde) are assigned via
  # inventory.instances in clan.nix. Wifi is provisioned via the clan wifi
  # service (home SSID prompted at `clan vars generate birte` time).
  clanarchy.hardware.cpu = "amd"; # Van Gogh APU (Zen 2 + RDNA 2 iGPU)
  clanarchy.users.admin.enable = true;

  # Hand big compiles to ernst.  birte is the machine the remote-builder
  # module's own header was written about — its Valve kernel is rebuilt from
  # source on every bump because this clan configures no substituters for it
  # — and yet it was never made a client.  A Steam Deck APU is the worst
  # place in the fleet to compile a kernel.
  clanarchy.remoteBuilder.client.enable = true;

  # Build against nixpkgs-unstable — Jovian-NixOS only supports unstable,
  # and Noctalia/Quickshell need unstable-flavoured pkgs too.  See
  # modules/channel.nix for how this swaps the pkgs instance.
  clanarchy.channel = "unstable";

  # btrfs rather than ZFS, and NOT set here: modules/rootfs.nix derives it from
  # `clanarchy.channel` above, because out-of-tree OpenZFS gates the kernel and
  # tracking a Valve kernel is the whole reason this machine is on unstable.
  # The backend rolls back @root on boot but, unlike the ZFS one, leaves home
  # persistent: deck's home holds Steam/gamescope state Gaming Mode expects to
  # survive.  The game library lives on its own @games subvol.
  # Bluetooth pairings. A handheld pairs controllers and headphones and must
  # not forget them on every boot; nothing else in the fleet persists this
  # because no other machine depends on pairing as a matter of course.
  environment.persistence."/persist".directories = ["/var/lib/bluetooth"];

  # Impermanence is on. It previously made this machine unbootable, and the
  # cause is worth keeping written down because the symptom pointed nowhere
  # near it: `btrfs subvolume snapshot` does not recurse into nested
  # subvolumes, so restoring @root left 0755 stubs at /var/tmp, /srv,
  # /var/lib/machines and /var/lib/portables. A 0755 /var/tmp breaks every
  # service with PrivateTmp=true — dbus-broker, logind, nscd, avahi,
  # bluetooth, wpa_supplicant — which surfaces as
  #
  #   Failed to spawn 'start' task: Operation not permitted
  #
  # and, with dbus and logind down, as a black screen with no sshd.
  # modules/btrfs-impermanence.nix now rebuilds those stubs after each
  # restore.
  #
  # When changing anything about the rollback, reboot TWICE. The first boot
  # only seeds the blank snapshots and exercises none of the restore path;
  # it looks like success and proves nothing.
  clanarchy.impermanence.rollback.enable = true;

  # Hybrid-sleep: the swap partition (see disko.nix) is the resume device.
  # `clanarchy.roles.laptop.hybridSleep.enable` defaults on here because this
  # machine is btrfs, which is itself derived from `clanarchy.channel =
  # "unstable"` — so no override. It is the only machine in the fleet that
  # hibernates; see modules/roles/laptop.nix for why ZFS is refused.
  #
  # Derived from the disko disk name rather than written out, because the two
  # must agree and nothing checks that they do. Hardcoding it as
  # disk-main-swap is what hung birte's first boot on the renamed layout: the
  # device unit for a swap partition that no longer existed sat in a start job
  # with "no limit", so the boot never progressed and never timed out either.
  boot.resumeDevice = "/dev/disk/by-partlabel/disk-${
    builtins.head (builtins.attrNames config.disko.devices.disk)
  }-swap";

  # (Steam / Proton are unfree — `allowUnfree = true` is already baked into
  # the pkgs instance built in lib/mk-machine.nix, so we intentionally do
  # NOT set `nixpkgs.config.allowUnfree` here.  Doing both trips a NixOS
  # assertion because `nixpkgs.config` cannot be set when `nixpkgs.pkgs`
  # is an externally created instance.)

  # App categories — keep minimal on the Deck. Flatpak is useful in Desktop Mode
  # for GUI apps that don't ship on Steam.
  clanarchy.apps.flatpak.enable = true;
  clanarchy.apps.desktopTools.enable = true;

  # Supersonic, for Navidrome in Desktop Mode. The default package is the
  # right one here: birte is `clanarchy.channel = "unstable"`, where
  # `supersonic-wayland` no longer exists.
  clanarchy.apps.subsonic.enable = true;

  # Switch emulation. RetroDECK (installed as a Flatpak, see deck.nix for the
  # persistence and data-folder wiring it needs) covers everything up to the
  # Switch and dropped the Switch itself in February 2026, so that one console
  # is packaged separately here.
  clanarchy.apps.emulation.switch.enable = true;

  # Machine-agnostic gaming bits (Steam + Proton-GE).
  # Jovian / Deck-hardware wiring lives in jovian.nix and deck.nix.
  clanarchy.gaming = {
    enable = true;
    user = "deck";
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
