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
#   enp12s0  Intel I226-V 2.5G (igc) — since M8 (2026-08-27) the DIRECT link
#            to the FRITZ!Box 6591's LAN, enslaved to the two-port bridge
#            br-fritz for the tvheadend container's SAT>IP leg.  Owned by
#            machines/ernst/containers/tvheadend.nix (units live with the
#            service); RequiredForOnline=no there, so it still never blocks
#            boot (see note 6).  The FRITZ segment never touches br0, the
#            trunk, or any skynet VLAN — that isolation is the point.
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
#    20  IoT               10.0.20.0/24    tagged   (M24 hass iot0 — the first
#                                                    thing to use it)
#    30  HA                10.0.30.0/24    NOT carried  (see below — M24
#                                                        deliberately did NOT
#                                                        use it)
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
#   VLAN 30 IS NAMED "HA" AND M24 PUT HOME ASSISTANT SOMEWHERE ELSE.  That is
#   the kind of thing someone re-derives from scratch two years later, so: 30
#   is where the Raspberry Pi instance lived, it is NOT on this trunk, and
#   carrying it would cost a port-profile edit on USW Pro 24 PoE port 6.  It
#   buys nothing — the leg that matters is the one on the segment the DEVICES
#   are on, and the household's wifi devices are on 20, which is already
#   tagged.  VLAN 30 retires with the Pi.  See containers/home-assistant.nix.
#
#   AND VLAN 20 NOW HAS A PORT ON THIS BRIDGE, which it did not when the notes
#   below were written.  It is the hass container's `iot0`, and it exists for
#   DISCOVERY: mDNS and SSDP are link-local, so a hub on VLAN 90 can open a
#   socket to any IoT device (Internal → Internal: Allow All on the UDM-Pro)
#   and still never SEE one.  Note 3's warning is untouched by this — the port
#   is a member of VLAN 20, br0 itself is not, so the host holds no address
#   there and Avahi's unpinned reflector stays off that segment.
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
{
  config,
  lib,
  ...
}: let
  # The MAC / address / veth / uid ledger. Four comment tables until this
  # change; see ./allocations.nix for why it is data now, and for the rules
  # the assertions below enforce.
  alloc = import ./allocations.nix;

  macOf = vlan: seq: "02:00:00:${vlan}:00:${lib.toLower (lib.fixedWidthString 2 "0" (lib.toHexString seq))}";
in {
  ###########################################################################
  # Container veth names are a HOST-GLOBAL namespace — asserted, not trusted.
  #
  # `containers.<c>.extraVeths.<name>` becomes nspawn's
  # `--network-veth-extra=<name>`, and with a single name nspawn uses it for
  # BOTH ends.  So the name lands in the host's one flat interface namespace,
  # two containers cannot share one, and stopping either deletes it
  # (nixos-containers.nix:245 runs `ip link del dev <name>` on stop).
  #
  # THIS IS HERE BECAUSE IT ALREADY HAPPENED.  M27 gave karakeep
  # `extraVeths.ai0`, which Open WebUI had held since M19.  Open WebUI lost its
  # inference leg on M27's deploy and nothing said so for five days: the host
  # end binds whether or not any interface carries the address, so
  # `llama-bridge-webui.socket` stayed active/running, `ss -ltn` still showed
  # [fdca:fe91::1]:11434 LISTENing, and the only symptom was an empty model
  # picker in a browser.  The facts needed to predict it were already written
  # down in service-modules/monitoring.nix:182-184; what was missing was
  # anything that checked.
  #
  # An eval-time failure instead.  This is the third member of the family
  # docs/guides/adding-a-module.md lists — a container name over 12 characters,
  # a uid colliding with nixpkgs' ids.nix — where the build is green and the
  # running system is wrong.
  ###########################################################################
  assertions = let
    # ── The registry's own internal consistency ───────────────────────────
    dupesOf = xs:
      lib.attrNames (lib.filterAttrs (_: v: lib.length v > 1)
        (lib.groupBy (x: toString x) xs));

    seq90 = lib.mapAttrsToList (_: v: v.seq) alloc.vlan90;
    seq20 = lib.mapAttrsToList (_: v: v.seq) alloc.vlan20;
    allIps =
      (lib.mapAttrsToList (_: v: v.ip) alloc.vlan90)
      ++ (lib.mapAttrsToList (_: v: v.ip) alloc.vlan20);
    allVeths =
      (lib.mapAttrsToList (_: v: v.veth) alloc.ula)
      ++ (lib.mapAttrsToList (_: v: v.veth) alloc.vlan20);
    # Uids among uids, gids among gids — NOT pooled together. A service
    # conventionally takes the same number for both (prowlarr is 3004/3004),
    # so a pooled check reports every such row as a duplicate. Measured:
    # pooling flagged 20 rows, all of them correct.
    uidList = lib.filter (x: x != null) (lib.mapAttrsToList (_: v: v.uid or null) alloc.ids);
    gidList = lib.filter (x: x != null) (lib.mapAttrsToList (_: v: v.gid or null) alloc.ids);
    numIds = uidList ++ gidList;

    # Next free, COMPUTED — the three disagreeing "NEXT FREE" sentences this
    # replaces are why. Quoted in the failure messages so a collision tells
    # you what to take.
    nextSeq90 = 1 + lib.foldl' lib.max 0 seq90;
    nextUid =
      1
      + lib.foldl' lib.max 3000
      (lib.filter (n: n >= 3000 && n < 4000) numIds);

    # 10.0.90.<8 + seq>. Not enforced by anything outside this file, and
    # worth enforcing: it is the only thing that makes a mistyped
    # reservation visible by inspection.
    wrongOctet = lib.attrNames (lib.filterAttrs
      (_: v: v.ip != "10.0.90.${toString (8 + v.seq)}")
      alloc.vlan90);

    # `vb-<name>` must fit IFNAMSIZ (15). Scoped to nspawn: the microvm's
    # interface is named explicitly, so `wg-qbittorrent` at 14 is fine.
    longNames = lib.attrNames (lib.filterAttrs
      (n: v: v.kind == "nspawn" && lib.stringLength n > 12)
      alloc.vlan90);

    # ── The registry against the configuration ───────────────────────────
    #
    # NOTHING CHECKED THIS BEFORE. A container's address is a DHCP
    # reservation on the UDM-Pro keyed on its MAC, so a mistyped
    # `localMacAddress` does not fail — it quietly takes a pool lease
    # instead of its reserved address, and every indicator on this host
    # stays green.
    # COVERS THE NSPAWN TIER ONLY, and that is a real limit rather than an
    # oversight: the podman tier sets its MAC with `ip link set address`
    # inside each `<svc>-netns` oneshot, and the microvm's is a QEMU
    # argument. Neither is reachable from `config.containers`. Measured
    # 2026-10-13: 16 containers declare one here, all 16 matching.
    declaredMacs =
      lib.mapAttrs (_: c: c.localMacAddress or null)
      (lib.filterAttrs (_: c: (c.localMacAddress or null) != null) config.containers);

    macMismatches = lib.filter (m: m.want != m.got) (lib.mapAttrsToList
      (name: got: {
        inherit name got;
        want =
          if alloc.vlan90 ? ${name}
          then macOf "90" alloc.vlan90.${name}.seq
          else "(no registry row)";
      })
      declaredMacs);

    # ── The pre-existing veth checks (unchanged) ─────────────────────────
    claims = lib.concatLists (lib.mapAttrsToList
      (container: cfg:
        map (veth: {inherit container veth;})
        (lib.attrNames (cfg.extraVeths or {})))
      config.containers);
    byName = lib.groupBy (c: c.veth) claims;
    collisions = lib.filterAttrs (_: cs: lib.length cs > 1) byName;

    # Every host end a container actually brings up.
    vethHostAddrs = lib.concatLists (lib.mapAttrsToList
      (_: cfg:
        lib.filter (a: a != null)
        (lib.mapAttrsToList (_: v: v.hostAddress6 or null) (cfg.extraVeths or {})))
      config.containers);

    # Every loopback bridge this host declares, whatever generated it —
    # `llama-bridge-*`, `mneme-bridge-*`, `wyoming-*-bridge-*`.  Matching on
    # the naming convention rather than on a list means a fifth generator
    # added later is covered without anyone remembering to add it here.
    bridgeSockets =
      lib.filterAttrs
      (n: _: lib.hasInfix "-bridge-" n)
      config.systemd.sockets;

    # ListenStream is "[addr]:port"; take what is between the brackets.
    # The brackets are matched with POSIX bracket expressions — `builtins.match`
    # is ERE, where a backslash-escaped `[` is rejected outright rather than
    # treated as a literal.
    addrOf = sock: let
      m = builtins.match "[[]([^]]+)[]]:[0-9]+" (sock.socketConfig.ListenStream or "");
    in
      if m == null
      then null
      else lib.head m;

    missingBridgeAddrs =
      lib.filter (b: b.addr != null && !(lib.elem b.addr vethHostAddrs))
      (lib.mapAttrsToList (unit: sock: {
          inherit unit;
          addr = addrOf sock;
        })
        bridgeSockets);
  in [
    {
      assertion = collisions == {};
      message = ''
        ernst: two or more containers declare the same extraVeths name, and
        only one of them can have it — the other silently gets no interface:

        ${lib.concatStringsSep "\n" (lib.mapAttrsToList
          (veth: cs: "  ${veth}: ${lib.concatMapStringsSep ", " (c: c.container) cs}")
          collisions)}

        The name is used for BOTH ends of the veth, so it must be unique
        across every container on this machine.  The convention here is to
        track the peer's ULA: fdca:fe91:: -> ai1, fdca:fe92:: -> ai2,
        fdca:fe93:: -> ai3.  Monitoring's mon0 predates it and keeps its name.

        A leg on a VLAN has no ULA to track and is numbered in order instead:
        iot0 (hass), iot1 (mass).  Two containers on the SAME VLAN still need
        different names — the name is an interface, not a description.
      '';
    }

    # ── AND THE OTHER HALF: A BRIDGE MUST LISTEN ON AN ADDRESS THAT EXISTS
    #
    # The uniqueness check above catches two containers fighting over one
    # interface.  This one catches the simpler, equally silent mistake it
    # sits next to: a bridge socket bound to a ULA that NO container's veth
    # carries — a typo'd nibble in an `exposeOn` entry, or an entry kept
    # after its consumer was removed.
    #
    # It is worth a separate assertion because the symptom is identical and
    # equally uninformative.  systemd binds the socket anyway (FreeBind, and
    # in fact even without it — measured), the unit reads active/running,
    # `ss -ltn` shows it LISTENing, and the consumer times out with nothing
    # logged anywhere, because the packet never reaches the proxy.
    #
    # `hostAddress6` is the authority rather than the host's own networkd:
    # these legs are created by nixos-containers from that option, and no
    # `.network` unit on this side declares them.
    {
      assertion = missingBridgeAddrs == [];
      message = ''
        ernst: these loopback bridges listen on addresses that no container
        veth carries, so nothing can ever reach them:

        ${lib.concatMapStringsSep "\n" (b: "  ${b.unit} -> ${b.addr}") missingBridgeAddrs}

        Every bridge address must equal some container's
        `extraVeths.<name>.hostAddress6`.  Known ends:
        ${lib.concatStringsSep ", " vethHostAddrs}
      '';
    }

    # ── The allocation registry ──────────────────────────────────────────
    {
      assertion = dupesOf seq90 == [] && dupesOf seq20 == [];
      message = ''
        ernst/allocations.nix: two rows share a sequence number, so they
        share a MAC. VLAN 90: ${lib.concatStringsSep ", " (dupesOf seq90)}
        VLAN 20: ${lib.concatStringsSep ", " (dupesOf seq20)}
        Next free on VLAN 90 is ${toString nextSeq90}.
      '';
    }
    {
      assertion = dupesOf allIps == [];
      message = ''
        ernst/allocations.nix: two rows claim the same address:
        ${lib.concatStringsSep ", " (dupesOf allIps)}
      '';
    }
    {
      assertion = dupesOf allVeths == [];
      message = ''
        ernst/allocations.nix: two rows claim the same veth name:
        ${lib.concatStringsSep ", " (dupesOf allVeths)}

        The name is used for BOTH ends of the pair, so it is a host-global
        allocation. M19 and M27 both chose `ai0` and Open WebUI silently had
        no second interface for five days.
      '';
    }
    {
      assertion = dupesOf uidList == [] && dupesOf gidList == [];
      message = ''
        ernst/allocations.nix: two rows claim the same id.
        Duplicate uids: ${lib.concatStringsSep ", " (dupesOf uidList)}
        Duplicate gids: ${lib.concatStringsSep ", " (dupesOf gidList)}
        Next free in the 3000 block is ${toString nextUid}.
      '';
    }
    {
      assertion = wrongOctet == [];
      message = ''
        ernst/allocations.nix: these VLAN-90 rows break the 8 + seq rule,
        so their address and their MAC disagree about which service they
        are: ${lib.concatStringsSep ", " wrongOctet}

        The rule does NOT apply on VLAN 20 — those addresses mirror the
        host's VLAN-90 last octet as a mnemonic.
      '';
    }
    {
      assertion = longNames == [];
      message = ''
        ernst/allocations.nix: these nspawn container names are longer than
        12 characters: ${lib.concatStringsSep ", " longNames}

        nspawn derives the host veth as `vb-<name>` and 15 is IFNAMSIZ, so
        this evaluates cleanly and fails at container START. It is why the
        machines are `mail`, `mass` and `hass`.
      '';
    }
    {
      assertion = macMismatches == [];
      message = ''
        ernst: a container's MAC does not match its row in allocations.nix:

        ${lib.concatMapStringsSep "\n"
          (m: "  ${m.name}: declares ${m.got}, registry says ${m.want}")
          macMismatches}

        The address is a DHCP reservation on the UDM-Pro keyed on the MAC,
        so a mismatch does not fail — the container quietly takes a pool
        lease instead of its reserved address, and every indicator on this
        host stays green. Either fix the MAC or add the registry row.
      '';
    }
  ];

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
      DefaultPVID = "none"; # note 4 — fail-closed for unconfigured ports
      # Single uplink, so there is no loop to detect; STP would only emit
      # BPDUs at the UDM-Pro and delay every new port reaching forwarding.
      STP = false;
    };
  };

  ###########################################################################
  # br0 — the host's L3 identity.  Address / Gateway / DNS / Domains /
  # MulticastDNS are carried over verbatim from the old 50-enp13s0 unit.
  ###########################################################################
  systemd.network.networks."50-br0" = {
    matchConfig.Name = "br0";
    networkConfig = {
      Address = "10.0.50.10/24";
      Gateway = "10.0.50.1";
      DNS = "10.0.5.3";
      Domains = "~. skynet.lan"; # note 1 — do not drop, do not reorder
      MulticastDNS = true; # note 2
      # Configure the address even before the trunk has carrier (atlantic
      # needs ~10 s).  Services binding 10.0.50.10 then do not race the link,
      # and on the KVM console "address present, no L2" is distinguishable
      # from "networkd never got here".
      ConfigureWithoutCarrier = true;
    };

    # note 3 — applied to the bridge device itself (BRIDGE_FLAGS_SELF).
    # This single block is what makes the HOST work untagged on VLAN 50.
    bridgeVLANs = [
      {
        VLAN = 50;
        PVID = 50;
        EgressUntagged = 50;
      }
    ];

    linkConfig.RequiredForOnline = "routable";
  };

  ###########################################################################
  # enp13s0 — tagged trunk port on br0.  No address of its own.
  ###########################################################################
  systemd.network.networks."50-enp13s0" = {
    matchConfig.Name = "enp13s0";
    networkConfig = {
      Bridge = "br0";
      # A bridge port carries no L3 of its own.
      LinkLocalAddressing = "no";
      IPv6AcceptRA = false;
    };

    bridgeVLANs = [
      # Untagged / PVID — the Servers VLAN.  This is ernst's own traffic, and
      # the VLAN stage-1 initrd SSH depends on (see the initrdSsh block).
      {
        VLAN = 50;
        PVID = 50;
        EgressUntagged = 50;
      }
      # Tagged, for guests later milestones place on br0.
      {VLAN = 1;} # LAN / "Family"
      {VLAN = 5;} # DNS-Container (Technitium 10.0.5.3)
      {VLAN = 20;} # IoT
      {VLAN = 90;} # Services — M2b Jellyfin, M5 Traefik
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
    Kind = "!*"; # physical devices only — bridges/veths/taps have a Kind
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
  # THE ALLOCATIONS LIVE IN ./allocations.nix, AND ARE CHECKED, NOT RECITED.
  #
  # Four comment tables used to sit here — ~1,570 lines of MAC/address rows,
  # VLAN-20 rows, ULA legs and the 3000-uid block, plus commented-out worked
  # examples of units that have since been written for real and live beside
  # their services.  Nothing checked any of it, and it had drifted: three
  # "NEXT FREE IN THE 3000 BLOCK" sentences disagreed with each other.
  #
  # The rows are now data in ./allocations.nix and the assertions at the top
  # of this file read them, including two things nothing checked before — a
  # container whose `localMacAddress` disagrees with its row (which costs it
  # its DHCP reservation, silently), and an nspawn name over 12 characters
  # (which fails at container START, not at eval).  `nextFree` is computed.
  #
  # The deleted worked examples are in git, and the real units they sketched
  # are in the container files.  What this file still owns is the TOPOLOGY:
  # the bridge, the trunk, the VLAN map, and the two attachment patterns
  # below — which six container files cite as "pattern A".
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
  # NO LONGER HYPOTHETICAL.  M2b implemented this pattern for Jellyfin, M4
  # followed it for the arr stack and M5 for Traefik; read
  # machines/ernst/containers/jellyfin.nix
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
    enable = true;
    interface = "enp13s0";
    address = "10.0.50.10/24"; # same as running-system; never up simultaneously
    gateway = "10.0.50.1";
    kernelModules = ["atlantic" "igc"];
    authorizedKeyFiles = [
      ../miralda/yubikey_ed25519.pub # mirrors modules/users/admin.nix
    ];
  };
}
