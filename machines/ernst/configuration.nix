{pkgs, ...}: {
  networking.hostName = "ernst";
  # Regenerate if cloning: head -c4 /dev/urandom | od -A none -t x4 | tr -d ' '
  networking.hostId = "e7c97a1f";
  # DNS: no global `networking.search` — see modules/networking/resolved.nix.
  # The skynet.lan search suffix + Technitium pin will be attached to the
  # static enp13s0 networkd unit in Phase 2 (still DHCP as of now).

  time.timeZone = "Europe/Berlin";

  clanarchy.locale = {
    language = "en_US";
    keyboard.layout = "us";
  };

  # Server role + admin user assigned via inventory.instances in clan.nix.
  clanarchy.hardware.cpu = "amd"; # 9950X — wires microcode (cpu.nix)
  clanarchy.hardware.gpu.amd.enable = true; # RX 7900 XTX baseline
  clanarchy.hardware.gpu.amd.rocm.enable = true; # ROCm compute stack
  clanarchy.virtualisation.libvirtd.enable = true; # KVM/QEMU + IOMMU
  clanarchy.users.admin.enable = true;

  # ZFS pool alerts via ntfy.sh — URL prompted at `clan vars generate ernst` time.
  clanarchy.zfs.ntfy.enable = true;

  # Bulk-storage diagnostics. smartd pulls in smartmontools.
  # rsync is here (not just for the one-time Arch → ernst media copy) because
  # ernst is the media server: `roles/server.nix` zeroes
  # `environment.defaultPackages`, so the NixOS-default rsync is absent, and
  # every future push/pull from another host lands on ssh's remote shell needing
  # rsync in root's PATH.
  environment.systemPackages = [ pkgs.pciutils pkgs.rsync pkgs.zellij ];
  services.smartd.enable = true;

  # Swap is defined as a partition on system-a in disko.nix; the kernel picks
  # it up automatically. zramSwap intentionally left off — 256 GB RAM is plenty.
  zramSwap.enable = false;

  # ── mirroredBoots follow-up (currently commented out) ─────────────────────
  # The default bootloader wiring (modules/base.nix: boot.loader.systemd-boot.enable
  # + boot.loader.efi.canTouchEfiVariables) installs to a single ESP mounted at
  # /boot — currently the one on system-a in disko.nix.  A slot-12 loss takes
  # /boot with it (see docs/incidents/ernst-slot12-drop-2026-08-11.md).
  #
  # Uncomment the block below **after** the second ESP on system-b exists (see
  # the mirroredBoots preparation header in machines/ernst/disko.nix for the
  # activation procedure).  Uncommenting before the /boot2 partition exists
  # will break `clan machines update ernst` — activation depends on the /boot2 mount.
  #
  # boot.loader.systemd-boot.mirroredBoots = [
  #   {
  #     path    = "/boot2";
  #     devices = [ "nodev" ];
  #   }
  # ];

  # Auto-import + unlock zdata in stage 2 using a raw keyfile on /persist.
  # /persist is a zroot dataset (neededForBoot=true, see modules/zfs-impermanence.nix),
  # so it is mounted before stage 2 systemd starts zfs-import-zdata.service.
  # requestEncryptionCredentials defaults to true, and any dataset whose
  # keylocation is a file:// URI has `zfs load-key` invoked non-interactively
  # by that same service, so no console prompt is needed.
  # One-time setup: see docs/guides/ (Phase 4 keyfile setup).
  boot.zfs.extraPools = ["zdata"];

  # Persist entries added when ernst was made genuinely impermanent.
  #
  # ernst had been running with no @blank snapshots at all since install, so
  # the rollback in modules/zfs-impermanence.nix was a silent no-op and root
  # simply accumulated.  An audit of the 31 MB that had built up found almost
  # all of it re-derivable (fwupd metadata cache, /root/.cache, sddm state) —
  # these two are the exceptions worth carrying across boots.
  environment.persistence."/persist".directories = [
    # Container root filesystems.  The declarative parts are rebuilt from the
    # flake on start, and the data that matters lives on zdata via bindMounts,
    # so this is not about the containers' *state* — it is about their
    # journals.  /var/log is persisted for the host, but each nspawn container
    # keeps its own under here (2.7 MB of Jellyfin's today), and losing that on
    # every reboot would mean no history for exactly the services that are
    # hardest to debug live.
    "/var/lib/nixos-containers"

    # fwupd's device and update history.  Currently inactive on ernst, so this
    # is cheap insurance rather than a fix: firmware work is rare and
    # episodic, and it is precisely the kind of thing where the record of what
    # was flashed last time matters. The pure metadata cache under
    # /var/cache/fwupd is deliberately NOT persisted — it re-downloads.
    "/var/lib/fwupd"
  ];

  system.stateVersion = "26.05";
}
