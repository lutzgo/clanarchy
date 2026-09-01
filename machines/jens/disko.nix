import ../../modules/disko/base.nix {
  # IMPORTANT:
  # Boot from the Clan installer USB.
  # SSH into the installer:
  #   ssh root@<installer-ip>
  #
  # Then determine the stable disk ID with:
  #   ls -l /dev/disk/by-id/
  #
  # Choose the correct disk and replace the value below
  # with the full path, e.g.:
  #   /dev/disk/by-id/nvme-WD_BLACK_SN770M_1TB_12345678
  #
  # DO NOT use /dev/sda or /dev/nvme0n1 directly.
  #
  # TODO(install): replace with the by-id path read off the installer.
  device = "/dev/disk/by-id/REPLACE-ME";

  # jens's ZFS pool is encrypted (default) and has no swap partition —
  # same as miralda.  See the hybridSleep note in configuration.nix.
}
