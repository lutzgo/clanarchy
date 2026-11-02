# jens — btrfs + LUKS2 + impermanence.
#
# Moved off ZFS on 2026-11-02. The fleet rule is now: ernst keeps ZFS (two
# pools, a raidz1 data array, native per-dataset encryption); every laptop
# runs btrfs under LUKS, the layout birte already proved.
#
# WHY LUKS AND NOT ZFS NATIVE ENCRYPTION, since both encrypt the disk:
# systemd-cryptsetup caches the passphrase it prompts for into the kernel
# keyring under the well-known name `cryptsetup`. That is what makes
# `clanarchy.singlePasswordBoot` possible — pam_systemd_loadkey reads it back
# at login and hands it to gnome-keyring, so one passphrase unlocks the disk
# AND the keyring. ZFS has no equivalent; an attempt to hand-roll it in a
# stage-1 unit put this machine in emergency mode (#372, reverted #376,
# removed #377) because the unit called a zfs binary the initrd does not
# carry. On LUKS there is no initrd unit to get wrong.
#
# The passphrase is prompted BEFORE stage 1 can roll back, so this machine
# needs a keyboard at boot — which it has. A headless LUKS machine would need
# `clanarchy.initrdSsh.enable` instead, and that path has never actually been
# completed even on ernst (docs/guides/remote-unlock.md:227).
import ../../modules/disko/btrfs.nix {
  # Three by-id names resolve to this device: a `_1` suffixed variant and an
  # `nvme-eui.…` alias. The plain model+serial is the stable one.
  device = "/dev/disk/by-id/nvme-WD_BLACK_SN770M_2TB_252738400046";

  # NOT the default "main" — that label collides with the Clan installer USB's,
  # which is flashed with `--disk main`, and the collision put this machine's
  # entire bootloader on the stick during the 2026-09-22 reinstall. The module
  # asserts on it now, but the name still has to be chosen here.
  diskName = "jens";

  enableEncryption = true;
  luksName = "cryptjens";

  # Swap sized for hibernation, which this machine GAINS by moving to btrfs.
  #
  # `clanarchy.roles.laptop.hybridSleep.enable` defaults to
  # `rootfs == "btrfs"`, so the filesystem switch turns it on — hibernation
  # with a ZFS root is documented unsafe and was refused outright before.
  # 48 G against 46 G of RAM: the image must fit, with headroom.
  #
  # encryptSwap = false is REQUIRED, not a preference. A randomly-keyed swap
  # partition loses its key across suspend-to-both, which is the one thing
  # hibernation needs it to keep. birte carries the same note.
  enableSwap = true;
  swapSize = "48G";
  encryptSwap = false;

  # gamesMountpoint stays at its default /games. jens is not a gaming machine,
  # so the @games subvol is created and left empty — harmless, and keeps the
  # layout identical across the laptops.
}
