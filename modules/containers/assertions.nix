# Checks over whatever containers a machine declares, however they were
# declared — by hand, or through ./nspawn.nix, or from a clan service.
#
# These read `config.containers` and `config.systemd.sockets` and nothing else,
# so they are host-agnostic: nothing here names ernst, a bridge, a VLAN or a
# domain. They moved out of machines/ernst/networking.nix, where they were
# correct but only ever applied to one machine.
#
# Every one of them exists because the failure it catches is SILENT. None of
# these produce an error at runtime; they produce a container that is simply
# unreachable while every indicator says healthy.
{ config, lib, ... }:
let
  # ── veth names are a host-global namespace ────────────────────────────────
  claims = lib.concatLists (lib.mapAttrsToList
    (container: cfg: map (veth: { inherit container veth; })
      (lib.attrNames (cfg.extraVeths or { })))
    config.containers);
  byName = lib.groupBy (c: c.veth) claims;
  collisions = lib.filterAttrs (_: cs: lib.length cs > 1) byName;

  # Every host end a container actually brings up.
  vethHostAddrs = lib.concatLists (lib.mapAttrsToList
    (_: cfg: lib.filter (a: a != null)
      (lib.mapAttrsToList (_: v: v.hostAddress6 or null) (cfg.extraVeths or { })))
    config.containers);

  # Every loopback bridge this host declares, whatever generated it. Matching
  # on the naming convention rather than on a list means a generator added
  # later is covered without anyone remembering to come back here.
  bridgeSockets = lib.filterAttrs (n: _: lib.hasInfix "-bridge-" n) config.systemd.sockets;

  # ListenStream is "[addr]:port"; take what is between the brackets. The
  # brackets are matched with POSIX bracket expressions — `builtins.match` is
  # ERE, where a backslash-escaped `[` is rejected outright rather than treated
  # as a literal.
  addrOf = sock:
    let m = builtins.match "[[]([^]]+)[]]:[0-9]+" (sock.socketConfig.ListenStream or "");
    in if m == null then null else lib.head m;

  missingBridgeAddrs = lib.filter (b: b.addr != null && !(lib.elem b.addr vethHostAddrs))
    (lib.mapAttrsToList (unit: sock: { inherit unit; addr = addrOf sock; }) bridgeSockets);

  # ── nspawn container names must fit IFNAMSIZ ──────────────────────────────
  longNames = lib.filter (n: lib.stringLength n > 12) (lib.attrNames config.containers);

  # ── one [BridgeVLAN] per bridge port ─────────────────────────────────────
  #
  # A second definition of `systemd.network.networks."60-<iface>"` does not
  # conflict: the attrsets merge, and `bridgeVLANs` being a LIST means the
  # entries concatenate instead. So a hand-written block left behind next to a
  # generated one renders the stanza twice and evaluates perfectly — which is
  # exactly what paperless shipped for the length of one migration.
  dupVlans = lib.filterAttrs (_: n: n > 1) (lib.mapAttrs
    (_: net: lib.length (net.bridgeVLANs or [ ]))
    (lib.filterAttrs (n: _: lib.hasPrefix "60-" n) config.systemd.network.networks));

  # ── podman-tier interface names ───────────────────────────────────────────
  podCfg = config.clanarchy.podmanContainers or { };
  podIfaces = lib.mapAttrsToList (_: c: c.interface) (lib.filterAttrs (_: c: c.enable) podCfg);
  podDupes = lib.attrNames (lib.filterAttrs (_: v: lib.length v > 1) (lib.groupBy (x: x) podIfaces));
in
{
  config.assertions = [
    {
      assertion = collisions == { };
      message = ''
        Two or more containers declare the same extraVeths name, and only one
        of them can have it — the other silently gets no interface:

        ${lib.concatStringsSep "\n" (lib.mapAttrsToList
          (veth: cs: "  ${veth}: ${lib.concatMapStringsSep ", " (c: c.container) cs}")
          collisions)}

        The name is used for BOTH ends of the pair, so it must be unique across
        every container on the host. M19 and M27 both chose `ai0`, and Open
        WebUI had no second interface for five days: the host end binds whether
        or not any interface carries the address, so the socket stayed
        active/running, `ss -ltn` still showed it LISTENing, and the only
        symptom was an empty model picker in a browser.
      '';
    }

    {
      assertion = missingBridgeAddrs == [ ];
      message = ''
        These loopback bridges listen on addresses that no container veth
        carries, so nothing can ever reach them:

        ${lib.concatMapStringsSep "\n" (b: "  ${b.unit} -> ${b.addr}") missingBridgeAddrs}

        Every bridge address must equal some container's
        `extraVeths.<name>.hostAddress6`. Known ends:
        ${lib.concatStringsSep ", " vethHostAddrs}

        This is the other half of the check above, and the symptom is identical
        and equally uninformative: systemd binds the socket anyway, the unit
        reads active/running, and the consumer times out with nothing logged,
        because the packet never reaches the proxy.
      '';
    }

    {
      assertion = longNames == [ ];
      message = ''
        These nspawn container names are longer than 12 characters:
        ${lib.concatStringsSep ", " longNames}

        nspawn derives the host veth as `vb-<name>` and 15 is IFNAMSIZ, so this
        evaluates cleanly and fails at container START. It is why ernst's are
        `mail`, `mass` and `hass` rather than the obvious spellings.
      '';
    }

    {
      assertion = dupVlans == { };
      message = ''
        These bridge-port networks carry more than one [BridgeVLAN] entry:

        ${lib.concatStringsSep "\n" (lib.mapAttrsToList
          (n: c: "  ${n}: ${toString c} entries") dupVlans)}

        One port, one VLAN stanza. More than one means the network is defined
        twice — usually a hand-written block left in place beside the one
        modules/containers/nspawn.nix generates. It does not conflict and it
        does not warn: the attrsets merge and the lists concatenate.
      '';
    }

    {
      assertion = podDupes == [ ];
      message = ''
        Two or more podman containers claim the same interface name:
        ${lib.concatStringsSep ", " podDupes}

        Unlike the nspawn tier, nothing fails here — it succeeds wrongly.
        dhcpcd keys its pidfile on the INTERFACE NAME rather than the netns,
        and these units share a mount namespace, so the second dhcpcd hands its
        arguments to the first and exits 0. The result is a container that is
        simply unreachable while every unit reports success.
      '';
    }
  ];
}
