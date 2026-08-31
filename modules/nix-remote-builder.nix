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
{ config, lib, pkgs, ... }:

let
  cfg = config.clanarchy.remoteBuilder;
  gen = config.clan.core.vars.generators.remote-builder-ssh;

  # readFile keeps ssh-keygen's trailing newline; it must not survive into an
  # authorized_keys line that carries a command= prefix.
  builderPubKey = lib.removeSuffix "\n" gen.files."builder_ed25519.pub".value;
in
{
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
      default = [ "ernst" "ernst.skynet.lan" "10.0.50.10" ];
      description = "Names/addresses the pinned builder host key is valid for.";
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
    # Declared on both ends so the one generator backs both roles.
    (lib.mkIf (cfg.client.enable || cfg.server.enable) {
      clan.core.vars.generators.remote-builder-ssh = {
        share = true;

        files."builder_ed25519" = {
          secret = true;
          # Only the dispatching side needs the private half; without this
          # gate, declaring the generator on the builder would ship it there
          # too, for nothing.
          deploy = cfg.client.enable;
          owner = "root";
          group = "root";
          mode = "0400";
        };
        files."builder_ed25519.pub".secret = false;

        runtimeInputs = [ pkgs.openssh ];
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

      nix.buildMachines = [{
        inherit (cfg) hostName maxJobs speedFactor;
        sshUser = "root";
        sshKey = gen.files."builder_ed25519".path;
        protocol = "ssh-ng";
        systems = [ "x86_64-linux" ];
        # Subset of ernst's advertised system-features
        # (nixos-test benchmark big-parallel kvm) — `big-parallel` is the one
        # that makes kernel builds eligible at all.
        supportedFeatures = [ "big-parallel" "kvm" "nixos-test" "benchmark" ];
      }];

      programs.ssh.knownHosts."clanarchy-remote-builder" = {
        hostNames = cfg.hostNames;
        publicKey = cfg.hostPublicKey;
      };
    })

    # ── Server: accept builds ─────────────────────────────────────────────
    (lib.mkIf cfg.server.enable {
      # Restricted to the nix-daemon protocol: this key grants remote *builds*,
      # not a root shell.  `restrict` additionally drops pty allocation and
      # all forwarding.
      users.users.root.openssh.authorizedKeys.keys = [
        ''command="${config.nix.package}/bin/nix-daemon --stdio",restrict ${builderPubKey}''
      ];
    })
  ];
}
