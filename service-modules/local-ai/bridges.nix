############################################################################
# mkBridges — a loopback service, reachable from one container and nothing
# else.  See the header for why this is shared rather than inlined.
#
# `unit` is the unit-name prefix; `targetPort` is the loopback port being
# published; each bridge is { name, address, allowedSource }.
############################################################################
{lib}: {
  pkgs,
  unit,
  what,
  targetPort,
  bridges,
  extraAfter ? [],
}: {
  systemd.sockets = lib.listToAttrs (map (b: {
      name = "${unit}-${b.name}";
      value = {
        description = "${what} listener for the ${b.name} container";
        wantedBy = ["sockets.target"];
        socketConfig = {
          # A LITERAL ADDRESS, never a wildcard.  This is the whole
          # containment: the only peer of that /128 is one container.
          ListenStream = "[${b.address}]:${toString targetPort}";
          BindIPv6Only = "ipv6-only";

          # THE BIND SUCCEEDS EVEN WHEN THE ADDRESS DOES NOT EXIST, which is
          # why this is stated rather than left implicit.  The address lives on
          # a veth that only exists while the peer container runs, so the
          # socket has to come up before it and survive it going away — and
          # measured on ernst 2026-09-24, it does so with or without this line.
          # It is set anyway because relying on undeclared kernel behaviour for
          # a boot-ordering property is how the Open WebUI outage stayed
          # invisible: a listening socket is NOT evidence that the leg exists.
          FreeBind = true;
        };
      };
    })
    bridges);

  systemd.services = lib.listToAttrs (map (b: {
      name = "${unit}-${b.name}";
      value = {
        description = "Proxy ${what} to the ${b.name} container";
        after = ["${unit}-${b.name}.socket"] ++ extraAfter;
        # SOCKET-ACTIVATED: no `wantedBy`.  With one, systemd starts this
        # directly and systemd-socket-proxyd exits 1 with "Didn't get any
        # sockets passed in", then restart-loops.
        requires = ["${unit}-${b.name}.socket"];

        serviceConfig = {
          ExecStart = lib.concatStringsSep " " [
            "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd"
            "127.0.0.1:${toString targetPort}"
          ];
          Restart = "on-failure";
          RestartSec = "10s";
          DynamicUser = true;
          NoNewPrivileges = true;
          PrivateDevices = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          MemoryDenyWriteExecute = true;

          # AF_INET IS REQUIRED and its absence is silent.  The LISTENER is
          # AF_INET6 and is created by systemd in the .socket unit; this
          # process has to DIAL 127.0.0.1, which is AF_INET.  Without it:
          # "Failed to get remote socket: Address family not supported by
          # protocol", and every request times out.
          RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];

          CapabilityBoundingSet = [""];
          AmbientCapabilities = [""];
          SystemCallFilter = ["@system-service" "~@resources" "~@privileged"];
          SystemCallErrorNumber = "EPERM";
          SystemCallArchitectures = "native";
          ProtectProc = "invisible";
          ProcSubset = "pid";
          ProtectClock = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          RemoveIPC = true;
          UMask = "0077";
          # Both ends are on this host: loopback upstream, the veth /64
          # downstream.
          IPAddressDeny = "any";
          IPAddressAllow = ["localhost" "${b.address}/128" "${b.allowedSource}/128"];
        };
      };
    })
    bridges);

  # One accept per bridge, appended to nixos-fw so it lands after
  # allowedTCPPorts and before the catch-all refuse — the placement
  # monitoring.nix and containers/arr/ rely on.  The chain is flushed and
  # rebuilt on every start, so extraStopCommands needs nothing.
  #
  # If a consumer times out while the stack is demonstrably alive:
  #   ip6tables -L nixos-fw -n --line-numbers | grep ${toString targetPort}
  # and then, because a listening socket proves nothing:
  #   ip -6 addr show dev <the consumer's veth>
  networking.firewall.extraCommands =
    lib.concatMapStrings (b: ''
      ip6tables -A nixos-fw -s ${b.allowedSource}/128 \
        -p tcp -m tcp --dport ${toString targetPort} -j nixos-fw-accept
    '')
    bridges;
}
