# Distributed Nix builds — dispatch heavy compiles to a beefier clan machine.
#
# Why this exists: birte pulls a Valve kernel from nixpkgs-unstable, and this
# clan configures no binary-cache substituters at all, so `linux-*-valve2` is
# compiled from source on every kernel bump.  A dry-run of birte's toplevel
# builds exactly six derivations and that kernel is effectively all of it.
# On miralda (16 cores, and routinely under 8 GB free) that pins the daily
# driver for the better part of an hour; ernst has 32 cores and 249 GB.
#
# The awkward part is *who* connects.  Remote builds are dispatched by the
# nix-daemon, which runs as root.  It cannot reuse lgo's access to ernst —
# that authenticates with the YubiKey (`openpgp:0x5E293E5A`), which needs
# gpg-agent inside an interactive session — and root on miralda has no key of
# its own (~/.ssh holds only a HM-managed config and known_hosts).  So this
# module generates a dedicated keypair as a *shared* clan var: the private
# half deploys to the client only, the public half is read at eval time by
# the builder and authorised for its root.
#
# Both halves come from one `share = true` generator, so the client and the
# builder resolve the same `vars/shared/remote-builder-ssh/...` files rather
# than needing a pubkey copy-pasted between machine configs.
#
# ORDERING: `.value` on a public var throws until the generator has run.  Run
# `clan vars generate miralda` once before deploying either side.
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.clanarchy.remoteBuilder;
  gen = config.clan.core.vars.generators.remote-builder-ssh;

  # The builder reads the public half straight out of the repo rather than by
  # declaring the generator itself.  Declaring it on both ends looks tidier
  # but does not work: the private half must deploy only to the client, that
  # makes the two definitions differ in `files`, and clan rejects a shared
  # generator whose definitions diverge between machines —
  #   "Machines ernst and miralda have different definitions for shared
  #    generator 'remote-builder-ssh' (differ in: files)"
  # which blocks *every* `clan machines install/update`, not just this one.
  pubKeyPath =
    config.clan.core.settings.directory
    + "/vars/shared/remote-builder-ssh/builder_ed25519.pub/value";

  # Absent until `clan vars generate` has run.  Degrade quietly rather than
  # throwing: a builder that cannot evaluate would wedge unrelated clan
  # operations on every machine in the flake.
  builderPubKey =
    if builtins.pathExists pubKeyPath
    then
      # readFile keeps ssh-keygen's trailing newline; it must not survive into
      # an authorized_keys line carrying a command= prefix.
      lib.removeSuffix "\n" (builtins.readFile pubKeyPath)
    else null;
in {
  options.clanarchy.remoteBuilder = {
    client.enable = lib.mkEnableOption "dispatching Nix builds to a remote clan builder";
    server.enable = lib.mkEnableOption "accepting Nix builds dispatched by clan clients";

    hostName = lib.mkOption {
      type = lib.types.str;
      default = "ernst.skynet.lan";
      description = ''
        Address the client's nix-daemon connects to.  Must be covered by
        {option}`clanarchy.remoteBuilder.hostNames` below.

        Deliberately not a `*.goclan.org` name: the clan CA in
        /etc/ssh/ssh_known_hosts is trusted for `ssh-ca,*.goclan.org`, but
        `ernst.goclan.org` does not currently resolve, so cert-based host
        verification is not reachable here.  The host key is pinned instead.
      '';
    };

    hostNames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "ernst"
        "ernst.skynet.lan"
        "10.0.50.10"

        # ernst's ZeroTier address, so offloading survives leaving the house.
        #
        # The LAN names resolve to nothing from a visiting network, so a
        # roaming client silently fell back to building locally — which is how
        # biene spent hours compiling inkscape and quickshell on a laptop while
        # a 32-core machine sat idle one overlay away.
        #
        # SAME KEY, NOT A SECOND TRUST ANCHOR, and that was checked rather than
        # assumed before this address was added.  ernst serves one
        # `HostKey /run/secrets/vars/openssh/ssh.id_ed25519` on every
        # interface, and all three agreed:
        #
        #   vars/per-machine/ernst/openssh/ssh.id_ed25519.pub
        #   ssh-keyscan -t ed25519 over the ZeroTier address
        #   `hostPublicKey` below
        #
        # all -> ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILd954KHVjUAOX06pHP/+ou78tpo6OYKMQL2ew3eUqEt
        "fdda:106a:123a:d561:1099:933e:4c60:711f"
      ];
      description = "Names/addresses the pinned builder host key is valid for.";
    };

    fallbackHostName = lib.mkOption {
      type = lib.types.str;
      default = "ernst-zt";
      description = ''
        Second builder entry, tried when {option}`hostName` is unreachable.

        A NAME and not the raw address, because `nix.buildMachines.hostName`
        is interpolated into an `ssh-ng://` URI and a bare IPv6 literal would
        have to be bracketed there.  The name is mapped to
        {option}`fallbackAddress` through `networking.hosts` on the client, so
        no DNS is involved and it resolves on a visiting network.
      '';
    };

    fallbackAddress = lib.mkOption {
      type = lib.types.str;
      default = "fdda:106a:123a:d561:1099:933e:4c60:711f";
      description = ''
        ernst's ZeroTier address, which is reachable wherever the overlay is.
      '';
    };

    hostPublicKey = lib.mkOption {
      type = lib.types.str;
      default = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILd954KHVjUAOX06pHP/+ou78tpo6OYKMQL2ew3eUqEt";
      description = ''
        The builder's SSH host public key, pinned so the daemon never has to
        TOFU.  Mirrors
        `vars/per-machine/ernst/openssh/ssh.id_ed25519.pub/value`; update both
        together if ernst's host key is ever regenerated.
      '';
    };

    maxJobs = lib.mkOption {
      type = lib.types.int;
      default = 8;
      description = ''
        Concurrent derivations the builder accepts.  Kept well under ernst's
        32 cores because the builds that matter here are `big-parallel`
        (kernels), where one job already saturates the machine.
      '';
    };

    speedFactor = lib.mkOption {
      type = lib.types.int;
      default = 2;
      description = "Relative speed vs the local machine (ernst 32c vs miralda 16c).";
    };
  };

  config = lib.mkMerge [
    # ── Shared keypair ────────────────────────────────────────────────────
    # Declared by the client only — see pubKeyPath above for why the builder
    # must not declare it too.  `share = true` still places it under
    # vars/shared/, which is what lets the builder read the public half.
    (lib.mkIf cfg.client.enable {
      clan.core.vars.generators.remote-builder-ssh = {
        share = true;

        files."builder_ed25519" = {
          secret = true;
          owner = "root";
          group = "root";
          mode = "0400";
        };
        files."builder_ed25519.pub".secret = false;

        runtimeInputs = [pkgs.openssh];
        script = ''
          ssh-keygen -t ed25519 -N "" -C "clanarchy-remote-builder" \
            -f "$out/builder_ed25519"
        '';
      };
    })

    # ── Client: dispatch builds ───────────────────────────────────────────
    (lib.mkIf cfg.client.enable {
      nix.distributedBuilds = true;

      # Let the builder fetch from binary caches itself instead of having
      # every dependency proxied over SSH from here.
      nix.settings.builders-use-substitutes = true;

      # TWO ENTRIES, TRIED IN ORDER: the LAN name first for speed, the
      # ZeroTier name second so a roaming client still offloads.
      #
      # nix walks `buildMachines` and skips one it cannot reach, logging
      # `cannot build on 'ssh-ng://…'` and moving on — which is exactly what
      # jens did while ernst was rebooting. That behaviour is what makes a
      # second entry a fallback rather than a hard dependency: at home the
      # LAN wins on copy throughput, away from home it fails fast and the
      # overlay takes over, and with ernst down both miss and the client
      # builds locally as before.
      nix.buildMachines = map (h: {
        hostName = h;
        inherit (cfg) maxJobs speedFactor;
        sshUser = "root";
        sshKey = gen.files."builder_ed25519".path;
        protocol = "ssh-ng";
        systems = ["x86_64-linux"];
        # Subset of ernst's advertised system-features
        # (nixos-test benchmark big-parallel kvm) — `big-parallel` is the one
        # that makes kernel builds eligible at all.
        supportedFeatures = ["big-parallel" "kvm" "nixos-test" "benchmark"];
      }) [cfg.hostName cfg.fallbackHostName];

      # The fallback name resolves through /etc/hosts, not DNS: skynet names
      # do not resolve on a visiting network, which is the whole point.
      networking.hosts.${cfg.fallbackAddress} = [cfg.fallbackHostName];

      programs.ssh.knownHosts."clanarchy-remote-builder" = {
        hostNames = cfg.hostNames ++ [cfg.fallbackHostName];
        publicKey = cfg.hostPublicKey;
      };
    })

    # ── Server: accept builds ─────────────────────────────────────────────
    (lib.mkIf cfg.server.enable {
      # Restricted to the nix-daemon protocol: this key grants remote *builds*,
      # not a root shell.  `restrict` additionally drops pty allocation and
      # all forwarding.
      users.users.root.openssh.authorizedKeys.keys =
        lib.optional (builderPubKey != null)
        ''command="${config.nix.package}/bin/nix-daemon --stdio",restrict ${builderPubKey}'';

      warnings = lib.optional (builderPubKey == null) ''
        clanarchy.remoteBuilder.server is enabled but the builder key does not
        exist yet, so no key has been authorised and remote builds will be
        refused. Run `clan vars generate miralda`, then redeploy this machine.
      '';
    })
  ];
}
