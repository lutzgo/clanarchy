import ../../modules/disko/btrfs.nix {
  # The Deck OLED's internal 1 TB NVMe, by stable id.  DO NOT use
  # /dev/nvme0n1 directly — the installer USB enumerates alongside it.
  #
  # udev also exposes this drive as `..._50026B7283737F09_1` (a duplicate
  # emitted for the second nvme id source) and as the EUI form
  # `nvme-eui.00000000000000000026b7283737f095`.  All three resolve to
  # nvme0n1; the bare model_serial below is the canonical one.
  #
  # To rediscover after a drive swap: boot the Clan installer USB (via a
  # USB-C hub on the Deck), SSH in, and run `ls -l /dev/disk/by-id/`.
  device = "/dev/disk/by-id/nvme-KINGSTON_OM3PGP41024P-A0_50026B7283737F09";

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
