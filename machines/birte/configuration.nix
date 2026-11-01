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

  # btrfs rather than ZFS.  Stated here, not derived: modules/rootfs.nix used
  # to compute this from `clanarchy.channel`, and that coupling is gone — a
  # ZFS machine now pins `zfs.latestCompatibleLinuxPackages` instead, so the
  # filesystem no longer has to be inferred from the channel.
  #
  # btrfs is still the right answer for this machine for the original reason:
  # it tracks a Valve kernel, and out-of-tree OpenZFS would gate it.
  #
  # The backend rolls back @root AND @home on boot — the same as the ZFS one.
  # (Earlier revisions of this comment claimed home was left persistent here;
  # that was never true of the code. See modules/btrfs-impermanence.nix:98.)
  # deck's Steam and gamescope state survives because it is persisted
  # explicitly in deck.nix, not because home escapes the rollback.  The game
  # library lives on its own @games subvol, outside the rollback path.
  clanarchy.rootfs = "btrfs";

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

  # Steam, Proton and the Deck's own hardware theme are unfree.  This line
  # could not exist while birte took `nixpkgs.pkgs` from a separate instance —
  # setting `nixpkgs.config` alongside an externally supplied `pkgs` trips a
  # NixOS assertion, so the flag lived inside that instance instead.  With the
  # fleet on one channel birte takes the ordinary path, and needs the same
  # line as its siblings for the same reason they do: pkgsForSystem's config
  # reaches clanInternals, not `nixosConfigurations.<name>`, which is what
  # `clan machines update` evaluates.
  #
  # Without it: `Refusing to evaluate package 'steamdeck-hw-theme-…' because
  # it has an unfree license (unfreeRedistributable)`.
  nixpkgs.config.allowUnfree = true;

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

  system.stateVersion = "25.11";
}
