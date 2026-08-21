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
#    70  Travel (wg)       10.0.70.0/24    NOT carried
#    90  Services          10.0.90.0/24    tagged   (M2b Jellyfin, M5 Traefik)
#
#   Services is 90, and the two numbers it is NOT are both deliberate:
#     not 70 — that is the travel/WireGuard VLAN, the one M5's ipAllowList and
#              M7's "wg-travel must not be locked out" note refer to;
#     not 80 — 10.0.80.0/24 is routed to a site-to-site WireGuard peer
#              (`allowed ips: 10.0.70.2/32, 10.0.80.0/24` on wgsrv1), so a
#              Services network there was shadowed by the VPN route and its
#              gateway silently never answered ARP.  See the root-cause box in
#              docs/runbooks/ernst-vlan-bridge-cutover.md.
#
#   The lesson, because it will happen again: a free VLAN ID does NOT imply a
#   free subnet.  Check `ip route show` on the UDM-Pro before allocating one —
#   VPN peers and site-to-site tunnels install routes that shadow a connected
#   network, and the failure is silent.
#
#   90 is tagged now, before anything uses it, so M2b/M3/M5 never need a
#   switch-port change.  30/40/60/70/80 are deliberately absent: a VLAN that is
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
#    themselves: a future tap on VLAN 90 reaches enp13s0's VLAN 90 without br0
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
      # br0's CURRENT live MAC, pinned so it stays that on the next boot.
      #
      # M2 deferred this to M2b on the theory that a Linux bridge adopts the
      # numerically LOWEST port MAC, so the veth M2b adds (random, locally
      # administered, 0x02/0x06/0x0a… — all below enp13s0's 0xa0) would
      # silently move the host's L2 identity.  MEASURED ON ernst 2026-08-20,
      # that is not what happens here:
      #
      #   ip -br link show br0            → b2:8b:e1:f2:1e:7c   (NOT enp13s0's)
      #   cat /sys/class/net/br0/addr_assign_type → 3            (NET_ADDR_SET)
      #
      # systemd-networkd sets a MAC on the netdevs it creates, so br0 is
      # NET_ADDR_SET and br_stp_recalculate_bridge_id() returns early rather
      # than adopting a port address.  The kernel behaviour is real; it just
      # cannot fire on a networkd-created bridge.  So M2b's veth was never a
      # threat to ernst's MAC, and pinning to enp13s0's a0:ad:9f:1c:9d:74 —
      # as M2 and the cutover runbook both instructed — would have CHANGED
      # br0's address on the same deploy that moves Jellyfin, on the interface
      # carrying ernst's only management address.  Two risks, one deploy, for
      # a hazard that does not exist.
      #
      # The pin is still worth having, for the reason nobody had checked:
      # br0 has NEVER survived a reboot.  `journalctl --list-boots` shows the
      # current boot began 2026-08-18 21:37, and br0 was created live by the
      # cutover deploy at 2026-08-20 10:11 — so no boot has ever regenerated
      # it, and nothing has confirmed networkd's generated value is
      # reproducible.  Pinning makes that question moot in the safe direction:
      # if the value is derived (machine-id + netdev name), this is a no-op
      # freeze; if it is random, this is what stops it moving every boot.
      #
      # Either way it is a NO-OP on the M2b deploy: it is what br0 already has.
      MACAddress = "b2:8b:e1:f2:1e:7c";
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
      { VLAN = 90; }   # Services — M2b Jellyfin, M5 Traefik
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
  # Do NOT use `containers.<n>.macvlans`.  A macvlan is not a bridge port:
  # attached to br0 it rides br0's own "self" VLAN — 50, the HOST VLAN — and
  # attached to enp13s0 it rides the trunk's native VLAN, also 50.  Either way
  # it cannot be placed on VLAN 90, which is the entire point.  (The sketch
  # that suggested it presumed a per-VLAN bridge fed by an enp13s0.90 VLAN
  # netdev: a different architecture, rejected here in favour of one
  # VLAN-aware br0.  It has been corrected in the header of
  # machines/ernst/containers/jellyfin.nix, which M2b owns.)
  #
  # WHERE THE REAL UNITS LIVE.  Not here.  M2b's vb-jellyfin unit sits in
  # machines/ernst/containers/jellyfin.nix, beside the container that creates
  # the veth and the rest of that service's host-side footprint (udev alias,
  # tmpfiles, perms oneshot).  Follow that convention: this file describes the
  # TOPOLOGY — bridge, trunk, VLAN map, the two attachment patterns — and does
  # not accumulate one unit per service as M3/M4/M5 land.  The MAC allocations
  # are the exception worth tracking centrally; see the table below.
  #
  # MAC ALLOCATIONS on 02:00:00:<vlan>:00:<seq> (the whole point of a
  # convention is that it is written down in one place), with the DHCP
  # reservation each one keys.  The reservations live on the UDM-Pro and are
  # NOT declared in the repo; they are listed here only so the two tables can
  # be read against each other:
  #   02:00:00:90:00:02   jellyfin container eth0   (M2b — allocated)  10.0.90.10
  #   02:00:00:90:00:03   wg-qbittorrent guest eth0 (M3  — allocated)  10.0.90.11
  #   02:00:00:90:00:04   traefik container eth0    (M5  — reserved)   10.0.90.12
  #   02:00:00:90:00:05   arr container eth0        (M4  — allocated)  10.0.90.13
  #
  # The last octet is 8 + <seq>.  That correspondence is not enforced by
  # anything and it is worth keeping anyway: it is the only thing that makes a
  # mis-typed reservation visible by inspection.  M4 took .13 rather than the
  # next free address so that M5 can still have .12 against the MAC already
  # reserved for it.  Every reservation must be INSIDE the DHCP pool
  # (10.0.90.6–.254) — UniFi accepts an address from the .2–.5 range the
  # cutover runbook set aside and then silently hands out a pool lease instead.
  #
  # NUMERIC ID ALLOCATIONS across the storage boundary — the sibling
  # convention, tracked here for the same reason.  virtiofs and nspawn both
  # pass uids/gids through unmapped, so a number chosen inside a guest is a
  # number on zdata:
  #   gid 3000  media        shared read/write group (containers/jellyfin.nix)
  #   uid  964  jellyfin     (containers/jellyfin.nix)
  #   uid 3001  qbittorrent  (microvms/wg-qbittorrent.nix — M3)
  #   uid 3002  sonarr       (containers/arr.nix — M4, group media)
  #   uid 3003  radarr       (containers/arr.nix — M4, group media)
  #   uid 3004  prowlarr     (containers/arr.nix — M4, NOT in media)
  #   gid 3004  prowlarr     (containers/arr.nix — M4)
  #
  # MAC policy for both: locally-administered (02:…) so it cannot collide with
  # a vendor OUI.  Convention below: 02:00:00:<vlan>:00:<seq>.  The MAC the
  # UDM-Pro sees — and that a DHCP reservation must key on — is the GUEST or
  # CONTAINER side, never the host-side veth/tap.
  #===========================================================================

  # ── A. microvm / QEMU guest (M3: VPN + qBittorrent) ──────────────────────
  #
  # NO LONGER HYPOTHETICAL.  M3 implemented this for wg-qbittorrent; the
  # working version is in machines/ernst/microvms/wg-qbittorrent.nix.  Copy
  # from there, and note the ONE correction it made to the sketch that used to
  # live here:
  #
  #   THERE IS NO NETDEV.  The sketch declared
  #     systemd.network.netdevs."60-tap-vpn" = {
  #       netdevConfig = { Name = "tap-vpn"; Kind = "tap"; };
  #       tapConfig    = { User = "microvm"; Group = "kvm"; };
  #     };
  #   microvm.nix creates the tap itself, from the VM's own bin/tap-up
  #   (`ip tuntap add … user microvm`), and DELETES + recreates it on every
  #   start.  A netdev unit races that for the same name.  Declare only the
  #   .network:
  #
  # systemd.network.networks."60-tap-vpn" = {
  #   matchConfig.Name = "tap-vpn";
  #   networkConfig = {
  #     Bridge              = "br0";     # ← Bridge=, unlike pattern B below
  #     LinkLocalAddressing = "no";
  #     IPv6AcceptRA        = false;
  #   };
  #   bridgeVLANs = [ { VLAN = 90; PVID = 90; EgressUntagged = 90; } ];
  #   linkConfig.RequiredForOnline = "enslaved";
  # };
  # …and in the guest:
  #   microvm.interfaces = [
  #     { type = "tap"; id = "tap-vpn"; mac = "02:00:00:90:00:03"; }
  #   ];
  #
  # Bridge= is correct HERE and wrong in pattern B, which is the whole
  # distinction: nothing else enslaves a microvm tap, so networkd does the
  # enslavement and the [BridgeVLAN] application in one step — and the VLAN
  # race that B has to work around cannot occur.

  # ── B. systemd-nspawn container (M4 arr, M5 Traefik) ─────────────────────
  #
  # NO LONGER HYPOTHETICAL.  M2b implemented this pattern for Jellyfin and M4
  # followed it for the arr stack; read machines/ernst/containers/jellyfin.nix
  # ("Networking — v2") for the working version with its full rationale, and
  # copy from there rather than from the sketch below.  The three things that
  # bite:
  #
  #   containers.<n> = {
  #     privateNetwork  = true;
  #     hostBridge      = "br0";                # → nspawn --network-bridge=br0
  #     localMacAddress = "02:00:00:90:00:0X";  # container eth0 → DHCP reservation
  #   };
  #
  # 1. THE INTERFACE NAME.  With --network-bridge= the host side of the veth
  #    uses the "vb-" prefix, not "ve-" (nixos-containers.nix deletes
  #    vb-$INSTANCE on stop).  The unit must match vb-<name>.
  # 2. NOT Bridge=, but KeepMaster=true.  nspawn creates AND enslaves the veth
  #    itself; Bridge= would make networkd fight it over the master.
  #    KeepMaster leaves the enslavement alone while still applying
  #    [BridgeVLAN].
  # 3. THE VLAN CAN RACE.  networkd applies [BridgeVLAN] when it observes the
  #    link's master, and nspawn sets that master out of band.  jellyfin.nix
  #    pairs the unit with an idempotent ExecStartPost that re-asserts the
  #    membership; do the same.  With DefaultPVID = "none" a missed
  #    application is fail-closed (no connectivity at all), not fail-open onto
  #    VLAN 50 — but verify it with `bridge vlan show` rather than trusting
  #    silence.

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
