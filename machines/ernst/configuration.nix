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

  # ── The per-host answers for modules/containers/ ──────────────────────────
  #
  # Every container on this machine shares these, and they are the only place
  # the modules learn anything about ernst: the modules themselves name no
  # bridge, VLAN, resolver or domain, which is what makes a second container
  # host an inventory edit rather than a rewrite.
  #
  # `stateSource` is the one with teeth. Each container's `<svc>-dirs` unit
  # refuses to create anything unless `/srv/state` is really backed by
  # `zdata/state` — because a service that comes up without its state
  # directory is not a degraded service, it is a NEW EMPTY one on zroot, which
  # rolls back on the next boot. See docs/guides/ernst-zdata-datasets.md.
  clanarchy.containerDefaults = {
    bridge       = "br0";
    vlan         = 90;
    resolver     = "10.0.5.3";   # Technitium; pinned, never inherited
    searchDomain = "skynet.lan";
    stateMount   = "/srv/state";
    stateSource  = "zdata/state";
  };

  # ── THE PODMAN TIER, ENABLED ONCE FOR THE HOST ──────────────────────────────
  #
  # This lived in containers/tubesync.nix only because tubesync was the tier's
  # first occupant, which meant the three services that came after it had to
  # know not to re-set it. `virtualisation.podman.enable = true` twice merges
  # fine, but two `oci-containers.backend` definitions do not — so the switch
  # belongs where the host's other once-per-machine answers are.
  #
  # `virtualisation.containers.enable` is what provides /etc/containers,
  # policy.json in particular. Without it podman refuses every image with
  # "no policy.json file found".
  virtualisation.containers.enable = true;
  virtualisation.oci-containers.backend = "podman";
  virtualisation.podman = {
    # No docker socket, no docker alias: nothing here speaks the docker API,
    # and modules/apps/containers.nix (lgo's workstation bundle, which does
    # enable dockerCompat) is not in scope on ernst.
    enable = true;
    dockerCompat = false;
    # The default `podman.service` socket activation is not needed either:
    # oci-containers drives podman by CLI from a systemd unit.
    dockerSocket.enable = false;
  };

  # Accept Nix builds dispatched by miralda's nix-daemon. The authorised key
  # is restricted to `nix-daemon --stdio`, so it buys builds, not a shell.
  clanarchy.remoteBuilder.server.enable = true;

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
