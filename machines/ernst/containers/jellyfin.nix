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
#   ernst carries two AMD GPUs (see PR test plan for probe commands):
#     /dev/dri/renderD128  card1  PCI 03:00.0  Navi 31 (RX 7900 XTX)  — DO NOT bind
#     /dev/dri/renderD129  card0  PCI 7b:00.0  Granite Ridge iGPU     — this file
#   Enumeration order can flip on future kernel updates.  If VAAPI stops
#   working after a bump, re-run the probe from the PR test plan and update
#   the paths below (and confirm via `vainfo` inside the container).
#
# Storage layout on this host (see machines/ernst/disko.nix):
#   /srv/media   zdata/media   RO into container at /srv/media/library
#   /srv/state   zdata/state   RW into container at /var/lib/jellyfin
#   Transcode temp is a tmpfs INSIDE the container — never on zdata.
{ config, lib, pkgs, ... }:
let
  # AMD iGPU render node on ernst (Granite Ridge, 9950X).  See file header
  # for the probe procedure and the rationale for pinning by number.
  iGpuRenderNode = "/dev/dri/renderD129";

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
  # The state dir + the library parent are plain subdirectories on already-
  # mounted datasets (zdata/state and zdata/media respectively), so tmpfiles
  # handles them fine — its rules apply after those parent-dataset mounts land.
  #
  # /srv/media/library/{movies,tvshows} are DIFFERENT: they are the mountpoints
  # of zdata/media/{movies,tvshows} themselves.  systemd-tmpfiles-setup.service
  # has no ordering relationship to those mount units, so a tmpfiles rule here
  # races the mount — the rule applies to the empty underlying directory, the
  # dataset then mounts over it, and what is visible after boot is what
  # `zfs create` left behind (drwxr-xr-x root:root, no setgid).  See the
  # library-perms oneshot below for the ordered fix.
  systemd.tmpfiles.rules = [
    "d /srv/media/library            0755 root       root       -"
    "d /srv/state/jellyfin           0700 ${toString jellyfinUid} ${toString jellyfinGid} -"
  ];

  # Ownership + setgid on the two library mountpoints, applied AFTER the ZFS
  # dataset mounts and BEFORE the container starts.  Non-recursive on purpose:
  # up to 20 TB of media may sit under these paths at any given deploy, and
  # the copy job (rsync --chown=root:media --chmod=…) already sets per-file
  # ownership — recursing here would rewrite metadata on ~33k files for no
  # benefit.  Mode 2750 = setgid + rwxr-x---: new files inherit gid=media,
  # group members read-only, root owns (only a root-invoked helper can
  # rearrange the library tree).  Idempotent: chown/chmod on an already-
  # correct dir is a no-op.
  #
  # Any future zdata dataset seeded with tmpfiles rules targeting the
  # dataset ROOT (as opposed to a subdirectory of an already-mounted dataset)
  # will hit the same race — the pattern to reach for is this oneshot, not
  # a fourth tmpfiles line.
  systemd.services.jellyfin-library-perms = {
    description = "Set root:media 2750 on Jellyfin library dataset mountpoints";
    wantedBy    = [ "multi-user.target" ];
    before      = [ "container@jellyfin.service" ];
    after       = [ "srv-media-library-movies.mount"
                    "srv-media-library-tvshows.mount" ];
    requires    = [ "srv-media-library-movies.mount"
                    "srv-media-library-tvshows.mount" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
      ExecStart = [
        "${pkgs.coreutils}/bin/chown root:media /srv/media/library/movies /srv/media/library/tvshows"
        "${pkgs.coreutils}/bin/chmod 2750       /srv/media/library/movies /srv/media/library/tvshows"
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
      # differently (dedicated zdata/media/{movies,tvshows} datasets under
      # /srv/media/library) so Nextcloud can later expose the same tree as
      # external storage without inheriting a legacy path scheme.  The bind
      # is the translation layer: the container sees the paths the DB
      # expects, the host keeps a clean /srv/media/library/{movies,tvshows}
      # layout.  RO on both — Jellyfin never writes to library data.
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
        # `render` grants access to /dev/dri/renderD129 (mode 0666 makes this
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
