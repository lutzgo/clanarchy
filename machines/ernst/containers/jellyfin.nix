# machines/ernst/containers/jellyfin.nix
#
# Jellyfin, running inside a declarative systemd-nspawn NixOS container.
#
# Why nspawn (not microvm, not Podman):
#   Trusted storage-heavy services on ernst run in systemd-nspawn.  It gives us
#   a real NixOS system view inside the container (services.jellyfin as-is,
#   with all its upstream hardening), while sharing the host kernel — no VM
#   overhead, no OCI image drift, no separate package tree to babysit.
#
# Networking — v1: HOST namespace (privateNetwork = false).
#   The VLAN bridge we intend to migrate to (a MAC-pinned tap on the
#   Services VLAN, so Jellyfin gets its own L2 identity and the UDM-Pro can
#   apply zone-based firewall rules against it directly) does not exist yet.
#   Migration path once the bridge is provisioned:
#     containers.jellyfin.privateNetwork = true;
#     containers.jellyfin.macvlans      = [ "br-services" ];   # or similar
#     …plus a systemd-networkd unit inside the container for DHCP/static.
#   At that point the host-side firewall port (8096/tcp below) goes away and
#   the ACL moves onto the UDM-Pro.
#
# GPU — iGPU only, XTX reserved for ROCm/gaming.
#   ernst carries two AMD GPUs:
#     PCI 03:00.0  Navi 31 (RX 7900 XTX)  — DO NOT bind; ROCm/Ollama + gaming
#     PCI 7b:00.0  Granite Ridge iGPU     — this file
#
#   Addressed by PCI path, not by renderD* number.  renderD12{8,9} is
#   enumeration order, which can flip on a kernel update — and a flip here is
#   not a broken-transcode failure, it silently hands the container the 7900
#   XTX and takes it away from ROCm.  The by-path symlinks udev maintains are
#   stable across reboots and kernel bumps because they are derived from the
#   PCI topology:
#     /dev/dri/by-path/pci-0000:7b:00.0-render -> ../renderD12X
#
#   Verify after a kernel bump (should print the iGPU, not Navi 31):
#     readlink -f /dev/dri/by-path/pci-0000:7b:00.0-render
#     nixos-container run jellyfin -- vainfo --display drm --device \
#       /dev/dri/by-path/pci-0000:7b:00.0-render
#
# Storage layout on this host (see machines/ernst/disko.nix):
#   /srv/media   zdata/media   RO into container at /srv/media/library
#   /srv/state   zdata/state   RW into container at /var/lib/jellyfin
#   Transcode temp is a tmpfs INSIDE the container — never on zdata.
{ config, lib, pkgs, ... }:
let
  # AMD iGPU render node on ernst (Granite Ridge, 9950X), addressed by PCI
  # path so kernel enumeration order cannot repoint it at the 7900 XTX.
  # See the file header for the rationale and the post-kernel-bump check.
  #
  # Used verbatim in all three places that must agree — allowedDevices, the
  # bind mount, and the VaapiDevice written into encoding.xml — so they
  # cannot drift apart.
  #
  # On allowedDevices specifically: NixOS passes this string straight through
  # to systemd's DeviceAllow= (nixos-containers.nix:341), and systemd stat()s
  # the path to derive major:minor for the eBPF device filter. stat() follows
  # symlinks, so the by-path link resolves correctly and no real node is
  # needed here. If a future systemd ever refuses the symlink, the fallback is
  # to put the numeric node in allowedDevices ONLY — derived with
  # `readlink -f` on the path below — and leave the bind mount and
  # VaapiDevice on the stable by-path name.
  iGpuRenderNode = "/dev/dri/by-path/pci-0000:7b:00.0-render";

  # Fixed numeric IDs so the RW state bind mount has coherent ownership
  # regardless of NixOS's dynamic allocation.  jellyfinUid matches the
  # LinuxServer Docker image's convention (uid 964), which makes future
  # comparisons/exports painless.
  jellyfinUid = 964;
  jellyfinGid = 964;

  # Shared `media` group.  nspawn maps gids 1:1 here (no user-namespace
  # remapping), so this gid MUST be identical on the host and inside the
  # container — otherwise the container sees numeric group 3000 on every
  # file, has no matching group name, and jellyfin (which is not member of
  # gid 3000) fails every mode-0640 read.  Files are staged root:media 0640
  # so that adding another consumer (Nextcloud, an *arr) is a group-add,
  # not a chown.  3000 is above NixOS's dynamic gid range (which tops out
  # in the 900s for system users on 26.05) so it cannot collide with a
  # future auto-allocated group.
  mediaGid = 3000;
in
{
  ##############################################################################
  # Host-side wiring: bind-source dirs, firewall, user shell for the state bind.
  ##############################################################################

  # Host-side group.  Fleet media consumers (jellyfin now; Nextcloud
  # external storage, *arr suite later) get access via group membership.
  users.groups.media = { gid = mediaGid; };

  # Parent dirs for the bind sources.
  #
  # All four media subdirs are now plain directories on the already-mounted
  # zdata/media dataset (see machines/ernst/disko.nix — movies/tvshows sub-
  # datasets were collapsed so *arr hardlinks work across torrents/ and
  # library/, which cannot cross ZFS dataset boundaries).  tmpfiles handles
  # creation fine on plain subdirs of a mounted dataset — no shadow-mount
  # race — but the setgid mode + group ownership are still applied by the
  # ordered oneshot below, so nothing depends on tmpfiles winning against
  # any post-boot mount ordering.
  systemd.tmpfiles.rules = [
    "d /srv/media/library            0755 root       root       -"
    "d /srv/media/library/movies     0755 root       root       -"
    "d /srv/media/library/tvshows    0755 root       root       -"
    "d /srv/media/torrents           0755 root       root       -"
    "d /srv/media/torrents/movies    0755 root       root       -"
    "d /srv/media/torrents/tv        0755 root       root       -"
    "d /srv/state/jellyfin           0700 ${toString jellyfinUid} ${toString jellyfinGid} -"
  ];

  # Ownership + setgid on the media subdirs, applied AFTER zdata/media is
  # mounted and BEFORE the container starts.  Non-recursive on purpose:
  # 8.77 TB is present under these paths, and per-file ownership was set
  # once during the Arch → ernst migration (rsync --chown=root:media
  # --chmod=…) — recursing here would rewrite metadata on ~23k files for
  # no benefit.  Mode 2770 = setgid + rwxrws---: new files inherit
  # gid=media, group members read+WRITE (Radarr/Sonarr/the download client
  # need to move and hardlink files across torrents/ and library/), root
  # owns.  Idempotent: chown/chmod on an already-correct dir is a no-op.
  systemd.services.jellyfin-library-perms = {
    description = "Set root:media 2770 on Jellyfin media subdirectories";
    wantedBy    = [ "multi-user.target" ];
    before      = [ "container@jellyfin.service" ];
    after       = [ "srv-media.mount" ];
    requires    = [ "srv-media.mount" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
      ExecStart = [
        "${pkgs.coreutils}/bin/chown root:media /srv/media/library/movies /srv/media/library/tvshows /srv/media/torrents/movies /srv/media/torrents/tv"
        "${pkgs.coreutils}/bin/chmod 2770       /srv/media/library/movies /srv/media/library/tvshows /srv/media/torrents/movies /srv/media/torrents/tv"
      ];
    };
  };

  # Firewall — v1 uses host networking, so this lives on the host.
  # Only 8096/tcp (HTTP) is exposed.  Explicitly NOT opened:
  #   8920/tcp   — HTTPS.  We terminate TLS elsewhere (future reverse proxy);
  #                Jellyfin's own HTTPS listener isn't used.
  #   7359/udp   — client auto-discovery.  Broadcast-based; no value on a
  #                routed network where clients bookmark the URL directly,
  #                and it leaks the server's existence to every VLAN it can
  #                reach.
  #   1900/udp   — DLNA/SSDP.  Same broadcast concerns as 7359; DLNA is
  #                also a well-worn RCE surface.  Disable in the Jellyfin
  #                UI too (Dashboard → DLNA).
  networking.firewall.allowedTCPPorts = [ 8096 ];

  ##############################################################################
  # The container itself.
  ##############################################################################
  containers.jellyfin = {
    autoStart      = true;
    ephemeral      = false;         # jellyfin state persists via bind mount below
    privateNetwork = false;         # see file header — v1 shares host netns

    # Only expose the iGPU render node to the container.  card0 is deliberately
    # NOT bound: modern VAAPI on mesa/radeonsi uses only the render node, and
    # keeping the card node out means the container cannot touch KMS, DPMS, or
    # anything else that requires the primary DRM device.
    allowedDevices = [
      { node = iGpuRenderNode; modifier = "rw"; }
    ];

    bindMounts = {
      # Media library — read-only.  Two separate binds because the imported
      # Jellyfin database (from the retired Arch box) records absolute paths
      # under /media/Server001/{Movies,TV-Shows}; the host tree is laid out
      # differently (plain subdirectories under /srv/media/library on the
      # single zdata/media dataset — collapsed from per-collection sub-
      # datasets so *arr hardlinks work across torrents/ and library/) so
      # Nextcloud can later expose the same tree as external storage without
      # inheriting a legacy path scheme.  The bind is the translation layer:
      # the container sees the paths the DB expects, the host keeps a clean
      # /srv/media/library/{movies,tvshows} layout.  RO on both — Jellyfin
      # never writes to library data.
      "/media/Server001/Movies" = {
        hostPath   = "/srv/media/library/movies";
        isReadOnly = true;
      };
      "/media/Server001/TV-Shows" = {
        hostPath   = "/srv/media/library/tvshows";
        isReadOnly = true;
      };

      # Jellyfin persistent state.  Remapped to the upstream default path
      # (/var/lib/jellyfin) inside the container so the packaged systemd unit
      # needs no path overrides.
      "/var/lib/jellyfin" = {
        hostPath   = "/srv/state/jellyfin";
        isReadOnly = false;
      };

      # iGPU render node — same path host/container, for symmetry with the
      # encoding.xml VaapiDevice value services.jellyfin writes below.
      "${iGpuRenderNode}" = {
        hostPath   = iGpuRenderNode;
        isReadOnly = false;
      };
    };

    ############################################################################
    # NixOS config for the container's own root filesystem.
    ############################################################################
    config = { config, pkgs, lib, ... }: {
      system.stateVersion = "26.05";

      # Use the host's resolv.conf — the container has no DNS config of its own
      # and needs to reach the internet for plugin/metadata downloads.
      networking.useHostResolvConf = lib.mkForce true;

      # Pin jellyfin's numeric UID/GID to match the host-side chown above so
      # the /var/lib/jellyfin bind is owned correctly from first boot.
      users.users.jellyfin = {
        isSystemUser = true;
        group        = "jellyfin";
        uid          = jellyfinUid;
        # `render` grants access to the iGPU render node (mode 0666 makes this
        # nominally unnecessary, but if a future udev rule tightens the node
        # to 0660, membership keeps VAAPI working without a redeploy).
        # `media` grants read on the library binds — files are staged
        # root:media 0640 by the copy job, so this membership is what makes
        # `jellyfin` (uid 964) able to read them at all.  Without it every
        # library scan finds zero items even though the mounts show up.
        extraGroups  = [ "render" "video" "media" ];
      };
      users.groups.jellyfin = { gid = jellyfinGid; };

      # Match host GIDs so `render`/`video`/`media` membership is meaningful
      # when host paths (dri render node, library binds) show up inside the
      # container.  nspawn does not remap gids here, so these MUST match the
      # host numeric ids exactly — video/render are the NixOS 26.05 defaults
      # (`getent group video render` on ernst); media is the fixed 3000 set
      # by the host-side `users.groups.media` above.
      users.groups.video  = { gid = 26;  };
      users.groups.render = { gid = 303; };
      users.groups.media  = { gid = mediaGid; };

      # VAAPI driver stack.  mesa ships the AMD radeonsi VAAPI driver
      # (radeonsi_drv_video.so) that Jellyfin's bundled ffmpeg dlopens when
      # HardwareAccelerationType=vaapi.  libva-utils gives us `vainfo` for
      # the PR test plan.
      hardware.graphics = {
        enable        = true;
        extraPackages = with pkgs; [ mesa libva ];
      };
      environment.systemPackages = with pkgs; [ libva-utils ];

      # Jellyfin itself.
      #
      # The upstream module (nixpkgs/nixos/modules/services/misc/jellyfin.nix)
      # already applies extensive systemd sandboxing (CapabilityBoundingSet="",
      # NoNewPrivileges, ProtectSystem, ProtectClock, ProtectHostname,
      # ProtectProc=invisible, PrivateUsers, RestrictAddressFamilies to
      # {UNIX,INET,INET6,NETLINK}, SystemCallFilter=@system-service ~@privileged,
      # RemoveIPC, etc.), and it correctly disables the handful of restrictions
      # that would break inside an nspawn container (ProtectKernel*, PrivateTmp,
      # ProtectControlGroups, RestrictNamespaces — all gated on
      # `!config.boot.isContainer`).  We don't duplicate any of that.
      services.jellyfin = {
        enable       = true;
        openFirewall = false;         # host firewall handles 8096 exposure
        hardwareAcceleration = {
          enable = true;
          type   = "vaapi";
          device = iGpuRenderNode;    # written into encoding.xml as VaapiDevice
        };
      };

      # Transcode temp = tmpfs on the container's own filesystem.  Jellyfin
      # defaults transcodes to <cacheDir>/transcodes, so mounting a tmpfs
      # at cacheDir keeps every scratch write off zdata/media (which is
      # exec/setuid/devices=off and, more importantly, not where you want
      # sustained short-lived writes on a raidz1).  8 GiB is comfortable
      # for a handful of concurrent 4K→1080p transcodes; bump if streams
      # start failing with "no space left on device" in transcode logs.
      fileSystems."/var/cache/jellyfin" = {
        device  = "tmpfs";
        fsType  = "tmpfs";
        options = [ "size=8G" "mode=0700" "nosuid" "nodev" "noexec"
                    "uid=${toString jellyfinUid}" "gid=${toString jellyfinGid}" ];
      };

      # Additional hardening on top of the upstream module.
      #
      # Applied:
      #   ProtectHome=true  — jellyfin has no reason to touch /home;
      #                       the upstream module doesn't set it.
      #   UMask=0077        — already set upstream, restated for clarity.
      #
      # Rejected (with reasons — do not enable without re-testing playback):
      #   MemoryDenyWriteExecute=true
      #     Breaks .NET's JIT and several ffmpeg codec paths.  Jellyfin will
      #     start but transcodes and some UI actions crash.
      #   IPAddressAllow=<LAN>/16 + IPAddressDeny=any
      #     We deliberately want cross-VLAN clients (see PR manual-steps
     #      checklist for the UDM-Pro ZBF rule); pinning IPAddressAllow to
      #     one subnet would silently break clients on other VLANs.  The
      #     UDM-Pro is the right place to enforce this, not the unit.
      #   RestrictNamespaces=true
      #     Upstream already keeps this false inside containers
      #     (!config.boot.isContainer); forcing it true here would prevent
      #     ffmpeg from doing its per-transcode user-namespace isolation.
      #   ProtectKernelTunables/Modules/Logs=true, PrivateTmp=true,
      #   ProtectControlGroups=true
      #     Same — upstream conditionally disables all of these under
      #     boot.isContainer because they conflict with nspawn's own mount
      #     namespace setup.  Overriding here would either error out at
      #     activation or silently no-op depending on the option.
      systemd.services.jellyfin.serviceConfig = {
        ProtectHome = true;
        UMask       = "0077";
      };
    };
  };
}
