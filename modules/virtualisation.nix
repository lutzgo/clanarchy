# modules/virtualisation.nix — KVM/QEMU + libvirtd toggle
#
#   clanarchy.virtualisation.libvirtd.enable
#       Turn on libvirtd, persist /var/lib/libvirt across ZFS rollback, and
#       set the IOMMU kernel parameters appropriate for the configured CPU
#       vendor (clanarchy.hardware.cpu).  IOMMU is required for PCI device
#       passthrough and harmless on host-only VMs.
{ config, lib, ... }:
let
  cfg = config.clanarchy.virtualisation;
  cpu = config.clanarchy.hardware.cpu;
in
{
  options.clanarchy.virtualisation = {
    libvirtd.enable =
      lib.mkEnableOption "libvirtd (KVM/QEMU) + IOMMU kernel params";
  };

  config = lib.mkIf cfg.libvirtd.enable {
    virtualisation.libvirtd.enable = true;

    # ── DO NOT START libvirtd EAGERLY.  LET THE SOCKET DO IT ────────────────
    #
    # Upstream's unit is BOTH socket-activated and `WantedBy=multi-user.target`,
    # and on a host with no guests those two disagree with each other.  What
    # that produced on ernst, measured 2026-09-11:
    #
    #   Active: failed (Result: exit-code) ... Duration: 2min 100ms
    #   .libvirtd-wrapp[...]: Make forcefull daemon shutdown
    #   libvirtd.service: Main process exited, code=exited, status=1/FAILURE
    #
    # The chain is: multi-user.target starts the daemon at boot and after every
    # `switch-to-configuration`; nixpkgs passes `--timeout 120`, so it waits two
    # minutes for a client that never comes; it then shuts itself down — and
    # libvirt 12.2.0 returns **1** from that forced shutdown rather than 0.  So
    # a daemon doing exactly what it was told to do lands in
    # `systemctl --failed`.
    #
    # THAT MATTERS MORE HERE THAN THE WASTED 120 SECONDS.  This fleet treats an
    # empty `systemctl --failed` as a health signal — it is the first line of
    # every milestone's test plan and of every runbook — and a unit that fails
    # on a timer teaches people to read past it.  The next real failure is then
    # one line in a list that is already expected to be dirty.
    #
    # Clearing `wantedBy` leaves socket activation intact: libvirtd.socket,
    # libvirtd-ro.socket and libvirtd-admin.socket are separately wanted by
    # sockets.target and stay active, so `virsh` still starts the daemon on
    # demand.  On a host with no guests it simply never runs.
    #
    # ── THE ONE CASE THIS WOULD BE WRONG FOR ───────────────────────────────
    #
    # A machine with `virsh autostart` guests needs the daemon up at boot to
    # start them, and socket activation will not do that — nothing connects.
    # Checked before changing this: **ernst is the only consumer of this
    # toggle** in the fleet, `virsh list --all` is empty, and
    # /etc/libvirt/qemu/autostart does not exist.  If a machine here ever
    # acquires autostart guests, this line is what has to come back —
    # preferably as `libvirt-guests.service` being wanted instead, which is the
    # unit that actually owns that job.
    #
    # mkForce because the upstream module sets it unconditionally.
    systemd.services.libvirtd.wantedBy = lib.mkForce [ ];

    boot.kernelParams =
      (if cpu == "amd"
       then [ "amd_iommu=on" ]
       else [ "intel_iommu=on" ])
      ++ [ "iommu=pt" ];

    environment.persistence."/persist".directories = [
      "/var/lib/libvirt"
    ];
  };
}
