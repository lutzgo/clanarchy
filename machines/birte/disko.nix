import ../../modules/disko/btrfs.nix {
  # IMPORTANT:
  # Boot from the Clan installer USB (via a USB-C hub on the Deck).
  # SSH into the installer, then:
  #   ls -l /dev/disk/by-id/
  # The Deck's internal NVMe shows up as something like:
  #   /dev/disk/by-id/nvme-<model>_<serial>
  # Replace the value below with the full by-id path.
  # DO NOT use /dev/nvme0n1 directly.
  device = "/dev/disk/by-id/CHANGEME-steamdeck-internal-nvme";

  # btrfs rather than the fleet's ZFS (modules/disko/base.nix).  OpenZFS is
  # out-of-tree and gates the kernel; birte tracks nixpkgs-unstable and a
  # Valve kernel via Jovian, so it can't afford that coupling.  btrfs is
  # in-tree and follows whatever kernel Jovian ships.  Must be kept in step
  # with `clanarchy.rootfs = "btrfs"` in configuration.nix.
  #
  # No encryption — matches biene.  The Deck's game library isn't
  # sensitive, and a passphrase prompt before Gaming Mode is a bad
  # experience.  (The btrfs template doesn't offer LUKS at all.)

  # 16 GB swap — matches Steam Deck OLED RAM, needed for hybrid-sleep
  # (suspend-to-both: RAM state is written to swap so the machine can
  # hibernate if the battery dies while suspended).  Swap is not
  # randomly-encrypted because the resume image must be readable after
  # a full power-off.  Standard for laptops / handheld consoles across
  # the clan (see clanarchy.roles.laptop.hybridSleep default = true).
  enableSwap = true;
  swapSize = "16G";
  encryptSwap = false;

  # @games stays at the neutral default (/games), outside the rollback path,
  # and is symlinked into deck's home by a tmpfiles rule in deck.nix.
  #
  # It deliberately does NOT mount straight at
  # /home/deck/.local/share/Steam: @home is rolled back on every boot and
  # .local/share is restored as an impermanence bind-mount, which would
  # shadow anything mounted underneath it.  Ownership of /games is fixed up
  # in deck.nix — a fresh subvolume is root:root.
  gamesMountpoint = "/games";
}
