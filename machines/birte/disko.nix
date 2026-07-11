import ../../modules/disko/base.nix {
  # IMPORTANT:
  # Boot from the Clan installer USB (via a USB-C hub on the Deck).
  # SSH into the installer, then:
  #   ls -l /dev/disk/by-id/
  # The Deck's internal NVMe shows up as something like:
  #   /dev/disk/by-id/nvme-<model>_<serial>
  # Replace the value below with the full by-id path.
  # DO NOT use /dev/nvme0n1 directly.
  device = "/dev/disk/by-id/CHANGEME-steamdeck-internal-nvme";

  # No encryption — matches biene.  Deck's game library isn't sensitive,
  # and encryption would prompt for a passphrase before Gaming Mode.
  enableEncryption = false;

  # No swap — the Deck relies on zram (kernel default) and hybrid-sleep
  # is disabled in configuration.nix.  Add enableSwap = true here plus
  # boot.resumeDevice + hybridSleep.enable = true if that changes.
}
