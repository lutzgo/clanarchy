# ernst — VLAN-filtering bridge networking (systemd-networkd).
#
# ── Physical NICs (AM5 / X870E) ───────────────────────────────────────────
#   enp13s0  Marvell AQtion AQC113CS (atlantic) — 10GBASE-T copper into
#            USW Pro 24 PoE **port 6**, which is a GbE port, so the link
#            negotiates at 1000 Mb/s (verified 2026-08-19: /sys/class/net/
#            enp13s0/speed = 1000).  Earlier revisions of this file called it
#            "SFP+ to the UDM-Pro" — wrong on both counts; the UDM-Pro's
#            SFP+2 is the 10G uplink to that switch, not ernst's port.
#            NO LONGER carries an address: it is a TAGGED TRUNK PORT on br0.
#            Takes ~10 s to gain link at boot; docs/guides/remote-unlock.md
#            polls for exactly that reason.
#   enp12s0  Intel I226-V 2.5G (igc) — intentionally unplugged, left
#            unconfigured.  Must never block boot (see note 6).
#
# ── Topology ──────────────────────────────────────────────────────────────
#
#   UDM-Pro SFP+ ══ trunk ══ enp13s0 ──┐
#                                      ├─ br0 ─ 10.0.50.10/24  (host, untagged VLAN 50)
#   per-service veths / taps (M2b…) ───┘
#
# ── VLAN map (source of truth: UDM-Pro "skynet-udmpro") ───────────────────
#
#    ID  Name              Subnet          On this trunk
#     1  LAN ("Family")    10.0.10.0/24    tagged
#     5  DNS-Container     10.0.5.0/24     tagged   (Technitium 10.0.5.3)
#    20  IoT               10.0.20.0/24    tagged
#    30  HA                10.0.30.0/24    NOT carried
#    40  Guest             10.0.40.0/24    NOT carried
#    50  Servers           10.0.50.0/24    UNTAGGED / PVID  ← ernst itself
#    60  Matter            10.0.60.0/24    NOT carried
#    70  Travel (wg)                       NOT carried
#    80  Services          10.0.80.0/24    tagged   (M2b Jellyfin, M5 Traefik)
#
#   Services is 80, not 70: 70 is already the travel/WireGuard VLAN — the one
#   M5's ipAllowList and M7's "wg-travel must not be locked out" note mean.
#
#   80 is tagged now, before anything uses it, so M2b/M3/M5 never need a
#   switch-port change.  30/40/60/70 are deliberately absent: a VLAN that is
#   not on the trunk cannot be reached by a typo in a future container unit.
#   Travel reaches services through Traefik (M5), not by riding this trunk.
#
# ── What is load-bearing ──────────────────────────────────────────────────
#
# 1. Domains = "~. skynet.lan" on 50-br0.  "~." is a ROUTING domain: it makes
#    10.0.5.3 (Technitium) the resolver for EVERY lookup this machine does, so
#    its blocklists and logging apply.  "skynet.lan" is the bare-hostname
#    search suffix.  modules/networking/resolved.nix sets NO global DNS — only
#    FallbackDNS = 1.1.1.1 9.9.9.9 — so losing this line does not fail loudly,
#    it silently moves ernst onto Cloudflare and the NEXT deploy fails on name
#    resolution.  Check with `resolvectl status br0`.
#
# 2. MulticastDNS = true — ernst.local across the LAN and ZeroTier
#    (modules/networking/mdns.nix).  clan-core only mkDefaults MulticastDNS
#    onto its own 99-* units, never ours, so it must be restated here.
#
# 3. The bridgeVLANs block on 50-br0 (NOT on the port).  On a VLAN-filtering
#    bridge the bridge DEVICE is itself a member port for locally-originated
#    traffic.  systemd-networkd expresses that by applying the [BridgeVLAN]
#    sections of the BRIDGE'S OWN .network with the netlink BRIDGE_FLAGS_SELF
#    flag — i.e. `bridge vlan add dev br0 vid 50 pvid untagged self`.  Without
#    it the host holds an address on br0 and cannot emit a single frame.
#    systemd.network(5) confirms both halves: the section "manages the VLAN ID
#    configuration of a bridge master or enslaved device", and "all assigned
#    VLAN IDs on the interface that are not configured in the .network file
#    will be removed" — so each list below is the complete truth for its link,
#    not an addition to a default.
#
#    br0's own list is 50 ONLY, deliberately.  The bridge master's membership
#    governs what the HOST terminates, not what the ports forward between
#    themselves: a future tap on VLAN 80 reaches enp13s0's VLAN 80 without br0
#    being a member, because ernst does not hold an address there.  Add a VLAN
#    here only if the host itself needs to speak on it — which would also put
#    Avahi's unpinned mDNS reflector onto that VLAN (modules/networking/
#    mdns.nix), so it is not a free change.
#
# 4. DefaultPVID = "none".  A numeric default PVID makes the KERNEL hand every
#    newly enslaved port that VLAN untagged — so a container veth that appears
#    before (or without) its own .network would silently join VLAN 50, the host
#    VLAN.  "none" makes an unconfigured port a dead port instead: fail-closed,
#    which is what architecture invariant #3 wants.  The price is that both
#    memberships below are explicit and both must be correct.
#
# 5. Unit ordering.  networkd applies the FIRST .network whose [Match] fits, in
#    lexical filename order; the 50-* prefix is what makes ours win against the
#    99-* wildcards.  br0 needs to win too, hence 50-br0.
#
# 6. wait-online.  clan-core sets `systemd.network.wait-online.enable = false`
#    as a PLAIN assignment (nixosModules/clanCore/networking.nix), so nothing
#    here can block boot on the unplugged enp12s0, and the anyInterface /
#    ignoredInterfaces workaround an earlier revision of this file suggested
#    would be inert (it would also need mkForce to re-enable the service at
#    all).  RequiredForOnline below is therefore `networkctl` hygiene and
#    documentation.  It still matters: a bridge PORT never reaches "routable",
#    so if wait-online is ever force-enabled the port must stay at "enslaved"
#    or boot would hang forever.
#
# Cutover procedure: docs/runbooks/ernst-vlan-bridge-cutover.md.  The UDM-Pro
# port changes happen BEFORE this config is deployed, and are verified with
# ernst still untouched.
{ ... }:
{
  ###########################################################################
  # The bridge device.
  ###########################################################################
  systemd.network.netdevs."50-br0" = {
    netdevConfig = {
      Name = "br0";
      Kind = "bridge";
      # MACAddress is deliberately NOT pinned here.  With exactly one port the
      # kernel gives br0 enp13s0's burned-in MAC, so ernst's L2 identity on
      # VLAN 50 is unchanged by the cutover — which is what we want on the one
      # deploy that can lock us out.
      #
      # BEFORE M2b adds a second port this MUST be pinned: a Linux bridge
      # adopts the numerically LOWEST port MAC, so a veth or tap appearing
      # later can silently move the host's MAC and invalidate the UDM-Pro's
      # client tracking.  §1 of the cutover runbook captures the value:
      #   ip -br link show enp13s0
      # MACAddress = "xx:xx:xx:xx:xx:xx";
    };
    bridgeConfig = {
      VLANFiltering = true;
      DefaultPVID   = "none";   # note 4 — fail-closed for unconfigured ports
      # Single uplink, so there is no loop to detect; STP would only emit
      # BPDUs at the UDM-Pro and delay every new port reaching forwarding.
      STP           = false;
    };
  };

  ###########################################################################
  # br0 — the host's L3 identity.  Address / Gateway / DNS / Domains /
  # MulticastDNS are carried over verbatim from the old 50-enp13s0 unit.
  ###########################################################################
  systemd.network.networks."50-br0" = {
    matchConfig.Name = "br0";
    networkConfig = {
      Address      = "10.0.50.10/24";
      Gateway      = "10.0.50.1";
      DNS          = "10.0.5.3";
      Domains      = "~. skynet.lan";   # note 1 — do not drop, do not reorder
      MulticastDNS = true;              # note 2
      # Configure the address even before the trunk has carrier (atlantic
      # needs ~10 s).  Services binding 10.0.50.10 then do not race the link,
      # and on the KVM console "address present, no L2" is distinguishable
      # from "networkd never got here".
      ConfigureWithoutCarrier = true;
    };

    # note 3 — applied to the bridge device itself (BRIDGE_FLAGS_SELF).
    # This single block is what makes the HOST work untagged on VLAN 50.
    bridgeVLANs = [ { VLAN = 50; PVID = 50; EgressUntagged = 50; } ];

    linkConfig.RequiredForOnline = "routable";
  };

  ###########################################################################
  # enp13s0 — tagged trunk port on br0.  No address of its own.
  ###########################################################################
  systemd.network.networks."50-enp13s0" = {
    matchConfig.Name = "enp13s0";
    networkConfig = {
      Bridge              = "br0";
      # A bridge port carries no L3 of its own.
      LinkLocalAddressing = "no";
      IPv6AcceptRA        = false;
    };

    bridgeVLANs = [
      # Untagged / PVID — the Servers VLAN.  This is ernst's own traffic, and
      # the VLAN stage-1 initrd SSH depends on (see the initrdSsh block).
      { VLAN = 50; PVID = 50; EgressUntagged = 50; }
      # Tagged, for guests later milestones place on br0.
      { VLAN = 1;  }   # LAN / "Family"
      { VLAN = 5;  }   # DNS-Container (Technitium 10.0.5.3)
      { VLAN = 20; }   # IoT
      { VLAN = 80; }   # Services — M2b Jellyfin, M5 Traefik
    ];

    # "enslaved", not "yes": a bridge port's terminal operational state IS
    # enslaved and it never becomes routable.  See note 6.
    linkConfig.RequiredForOnline = "enslaved";
  };

  ###########################################################################
  # Restore the upstream [Match] on nixpkgs' catch-all DHCP unit.
  #
  # That unit normally carries `matchConfig = { Type = "ether"; Kind = "!*"; }`,
  # but the whole block is `mkIf networking.useDHCP`, and useDHCP is FALSE on
  # ernst (NetworkManager, pulled in by the htpc role via modules/desktop/
  # kde.nix, sets it false).  clan-core still writes
  # `networks."99-ethernet-default-dhcp".networkConfig.MulticastDNS`
  # unconditionally, so the unit survives with an EMPTY [Match] — which matches
  # EVERY link.  Verified:
  #   nix eval --json '.#nixosConfigurations.ernst.config.systemd.network\
  #     .networks."99-ethernet-default-dhcp".matchConfig'      →      {}
  #
  # Harmless while every interface has its own 50-* unit.  Not harmless on a
  # bridge host, which grows taps and vb-* veths that a matchless .network can
  # claim — and, having no Bridge= and no KeepMaster=, detach from br0.
  ###########################################################################
  systemd.network.networks."99-ethernet-default-dhcp".matchConfig = {
    Type = "ether";
    Kind = "!*";   # physical devices only — bridges/veths/taps have a Kind
  };

  ###########################################################################
  # NetworkManager: hands off the bridge and its uplink.
  #
  # ernst runs BOTH networkd (this file) and NetworkManager (kde.nix, via the
  # htpc role).  NM auto-creating a DHCP profile on br0 during the cutover
  # would be a lockout, so the hands-off is stated explicitly rather than left
  # to udev's ID_NET_MANAGED_BY tagging.
  #
  # Container veths are NOT listed: nixpkgs already ships a udev rule marking
  # v[eb]-* as NM_UNMANAGED whenever NetworkManager is enabled (see
  # nixos/modules/virtualisation/nixos-containers.nix).  Repeating it here
  # would be a second source of truth for the same thing.  tap-* IS listed —
  # nothing upstream covers the microvm taps M3 will add.
  #
  # This appends to clan-core's existing "interface-name:zt*" entry.
  ###########################################################################
  networking.networkmanager.unmanaged = [
    "interface-name:br0"
    "interface-name:enp13s0"
    "interface-name:enp12s0"
    "interface-name:tap-*"
  ];

  #===========================================================================
  # WORKED EXAMPLES for M2b / M3 / M5 — commented out on purpose.
  #
  # These are TWO patterns, not one.  Earlier notes said "MAC-pinned tap" for
  # both nspawn containers and microvms; that is only correct for microvms.  A
  # tap is a SINGLE netdev, and handing it to an nspawn container would move it
  # out of the host netns and off the bridge.  nspawn's primitive is a veth
  # PAIR.  Use A for microvms, B for nspawn containers.
  #
  # Do NOT use `containers.<n>.macvlans`, as sketched in the header of
  # machines/ernst/containers/jellyfin.nix.  A macvlan is not a bridge port:
  # attached to br0 it rides br0's own "self" VLAN — 50, the HOST VLAN — and
  # attached to enp13s0 it rides the trunk's native VLAN, also 50.  Either way
  # it cannot be placed on VLAN 80, which is the entire point.  (That sketch
  # presumes a per-VLAN bridge fed by an enp13s0.80 VLAN netdev: a different
  # architecture, rejected here in favour of one VLAN-aware br0.  Correcting
  # that file header belongs to M2b, which owns the file.)
  #
  # MAC policy for both: locally-administered (02:…) so it cannot collide with
  # a vendor OUI.  Convention below: 02:00:00:<vlan>:00:<seq>.  The MAC the
  # UDM-Pro sees — and that a DHCP reservation must key on — is the GUEST or
  # CONTAINER side, never the host-side veth/tap.
  #===========================================================================

  # ── A. microvm / QEMU guest (M3: VPN + qBittorrent) ──────────────────────
  #
  # systemd.network.netdevs."60-tap-vpn" = {
  #   netdevConfig = { Name = "tap-vpn"; Kind = "tap"; };
  #   tapConfig    = { User = "microvm"; Group = "kvm"; };   # who may open it
  # };
  # systemd.network.networks."60-tap-vpn" = {
  #   matchConfig.Name = "tap-vpn";
  #   networkConfig = {
  #     Bridge              = "br0";
  #     LinkLocalAddressing = "no";
  #     IPv6AcceptRA        = false;
  #   };
  #   bridgeVLANs = [ { VLAN = 80; PVID = 80; EgressUntagged = 80; } ];
  #   linkConfig.RequiredForOnline = "enslaved";
  # };
  # …and in the guest:
  #   microvm.interfaces = [
  #     { type = "tap"; id = "tap-vpn"; mac = "02:00:00:80:00:03"; }
  #   ];

  # ── B. systemd-nspawn container (M2b Jellyfin, M4 arr, M5 Traefik) ───────
  #
  # containers.jellyfin = {
  #   privateNetwork  = true;
  #   hostBridge      = "br0";                # → nspawn --network-bridge=br0
  #   localMacAddress = "02:00:00:80:00:02";  # container eth0 → DHCP reservation
  # };
  #
  # NOTE THE INTERFACE NAME.  With --network-bridge= the host side of the veth
  # uses the "vb-" prefix, not "ve-" (nixos-containers.nix deletes vb-$INSTANCE
  # on stop).  So the unit must match vb-jellyfin.
  #
  # nspawn creates AND enslaves that veth itself, so this unit must NOT set
  # Bridge= — that would make networkd fight nspawn over the master — but MUST
  # set KeepMaster so networkd leaves the enslavement alone while still
  # applying the [BridgeVLAN].
  #
  # systemd.network.networks."60-vb-jellyfin" = {
  #   matchConfig.Name = "vb-jellyfin";
  #   networkConfig = {
  #     KeepMaster          = true;   # do not detach it from nspawn's br0
  #     LinkLocalAddressing = "no";
  #     IPv6AcceptRA        = false;
  #   };
  #   bridgeVLANs = [ { VLAN = 80; PVID = 80; EgressUntagged = 80; } ];
  #   linkConfig.RequiredForOnline = "enslaved";
  # };
  #
  # M2b must VERIFY with `bridge vlan show` that the VLAN actually landed:
  # networkd applies [BridgeVLAN] when it observes the link's master, and nspawn
  # sets that master out of band.  If it races, the fallback is an ExecStartPost
  # on container@jellyfin.service running
  #   bridge vlan add dev vb-jellyfin vid 80 pvid untagged
  # With DefaultPVID = "none" a missed application is fail-closed (the container
  # simply has no connectivity), not fail-open onto VLAN 50.

  ###########################################################################
  # Stage-1 SSH for remote zroot passphrase entry — UNCHANGED, and it must
  # stay bound to the RAW enp13s0.
  #
  # Stage 1 has no bridge and no br0: boot.initrd.systemd.network is a separate
  # unit tree (boot.initrd.systemd.network.networks."50-initrd-enp13s0", from
  # modules/networking/initrd-ssh.nix), so there is no collision with the
  # stage-2 50-* units above and nothing there needs to change.
  #
  # This is WHY the UDM-Pro port must keep VLAN 50 as its UNTAGGED native VLAN.
  # In stage 1 the raw NIC speaks untagged; convert the port to a pure tagged
  # trunk and initrd SSH dies, leaving the Comet KVM as the only way to unlock
  # zroot on every future boot.  See the cutover runbook.
  #
  # See modules/networking/initrd-ssh.nix for one-time host-key setup and
  # docs/guides/remote-unlock.md for the operator flow from miralda.
  ###########################################################################
  clanarchy.initrdSsh = {
    enable        = true;
    interface     = "enp13s0";
    address       = "10.0.50.10/24";   # same as running-system; never up simultaneously
    gateway       = "10.0.50.1";
    kernelModules = [ "atlantic" "igc" ];
    authorizedKeyFiles = [
      ../miralda/yubikey_ed25519.pub   # mirrors modules/users/admin.nix
    ];
  };
}
