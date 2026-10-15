# The parts both container tiers build identically: state directories that must
# land on the right dataset, secrets staged out of the clan-vars tree, and a
# firewall that admits named peers and nothing else.
#
# ── A PLAIN FUNCTION, NOT A MODULE ──────────────────────────────────────────
#
# Called by ./nspawn.nix and ./podman-netns.nix with the host's answers. It is
# not a module and does not touch `_module.args`, for two reasons: reading
# `config` to build a module argument that another module's *signature*
# requires is a recursion waiting to happen, and a plain call is what
# machines/ernst/containers/ingress-policy.nix already uses to cross exactly
# this kind of boundary.
#
# ── WHY SHARED AT ALL ───────────────────────────────────────────────────────
#
# These were hand-written once per service — 11 `<svc>-dirs` units and 13
# `<svc>-secrets` units — across two tiers whose *networking* genuinely
# differs but whose *storage and secrets* do not. One implementation is what
# stops the tiers drifting in the parts that are the same.
#
# Nothing here names a host, a bridge, a VLAN or a domain.
{ lib, pkgs }:
{
  # `unitFor` is the only thing the two tiers differ on:
  # `container@<name>.service` for nspawn, `podman-<name>.service` for podman.
  mkSupportUnits =
    { name
    , unitFor
    , stateMount
    , stateSource
    , secretsDir
    , stateDirs ? [ ]
    , secrets ? { }
    , extraMounts ? [ ]
    }:
    let
      # A mount unit's name is its path with slashes turned into dashes.
      mountUnit = p: "${lib.replaceStrings [ "/" ] [ "-" ] (lib.removePrefix "/" p)}.mount";

      # EACH MOUNT IS CHECKED AGAINST ITS OWN SOURCE, not one global one.
      # immich owns `zdata/photos` as well as living on `zdata/state`, so a
      # single expected source asserts the wrong thing for one of its mounts.
      guardedMounts =
        [ { path = stateMount; source = stateSource; fstype = null; } ] ++ extraMounts;

      # THE TARGET IS THE PARENT, NOT THE LEAF. `findmnt --target` on a path
      # that does not exist yet returns nothing — it does not walk up to the
      # nearest existing ancestor — so checking the directory this unit is
      # about to create fails on every first run. immich-dirs refused its own
      # first deploy that way on 2026-09-11.
      #
      # fstype is checked where asked for: a path can be backed by a
      # right-looking SOURCE and still not be the dataset intended.
      guardFor = m: ''
        src=$(findmnt --noheadings --output SOURCE --target ${m.path} || true)
      '' + lib.optionalString (m.fstype != null) ''
        fstype=$(findmnt --noheadings --output FSTYPE --target ${m.path} || true)
      '' + ''
        if [ "$src" != ${lib.escapeShellArg m.source} ]${lib.optionalString (m.fstype != null) " || [ \"$fstype\" != ${lib.escapeShellArg m.fstype} ]"}; then
          echo "${name}-dirs: ${m.path} is not ${m.source}${lib.optionalString (m.fstype != null) " (${m.fstype})"}." >&2
          echo "  found: source='$src'${lib.optionalString (m.fstype != null) " fstype='$fstype'"}" >&2
          echo "  Refusing to create ${name}'s directories: they would land on" >&2
          echo "  a filesystem that is rolled back on the next boot." >&2
          echo "  See docs/guides/ernst-zdata-datasets.md." >&2
          exit 1
        fi
      '';

      # Numeric ids on purpose: these are CONTAINER users, and the host has no
      # matching passwd entry to resolve a name against.
      installDir = d:
        "install -d -o ${toString d.owner} -g ${toString d.group} -m ${d.mode} ${d.path}\n";
    in
    # ── AN ORDERED UNIT, AND NOT `systemd.tmpfiles.rules`, AND THAT IS
    #    MEASURED ──────────────────────────────────────────────────────────
    #
    # immich's host-side directories once shipped as tmpfiles rules and the
    # container died five times into its start limit with
    #
    #     systemd-nspawn: Failed to clone /srv/state/immich/ml-cache:
    #                     No such file or directory
    #
    # because activating a configuration does not re-run
    # systemd-tmpfiles-setup.service in time for a container the same
    # activation starts. Nor is a path declared BOTH ways: tmpfiles re-applies
    # mode and ownership on every run, so two definitions that disagree take
    # turns winning, one per deploy.
    lib.optionalAttrs (stateDirs != [ ]) {
      "${name}-dirs" = {
        description = "Verify state is mounted and create ${name}'s directories";
        wantedBy   = [ "multi-user.target" ];
        after      = map (m: mountUnit m.path) guardedMounts;
        requires   = map (m: mountUnit m.path) guardedMounts;
        before     = [ unitFor ];
        # BLOCKING (`requires` + `requiredBy`), not advisory: a service that
        # comes up without its state directory is a NEW EMPTY one on a
        # filesystem that rolls back, which will accept data and lose it.
        requiredBy = [ unitFor ];
        serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
        path = [ pkgs.util-linux pkgs.coreutils ];
        script = ''
          set -eu
          ${lib.concatMapStrings guardFor guardedMounts}
          ${lib.concatMapStrings installDir stateDirs}
        '';
      };
    }
    // lib.optionalAttrs (secrets != { }) {
      "${name}-secrets" = {
        description = "Stage ${name}'s credentials for ${unitFor}";
        after       = [ "local-fs.target" ];
        before      = [ unitFor ];
        requiredBy  = [ unitFor ];
        serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
        path = [ pkgs.coreutils ];
        # NOT a bind of /run/secrets itself: that path is a symlink to a
        # per-generation directory REPLACED on every deploy, so a bind
        # established at container start keeps exposing a deleted generation.
        # This stages the contents instead.
        #
        # 0711 on the directory — traversable by anyone, listable by nobody.
        # 0400 root:root on the files, because an `EnvironmentFile=` is read by
        # PID 1 while it builds the execution context, BEFORE any DynamicUser
        # drop: root ownership is correct, and a service-uid chown would be
        # both pointless and impossible to name.
        #
        # Write-then-rename, so a consumer never reads a half-written file.
        script = ''
          set -euo pipefail
          install -d -m 0711 -o root -g root ${secretsDir}
          umask 077

          # A MISSING VAR MUST NOT TAKE THE SERVICE DOWN. Under `set -eu` a
          # bare `cat` on an ungenerated var exits the unit, and the unit is
          # `requiredBy` the container — so a deploy that runs before
          # `clan vars generate` does not degrade the service, it stops it.
          # That took RomM down on 2026-09-07.
          #
          # The value lands empty instead, which the application then rejects
          # in its own terms — a readable failure in one service rather than a
          # container that will not start.
          readvar() { [ -r "$1" ] && cat "$1" || true; }

          ${lib.concatStrings (lib.mapAttrsToList (envFile: vars: ''
            {
            ${lib.concatStrings (lib.mapAttrsToList (k: v:
              # A key is either read from a var file or a literal constant.
              # Both end up in the same env file, because systemd reads one
              # `EnvironmentFile=` per service and splitting a client id from
              # its secret would mean two files for one consumer.
              if v.file != null then ''
                printf '%s=%s\n' ${lib.escapeShellArg k} "$(readvar ${v.file})"
              '' else ''
                printf '%s=%s\n' ${lib.escapeShellArg k} ${lib.escapeShellArg v.value}
              '') vars)}
            } > ${secretsDir}/${envFile}.tmp
            chmod 0400 ${secretsDir}/${envFile}.tmp
            mv -f ${secretsDir}/${envFile}.tmp ${secretsDir}/${envFile}
          '') secrets)}
        '';
      };
    };

  # One accept per named peer, and nothing else.
  #
  # `extraCommands`, NOT `extraInputRules`: the latter is declared
  # unconditionally but consumed only under `networking.nftables`, so here it
  # would produce no rule and no warning.
  #
  # THE NEGATIVE CONTROL THIS IMPLIES: a curl from the host to the container's
  # own address is REFUSED, by design — the host matches none of these accepts.
  # A test plan expecting a 200 there is testing something that cannot happen.
  mkFirewall = allowFrom: {
    allowedTCPPorts = [ ];
    # Fields are emitted in iptables' own order, and each is omitted when it
    # is null rather than defaulted to something permissive: no `-s` means any
    # source, which is only ever correct deliberately.
    #
    # THE FAMILY IS INFERRED FROM THE PEER, because a ULA leg's accept has to
    # be an `ip6tables` rule and getting that wrong fails in the direction that
    # looks fine: the v4 rule loads, the unit is green, and the one consumer
    # the leg exists for is refused. A v6 literal always contains a colon and a
    # v4 one never does, so the inference is exact wherever a peer is named;
    # `family` is there for the peerless rules, where there is nothing to read.
    extraCommands = lib.concatMapStrings (a:
      let
        v6 = if a.family != null
             then a.family == "inet6"
             else a.peer != null && lib.hasInfix ":" a.peer;
      in
      lib.concatStringsSep " " (
        [ "${if v6 then "ip6tables" else "iptables"} -A nixos-fw" ]
        ++ lib.optional (a.interface != null) "-i ${a.interface}"
        ++ [ "-p ${a.proto}" ]
        ++ lib.optional (a.peer != null) "-s ${a.peer}/${if v6 then "128" else "32"}"
        ++ lib.optional (a.port != null) "--dport ${toString a.port}"
        ++ [ "-j nixos-fw-accept" ]
      ) + "\n"
    ) allowFrom;
  };
}
