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
  #   /dev/disk/by-id/nvme-Samsung_SSD_980_PRO_1TB_S6XYZ123456
  #
  # DO NOT use /dev/sda or /dev/nvme0n1 directly.
  device = "/dev/disk/by-id/nvme-WD_BLACK_SN850X_1000GB_23141B801914";

  # miralda's ZFS pool is encrypted (default) and has no swap partition.
}
