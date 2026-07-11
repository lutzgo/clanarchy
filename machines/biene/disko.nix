import ../../modules/disko/base.nix {
  # See machines/miralda/disko.nix for the disk-ID rationale.
  device = "/dev/disk/by-id/ata-V7_SSD_1701642006054300";

  # Unencrypted pool (intentional — this is Sabine's daily driver and
  # a boot passphrase would block her from turning it on).
  enableEncryption = false;

  # 8 GB swap — matches biene's RAM, required for hybrid-sleep
  # (suspend-to-both: RAM state is written to swap so the machine can
  # hibernate if the battery dies while suspended).  Swap is not
  # randomly-encrypted because the resume image must be readable after
  # a full power-off.
  enableSwap = true;
  swapSize = "8G";
  encryptSwap = false;
}
