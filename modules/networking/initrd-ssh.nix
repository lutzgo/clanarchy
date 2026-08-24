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
{ config, lib, ... }:
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
        # So the unlock window was 19:09:25-19:10:21 and the first six seconds
        # of it were spent waiting for a link that was coming up anyway.  Six
        # seconds is not the reason that reboot was unlocked at the TV (see
        # docs/guides/remote-unlock.md — the reason was a 36-minute POST), and
        # it is not claimed to be.  It is set because the address existing
        # before carrier is strictly better on a recovery path: if negotiation
        # is ever slow or flaky rather than merely late, the difference is
        # between "reachable as soon as the link is up" and "not configured at
        # all".
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
    };
  };
}
