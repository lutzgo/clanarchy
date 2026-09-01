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
  # Read off the installer on 2026-09-01.  Note that udev also publishes
  # `nvme-WD_BLACK_SN770M_2TB_252738400046_1` and an
  # `nvme-eui.e8238fa6bf530001001b444a4580669f` alias for this same device;
  # the plain model+serial name below is the stable one to use.
  device = "/dev/disk/by-id/nvme-WD_BLACK_SN770M_2TB_252738400046";

  # jens's ZFS pool is encrypted (default) and has no swap partition —
  # same as miralda.  See the hybridSleep note in configuration.nix.
}
