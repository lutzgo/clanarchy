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

  # 16 GB swap — matches Steam Deck OLED RAM, needed for hybrid-sleep
  # (suspend-to-both: RAM state is written to swap so the machine can
  # hibernate if the battery dies while suspended).  Swap is not
  # randomly-encrypted because the resume image must be readable after
  # a full power-off.  Standard for laptops / handheld consoles across
  # the clan (see clanarchy.roles.laptop.hybridSleep default = true).
  enableSwap = true;
  swapSize = "16G";
  encryptSwap = false;
}
