# `clanarchy.podmanContainers.<name>` — a podman container on a VLAN, with the
# network namespace built for it rather than by it.
#
# ── WHY THIS TIER EXISTS, AND WHY IT IS A SECOND SKELETON ───────────────────
#
# Podman is the escape hatch for upstreams that ship only an OCI image. It is
# handed a ready-made netns instead of building one, so everything nspawn gets
# for free has to be written out: the namespace, the veth pair, the MAC, the
# firewall, a DHCP client inside the namespace, and the ordering between them.
# Four services did that by hand.
#
# Storage and secrets are NOT duplicated here — ./lib.nix generates those, the
# same ones the nspawn tier gets, which is what stops the two drifting in the
# parts that are genuinely the same.
#
# ── `virtualisation.oci-containers` INSIDE AN NSPAWN CONTAINER IS REJECTED ──
#
# This is the argument each of the four occupants used to restate, and it lives
# here once instead. The hybrid — an OCI image running inside one of the nspawn
# containers — looks like it would avoid a second skeleton. It does not, and it
# gives up the thing the nspawn tier is for: the value of containers/arr/ is
# that upstream units, upstream hardening and `systemd-analyze` scores are all
# legible, and an opaque image inside it is opaque to all three. The escape
# hatch is THIS TIER, not that hybrid.
#
# THE COST OF THIS TIER, accepted explicitly wherever it is used: an image we
# do not build, a package tree we do not build, and a `systemd-analyze
# security` score for `podman-<name>.service` that measures podman rather than
# the application. A service file notes only what is specific to it — how many
# images, and anything it had to do that the others did not.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.clanarchy.podmanContainers;
  defaults = config.clanarchy.containerDefaults;
  clib = import ./lib.nix {inherit lib pkgs;};

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
    };
  };

  # A mount the dirs unit must verify before creating anything under it, with
  # its OWN expected source — not the host's state source, because a service
  # may own a dataset of its own.
  guardedMountType = lib.types.submodule {
    options = {
      path = lib.mkOption {
        type = lib.types.str;
        description = "Mount point to verify.";
      };
      source = lib.mkOption {
        type = lib.types.str;
        description = "What `findmnt --output SOURCE` must report.";
      };
      fstype = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optionally also require this `FSTYPE`; a right-looking source can still be the wrong thing.";
      };
    };
  };

  stateDirType = lib.types.submodule {
    options = {
      path = lib.mkOption {type = lib.types.str;};
      owner = lib.mkOption {type = lib.types.either lib.types.int lib.types.str;};
      group = lib.mkOption {type = lib.types.either lib.types.int lib.types.str;};
      mode = lib.mkOption {
        type = lib.types.str;
        default = "0700";
      };
    };
  };

  podType = lib.types.submodule ({name, ...}: {
    options = {
      enable = lib.mkEnableOption "this podman container";

      mac = lib.mkOption {
        type = lib.types.str;
        description = "MAC of the namespace end, which the DHCP reservation keys on.";
      };
      vlan = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
      };
      bridge = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };

      interface = lib.mkOption {
        type = lib.types.str;
        example = "rm0";
        description = ''
          Name of the namespace end of the veth pair.

          UNIQUE PER HOST, not per container, and nothing fails if it is not:
          dhcpcd keys its pidfile on the interface NAME rather than the netns,
          and these units share a mount namespace, so a duplicate makes the
          second dhcpcd hand its arguments to the first and exit 0. The
          container is then unreachable while every unit reports success.
          Asserted in ./assertions.nix.
        '';
      };

      images = lib.mkOption {
        type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
        default = {};
        description = ''
          Passed through to `virtualisation.oci-containers.containers`, with
          the netns, DNS and user options added. More than one entry shares
          ONE namespace — which is how a database ends up on `127.0.0.1` and
          structurally unaddressable from anywhere else, rather than on a
          podman network where its exposure would be a matter of getting rules
          right.
        '';
      };

      stateDirs = lib.mkOption {
        type = lib.types.listOf stateDirType;
        default = [];
      };
      extraGuardedMounts = lib.mkOption {
        type = lib.types.listOf guardedMountType;
        default = [];
      };
      secrets = lib.mkOption {
        type = lib.types.attrsOf (lib.types.attrsOf secretValueType);
        default = {};
      };
      allowFrom = lib.mkOption {
        type = lib.types.listOf clib.allowType;
        default = [];
      };

      uidgid = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "3029:3029";
        description = ''
          `--user` for the images. ROOTFUL AND UNMAPPED on purpose: rootless
          podman always has a user namespace, so the in-container PUID/PGID are
          NOT what lands on disk — files appear as some sub-uid, or as
          nobody:nobody. Recovering from that means `--userns=keep-id` or an
          idmap, i.e. bolting a second id model onto a pool whose whole
          convention is that ids are literal, and `/srv/media` is a shared
          hardlink domain with the *arr. Rootful with no remapping makes podman
          behave like nspawn here: the numbers set here are exactly what
          appears on zdata.

          THE SECURITY COST, stated rather than buried: the container runtime
          runs as root on the host. What would move a service to rootless is an
          idmapped-mount story for its storage that keeps on-disk ids literal —
          `--userns=keep-id:uid=<n>,gid=<n>` is the shape — and that is a
          per-service argument, not a flag to flip.
        '';
      };

      resolver = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      searchDomain = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };

      healthcheck.enable = lib.mkEnableOption ''
        a unit that polls `podman inspect` until the container reports
        healthy.

        `podman-<name>.service` is considered started once the container is
        CREATED, so without this, anything ordered after it races a container
        that is still coming up. An `ExecStartPost` would instead hold the
        unit in `activating` for the length of the healthcheck — two minutes
        for CWA — which is worse
      '';
    };
  });

  mkOne = name: c: let
    netns = name;
    vethHost = "vb-${name}";
    secretsDir = "${defaults.secretsRoot}/${name}-secrets";
    primaryUnit = "podman-${name}.service";

    # Resolved here rather than as option defaults — an option default that
    # reads `config` is evaluated while the option set is still being built,
    # which is infinite recursion.
    vlan =
      if c.vlan != null
      then c.vlan
      else defaults.vlan;
    bridge =
      if c.bridge != null
      then c.bridge
      else defaults.bridge;
    resolver =
      if c.resolver != null
      then c.resolver
      else defaults.resolver;
    searchDomain =
      if c.searchDomain != null
      then c.searchDomain
      else defaults.searchDomain;
    imageUnits = map (n: "podman-${n}.service") (lib.attrNames c.images);

    support = clib.mkSupportUnits {
      inherit name secretsDir;
      # EVERY image unit, not just the primary — see the note in ./lib.nix.
      unitsFor = imageUnits;
      inherit (defaults) stateMount stateSource;
      inherit (c) stateDirs secrets;
      extraMounts = c.extraGuardedMounts;
    };

    fw = clib.mkFirewall c.allowFrom;
  in {
    systemd.services =
      support
      // {
        "${name}-netns" = {
          description = "Network namespace and veth for the ${name} container";
          wantedBy = ["multi-user.target"];
          before = imageUnits;
          # REQUIRED, not merely ordered. `before` is ordering alone, and the
          # four hand-written versions of this all said `requires` as well —
          # correctly: the image is started with `--network=ns:/run/netns/…`,
          # so without the namespace podman has nothing to join. Ordering by
          # itself would start the container anyway when this unit failed.
          #
          # The DHCP unit below is deliberately NOT required: a lease that
          # does not arrive must leave a RUNNING container with one failed
          # unit, not a container that never starts.
          requiredBy = imageUnits;
          after = ["systemd-networkd.service"];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          path = [pkgs.iproute2 pkgs.iptables];
          # Idempotent throughout: this is a RemainAfterExit oneshot that a
          # deploy may re-run against a namespace that already exists.
          script = ''
            set -eu
            if ! ip netns list | grep -qw '${netns}'; then
              ip netns add '${netns}'
            fi
            ip -n '${netns}' link set lo up
            if ! ip link show '${vethHost}' >/dev/null 2>&1; then
              ip link add '${vethHost}' type veth peer name '${c.interface}' netns '${netns}'
            fi
            ip -n '${netns}' link set '${c.interface}' address '${c.mac}'
            ip -n '${netns}' link set '${c.interface}' up
            ip link set '${vethHost}' up

            # Default-deny, then the named peers. This is the only enforcement
            # point for bridge-local traffic: those frames are one L2 hop and
            # the router never sees them.
            ip netns exec '${netns}' iptables -F INPUT
            ip netns exec '${netns}' iptables -P INPUT DROP
            ip netns exec '${netns}' iptables -A INPUT -i lo -j ACCEPT
            ip netns exec '${netns}' iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
            ${lib.concatMapStrings (a: ''
                ${lib.concatStringsSep " " (
                  ["ip netns exec '${netns}' ${clib.ipt a} -A INPUT"]
                  ++ clib.acceptParts a ++ ["-j ACCEPT"]
                )}
              '')
              c.allowFrom}
            # DHCP replies and ICMP, without which the lease never completes
            # and the container is unreachable for reasons that look like the
            # firewall is right.
            ip netns exec '${netns}' iptables -A INPUT -p udp --sport 67 --dport 68 -j ACCEPT
            ip netns exec '${netns}' iptables -A INPUT -p icmp -j ACCEPT
          '';
          preStop = ''
            ${pkgs.iproute2}/bin/ip netns del '${netns}' 2>/dev/null || true
            ${pkgs.iproute2}/bin/ip link del '${vethHost}' 2>/dev/null || true
          '';
        };

        "${name}-dhcp" = {
          description = "DHCP client inside the ${name} network namespace";
          wantedBy = ["multi-user.target"];
          after = ["${name}-netns.service"];
          requires = ["${name}-netns.service"];
          before = imageUnits;
          serviceConfig = {
            NetworkNamespacePath = "/run/netns/${netns}";
            # --nohook resolv.conf IS LOAD-BEARING: the MOUNT namespace is
            # shared with the host, so without it dhcpcd rewrites the HOST's
            # /etc/resolv.conf from a lease meant for a container.
            ExecStart = "${pkgs.dhcpcd}/bin/dhcpcd --nobackground --nohook resolv.conf --ipv4only ${c.interface}";
            Restart = "on-failure";
            RestartSec = "5s";
          };
        };
      }
      // lib.optionalAttrs c.healthcheck.enable {
        "${name}-healthy" = {
          description = "Wait until the ${name} container reports healthy";
          wantedBy = ["multi-user.target"];
          after = [primaryUnit];
          requires = [primaryUnit];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          path = [pkgs.podman pkgs.coreutils];
          script = ''
            for _ in $(seq 1 120); do
              s=$(podman inspect -f '{{.State.Health.Status}}' ${name} 2>/dev/null || echo starting)
              [ "$s" = healthy ] && exit 0
              sleep 1
            done
            echo "${name}: still not healthy after 120s" >&2
            exit 1
          '';
        };
      };

    # Bridge=, NOT KeepMaster, and the difference is the whole of pattern A:
    # the nspawn tier needs KeepMaster because nspawn enslaves the link
    # itself and networkd must not fight it. Here the oneshot above only
    # CREATES the pair, so networkd owns the enslavement and applies
    # [BridgeVLAN] in the same step — no race, and no backstop needed.
    systemd.network.networks."60-${vethHost}" = {
      matchConfig.Name = vethHost;
      networkConfig = {
        Bridge = bridge;
        LinkLocalAddressing = "no";
        IPv6AcceptRA = false;
      };
      bridgeVLANs =
        lib.optionals (vlan != null)
        [
          {
            VLAN = vlan;
            PVID = vlan;
            EgressUntagged = vlan;
          }
        ];
      linkConfig.RequiredForOnline = "enslaved";
    };

    virtualisation.oci-containers.containers = lib.mapAttrs (_: image:
      image
      // {
        extraOptions =
          (image.extraOptions or [])
          ++ [
            "--network=ns:/run/netns/${netns}"
            "--dns=${resolver}"
            "--dns-search=${searchDomain}"
          ]
          ++ lib.optional (c.uidgid != null) "--user=${c.uidgid}";
      })
    c.images;

    # Unused on this tier — the firewall is iptables inside the namespace,
    # above — but computed so the shape stays identical to nspawn's and a
    # reader can see the two are the same policy.
    warnings =
      lib.optional (fw.allowedTCPPorts != [])
      "clanarchy.podmanContainers.${name}: allowedTCPPorts is not used on the podman tier";
  };
in {
  options.clanarchy.podmanContainers = lib.mkOption {
    type = lib.types.attrsOf podType;
    default = {};
    description = ''
      Podman containers given a pre-built network namespace.

      The tier itself — `virtualisation.containers.enable`,
      `virtualisation.podman`, and `oci-containers.backend` — is enabled once
      per host and is NOT set here, because duplicate
      `virtualisation.podman.enable = true` definitions merge fine while two
      backends do not.
    '';
  };

  # A STATIC SPINE — see the long note in ./nspawn.nix. The set of attributes
  # here must not depend on `config`, or `_module.freeformType` cannot be
  # collected without forcing the very thing being defined.
  config = {
    systemd.services = lib.mkMerge (map (x: x.systemd.services) perContainer);
    systemd.network.networks = lib.mkMerge (map (x: x.systemd.network.networks) perContainer);
    warnings = lib.concatMap (x: x.warnings) perContainer;
    virtualisation.oci-containers.containers =
      lib.mkMerge (map (x: x.virtualisation.oci-containers.containers) perContainer);
  };
}
