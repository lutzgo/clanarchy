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

  # machine-type (laptop, no Framework hw) and desktop (niri) are assigned via
  # inventory.instances in clan.nix. Wifi is provisioned via the clan wifi
  # service (home SSID prompted at `clan vars generate birte` time).
  clanarchy.hardware.cpu = "amd"; # Van Gogh APU (Zen 2 + RDNA 2 iGPU)
  clanarchy.users.admin.enable = true;

  # deck's Desktop Mode is lgo's desktop: his palette, wallpapers and niri
  # look (modules/themes, modules/wallpapers/nix-anarchy.nix,
  # modules/desktop/niri-look.nix); his bar comes with the deck account
  # (noctalia-hm.nix, `lgoLayout`). birte used to have its own Catppuccin
  # Mocha theme in machines/birte/stylix.nix.
  imports = [../../modules/desktop/niri-look.nix];
  clanarchy.theme = "rose-pine";
  clanarchy.wallpapers.nixAnarchy.users = ["deck"];

  # Stylix's KDE HM target, off for `admin` only: it builds a
  # writeShellApplication whose `username=admin` preamble line ShellCheck
  # rejects as SC2209 (`admin` is a command name it knows; `deck` is not).
  # Moved here from the retired machines/birte/stylix.nix.
  home-manager.users.admin.stylix.targets.kde.enable = false;

  # The Voyager, when it is plugged into the Deck: Vial and the ZSA udev rules
  # it needs to reach the keyboard. Keymapp stays on miralda and jens — Vial
  # is what was asked for here, and flashing happens at a desk.
  clanarchy.hardware.zsa = {
    enable = true;
    keymapp.enable = false;
    vial.enable = true;
  };

  # Touch-first: niri-tablet's touchscreen gestures and the on-screen keyboard
  # (swipe up from the bottom edge), since Desktop Mode has no keyboard and
  # Steam's controller-as-mouse only runs inside Steam. NO auto-rotation: the
  # Deck has no accelerometer the kernel exposes — its only IIO devices are
  # the ltrf216a light sensor — so iio-niri would have nothing to listen to.
  clanarchy.hardware.convertible = {
    enable = true;
    autoRotate.enable = false;
  };

  # NO output transform, although the panel is natively PORTRAIT (800×1280 in
  # /sys/class/drm/…-eDP-1/modes). The kernel reports the Deck's panel
  # orientation through the DRM "panel orientation" property — `Right Side
  # Up` on birte (drm_info) — and niri ADDS that to the configured transform
  # (niri.rs: `panel_orientation(output) + config transform`), so it corrects
  # the panel by itself. The `transform 270` other compositors' Deck configs
  # carry was set here first, and stacked on top of niri's own correction it
  # left the desktop turned 90° clockwise (seen on birte 2026-11-04).

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
  # machine is btrfs (`clanarchy.rootfs` above) — so no override. It is the only machine in the fleet that
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
  # only one: `supersonic-wayland` no longer exists in nixpkgs.
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
