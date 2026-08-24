# Stage-1 SSH server for remote pool/passphrase unlock.
#
# Enable with `clanarchy.initrdSsh.enable = true;` on any machine that also
# has `boot.initrd.systemd.enable = true` (the fleet default — set in
# modules/zfs-impermanence.nix).  On boot the machine pauses at the
# `systemd-ask-password` prompt for the encrypted root pool.  Connect from
# another machine on the LAN and run:
#
#     systemd-tty-ask-password-agent --query
#
# to see and answer any pending prompts (the zroot passphrase).
#
# ── ONE-TIME per target: generate the initrd host key ────────────────────
# Run on the target (chicken-and-egg — needs /persist mounted, so first do
# a normal boot):
#
#     umask 077
#     mkdir -p /persist/etc/secrets/initrd
#     ssh-keygen -t ed25519 -N "" -C "$(hostname) initrd" \
#       -f /persist/etc/secrets/initrd/ssh_host_ed25519_key
#     chmod 400 /persist/etc/secrets/initrd/ssh_host_ed25519_key
#
# The key lives on encrypted zroot.  At `nixos-rebuild boot|switch` NixOS
# reads it via `boot.initrd.secrets` and appends it to the initrd cpio.
# The final initrd sits on /boot (unencrypted vfat) — a physical attacker
# with /boot access can extract the initrd host key and MITM your unlock
# session.  For a homelab this is an acceptable trade-off; higher threat
# models want unified-kernel-image + encrypted /boot.
#
# ── Client-side (miralda) known_hosts caveat ─────────────────────────────
# The initrd sshd host key differs from the running-system host key.  Use
# `HostKeyAlias` on the client so both keys can coexist in known_hosts
# without conflict — see the "ernst-initrd" block in modules/users/lgo.nix.
{ config, lib, pkgs, ... }:
let
  cfg = config.clanarchy.initrdSsh;
in
{
  options.clanarchy.initrdSsh = {
    enable = lib.mkEnableOption "stage-1 SSH server for remote pool/passphrase unlock";

    port = lib.mkOption {
      type    = lib.types.port;
      default = 2222;
      description = ''
        TCP port for the initrd sshd.  Off 22 so the initrd and running-system
        host keys never clash in a single known_hosts entry.
      '';
    };

    hostKey = lib.mkOption {
      type    = lib.types.path;
      default = "/persist/etc/secrets/initrd/ssh_host_ed25519_key";
      description = ''
        Path (on the target) to the ed25519 host key.  Must exist at
        nixos-rebuild activation time; see the file header for one-time
        generation.  Passed to `boot.initrd.network.ssh.hostKeys`, so NixOS
        reads it during activation and appends it to the initrd cpio.
      '';
    };

    authorizedKeyFiles = lib.mkOption {
      type    = lib.types.listOf lib.types.path;
      default = [ ];
      description = ''
        Public-key files whose contents authorise root logins to the
        initrd sshd.  Read at eval time (same pattern as modules/users/
        admin.nix's openssh.authorizedKeys.keys).
      '';
    };

    interface = lib.mkOption {
      type = lib.types.str;
      description = "NIC to bring up in stage 1.  Same name as in stage 2 (systemd persistent naming applies in initrd too).";
    };

    address = lib.mkOption {
      type = lib.types.str;
      example = "10.0.50.10/24";
      description = "Static IPv4 CIDR for the initrd interface — typically identical to the running-system address (never up simultaneously).";
    };

    gateway = lib.mkOption {
      type = lib.types.str;
      example = "10.0.50.1";
      description = "IPv4 default-route gateway for the initrd interface.";
    };

    kernelModules = lib.mkOption {
      type    = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "atlantic" "igc" ];
      description = "NIC drivers to include in the initrd so the interface is up before sshd starts.";
    };

    debug = lib.mkOption {
      type    = lib.types.bool;
      default = false;
      description = ''
        Instrument stage 1 for ONE diagnostic boot, then turn it off again.

        Adds two things: `LogLevel VERBOSE` on the initrd sshd, so an accepted
        TCP connection logs `Connection from <ip> port <n>` before any
        authentication; and a oneshot that dumps `ip -br address`, `ip route`
        and `ip neigh` into the stage-1 journal.

        Why it is not on by default: it is diagnostic scaffolding, and
        scaffolding left up permanently stops being read. VERBOSE also logs
        every connection attempt to a port on the recovery path, which is more
        detail than a normal boot has any use for.

        Why it exists at all: on 2026-08-24 remote unlock failed and could not
        be diagnosed afterwards, because stage-1 sshd logged exactly two lines
        for the whole boot and nothing recorded whether the interface ever held
        an address. "sshd logged nothing" could not be read as "no packets
        arrived", and those two have different fixes.

        Turn it on, deploy, reboot, read the journal, turn it off:
            journalctl -b 0 | grep -iE "sshd|clanarchy-initrd-netdebug"
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.boot.initrd.systemd.enable;
        message   = "clanarchy.initrdSsh requires boot.initrd.systemd.enable = true.";
      }
      {
        assertion = cfg.authorizedKeyFiles != [ ];
        message   = "clanarchy.initrdSsh.authorizedKeyFiles must not be empty.";
      }
    ];

    # NIC drivers so the interface is available to udev before networkd.
    boot.initrd.availableKernelModules = cfg.kernelModules;

    # systemd-initrd network setup.  boot.initrd.network.enable = true
    # cascades to systemd.network.enable in stage 1 (see boot/networkd.nix
    # line 4297 in nixpkgs).
    boot.initrd.network.enable = true;
    boot.initrd.systemd.network.networks."50-initrd-${cfg.interface}" = {
      matchConfig.Name = cfg.interface;
      networkConfig    = {
        Address = cfg.address;
        Gateway = cfg.gateway;

        # Configure the address before the link has carrier.
        #
        # machines/ernst/networking.nix sets exactly this on 50-br0, for
        # exactly this NIC, with the reason written next to it: the atlantic
        # 10G part takes ~10 s to negotiate.  Stage 1 did not, which is an
        # inconsistency rather than a decision — the same card behaves the same
        # way in both stages.
        #
        # MEASURED on ernst's 2026-08-24 reboot:
        #
        #   19:09:19  networkd: enp13s0: Configuring with 50-initrd-enp13s0
        #   19:09:19  sshd: Server listening on 0.0.0.0 port 2222
        #   19:09:25  networkd: enp13s0: Gained carrier          ← 6 s later
        #   19:10:21  sshd: Received signal 15; terminating      ← handoff
        #
        # So the first six seconds of the window were spent waiting for a link
        # that was coming up anyway.  Six seconds is not why that reboot was
        # unlocked at the TV, and it is not claimed to be.  It is set because
        # an address that exists before carrier is strictly better on a
        # recovery path: if negotiation is ever slow or flaky rather than
        # merely late, the difference is between "reachable as soon as the link
        # is up" and "not configured at all".
        #
        # WHY THAT REBOOT WENT TO THE TV — corrected 2026-08-24, having first
        # been recorded here as a 36-minute firmware POST.  It was not.
        # `systemd-analyze time` puts firmware at 36.851 SECONDS and the whole
        # boot at 2min05.  The 36 minutes was the machine sitting at the
        # passphrase prompt, reachable, until it was power-cycled — confirmed
        # by the operator and by `zpool history`, which shows a zroot import at
        # 18:33:23 (fifty seconds after shutdown) with no matching zdata
        # import, i.e. a boot that stopped in stage 1 and left no journal.
        #
        # The lesson is the one this repo keeps relearning: a gap in the
        # journal is not a measurement.  It was read as POST because nothing
        # else was logged, and the one command that would have settled it
        # (`systemd-analyze time`) was never run.  See
        # docs/guides/remote-unlock.md for the corrected timeline.
        ConfigureWithoutCarrier = true;
      };
    };

    # sshd itself.  Under boot.initrd.systemd.enable, the upstream module
    # (nixos/modules/system/boot/initrd-ssh.nix) wires this via
    # boot.initrd.systemd.services.sshd + /etc/ssh/authorized_keys.d/root.
    boot.initrd.network.ssh = {
      enable             = true;
      port               = cfg.port;
      hostKeys           = [ cfg.hostKey ];
      authorizedKeyFiles = cfg.authorizedKeyFiles;

      # OPT-IN ONLY — see clanarchy.initrdSsh.debug.  At the default LogLevel
      # an aborted or rejected connection can leave no trace at all, so "sshd
      # logged nothing" cannot be read as "no packets arrived"; VERBOSE logs
      # `Connection from <ip> port <n>` before any authentication, which is
      # exactly the line that tells those two apart.
      #
      # Not on permanently, deliberately: it is scaffolding, and scaffolding
      # left up stops being read.
      extraConfig = lib.mkIf cfg.debug "LogLevel VERBOSE";
    };

    # Record stage-1 network state, once, after networkd has configured it.
    # OPT-IN — see clanarchy.initrdSsh.debug.
    #
    # THE REASON THIS EXISTS: on 2026-08-24 nothing in the journal could answer
    # "did enp13s0 actually have 10.0.50.10 in stage 1?".  networkd logs a DHCP
    # lease but not a static address, so the only IPv4 evidence for the whole
    # initrd was an absence — and an absence is not a measurement, which is the
    # mistake this file's history already records twice.
    #
    # Three commands, one oneshot, no network traffic.  `ip neigh` is included
    # deliberately: stage 1 speaks from the interface's HARDWARE MAC while
    # stage 2 speaks from br0's pinned MAC (machines/ernst/networking.nix), so
    # the same address has two link-layer identities depending on boot stage,
    # and a stale neighbour entry upstream is one candidate explanation for
    # packets that never arrive.
    boot.initrd.systemd.storePaths =
      lib.mkIf cfg.debug [ pkgs.iproute2 ];

    boot.initrd.systemd.services.clanarchy-initrd-netdebug = lib.mkIf cfg.debug {
      description = "Record stage-1 network state for post-mortem";
      wantedBy    = [ "initrd.target" ];
      after       = [ "systemd-networkd.service" "network.target" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type            = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${pkgs.iproute2}/bin/ip -br address show
        ${pkgs.iproute2}/bin/ip route show
        ${pkgs.iproute2}/bin/ip neigh show
      '';
    };
  };
}
