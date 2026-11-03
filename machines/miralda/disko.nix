# miralda — btrfs on LVM on LUKS2, with impermanence and hibernation.
#
# The laptop layout jens moved to on 2026-11-02 (see machines/jens/disko.nix
# for why LUKS rather than ZFS native encryption: it is what makes
# `clanarchy.singlePasswordBoot` possible), with one difference: swap lives
# INSIDE the LUKS container (`swapInLuks`), so the hibernation image is
# encrypted with the disk key instead of sitting on a plain partition.
#
# Rendered: ESP + LUKS2 `cryptmiralda` -> LVM VG `miralda` -> LVs `swap`
# (/dev/mapper/miralda-swap, the resume device) and `root` (btrfs, subvolumes
# @root @home @nix @persist @games).
import ../../modules/disko/btrfs.nix {
  # udev also publishes a `_1` suffixed variant and an `nvme-eui.…` alias for
  # this device; the plain model+serial name is the stable one.
  device = "/dev/disk/by-id/nvme-WD_BLACK_SN850X_1000GB_23141B801914";

  # Never "main" — it collides with the Clan installer USB's labels. Also the
  # LVM volume group name, so lowercase alphanumeric only (asserted).
  diskName = "miralda";

  enableEncryption = true;
  luksName = "cryptmiralda";

  # Hibernation (`roles.laptop.hybridSleep`, on by default for btrfs) needs
  # swap >= RAM: 40 G against 30 G of RAM.
  enableSwap = true;
  swapSize = "40G";
  swapInLuks = true;
}
