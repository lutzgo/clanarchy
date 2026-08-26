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
# Networking — v2: PRIVATE namespace, veth on br0, Services VLAN 90.
#   Jellyfin has its own L2 identity: a MAC-pinned veth pair whose host side
#   (vb-jellyfin) is a VLAN-90 port on br0, so the UDM-Pro firewalls it as a
#   distinct client rather than as "ernst".  That is what retired ledger row
#   L3 in docs/roadmap.md — the host-side 8096/tcp opening is gone, because
#   the port is no longer a host port.  The ACL lives on the UDM-Pro now.
#
#   THREE THINGS THE v1 HEADER GOT WRONG, kept here so they are not retried:
#     - `containers.jellyfin.macvlans = [ "br-services" ]`.  A macvlan is not
#       a bridge port.  On br0 it rides br0's own "self" VLAN (50, the HOST
#       VLAN); on enp13s0 it rides the trunk's native VLAN, also 50.  Either
#       way it cannot be placed on VLAN 90, which is the entire point.  Use a
#       veth (hostBridge=) instead.
#     - "a MAC-pinned TAP".  A tap is a single netdev and a microvm primitive;
#       handing one to nspawn would move it out of the host netns and off the
#       bridge.  nspawn's primitive is a veth PAIR.  M3's VPN guest is the one
#       that gets a tap.
#     - "br-services".  There is no per-VLAN bridge.  ernst runs ONE
#       VLAN-filtering bridge, br0, and membership is per port.
#     See machines/ernst/networking.nix, worked example B.
#
#   Addressing is DHCP with a reservation on the UDM-Pro, keyed on the pinned
#   MAC below — NOT a static address in this file.  The UDM-Pro already owns
#   the subnet, the pool and every other reservation; a second, silently
#   diverging copy of that here is how you get a duplicate address six months
#   from now.  What IS declared here is the resolver (10.0.5.3, Technitium),
#   for the same reason machines/ernst/networking.nix declares it on br0: a
#   DHCP-supplied resolver that quietly changes does not fail loudly, it fails
#   on the next metadata fetch.
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
#   PCI topology.
#
#   The naive path — /dev/dri/by-path/pci-0000:7b:00.0-render — cannot be
#   used as a systemd-nspawn bind source directly: the --bind=SRC:DST
#   parser tokenizes on ':' and rejects source paths with extra colons.
#   Workaround: an udev rule below creates a colon-free stable symlink
#   /dev/jellyfin-igpu-render pointing at the same physical device, matched
#   by ID_PATH so the PCI-topology guarantee is preserved.  All three
#   consumers (allowedDevices, bindMount, VaapiDevice) use that symlink.
#
#   Verify after a kernel bump (should print the iGPU, not Navi 31):
#     readlink -f /dev/jellyfin-igpu-render
#     nixos-container run jellyfin -- vainfo --display drm --device \
#       /dev/jellyfin-igpu-render
#
# Storage layout on this host (see machines/ernst/disko.nix):
#   /srv/media   zdata/media   RO into container at /srv/media/library
#   /srv/state   zdata/state   RW into container at /var/lib/jellyfin
#   Transcode temp is a tmpfs INSIDE the container — never on zdata.
{ config, lib, pkgs, ... }:
let
  # AMD iGPU render node on ernst (Granite Ridge, 9950X), addressed via a
  # colon-free udev-managed symlink pinned to the PCI address so kernel
  # enumeration order cannot repoint it at the 7900 XTX.  See the file
  # header for the rationale and the post-kernel-bump check.
  #
  # Used verbatim in all three places that must agree — allowedDevices, the
  # bind mount, and the VaapiDevice written into encoding.xml — so they
  # cannot drift apart.
  #
  # On allowedDevices specifically: NixOS passes this string straight through
  # to systemd's DeviceAllow= (nixos-containers.nix:341), and systemd stat()s
  # the path to derive major:minor for the eBPF device filter. stat() follows
  # symlinks, so the symlink resolves correctly and no real node is needed
  # here. If a future systemd ever refuses the symlink, the fallback is
  # to put the numeric node in allowedDevices ONLY — derived with
  # `readlink -f` on the path below — and leave the bind mount and
  # VaapiDevice on the stable symlink name.
  iGpuRenderNode = "/dev/jellyfin-igpu-render";

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

  # Traefik's veth address on VLAN 90 (M5, DHCP reservation on the UDM-Pro
  # keyed on 02:00:00:90:00:04).  Until M13, the ONLY source permitted to reach
  # 8096.
  #
  # Naming a peer's address here is the deliberate opposite of the rule this
  # file follows for its own — see the "BACKEND BYPASS HARDENING" section of
  # machines/ernst/containers/traefik.nix, which owns the argument for why the
  # restriction lives on this side rather than on the UDM-Pro.
  traefikAddr = "10.0.90.12";

  # M13's two API clients.  Same bridge, same VLAN, same one-hop caveat as
  # traefikAddr; see the firewall block below for what each of them wants and
  # why neither can go through the proxy.
  #
  #   .13  arr container      Janitorr, as a real Jellyfin user
  #   .14  monitoring         Prometheus, scraping the NATIVE /metrics endpoint
  arrAddr        = "10.0.90.13";
  monitoringAddr = "10.0.90.14";
in
{
  ##############################################################################
  # Host-side wiring: bind-source dirs, firewall, user shell for the state bind.
  ##############################################################################

  # Colon-free stable symlink for the iGPU render node.  See the file
  # header — systemd-nspawn's --bind=SRC:DST parser rejects paths with
  # extra colons, so we cannot bind /dev/dri/by-path/pci-0000:7b:00.0-render
  # directly.  Matching on ENV{ID_PATH} preserves the same PCI-topology
  # stability guarantee: renderD* enumeration order can flip on a kernel
  # bump, but ID_PATH is derived from the PCI address and cannot.  The
  # SYMLINK+= form adds an alias alongside the stock by-path/by-id links,
  # so nothing else on the host loses its existing render-node names.
  services.udev.extraRules = ''
    SUBSYSTEM=="drm", ENV{ID_PATH}=="pci-0000:7b:00.0", KERNEL=="renderD*", SYMLINK+="jellyfin-igpu-render"
  '';

  # Belt-and-braces: block container start until the symlink exists.
  # On a normal boot udev fires our SYMLINK+= rule when amdgpu loads and
  # the symlink appears before any application service starts, so this is
  # redundant.  Where it earns its keep is the corner case: a runtime
  # udev-rules reload (nixos-rebuild switch) against already-enumerated
  # DRM devices does not re-fire "add" events, so the rule doesn't run
  # and container@jellyfin fails with "Failed to clone
  # /dev/jellyfin-igpu-render: No such file or directory".
  #
  # `udevadm settle --exit-if-exists=<path>` returns as soon as the path
  # exists or the timeout expires.  We pair it with an explicit trigger of
  # the drm subsystem so that reload-then-start deploys don't have to wait
  # for the settle timeout to fail — the trigger fires "add" events for
  # any drm device already present, our rule runs, symlink appears, settle
  # returns immediately.  On a normal boot the trigger is a no-op (the
  # symlink already exists) and the whole service completes in <100 ms.
  systemd.services.jellyfin-igpu-render-symlink = {
    description = "Ensure /dev/jellyfin-igpu-render exists for container@jellyfin";
    wantedBy    = [ "container@jellyfin.service" ];
    before      = [ "container@jellyfin.service" ];
    after       = [ "systemd-udevd.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = false;
      ExecStart = [
        "${pkgs.systemd}/bin/udevadm trigger --subsystem-match=drm --action=add"
        "${pkgs.systemd}/bin/udevadm settle --exit-if-exists=/dev/jellyfin-igpu-render --timeout=30"
      ];
    };
  };

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
  # THE MODES HERE ARE AUTHORITATIVE, and until M3 they disagreed with the
  # oneshot below — which tmpfiles then silently undid on every deploy.
  #
  # The four content directories were declared `0755 root root` here and
  # chowned to `root:media 2770` by jellyfin-library-perms.service. tmpfiles
  # ENFORCES mode and ownership every time it runs, not just at creation, and
  # it runs on every `clan machines update`; the oneshot is RemainAfterExit and
  # runs once per boot. So the oneshot won at boot and tmpfiles took it back at
  # the next deploy, leaving `0755 root:root`.
  #
  # That was invisible for as long as Jellyfin was the only consumer: it never
  # writes, and 0755 grants the traversal it needs while the files themselves
  # are `root:media 0640`. M3 is the first thing to WRITE here, and the failure
  # it produced was `EACCES` on `ln` into library/movies — i.e. exactly the
  # silent copy-instead-of-hardlink that M4 is written to catch, arriving one
  # milestone early. Measured on ernst 2026-08-20.
  #
  # 2770 = setgid + rwxrws---: new files inherit gid media, group members read
  # AND write (qBittorrent writes, the *arr moves and hardlinks), root owns.
  systemd.tmpfiles.rules = [
    "d /srv/media/library            0755 root       root       -"
    "d /srv/media/library/movies     2770 root       media      -"
    "d /srv/media/library/tvshows    2770 root       media      -"
    "d /srv/media/torrents           0755 root       root       -"
    "d /srv/media/torrents/movies    2770 root       media      -"
    "d /srv/media/torrents/tv        2770 root       media      -"
    "d /srv/state/jellyfin           0700 ${toString jellyfinUid} ${toString jellyfinGid} -"
  ];

  # Ownership + setgid on the media subdirs — now a REDUNDANT BACKSTOP that
  # merely agrees with the tmpfiles rules above.  It is kept because it is
  # ordered explicitly after srv-media.mount, which tmpfiles is only implicitly
  # (via local-fs.target); it must never be edited to disagree with them again.
  # If it is ever removed, the tmpfiles rules are the thing that matters.
  #
  # Applied AFTER zdata/media is mounted and BEFORE the container starts.
  # Non-recursive on purpose:
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

  # Host side of the container's veth — a VLAN-90 port on br0.
  #
  # There is deliberately NO `networking.firewall.allowedTCPPorts = [ 8096 ]`
  # here any more.  Under v1 the container shared the host netns, so Jellyfin's
  # port was a host port and had to be opened on the host; that was ledger row
  # L3 in docs/roadmap.md and this milestone retires it.  8096 is now opened
  # inside the container's own netns (see its networking.firewall block) and
  # reachability across VLANs is the UDM-Pro's job.
  #
  # NOT Bridge= — KeepMaster.  nspawn creates this link AND enslaves it to br0
  # itself (--network-bridge=br0).  Setting Bridge= would make networkd fight
  # nspawn over the master; KeepMaster tells networkd to leave the enslavement
  # alone while still applying the [BridgeVLAN] section, which is the only
  # thing we actually want from it.
  #
  # No L3 of its own: a bridge port carries no address, and IPv6AcceptRA on a
  # port would have it answer router advertisements meant for the container.
  #
  # 60- prefix, so it sorts after the 50-* topology units in
  # machines/ernst/networking.nix and well ahead of the 99-* wildcards.
  systemd.network.networks."60-vb-jellyfin" = {
    matchConfig.Name = "vb-jellyfin";   # "vb-", not "ve-" — see the header
    networkConfig = {
      KeepMaster          = true;
      LinkLocalAddressing = "no";
      IPv6AcceptRA        = false;
    };
    bridgeVLANs = [ { VLAN = 90; PVID = 90; EgressUntagged = 90; } ];
    # A bridge port's terminal operational state is "enslaved"; it never
    # becomes routable, and waiting for that would hang boot.
    linkConfig.RequiredForOnline = "enslaved";
  };

  # Re-assert the VLAN membership after nspawn has created the veth.
  #
  # This is a real race, not a defensive tic.  networkd applies [BridgeVLAN]
  # only once it observes the link's master — and nspawn sets that master out
  # of band, from container@jellyfin.service, after the link appears.  If
  # networkd processes the "new link" event before nspawn's `ip link set …
  # master br0`, the bridgeVLANs block above is applied to a link that is not
  # yet a bridge port and quietly does nothing.
  #
  # With DefaultPVID = "none" on br0 (machines/ernst/networking.nix, note 4)
  # the failure is fail-CLOSED — the container ends up on no VLAN at all and
  # has no connectivity — rather than fail-open onto VLAN 50, the host VLAN.
  # That is the right failure, but it is still a failure, and one that looks
  # like "Jellyfin is down" rather than like a VLAN problem.
  #
  # `bridge vlan add` is idempotent: re-adding an existing vid/pvid/untagged
  # tuple is a no-op, so this agrees with networkd rather than competing with
  # it.  Same belt-and-braces shape as jellyfin-igpu-render-symlink above.
  # `bridge vlan show dev vb-jellyfin` remains the check — do not trust
  # silence from either mechanism.
  #
  # The "-" prefix is deliberate: a backstop must not become a new failure
  # mode.  Without it, `bridge` exiting non-zero (link already gone during a
  # restart, say) would fail container@jellyfin and put it in a restart loop —
  # taking Jellyfin down to protect against a race that networkd usually wins
  # on its own.
  systemd.services."container@jellyfin".serviceConfig.ExecStartPost = [
    "-${pkgs.iproute2}/bin/bridge vlan add dev vb-jellyfin vid 90 pvid untagged"
  ];

  ##############################################################################
  # The container itself.
  ##############################################################################
  containers.jellyfin = {
    autoStart      = true;
    ephemeral      = false;         # jellyfin state persists via bind mount below

    # Own netns, own L2 identity.  See the file header for why this is a veth
    # on br0 and not a macvlan or a tap.
    #
    # hostBridge makes nixos-containers pass --network-bridge=br0 to nspawn,
    # which creates the pair, names the HOST side vb-jellyfin (not ve-) and
    # enslaves it to br0 itself.  The container side is renamed host0 → eth0
    # by container-init, which also applies the MAC below before the interface
    # is brought up — so the address is stable from the first DHCP DISCOVER,
    # which is exactly what a reservation needs.
    #
    # Locally-administered (02:…) so it cannot collide with a vendor OUI.
    # Convention 02:00:00:<vlan>:00:<seq>; the allocation table lives in
    # machines/ernst/networking.nix.  This is the MAC the UDM-Pro sees and the
    # one the DHCP reservation must key on — never the host-side vb-jellyfin.
    #
    # No hostAddress/localAddress: those are for the point-to-point veth mode,
    # where nspawn's veth is not on a bridge and the host routes to it.  Here
    # the bridge carries the traffic and the UDM-Pro supplies the address.
    privateNetwork  = true;
    hostBridge      = "br0";
    localMacAddress = "02:00:00:90:00:02";

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

      # The canonical DRM directory.  This is what made VAAPI work; without it
      # libva fails with "Failed to a DRM display for the given device" even
      # though the render node above opens fine.
      #
      # The alias is enough to *open* the device but not enough for mesa to
      # bring up a DRM display: it re-derives canonical /dev/dri/renderD* and
      # /dev/dri/card* names from the fd and looks them up on disk, so a
      # container where /dev/dri does not exist cannot initialise radeonsi no
      # matter how the node is bound.  See docs/incidents/
      # ernst-jellyfin-vaapi-drm-display-failure-2026-08-18.md for the A/B
      # reproduction.
      #
      # This does NOT widen the container's reach to the 7900 XTX.  Binding
      # the directory only makes the nodes *visible*; DeviceAllow above still
      # gates opening them, and it is keyed on major:minor.  Verified inside a
      # container with exactly this config:
      #     /dev/dri/renderD129 (iGPU)  OPEN_OK
      #     /dev/dri/renderD128 (dGPU)  DENIED
      #     /dev/dri/card1      (dGPU)  DENIED
      # so the "do not hand the XTX to Jellyfin" property in the file header
      # is preserved by the cgroup rather than by absence of the node.
      "/dev/dri" = {
        hostPath   = "/dev/dri";
        isReadOnly = false;
      };
    };

    ############################################################################
    # NixOS config for the container's own root filesystem.
    ############################################################################
    config = { config, pkgs, lib, ... }: {
      system.stateVersion = "26.05";

      ##########################################################################
      # Networking.  The container owns its netns now, so it owns all of this.
      ##########################################################################

      # v1 inherited the host's resolv.conf, which was only ever correct
      # BECAUSE the container shared the host's netns.  With a private netns
      # that copy is a stale snapshot of someone else's resolver, so it has to
      # go — and it has to go for a second reason: services.resolved asserts
      # !networking.useHostResolvConf, so leaving it true is a hard eval error
      # rather than a subtle one.  virtualisation/container-config.nix sets it
      # `mkDefault true`, so a plain `false` wins without mkForce.
      networking.useHostResolvConf = false;

      # networkd + resolved, mirroring the host (machines/ernst/networking.nix)
      # rather than inventing a second idiom for the same job.  networkd on its
      # own never writes /etc/resolv.conf — that is resolved's half of the pair,
      # and without it the DNS= line below would be inert.
      networking.useNetworkd = true;
      services.resolved.enable = true;

      # eth0 — renamed from host0 by container-init before stage 2 runs, so it
      # already exists under this name by the time networkd starts.
      #
      # ADDRESS: DHCP, reserved on the UDM-Pro against the pinned MAC.  See the
      # file header for why the reservation is not duplicated here.
      #
      # RESOLVER: declared, not inherited.  UseDNS/UseDomains = false so a
      # future change to the Services network's DHCP options cannot silently
      # move Jellyfin off Technitium — the same reasoning as note 1 in
      # machines/ernst/networking.nix, and the same failure mode: it would not
      # error, it would just start resolving somewhere else.
      #
      # "~." is a ROUTING domain — every lookup goes to 10.0.5.3, so
      # Technitium's blocklists and logging cover the container too.
      # "skynet.lan" is the bare-hostname search suffix.
      #
      # Check on ernst with:  nixos-container run jellyfin -- resolvectl status eth0
      systemd.network.networks."10-eth0" = {
        matchConfig.Name = "eth0";
        networkConfig = {
          DHCP         = "ipv4";
          DNS          = "10.0.5.3";
          Domains      = "~. skynet.lan";
          IPv6AcceptRA = false;
        };
        dhcpV4Config = {
          UseDNS     = false;
          UseDomains = false;
        };
        linkConfig.RequiredForOnline = "routable";
      };

      # 20 s, and the number is load-bearing — do not raise it past ~50.
      #
      # services.jellyfin is `after`/`wants` network-online.target, so inside
      # the container systemd-networkd-wait-online gates Jellyfin's start on
      # eth0 reaching "routable", i.e. on a DHCP lease.  That ordering is what
      # we want in the happy path.
      #
      # The trap is the interaction with the HOST unit.  container@jellyfin is
      # Type=notify with TimeoutStartSec=1min (the nixos-containers default),
      # and the container only notifies READY once its own boot completes.  At
      # the stock 120 s wait-online timeout, a DHCP failure — a missing UDM-Pro
      # reservation, a VLAN 90 that did not land — would stall the container's
      # boot past 60 s, so the host would kill it and Restart=on-failure would
      # loop it forever, never reaching a state you can log into and debug.
      #
      # At 20 s the container finishes booting in every case: wait-online fails,
      # network-online.target is reached anyway (a failed Wants= does not block
      # a target), Jellyfin starts, and you are left with a RUNNING container
      # holding one obviously failed unit.  That is the diagnosable failure.
      systemd.network.wait-online.timeout = 20;

      # The container's own firewall, in its own netns.  NixOS enables the
      # firewall by default and virtualisation/container-config.nix does not
      # turn it off, so this is a real enforcement point rather than a
      # decoration — but it is now the ONLY one in the repo: under v1 the host
      # opened this port (ledger row L3), and cross-VLAN reachability is the
      # UDM-Pro's job from here on.
      #
      # 8096/tcp (HTTP) only.  The v1 rationale for each exclusion is unchanged
      # and, if anything, stronger on an isolated VLAN:
      #   8920/tcp   HTTPS.  TLS terminates at Traefik (M5); Jellyfin's own
      #              HTTPS listener is unused.
      #   7359/udp   client auto-discovery.  Broadcast-based, so it is worth
      #              even less on VLAN 90 than it was on VLAN 50 — nothing that
      #              would answer it shares this broadcast domain.
      #   1900/udp   DLNA/SSDP.  Same, plus a well-worn RCE surface.  Disable
      #              it in the Jellyfin UI too (Dashboard → DLNA).
      #
      # ── M5: 8096 IS NO LONGER OPEN TO THE VLAN ────────────────────────────
      #
      # It was `allowedTCPPorts = [ 8096 ]` until M5.  Now the only source that
      # may reach it is Traefik, and the list is EMPTY so that nothing grants
      # the port unconditionally before the restricted rule below is reached.
      #
      # Why extraCommands and not allowedTCPPorts: the NixOS firewall has no
      # per-source form of that option.  `extraInputRules` looks like the
      # modern answer and is a TRAP HERE — it is declared unconditionally in
      # nixos/modules/services/networking/firewall-nftables.nix but consumed
      # ONLY when networking.nftables.enable is true, which it is not.  Setting
      # it would produce no rule, no warning and no error: a bypass protection
      # that silently does not exist.  extraCommands is the iptables backend's
      # own escape hatch and cannot fail quietly — a rule that will not insert
      # fails the firewall unit.
      #
      # PLACEMENT IS WHAT MAKES IT WORK.  firewall-iptables.nix's start script
      # emits, in order: the allowedTCPPorts accepts, then extraCommands, then
      # a final `-A nixos-fw -j nixos-fw-log-refuse`.  So appending here lands
      # after every other accept and before the catch-all refuse — traffic from
      # traefikAddr is accepted, everything else to 8096 falls through and is
      # rejected.  There is nothing to add to extraStopCommands: the script
      # flushes and recreates the nixos-fw chain on every start and reload, so
      # these rules are rebuilt from scratch rather than accumulated.
      #
      # `iptables`, not `ip46tables`: traefikAddr is IPv4 and IPv6AcceptRA is
      # off on eth0, so there is no v6 path to this port to restrict.
      #
      # CONSEQUENCE: `curl http://10.0.90.10:8096` from a laptop or from ernst
      # now fails, and that is the milestone working.  To reach Jellyfin
      # directly for debugging, go in through the container, where `lo` is
      # always trusted by the NixOS firewall:
      #     nixos-container run jellyfin -- curl -sS localhost:8096/health
      #
      # ── M13: TWO MORE SOURCES, AND NEITHER IS A BROWSER ───────────────────
      #
      # Until M13 this list had exactly one entry, because 8096 only ever
      # fronted a browser and Traefik was the only way to a browser.  M13 adds
      # two API clients that are not behind the proxy and cannot be:
      #
      #   10.0.90.13  the arr container — JANITORR.  It needs Jellyfin's API to
      #               build the "Leaving Soon" collections and, once dry-run is
      #               turned off, to issue deletes.  It authenticates as a real
      #               Jellyfin USER (see the janitorr blocks in arr.nix); it is
      #               not riding Traefik's session.
      #   10.0.90.14  the monitoring container — PROMETHEUS.  Jellyfin's NATIVE
      #               /metrics endpoint, enabled below.  No exporter.
      #
      # Both are single layer-2 hops on br0, so — as with the Traefik rule —
      # their frames never reach the UDM-Pro and this chain is the only
      # enforcement point that exists for them.
      #
      # THE SAME PORT, THREE SOURCES, AND THAT IS THE COST OF JELLYFIN'S
      # DESIGN: /metrics is served on 8096 alongside the media API rather than
      # on a separate listener, so permitting a scrape necessarily permits the
      # monitoring container to reach everything else on 8096 too.  That is
      # accepted here — the monitoring container runs Prometheus, Alertmanager
      # and Grafana and nothing that takes untrusted input — but it is stated
      # rather than glossed, because it is strictly weaker than Authelia's and
      # Traefik's arrangement, where the telemetry listener is its own port.
      networking.firewall.allowedTCPPorts = [ ];
      networking.firewall.extraCommands = ''
        iptables -A nixos-fw -p tcp -s ${traefikAddr}/32 --dport 8096 -j nixos-fw-accept
        iptables -A nixos-fw -p tcp -s ${arrAddr}/32 --dport 8096 -j nixos-fw-accept
        iptables -A nixos-fw -p tcp -s ${monitoringAddr}/32 --dport 8096 -j nixos-fw-accept
      '';

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
        enable = true;

        # STILL false, and for a new reason.  Under v1 this was false because
        # the host firewall carried the port; the obvious v2 move is to flip it
        # true now that the container has its own netns.  Don't: upstream's
        # openFirewall opens 8096 AND 8920/tcp AND 1900+7359/udp
        # (nixos/modules/services/misc/jellyfin.nix), i.e. exactly the three
        # ports this file has always refused.  The explicit 8096-only list is
        # in the networking block above.
        openFirewall = false;

        # ── M13: /metrics IS NATIVE.  SEE jellyfin-enable-metrics BELOW ──────
        #
        # M13 requires Jellyfin's OWN metrics endpoint and forbids adding an
        # exporter for it.  The endpoint is real in this version: 10.11.11
        # ships Prometheus.AspNetCore.dll, Prometheus.NetStandard.dll and
        # prometheus-net.DotNetRuntime.dll (checked in the store path, not
        # assumed from release notes).
        #
        # Enabling it is NOT a dashboard step — see that unit for why this file
        # ended up owning one XML element.
        hardwareAcceleration = {
          enable = true;
          type   = "vaapi";
          device = iGpuRenderNode;    # written into encoding.xml as VaapiDevice
        };

        # NixOS owns encoding.xml from here on.
        #
        # Without this, the module writes encoding.xml only when the file is
        # absent, and otherwise logs "encoding.xml already exists and is
        # different from the configured settings. transcoding options NOT
        # applied." That is how HardwareAccelerationType silently drifted to
        # `none` — set through Jellyfin's dashboard during the 2026-08-18
        # rollback, then never corrected on deploy, so the settings below were
        # declared but inert. Enabling hardware encoding under type `none`
        # does nothing at all, which is a genuinely hard failure to read.
        #
        # The trade documented upstream: transcoding settings changed in the
        # web dashboard are now discarded on the next restart. That is the
        # intent — this is the machine where "what the repo says" should win.
        # The module writes a timestamped encoding.xml.backup-* before each
        # overwrite.
        #
        # Note the generated file is *smaller* than what Jellyfin maintains:
        # the module's template omits ~20 elements (tonemapping algorithm,
        # deinterlace method, muxing queue size, EnableDecodingColorDepth10*,
        # …). Those revert to Jellyfin's own defaults, which is where they
        # already were — checked element by element against the live file
        # before this was turned on. TranscodingTempPath is likewise absent,
        # so transcodes land in <cacheDir>/transcodes, i.e. the tmpfs below.
        forceEncodingConfig = true;

        transcoding = {
          # The setting the whole VAAPI exercise was about. Verified on ernst
          # after PR #50: 10-bit HEVC -> h264_vaapi at 9.4x realtime on the
          # iGPU. Everything else in `transcoding` is left at the module
          # default, each of which already matches what Jellyfin had.
          enableHardwareEncoding = true;

          # Decode side. Mirrors what the library actually holds; hevc is the
          # one that matters most, since much of it is HEVC Main 10.
          hardwareDecodingCodecs = {
            h264 = true;
            hevc = true;
            vp9  = true;
          };
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
      ##########################################################################
      # M13 — flip EnableMetrics in Jellyfin's own system.xml.
      #
      # ── THIS WAS PLANNED AS A MANUAL STEP AND THE MANUAL STEP DOES NOT EXIST
      #
      #   The PR body said "Dashboard → Advanced → enable metrics".  THERE IS
      #   NO SUCH TOGGLE.  Jellyfin removed the metrics switch from the web UI;
      #   in 10.11.11 `EnableMetrics` is a ServerConfiguration property that
      #   lives ONLY in config/system.xml, and the NixOS module exposes no
      #   option for it.  Confirmed on ernst, 2026-08-26:
      #
      #     <EnableMetrics>false</EnableMetrics>
      #
      #   present in the file, absent from every dashboard page.  So the choice
      #   was never "declare it or let a human click it" — it was "declare it
      #   or hand-edit XML on every fresh install and after any reset".
      #
      # ── WHY THIS DOES NOT CONTRADICT THE `forceEncodingConfig` REASONING ──
      #
      #   The argument against Nix owning system.xml still holds completely:
      #   that file carries every other server setting there is, and a
      #   store-rendered copy would clobber settings this repo has no opinion
      #   about.  This unit does NOT own the file.  It rewrites ONE ELEMENT and
      #   leaves the other several hundred bytes exactly as Jellyfin wrote
      #   them — closer to `sed -i` than to a template.
      #
      # ── IT HAS TO RUN WHILE JELLYFIN IS STOPPED ──────────────────────────
      #
      #   Jellyfin rewrites system.xml from memory on shutdown, so an edit made
      #   while it is running is discarded at the next restart — which is
      #   exactly how a hand-edit "mysteriously reverts".  ExecStartPre runs in
      #   the gap and is therefore the only safe moment.
      #
      #   Idempotent by construction: it matches only the `false` form, so a
      #   second run is a no-op, and a future Jellyfin that ships the element
      #   already true is left alone.
      #
      #   It does NOT create the element if absent.  An upstream that stops
      #   emitting `EnableMetrics` has changed something this file should not
      #   paper over, so it warns and lets the scrape job go down visibly.
      systemd.services.jellyfin.serviceConfig.ExecStartPre = [
        "${pkgs.writeShellScript "jellyfin-enable-metrics" ''
          set -euo pipefail
          conf=/var/lib/jellyfin/config/system.xml

          if [ ! -f "$conf" ]; then
            echo "jellyfin: $conf does not exist yet — first start, nothing to patch" >&2
            exit 0
          fi

          if ! ${pkgs.gnugrep}/bin/grep -q '<EnableMetrics>' "$conf"; then
            echo "jellyfin: no <EnableMetrics> element in $conf — upstream changed; /metrics will stay off" >&2
            exit 0
          fi

          ${pkgs.gnused}/bin/sed -i \
            's|<EnableMetrics>false</EnableMetrics>|<EnableMetrics>true</EnableMetrics>|' \
            "$conf"
        ''}"
      ];

      systemd.services.jellyfin.serviceConfig = {
        ProtectHome = true;
        UMask       = "0077";
      };
    };
  };
}
