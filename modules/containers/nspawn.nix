# `clanarchy.containers.<name>` — a declarative systemd-nspawn container with
# the ~230 lines of per-service skeleton generated instead of written.
#
# ── WHAT IT REPLACES ────────────────────────────────────────────────────────
#
# Thirteen container files repeated the same eight blocks: a `<svc>-dirs`
# oneshot, a `<svc>-secrets` staging unit, a `60-vb-<svc>` networkd file, an
# idempotent `bridge vlan add` backstop, the five-line `containers.<n>`
# preamble, a 26-line in-container networking block, the uid/gid pins, and an
# `allowedTCPPorts = [ ]` + `extraCommands` pair. The comments explaining them
# were copied too — the VLAN-race paragraph appears in nine files, the
# `extraInputRules` note in nine, the `wait-online` cap in eight.
#
# ── HOST-AGNOSTIC BY CONSTRUCTION ───────────────────────────────────────────
#
# Nothing here names ernst, br0, VLAN 90 or goclan.org. The per-host answers
# live in one `clanarchy.containers.defaults` block in the machine's own
# configuration.nix, so a second container host is an inventory edit rather
# than a rewrite. Imported fleet-wide and inert until a machine declares a
# container — the same shape as modules/hardware/convertible.nix.
#
# ── NOT A CLAN SERVICE, DELIBERATELY ────────────────────────────────────────
#
# docs/guides/adding-a-module.md says to reach for `service-modules/` only when
# a feature genuinely has roles, and that "which role? the only one" is the
# signal not to. A container host has no roles; it has named instances.
{ config, lib, pkgs, ... }:
let
  cfg = config.clanarchy.containers;
  defaults = config.clanarchy.containerDefaults;
  clib = import ./lib.nix { inherit lib pkgs; };

  enabled = lib.filterAttrs (_: c: c.enable) cfg;
  perContainer = lib.mapAttrsToList mkOne enabled;

  # A staged env value is either read from a clan var at activation time, or a
  # constant. Making the caller say which is deliberate: the previous version
  # took a bare path string, and a literal like an OIDC *client id* — which is
  # not a secret — had no way to be expressed at all.
  secretValueType = lib.types.submodule {
    options = {
      file = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to a clan var, read with a tolerant `readvar` at activation.";
      };
      value = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "A constant. Ends up in the store, so never a secret.";
      };
      required = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Fail the staging unit when the var is missing or empty, instead of
          passing an empty value through.

          FALSE BY DEFAULT because the unit is `requiredBy` the container, so
          failing it stops the service rather than degrading it — that took
          RomM down on 2026-09-07. Set it true only where an empty value is
          WORSE than a stopped service: a session-signing key, where the
          application starts happily and every session is forgeable with
          nothing in the log to say so.
        '';
      };
    };
  };

  # A mount the dirs unit must verify before creating anything under it, with
  # its OWN expected source — not the host's state source, because a service
  # may own a dataset of its own.
  guardedMountType = lib.types.submodule {
    options = {
      path   = lib.mkOption { type = lib.types.str; description = "Mount point to verify."; };
      source = lib.mkOption { type = lib.types.str; description = "What `findmnt --output SOURCE` must report."; };
      fstype = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optionally also require this `FSTYPE`; a right-looking source can still be the wrong thing.";
      };
    };
  };

  stateDirType = lib.types.submodule {
    options = {
      path  = lib.mkOption { type = lib.types.str; description = "Absolute path to create."; };
      owner = lib.mkOption { type = lib.types.either lib.types.int lib.types.str; description = "Numeric uid (a container user the host cannot name)."; };
      group = lib.mkOption { type = lib.types.either lib.types.int lib.types.str; description = "Numeric gid."; };
      mode  = lib.mkOption { type = lib.types.str; default = "0700"; description = "Mode, as install(1) takes it."; };
    };
  };

  # A SECOND LEG ON A VLAN, which is not the same thing as a ULA leg.
  #
  # mDNS and SSDP are link-local, and this repo refuses to relay them across a
  # firewall boundary — so a service that must discover devices on another VLAN
  # gets its own port on the bridge rather than a relay. Two containers need
  # one (Home Assistant for the wifi devices, Music Assistant for the MusicCast
  # receiver).
  #
  # `extraVeths.<name>` becomes nspawn's `--network-veth-extra=<name>`, which
  # names BOTH ends identically — so the host-side networkd file matches the
  # plain name, not `vb-<name>`, and the name is a host-global allocation.
  vlanLegType = lib.types.submodule {
    options = {
      veth = lib.mkOption {
        type = lib.types.str;
        example = "iot1";
        description = "Interface name, used for both ends. Host-global; asserted unique.";
      };
      vlan = lib.mkOption {
        type = lib.types.int;
        description = "VLAN this leg is tagged into.";
      };
      mac = lib.mkOption {
        type = lib.types.str;
        description = ''
          MAC for the container end. Pinned here because `extraVeths` has no
          option for it and the DHCP reservation has to key on a value this
          repo chose rather than on whatever nspawn derives from the machine
          name.
        '';
      };
      useGateway = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Accept a default route from this leg's DHCP lease.

          FALSE IS LOAD-BEARING and the default for that reason: both legs take
          DHCP and both servers hand out a default route, so with this on the
          container ends up with TWO `default via` entries and its path
          off-segment is decided by whichever lease applied last — a coin toss
          on every boot.
        '';
      };
      requiredForOnline = lib.mkOption {
        type = lib.types.str;
        default = "no";
        description = ''
          NOT "routable" by default: a DHCP problem on a secondary leg must
          leave a RUNNING container with one failed unit, not a host-side
          restart loop because a lease did not arrive.
        '';
      };
    };
  };

  # A LEG ON A BRIDGE THAT IS NOT THE PRIMARY ONE — a segment reached over L2
  # that the house router never sees at all (tvheadend's FRITZ!Box leg).
  #
  # The host side uses `Bridge =` and NOT `KeepMaster`, which is the opposite
  # of the primary leg and is load-bearing both ways: nspawn enslaves the
  # `vb-<name>` veth itself, so networkd must be told to keep its hands off it
  # — but nspawn only knows about `hostBridge`, so for an extraVeth on another
  # bridge nothing enslaves it unless networkd does.
  bridgeLegType = lib.types.submodule {
    options = {
      veth = lib.mkOption {
        type = lib.types.str;
        example = "fritz0";
        description = "Interface name, used for both ends. Host-global; asserted unique.";
      };
      bridge = lib.mkOption {
        type = lib.types.str;
        example = "br-fritz";
        description = "Host bridge networkd enslaves this leg into. Declared by the machine, not here.";
      };
      address = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "192.168.178.2/24";
        description = ''
          Static address for the container end. Null takes DHCP instead.
          Static is the common case here: a foreign segment's DHCP server is
          not ours to depend on, and the leg usually exists to reach exactly
          one on-link address.
        '';
      };
      mac = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optionally pin the container end's MAC.";
      };
      requiredForOnline = lib.mkOption {
        type = lib.types.str;
        default = "no";
        description = ''
          NOT "routable": the far end of a leg like this is equipment nobody
          here controls, and it being powered off must not hold up a boot.
        '';
      };
    };
  };

  ulaType = lib.types.submodule {
    options = {
      veth = lib.mkOption {
        type = lib.types.str;
        description = ''
          Interface name, used for BOTH ends of the pair — so it is a
          HOST-GLOBAL allocation, not a per-container one. M19 and M27 both
          chose `ai0`; only one container could hold it, and Open WebUI
          silently had no second interface for five days. Asserted in
          modules/containers/assertions.nix.
        '';
      };
      hostAddress6  = lib.mkOption { type = lib.types.str; description = "Host end, a /128."; };
      localAddress6 = lib.mkOption { type = lib.types.str; description = "Container end, a /128."; };
      routes = lib.mkOption {
        type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
        default = [ ];
        example = lib.literalExpression ''[ { Destination = "fdda::1/128"; Gateway = "fdca:fe90::1"; } ]'';
        description = ''
          Further routes on this leg, appended after the link-scope route to
          the host end.

          A leg that only answers its one consumer needs none. The monitoring
          container needs one per clan machine, via the host end, because its
          Prometheus SCRAPES them over ZeroTier and the host SNATs that
          traffic out — without these the leg reaches the host and nothing
          beyond it, which is a leg that looks up and scrapes nothing.
        '';
      };
    };
  };


  containerType = lib.types.submodule ({ name, ... }: {
    options = {
      enable = lib.mkEnableOption "this container";

      mac = lib.mkOption {
        type = lib.types.str;
        example = "02:00:00:90:00:14";
        description = ''
          The container's own MAC. Its address is a DHCP reservation keyed on
          this, so a typo does not fail — it quietly takes a pool lease
          instead, with every indicator on the host staying green. On ernst
          this must match the row in machines/ernst/allocations.nix, which is
          asserted there.
        '';
      };

      vlan = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "VLAN the primary leg sits on. Null falls back to `clanarchy.containerDefaults.vlan`.";
      };

      bridge = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Host bridge the primary leg is enslaved to. Null falls back to the host default.";
      };

      stateDirs = lib.mkOption {
        type = lib.types.listOf stateDirType;
        default = [ ];
        description = "Directories to create before the container starts, with numeric ownership.";
      };

      extraGuardedMounts = lib.mkOption {
        type = lib.types.listOf guardedMountType;
        default = [ ];
        example = lib.literalExpression ''[ { path = "/srv/photos"; source = "zdata/photos"; fstype = "zfs"; } ]'';
        description = ''
          Further mounts the dirs unit must verify and order after, beyond the
          state mount. Each names its OWN expected source, because a service
          that owns a dataset of its own is not checking for the state one.
        '';
      };

      secrets = lib.mkOption {
        type = lib.types.attrsOf (lib.types.attrsOf secretValueType);
        default = { };
        example = lib.literalExpression ''{ "oidc.env" = {
            OAUTH_CLIENT_ID     = { value = "karakeep"; };
            OAUTH_CLIENT_SECRET = { file = gen.files."secret".path; };
          }; }'';
        description = ''
          Env files to stage, as `<file>.<KEY> = { file = …; }` for a value
          read out of a clan var, or `{ value = "…"; }` for a constant.

          Staged host-side and bind-mounted, because a clan var path does not
          exist inside the container — pointing an in-container unit at
          `/run/secrets/vars/...` fails with a silent `243/CREDENTIALS`.
        '';
      };

      bindMounts = lib.mkOption {
        type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
        default = { };
        description = "Passed through to `containers.<name>.bindMounts`. The secrets directory is added automatically.";
      };

      ula = lib.mkOption {
        type = lib.types.listOf ulaType;
        default = [ ];
        description = ''
          Point-to-point ULA legs. Each gets an `extraVeths` entry and an
          in-container network with a link-scope route to the host end — the
          shape a loopback-bound producer needs in order to serve one consumer
          without listening on any VLAN.
        '';
      };

      vlanLegs = lib.mkOption {
        type = lib.types.listOf vlanLegType;
        default = [ ];
        description = ''
          Additional legs on other VLANs, for link-local discovery that cannot
          be relayed. Each gets an `extraVeths` entry, a VLAN-tagged host-side
          network, the same idempotent `bridge vlan add` backstop as the
          primary leg, and a DHCP network inside the container.
        '';
      };

      bridgeLegs = lib.mkOption {
        type = lib.types.listOf bridgeLegType;
        default = [ ];
        description = ''
          Legs on a bridge other than the primary one. Each gets an
          `extraVeths` entry, a host-side network that enslaves it, and a
          static or DHCP network inside the container. The bridge itself — its
          netdev, its physical port, any avahi exclusion — belongs to the
          machine: those are facts about the house's wiring, not about a
          container.
        '';
      };

      manageFirewall = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Generate the container's firewall from `allowFrom`. Set false where
          the container's firewall is not a peer list at all.

          THE ONE CONTAINER THAT SETS THIS IS THE INGRESS. Traefik opens 80,
          443 and the WAN port to the whole internet — "which peers" is the
          wrong question for it — and it is the only container here running
          `networking.nftables`, where the `extraCommands` this module emits
          is declared but never consumed: no rule, no warning, no firewall.
          An opt-out is honest; translating `allowFrom` into nftables for a
          single consumer would be a second renderer maintained on spec.
        '';
      };

      allowedDevices = lib.mkOption {
        type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
        default = [ ];
        example = lib.literalExpression ''[ { node = "char-ttyACM"; modifier = "rw"; } ]'';
        description = ''
          Passed through to `containers.<name>.allowedDevices`.

          ANY entry here turns the device filter ON, which means an incomplete
          list takes access away rather than leaving it alone. Naming a
          DIRECTORY grants nothing (service-modules/local-ai.nix measured
          that); a device-node GROUP like `char-ttyACM` covers every minor.
        '';
      };

      allowFrom = lib.mkOption {
        type = lib.types.listOf clib.allowType;
        default = [ ];
        description = "Peers allowed in, one accept each. Everything else is refused.";
      };

      uid = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = ''
          Numeric uid to pin for the container's service user. nspawn passes
          ids through UNMAPPED, so a number chosen inside the container is a
          number on the host's storage. Null means the service takes no id of
          its own (DynamicUser, or an upstream-static id it must keep).
        '';
      };

      gid = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Numeric gid to pin, same reasoning as `uid`.";
      };

      user = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Name of the in-container user `uid`/`gid` apply to.";
      };

      resolver = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "DNS server the container uses; null falls back to the host default. Pinned rather than inherited from the host.";
      };

      searchDomain = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Search domain; null falls back to the host default.";
      };

      useResolved = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Run `services.resolved` inside the container. The one service that
          sets this false is the mail container, whose kresd recurses itself —
          DNSBL operators refuse shared resolvers, so it cannot forward.

          THERE IS DELIBERATELY NO ASSERTION that something else provides DNS.
          The obvious one — "resolved off requires `networking.nameservers`" —
          fails the only legitimate consumer: mail's `networking.nameservers`
          is empty and kresd writes resolv.conf itself. A check that would
          pass it has to know about simple-nixos-mailserver, which is exactly
          what this module must not know.
        '';
      };

      stateVersion = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "`system.stateVersion` for the container; null follows the host.";
      };

      config = lib.mkOption {
        type = lib.types.deferredModule;
        default = { };
        description = ''
          The service itself — the irreducible half. Merged with the generated
          networking, firewall and id pins into `containers.<name>.config`.
        '';
      };
    };
  });

  mkOne = name: c:
    let
      vethHost   = "vb-${name}";
      secretsDir = "${defaults.secretsRoot}/${name}-secrets";
      unitsFor   = [ "container@${name}.service" ];

      # Fallbacks are resolved HERE, in the config phase, and not as option
      # defaults. An option default that reads `config` is evaluated while the
      # option set is still being built — which is infinite recursion, and is
      # exactly what the first version of this module did.
      vlan         = if c.vlan         != null then c.vlan         else defaults.vlan;
      bridge       = if c.bridge       != null then c.bridge       else defaults.bridge;
      resolver     = if c.resolver     != null then c.resolver     else defaults.resolver;
      searchDomain = if c.searchDomain != null then c.searchDomain else defaults.searchDomain;
      stateVersion = if c.stateVersion != null then c.stateVersion else config.system.stateVersion;

      support = clib.mkSupportUnits {
        inherit name unitsFor secretsDir;
        inherit (defaults) stateMount stateSource;
        inherit (c) stateDirs secrets;
        extraMounts = c.extraGuardedMounts;
      };
    in
    {
      # ── Host side ─────────────────────────────────────────────────────────
      systemd.services = support // {
        # The VLAN race, and the idempotent backstop for it. networkd applies
        # [BridgeVLAN] only once it observes the link's master, and nspawn sets
        # that master out of band. With `DefaultPVID = "none"` on the bridge a
        # miss is fail-CLOSED, so the container is simply unreachable.
        # `bridge vlan show dev vb-<name>` is the check.
        #
        # The "-" prefix is load-bearing: a backstop must not become a new
        # failure mode. Without it, `bridge` exiting non-zero — the link
        # already gone during a restart, say — fails `container@<name>` and
        # puts it in a restart loop, taking the service down to guard against
        # a race networkd usually wins on its own.
        "container@${name}" = {
          serviceConfig.ExecStartPost =
            lib.optional (vlan != null)
              "-${pkgs.iproute2}/bin/bridge vlan add dev ${vethHost} vid ${toString vlan} pvid untagged"
            # Every secondary leg needs the same backstop, against its own
            # interface name — which for an extraVeth is the plain name, not
            # `vb-<name>`.
            ++ map (v:
              "-${pkgs.iproute2}/bin/bridge vlan add dev ${v.veth} vid ${toString v.vlan} pvid untagged"
            ) c.vlanLegs;
        };
      };

      # Host side of each secondary leg: a bridge port on its own VLAN. The
      # name matches the plain interface, not `vb-<name>`, because
      # --network-veth-extra names both ends identically.
      systemd.network.networks = lib.listToAttrs (map (v:
        lib.nameValuePair "60-${v.veth}" {
          matchConfig.Name = v.veth;
          networkConfig = {
            Bridge              = bridge;
            LinkLocalAddressing = "no";
            IPv6AcceptRA        = false;
          };
          bridgeVLANs = [ { VLAN = v.vlan; PVID = v.vlan; EgressUntagged = v.vlan; } ];
          # A bridge port's terminal state is "enslaved"; it never becomes
          # routable.
          linkConfig.RequiredForOnline = "enslaved";
        }) c.vlanLegs)

      # Host side of each leg on another bridge. `Bridge =`, not `KeepMaster`:
      # nspawn only enslaves the primary veth, so for this one networkd is the
      # only thing that will. No [BridgeVLAN] either — a dedicated segment has
      # one port pair and nothing to filter.
      // lib.listToAttrs (map (b:
        lib.nameValuePair "60-${b.veth}" {
          matchConfig.Name = b.veth;
          networkConfig = {
            Bridge              = b.bridge;
            LinkLocalAddressing = "no";
            IPv6AcceptRA        = false;
          };
          linkConfig.RequiredForOnline = b.requiredForOnline;
        }) c.bridgeLegs)
      // {
      "60-${vethHost}" = {
        matchConfig.Name = vethHost;
        networkConfig = {
          # KeepMaster AND NOT Bridge=. nspawn creates this link and enslaves
          # it itself (`--network-bridge=`), so `Bridge =` here would have
          # networkd fight nspawn for the master. KeepMaster leaves the
          # enslavement alone while still applying [BridgeVLAN], which is the
          # only thing we want networkd for on this link.
          #
          # No L3 either: a bridge port carries no address, and accepting an
          # RA on one would have it answer advertisements meant for the hosts
          # behind it.
          KeepMaster          = true;
          LinkLocalAddressing = "no";
          IPv6AcceptRA        = false;
        };
        bridgeVLANs = lib.optionals (vlan != null)
          [ { VLAN = vlan; PVID = vlan; EgressUntagged = vlan; } ];
        linkConfig.RequiredForOnline = "enslaved";
      };
      };

      containers.${name} = {
        autoStart = true;
        ephemeral = false;

        privateNetwork  = true;
        hostBridge      = bridge;
        localMacAddress = c.mac;

        # A ULA LEG GETS NO HOST-SIDE `60-*` NETWORK, AND THAT IS MEASURED:
        # `hostAddress6` here is what nixos-containers configures the host end
        # from directly, so declaring it in networkd as well is two things
        # racing for one address — and the loser is the container, which dies
        # with `ipv6: address already assigned` and `status=2/INVALIDARGUMENT`
        # in a restart loop naming neither the veth nor the file (paperless,
        # 2026-10-05, four restarts). Only VLAN legs take a `60-*` network.
        extraVeths =
          lib.listToAttrs (map (u:
            lib.nameValuePair u.veth {
              inherit (u) hostAddress6 localAddress6;
            }) c.ula)
          # A VLAN leg takes no addresses here: nspawn creates the pair and
          # the container end gets its address from DHCP.
          // lib.listToAttrs (map (v: lib.nameValuePair v.veth { }) c.vlanLegs)
          # Same for a secondary-bridge leg: the pair is all nspawn provides,
          # and the container end is addressed by its own networkd below.
          // lib.listToAttrs (map (b: lib.nameValuePair b.veth { }) c.bridgeLegs);

        allowedDevices = c.allowedDevices;

        bindMounts = c.bindMounts // lib.optionalAttrs (c.secrets != { }) {
          ${secretsDir} = { hostPath = secretsDir; isReadOnly = true; };
        };

        config = { ... }: {
          imports = [ c.config ];

          system.stateVersion = stateVersion;

          # ── Networking, the ordinary shape ────────────────────────────────
          networking.useHostResolvConf = false;
          networking.useNetworkd = true;
          services.resolved.enable = c.useResolved;

          systemd.network.networks = {
            "10-eth0" = {
            matchConfig.Name = "eth0";
            networkConfig = {
              DHCP         = "ipv4";
              IPv6AcceptRA = false;
              # SN2: v4 only. IPv6AcceptRA alone blocks an RA but NOT
              # link-local assignment; this is the line that actually makes
              # `ip -6 addr show dev eth0` empty.
              LinkLocalAddressing = "no";
            }
            # THE RESOLVER IS NAMED ONLY IF THE CONTAINER RUNS ONE. `DNS=` in
            # a .network is consumed by resolved, so with resolved off it is
            # at best inert — and the one container in that position (mail)
            # must not be pointed at the house resolver at all, because its
            # own kresd is the whole reason it opted out.
            // lib.optionalAttrs c.useResolved {
              DNS     = resolver;
              Domains = "~. ${searchDomain}";
            };
              dhcpV4Config = { UseDNS = false; UseDomains = false; };
              linkConfig.RequiredForOnline = "routable";
            };
          }

          # Each ULA leg: its own /128 and a link-scope route to the host end.
          # RequiredForOnline = "no" because a veth has no carrier until BOTH
          # ends are up, and the host end is brought up after the container's
          # own boot — so wait-online would be waiting on an event its own
          # completion gates.
          // lib.listToAttrs (map (u:
            lib.nameValuePair "20-${u.veth}" {
              matchConfig.Name = u.veth;
              address = [ "${u.localAddress6}/128" ];
              routes  = [ { Destination = "${u.hostAddress6}/128"; Scope = "link"; } ] ++ u.routes;
              networkConfig.IPv6AcceptRA = false;
              linkConfig.RequiredForOnline = "no";
            }) c.ula)

          # A VLAN leg takes DHCP like the primary one, with two differences
          # that both matter. `UseGateway`/`UseRoutes` are off by default
          # because two leases each offering a default route leaves the
          # container choosing its off-segment path by whichever applied last.
          # And the MAC is pinned HERE because `extraVeths` has no option for
          # it, while the DHCP reservation must key on a value this repo chose.
          // lib.listToAttrs (map (v:
            lib.nameValuePair "20-${v.veth}" {
              matchConfig.Name = v.veth;
              networkConfig = {
                DHCP                = "ipv4";
                IPv6AcceptRA        = false;
                LinkLocalAddressing = "no";
              };
              dhcpV4Config = {
                UseDNS     = false;
                UseDomains = false;
                UseGateway = v.useGateway;
                UseRoutes  = v.useGateway;
              };
              linkConfig = {
                MACAddress = v.mac;
                RequiredForOnline = v.requiredForOnline;
              };
            }) c.vlanLegs)

          # A secondary-bridge leg: static by default, no gateway and no DNS.
          # The leg exists to reach something on-link, and taking a default
          # route from a segment we do not administer is how a container
          # acquires a second, wrong path to the internet — which is what
          # IPv6AcceptRA = false is here to prevent on a FRITZ!Box segment
          # that advertises one over RA.
          // lib.listToAttrs (map (b:
            lib.nameValuePair "20-${b.veth}" {
              matchConfig.Name = b.veth;
              networkConfig = {
                IPv6AcceptRA        = false;
                LinkLocalAddressing = "no";
              } // (if b.address != null
                    then { Address = b.address; }
                    else { DHCP = "ipv4"; })
              ;
              dhcpV4Config = lib.optionalAttrs (b.address == null) {
                UseDNS     = false;
                UseDomains = false;
                UseGateway = false;
                UseRoutes  = false;
              };
              linkConfig = lib.optionalAttrs (b.mac != null) { MACAddress = b.mac; }
                // { RequiredForOnline = b.requiredForOnline; };
            }) c.bridgeLegs);

          # A DHCP failure must leave a RUNNING container with one failed unit,
          # not a host-side restart loop.
          systemd.network.wait-online.timeout = 20;

          # The container firewall is the ONLY enforcement point for
          # bridge-local traffic: those frames are one L2 hop and the router
          # never sees them.
          networking.firewall = lib.mkIf c.manageFirewall (clib.mkFirewall c.allowFrom);

          users = lib.optionalAttrs (c.user != null && c.uid != null) {
            users.${c.user}.uid = c.uid;
          } // lib.optionalAttrs (c.user != null && c.gid != null) {
            groups.${c.user}.gid = c.gid;
          };
        };
      };
    };
in
{
  options.clanarchy.containerDefaults = {
    bridge        = lib.mkOption { type = lib.types.str; default = "br0"; description = "Default host bridge."; };
    vlan          = lib.mkOption { type = lib.types.nullOr lib.types.int; default = null; description = "Default VLAN; null means untagged."; };
    resolver      = lib.mkOption { type = lib.types.str; default = "127.0.0.53"; description = "Default DNS server for containers."; };
    searchDomain  = lib.mkOption { type = lib.types.str; default = "local"; description = "Default search domain."; };
    stateMount    = lib.mkOption { type = lib.types.str; default = "/srv/state"; description = "Where per-service state lives."; };
    stateSource   = lib.mkOption { type = lib.types.str; default = ""; description = "What `stateMount` must be backed by; the dirs units refuse to run otherwise."; };
    secretsRoot   = lib.mkOption { type = lib.types.str; default = "/run"; description = "Parent of each `<name>-secrets` staging directory."; };
  };

  options.clanarchy.containers = lib.mkOption {
    type = lib.types.attrsOf containerType;
    default = { };
    description = ''
      Declarative nspawn containers. A name here must be at most 12
      characters: nspawn derives the host veth as `vb-<name>` and 15 is
      IFNAMSIZ, so a longer one evaluates cleanly and fails at container
      START. It is why ernst's are `mail`, `mass` and `hass`.
    '';
  };

  # ── THE SHAPE OF `config` MUST NOT DEPEND ON `config` ───────────────────
  #
  # Three versions of this were infinite recursion, each one subtler:
  #
  #   1. option defaults that read `config.clanarchy.containerDefaults` —
  #      evaluated while the option set is still being built;
  #   2. `lib.mkIf (enabled != { }) …` — a mkIf CONDITION reading `config`,
  #      forced during the same early phase;
  #   3. `lib.mkMerge (mapAttrsToList mkOne enabled)` as the whole of `config`
  #      — which still makes the SET OF ATTRIBUTES depend on `config`, so
  #      `_module.freeformType` cannot be collected without forcing it.
  #
  # The fix is a STATIC SPINE: these four keys always exist, and only their
  # values are computed from the declarations. Per-container fallbacks are
  # resolved in `mkOne`, which is inside a value and therefore safe.
  config = {
    systemd.services         = lib.mkMerge (map (x: x.systemd.services) perContainer);
    systemd.network.networks = lib.mkMerge (map (x: x.systemd.network.networks) perContainer);
    containers               = lib.mkMerge (map (x: x.containers) perContainer);
  };
}
