# machines/ernst/microvms/wg-qbittorrent.nix
#
# qBittorrent behind a commercial WireGuard VPN, in a microvm with a real
# killswitch.  M3 in docs/roadmap.md.
#
# Why a microvm and not an nspawn container:
#   Architecture invariant #1 puts a workload in a VM — its own kernel — when it
#   talks to the open internet on its own behalf.  This is the only such
#   workload on ernst: it accepts connections from arbitrary BitTorrent peers
#   and runs a protocol stack against them.  Jellyfin and the arr suite are
#   trusted and storage-heavy, so they stay in nspawn on the shared kernel; a
#   kernel-level escape from libtorrent must not land on the host that owns
#   zdata.
#
# ── The killswitch is nftables, not the routing table ─────────────────────────
#
#   Both halves exist and they do different jobs:
#
#     ROUTING (wg-quick's automatic policy routing) decides where packets try
#     to go.  It is a correctness mechanism and it fails open — delete wg0 and
#     the default route reverts to the LAN.
#
#     NFTABLES decides what is allowed to leave.  Output policy is `drop` on
#     the LAN interface with exactly three exceptions: the encrypted tunnel to
#     the provider's endpoint, DHCPv4, and replies to management-network
#     connections.  Everything else — trackers, peers, DNS — is only reachable
#     via `oifname "wg0"`.  When wg0 disappears, so does the only path out.
#
#   That ordering matters: the firewall is loaded by nftables.service, which is
#   `before network-pre.target`, so the guest is fail-closed from before it has
#   an address, not from whenever the tunnel first comes up.
#
#   DNS RESOLVES IN-TUNNEL ONLY.  The guest runs no resolver of its own,
#   networkd is told `UseDNS=false`, and /etc/resolv.conf is written by
#   wg-quick from the DNS= line in the (secret) tunnel config.  A killswitch
#   that blocks packets but leaks names to the LAN resolver is not a
#   killswitch.
#
#   THE ENDPOINT MUST BE AN IP LITERAL, and the vars generator enforces it.
#   wg-quick resolves a hostname endpoint using the guest's resolver — which is
#   in-tunnel, which does not exist until the handshake completes, which needs
#   the endpoint.  A hostname there does not fail loudly; it fails at every
#   boot, forever.
#
# ── Exposure: the WebUI is a deliberate, permanent Traefik bypass ─────────────
#
#   Architecture invariant #4 names this one explicitly.  The WebUI is reachable
#   from the management networks only (LAN 10.0.10.0/24 and Servers
#   10.0.50.0/24), enforced twice: guest-side nftables here, and a ZBF rule on
#   the UDM-Pro.  It gets NO Traefik route, ever — not in M5, not in M7.  A
#   torrent client's admin surface does not belong on a name that resolves for
#   the household, and forward-auth in front of its API would break the arr
#   integration M4 builds.  Do not "fix" this.
#
# ── uid/gid: the decision the whole media stack rests on ──────────────────────
#
#   virtiofsd runs WITHOUT id translation (no --translate-uid/--translate-gid),
#   so numeric ids pass through the share unchanged in both directions: guest
#   uid 3001 IS host uid 3001.  Everything below follows from that.
#
#     uid 3001  qbittorrent     allocated here (see the id table in
#                               machines/ernst/networking.nix's MAC block for
#                               the sibling convention)
#     gid 3000  media           fixed on the host in containers/jellyfin.nix;
#                               restated in the guest, and it MUST match
#                               numerically or every file the guest writes
#                               lands in a group the host cannot name
#
#   media is qbittorrent's PRIMARY group, not a supplementary one.  Upstream's
#   unit sets PrivateUsers=true, which maps only User= and Group= into the
#   service's user namespace; a supplementary membership would be squashed to
#   nogroup inside it and every write would land root-less.
#
#   UMask=0002 is load-bearing, and this is the failure M4 exists to catch.
#   The download directories are setgid (2770 root:media) so new files inherit
#   gid media whatever the process's umask — but the systemd default umask 0022
#   would still make them mode 0644, i.e. group-READ only.  fs.protected_hardlinks
#   is 1 (kernel default) and refuses `link()` on a file you do not own unless
#   you have read AND WRITE on it.  The M4 arr stack runs host-side as a
#   different uid in group media, so with 0644 every import would fail to
#   hardlink and silently fall back to copying — which is exactly the failure
#   that fills a 6-wide raidz1 twice over.  0002 gives 0664 and the link
#   succeeds.  The PR test plan proves this with `stat` rather than assuming it.
#
# ── virtiofs, not 9p ─────────────────────────────────────────────────────────
#
#   Decided on hardlink and ownership fidelity, as M3 instructed — not on
#   throughput, though virtiofs wins there too.
#
#     9p's security models are disqualifying, not merely slow.  `mapped` and
#     `mapped-file` store ownership in xattrs or a side file, so a file the
#     guest writes appears on the host as the virtfs process's uid.  That
#     breaks the identity mapping above at the root, and with it every
#     host-side hardlink.  `passthrough` preserves ids but is documented as
#     unreliable for exactly the metadata operations that matter here.
#
#     virtiofsd passes uid/gid through unmodified and implements link(),
#     rename() and the rest with full POSIX semantics, which is what qBittorrent
#     needs for its own incomplete → complete moves and what M4 needs for the
#     import.
#
#   ZFS CAVEAT — posixAcl = false on every share.  microvm.nix passes
#   `--posix-acl --xattr` by default, and its own documentation notes that a
#   ZFS-backed share then requires `xattr=sa` + `acltype=posixacl` on the
#   dataset.  Neither zroot nor zdata/{media,state} sets either (see
#   machines/ernst/disko.nix — only zdata/{unsorted,gardens} carry acltype).
#   Nothing here wants POSIX ACLs, so the flag is switched off rather than the
#   pool properties changed.
#
# ── Where the download tree lives ────────────────────────────────────────────
#
#   M3's prompt said /srv/media/downloads.  The deployed tree says
#   /srv/media/torrents: containers/jellyfin.nix already creates
#   torrents/{movies,tv} root:media 2770 beside library/{movies,tvshows}, and
#   those are the directories M4's arr will import FROM.  Inventing a fourth
#   top-level directory would have split the download area in two.  This file
#   adds only the two directories the client itself needs:
#
#     /srv/media/torrents/incomplete   in-progress writes (Session\TempPath)
#     /srv/media/torrents/complete     default save path for uncategorised
#
#   Both inside /srv/media, which is ONE hardlink domain — plain subdirectories,
#   never sub-datasets (invariant #2).
#
# ── State, and what survives a rollback ──────────────────────────────────────
#
#   The guest is STATELESS.  Root is a tmpfs, /nix/store is a read-only share of
#   the host's, and there is no volume: everything that must survive is a share
#   of a zdata path.
#
#     /srv/state/qbittorrent  → /var/lib/qBittorrent   (profile, torrent state)
#     /srv/media/torrents     → same path in the guest  (the data)
#
#   /var/lib/microvms is deliberately NOT persisted, and that is not an
#   oversight.  For a fully-declarative VM, install-microvm-wg-qbittorrent.service
#   is wantedBy microvms.target (→ multi-user.target) and rewrites the state
#   directory's symlinks from the store on every boot, so the zroot rollback
#   has nothing to lose.  Persisting it would freeze a stale `current` symlink
#   across a redeploy — the opposite of what it looks like it does.
#
# ── Side effects of importing microvm.nixosModules.host, checked ─────────────
#
#   1. boot.kernelModules gains "tap" and "vhost_net" host-wide.  Wanted.
#   2. hardware.ksm.enable is mkDefault true.  Turned off below: with one small
#      guest there is nothing for ksmd to merge against on a 256 GB host.
#   3. environment.etc."qemu/bridge.conf" is set to `allow all` — with
#      lib.mkDefault, and modules/virtualisation.nix already enables libvirtd,
#      whose own module sets that file from allowedBridges (default virbr0) as a
#      plain definition.  libvirtd wins; the setuid qemu-bridge-helper is NOT
#      widened to br0.  Checked, because "allow all" in front of a
#      VLAN-filtering bridge would have been a real hole.
#   4. A `microvm` system user (group kvm) with memlock unlimited.  Required —
#      microvm@ runs unprivileged as that user.
#
#   The host module is imported from flake.nix, beside this file, and NOT with
#   an `imports = [ inputs.microvm.nixosModules.host ]` here.  `inputs` reaches
#   a machine module through _module.args, and reading _module.args from
#   `imports` is an infinite recursion — the module system has to know the
#   import list before it can compute the arguments.
{ config, lib, pkgs, ... }:
let
  vmName  = "wg-qbittorrent";

  # Host-side tap.  The name matters twice: machines/ernst/networking.nix
  # already lists "interface-name:tap-*" as NetworkManager-unmanaged, and the
  # networkd unit below matches it.
  tapName = "tap-vpn";

  # Guest-side MAC — 02:00:00:<vlan>:00:<seq>, allocated in the table in
  # machines/ernst/networking.nix.  This is the address the UDM-Pro sees and
  # the one the DHCP reservation keys on; never the host-side tap.
  guestMac = "02:00:00:90:00:03";
  vlanId   = 90;

  qbtUid   = 3001;
  mediaGid = 3000;

  webuiPort   = 8080;
  torrentPort = 6881;

  downloadRoot = "/srv/media/torrents";
  stateSource  = "/srv/state/qbittorrent";

  # Management networks allowed to reach the WebUI and SSH.  LAN (1) is where
  # lgo's machines live; Servers (50) is ernst itself, so a port-forward from
  # the host works without a second hop.
  #
  # ONE list, THREE consumers, deliberately: the guest's nftables input chain,
  # its output chain's established-reply rule, and its routing carve-out.  That
  # is the correct coupling — the set of networks whose traffic may come IN is
  # exactly the set whose replies must be allowed to go back OUT rather than
  # into the tunnel.  The UDM-Pro rule is the fourth consumer and the one that
  # cannot be derived from here; it has to be kept in step by hand.
  mgmtNets = [ "10.0.10.0/24" "10.0.50.0/24" ];

  # Secrets are staged out of sops into a host tmpfs directory and shared into
  # the guest read-only.  NOT a share of /run/secrets itself: that path is a
  # symlink to a per-generation directory which is replaced on every deploy, so
  # a running virtiofsd would keep serving a deleted generation.  A directory
  # we own has a stable identity and is rewritten in place.
  hostSecretsDir  = "/run/microvm-${vmName}-secrets";
  guestSecretsDir = "/run/wg-secrets";

  gen = config.clan.core.vars.generators.wg-qbittorrent;

  # qBittorrent.conf, with the WebUI password hash left as a placeholder that
  # the guest substitutes at start.  The ExecStartPre that renders it carries
  # the reasoning: why the whole file is declarative, and what that costs.
  qbtConfTemplate = pkgs.writeText "qBittorrent.conf" ''
    [LegalNotice]
    Accepted=true

    [BitTorrent]
    Session\DefaultSavePath=${downloadRoot}/complete
    Session\TempPath=${downloadRoot}/incomplete
    Session\TempPathEnabled=true
    Session\Interface=wg0
    Session\InterfaceName=wg0
    Session\Preallocation=true
    Session\QueueingSystemEnabled=false

    [Preferences]
    General\Locale=en
    WebUI\Address=*
    WebUI\Username=admin
    WebUI\Password_PBKDF2=@WEBUI_PASSWORD_PBKDF2@
    WebUI\LocalHostAuth=true
    WebUI\CSRFProtection=true
    WebUI\ClickjackingProtection=true
    WebUI\HostHeaderValidation=true
  '';
in
{
  ##############################################################################
  # Host side.
  ##############################################################################

  # See side-effect note 2 in the file header.
  hardware.ksm.enable = false;

  # Bind sources.  The two new directories are the client's own; the category
  # directories (torrents/movies, torrents/tv) already exist and are chowned
  # root:media 2770 by containers/jellyfin.nix, which owns those rules.
  #
  # 2770 = setgid + rwxrws---: new files inherit gid media, group members read
  # AND write (the arr must be able to hardlink and move), root owns.
  #
  # NOTE ON A DUPLICATE: microvm.nixosModules.host emits its own tmpfiles line
  # for every share source, in 10-microvm.conf.  systemd.tmpfiles.rules lands in
  # 00-nixos.conf, which sorts first and therefore wins; the microvm copy is
  # logged as a duplicate and ignored.  That ordering is why the modes here are
  # the ones that take effect and not microvm's :0775 microvm:kvm — do not
  # rename this into a higher-numbered settings file without rechecking.
  systemd.tmpfiles.rules = [
    "d ${downloadRoot}/incomplete 2770 root media -"
    "d ${downloadRoot}/complete   2770 root media -"
    "d ${stateSource}             0700 ${toString qbtUid} ${toString mediaGid} -"
  ];

  ##############################################################################
  # Secrets: sops → a tmpfs directory → virtiofs → the guest.
  #
  # The guest cannot run sops-nix: it has no persistent state and no age key of
  # its own, and giving it one would put a fleet secret inside the machine whose
  # entire job is to face the internet.  So the host decrypts, and hands over
  # five files.
  #
  # `install -d` on the directory is not redundant.  microvm.nixosModules.host
  # emits a tmpfiles line for every share source, so this path would otherwise
  # be created 0775 microvm:kvm — and unlike the /srv paths above, there is no
  # 00-nixos.conf rule of ours to win the duplicate.  install -d applies mode
  # and ownership to an existing directory too, and it runs immediately before
  # virtiofsd, so the correction always lands.
  #
  # Modes are the interesting part:
  #   0400 root:root   wg0.conf, ssh_host_ed25519_key, endpoint-{ip,port}
  #                    — read by the guest's root (wg-quick, sshd, the nft
  #                    endpoint oneshot) and by nothing else.
  #   0440 root:media  webui-password-pbkdf2 — qBittorrent's own ExecStartPre
  #                    runs as qbittorrent:media and substitutes it into the
  #                    profile.  Group-readable so that step does NOT need a
  #                    `+`-prefixed root escape out of the unit's sandbox.
  #
  # GENERATE BEFORE YOU DEPLOY, and the reason is not politeness.  clan-core
  # cannot know a sops secret's path until the secret exists: until then
  # `files.<n>.path` evaluates to the literal "/no-such-path"
  # (clan-core nixosModules/clanCore/vars/secret/sops/default.nix), and that
  # string is what gets baked into the script below.  So a deploy that runs
  # before `clan vars generate ernst` produces a system whose staging unit can
  # never succeed, no matter how many times it is restarted — it has to be
  # rebuilt.  The failure is at least loud and fail-closed: this unit fails,
  # and microvm@ never starts.  No tunnel config means no VM, not a VM with no
  # tunnel.
  ##############################################################################
  systemd.services."microvm-secrets-${vmName}" = {
    description = "Stage clan-vars secrets for MicroVM '${vmName}'";
    after       = [ "local-fs.target" ];
    before      = [ "microvm-virtiofsd@${vmName}.service" "microvm@${vmName}.service" ];
    requiredBy  = [ "microvm@${vmName}.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # 0750 root:media, NOT 0700 root:root.  The WebUI hash below is
      # group-readable so qBittorrent's own ExecStartPre can read it without a
      # `+`-prefixed escape from the unit's sandbox — but a group-readable file
      # inside a group-untraversable directory is unreadable, which is exactly
      # the bug this deployed with: the render step silently substituted an
      # EMPTY password and the WebUI rejected every login with nothing in any
      # log to say why.  Group needs x on the directory, not just r on the file.
      ${pkgs.coreutils}/bin/install -d -m 0750 -o root -g media ${hostSecretsDir}
      ${pkgs.coreutils}/bin/install -m 0400 -o root -g root \
        ${gen.files."wg0.conf".path}             ${hostSecretsDir}/wg0.conf
      ${pkgs.coreutils}/bin/install -m 0400 -o root -g root \
        ${gen.files."endpoint-ip".path}          ${hostSecretsDir}/endpoint-ip
      ${pkgs.coreutils}/bin/install -m 0400 -o root -g root \
        ${gen.files."endpoint-port".path}        ${hostSecretsDir}/endpoint-port
      ${pkgs.coreutils}/bin/install -m 0400 -o root -g root \
        ${gen.files."ssh-host-key".path}         ${hostSecretsDir}/ssh_host_ed25519_key
      ${pkgs.coreutils}/bin/install -m 0440 -o root -g media \
        ${gen.files."webui-password-pbkdf2".path} ${hostSecretsDir}/webui-password-pbkdf2
    '';
  };

  ##############################################################################
  # The tap: a VLAN-90 port on br0.
  #
  # THERE IS NO NETDEV HERE, and the worked example this replaces in
  # machines/ernst/networking.nix has been corrected to match.  microvm.nix
  # creates the tap itself, from the VM's own bin/tap-up
  # (`ip tuntap add … user microvm`), deleting and recreating it on every start.
  # A netdev unit would race that for ownership of the same name.
  #
  # Bridge=, not KeepMaster=.  This is the OPPOSITE of containers/jellyfin.nix
  # and the difference is real: nspawn enslaves its veth itself, out of band,
  # so networkd must be told to keep its hands off the master while still
  # applying [BridgeVLAN].  Nothing enslaves a microvm tap, so networkd does
  # both — which also means the VLAN race that file documents CANNOT occur
  # here, and no ExecStartPost backstop is needed.  Verify anyway with
  # `bridge vlan show dev tap-vpn`; the failure with DefaultPVID="none" is
  # fail-closed (no VLAN at all), not fail-open onto VLAN 50.
  ##############################################################################
  systemd.network.networks."60-${tapName}" = {
    matchConfig.Name = tapName;
    networkConfig = {
      Bridge              = "br0";
      LinkLocalAddressing = "no";
      IPv6AcceptRA        = false;
    };
    bridgeVLANs = [ { VLAN = vlanId; PVID = vlanId; EgressUntagged = vlanId; } ];
    linkConfig.RequiredForOnline = "enslaved";
  };

  ##############################################################################
  # Vars generator.
  #
  # Everything the tunnel needs is prompted, and the generator assembles a
  # complete wg-quick config rather than exporting the pieces for Nix to
  # reassemble.  Two reasons: the provider's peer material, address and
  # in-tunnel resolver are all credentials, so none of them may be committed;
  # and a single file keeps the provider's own downloaded config recognisable
  # when it is pasted in.
  #
  # endpoint-ip / endpoint-port are emitted separately because the killswitch
  # needs them at runtime, on the guest, before the tunnel exists — parsing a
  # secret at boot to find out what to allow is worse than being handed it.
  #
  # The SSH host key is generated here, not in the guest.  The guest's root is a
  # tmpfs: a self-generated host key would change on every boot and train
  # everyone to click through the warning that is supposed to mean something.
  ##############################################################################
  clan.core.vars.generators.wg-qbittorrent = {
    files."wg0.conf".secret              = true;
    files."endpoint-ip".secret           = true;
    files."endpoint-port".secret         = true;
    files."webui-password-pbkdf2".secret = true;
    files."ssh-host-key".secret          = true;
    files."ssh-host-key.pub".secret      = false;

    prompts."private-key" = {
      description = "WireGuard PRIVATE key for this peer (from the VPN provider's config)";
      type        = "hidden";
    };
    prompts."peer-public-key" = {
      description = "WireGuard PUBLIC key of the provider's server";
      type        = "line";
    };
    prompts."endpoint" = {
      description = "Provider endpoint as IP:PORT — an IP LITERAL, not a hostname (e.g. 193.32.127.70:51820)";
      type        = "line";
    };
    prompts."address" = {
      description = "Tunnel address assigned by the provider, with prefix (e.g. 10.68.4.21/32)";
      type        = "line";
    };
    prompts."dns" = {
      description = "In-tunnel DNS server supplied by the provider (IVPN standard: 172.16.0.1)";
      type        = "line";
    };
    prompts."mtu" = {
      # Optional, and the only prompt that accepts an empty answer.
      #
      # wg-quick derives an MTU when the config does not set one: the egress
      # link's MTU minus 80, i.e. 1420 on ethernet.  Several providers ship a
      # LOWER value — IVPN's own guides say 1412 — and the difference does not
      # fail cleanly.  The handshake completes, `wg show` looks healthy, small
      # requests work, and transfers stall on the first full-size packet.  For
      # a torrent client that is the entire workload.
      #
      # Empty answer → no MTU line at all → wg-quick's derivation, which is the
      # right default for a provider that does not specify one.
      description = "MTU from the provider's config, or EMPTY for wg-quick's default (IVPN: 1412)";
      type        = "line";
    };
    prompts."webui-password" = {
      description = "qBittorrent WebUI password for user 'admin'";
      type        = "hidden";
    };

    runtimeInputs = [ pkgs.coreutils pkgs.gnugrep pkgs.python3 pkgs.openssh ];

    script = ''
      set -euo pipefail

      priv=$(tr -d '[:space:]' < "$prompts/private-key")
      peer=$(tr -d '[:space:]' < "$prompts/peer-public-key")
      endpoint=$(tr -d '[:space:]' < "$prompts/endpoint")
      address=$(tr -d '[:space:]' < "$prompts/address")
      dns=$(tr -d '[:space:]' < "$prompts/dns")
      mtu=$(tr -d '[:space:]' < "$prompts/mtu")

      ##########################################################################
      # Validate EVERYTHING before doing any work, and report every problem in
      # one pass.
      #
      # clan collects all seven prompts and only then runs this script, so an
      # `exit 1` on the first bad value costs the operator every other answer
      # too.  The first version did exactly that and charged six correct
      # answers for one mistyped separator.  Accumulating the errors means one
      # re-run fixes everything, however many things are wrong.
      #
      # Validating here at all is the point of the exercise: every one of these
      # values fails LATE and QUIETLY otherwise — a bad key is "the handshake
      # never completes", a v6 address is "wg-quick aborts at every boot", a
      # hostname endpoint is "unresolvable, because the resolver is inside the
      # tunnel it is needed to build".  A human is watching exactly once.
      ##########################################################################
      fail=0
      err() { echo "  ✗ $*" >&2; fail=1; }

      # 32 bytes of base64 — every WireGuard key is 43 chars plus one '='.
      # Catches the truncated paste, which otherwise presents as a tunnel that
      # comes up and never handshakes.
      wgkey='^[A-Za-z0-9+/]{43}=$'

      valid_ipv4() {
        local ip="$1" octet
        printf '%s' "$ip" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}$' || return 1
        for octet in ''${ip//./ }; do
          [ "$octet" -le 255 ] || return 1
        done
      }

      # ── endpoint ────────────────────────────────────────────────────────────
      case "$endpoint" in
        *:*)
          ep_ip="''${endpoint%:*}"
          ep_port="''${endpoint##*:}"
          valid_ipv4 "$ep_ip" || err \
            "endpoint host '$ep_ip' is not an IPv4 literal. Resolve the provider's hostname yourself (dig +short <host>) and paste an address — the guest's only resolver is inside the tunnel this endpoint builds."
          printf '%s' "$ep_port" | grep -Eq '^[0-9]{1,5}$' || err \
            "endpoint port '$ep_port' is not a number."
          ;;
        *)
          ep_ip=""; ep_port=""
          err "endpoint '$endpoint' has no ':' before the port."
          err "  A dot instead of a colon is the usual slip: 1.2.3.4.51820 should be 1.2.3.4:51820."
          ;;
      esac

      # ── address ─────────────────────────────────────────────────────────────
      # IPv4 only, prefix optional (ip(8) assumes /32 for a bare IPv4).  A v6
      # component is rejected rather than carried: the guest sets
      # net.ipv6.conf.all.disable_ipv6, so wg-quick's `ip -6 address add` would
      # fail, and wg-quick runs under `set -e` — the tunnel would never come up,
      # at every boot, for a reason nothing states out loud.
      case "$address" in
        *,*|*:*)
          err "address '$address' looks dual-stack. Paste ONLY the IPv4 part: the guest has IPv6 disabled, and wg-quick aborts when 'ip -6 address add' fails."
          ;;
        */*)
          valid_ipv4 "''${address%/*}" || err "address '$address' is not an IPv4 address with a prefix."
          printf '%s' "''${address##*/}" | grep -Eq '^[0-9]{1,2}$' || err "address '$address' has a malformed prefix."
          ;;
        *)
          valid_ipv4 "$address" || err "address '$address' is not an IPv4 address."
          ;;
      esac

      # ── the rest ────────────────────────────────────────────────────────────
      valid_ipv4 "$dns" || err \
        "dns '$dns' is not an IPv4 address. IVPN: 172.16.0.1 plain, or one of the 10.0.254.x AntiTracker resolvers."
      printf '%s' "$peer" | grep -Eq "$wgkey" || err \
        "peer-public-key is not a 44-character WireGuard key — check for a truncated paste."
      printf '%s' "$priv" | grep -Eq "$wgkey" || err \
        "private-key is not a 44-character WireGuard key — check for a truncated paste."
      [ -z "$mtu" ] || printf '%s' "$mtu" | grep -Eq '^[0-9]{3,4}$' || err \
        "mtu '$mtu' is not a number (and may be left empty)."

      if [ "$fail" -ne 0 ]; then
        echo "" >&2
        echo "Nothing was written. Fix the above and re-run: clan vars generate ernst" >&2
        exit 1
      fi

      # No Table= line, deliberately: wg-quick's automatic policy routing
      # (fwmark + `suppress_prefixlength 0`) is what puts every non-tunnel
      # destination on wg0.  Setting Table= disables it.
      cat > "$out/wg0.conf" <<EOF
      [Interface]
      PrivateKey = $priv
      Address = $address
      DNS = $dns
      EOF

      # Omitted entirely when the prompt was left empty — an "MTU = " line is
      # not the same thing as no MTU line.
      if [ -n "$mtu" ]; then
        printf 'MTU = %s\n' "$mtu" >> "$out/wg0.conf"
      fi

      cat >> "$out/wg0.conf" <<EOF

      [Peer]
      PublicKey = $peer
      Endpoint = $endpoint
      AllowedIPs = 0.0.0.0/0
      PersistentKeepalive = 25
      EOF

      printf '%s' "$ep_ip"   > "$out/endpoint-ip"
      printf '%s' "$ep_port" > "$out/endpoint-port"

      # qBittorrent's password format: @ByteArray(<b64 salt>:<b64 hash>), where
      # the hash is PBKDF2-HMAC-SHA512, 100000 iterations, 64-byte key over a
      # 16-byte salt.  Generated here so the hash — not the password — is what
      # ever reaches the guest.
      python3 - "$prompts/webui-password" > "$out/webui-password-pbkdf2" <<'PY'
      import base64, hashlib, os, sys
      password = open(sys.argv[1], "rb").read().rstrip(b"\n")
      salt = os.urandom(16)
      digest = hashlib.pbkdf2_hmac("sha512", password, salt, 100000, 64)
      sys.stdout.write("@ByteArray(%s:%s)" % (
          base64.b64encode(salt).decode(),
          base64.b64encode(digest).decode(),
      ))
      PY

      ssh-keygen -t ed25519 -N "" -C "root@wg-qbittorrent" -f "$out/ssh-host-key" >/dev/null
    '';
  };

  ##############################################################################
  # The guest.
  ##############################################################################
  microvm.vms.${vmName} = {
    autostart = true;

    config = { config, lib, pkgs, ... }: {
      system.stateVersion = "26.05";

      microvm = {
        # qemu, and the choice has a consequence worth knowing: the qemu runner
        # does not implement a notify socket, so microvm.nixosModules.host gives
        # microvm@wg-qbittorrent Type=simple.  A guest that fails to finish
        # booting therefore leaves a RUNNING service and a diagnosable console
        # log, instead of the host killing it at TimeoutSec and
        # Restart=always looping it out of reach — the trap
        # containers/jellyfin.nix caps wait-online to 20 s to avoid.
        hypervisor = "qemu";
        vcpu = 2;
        # NOT 2048.  microvm.nix emits an eval warning for exactly that value:
        # qemu hangs when the guest has precisely 2 GB
        # (microvm-nix/microvm.nix#171).  4096 also leaves headroom for
        # libtorrent's piece cache once the session is large; ernst has 256 GB.
        mem  = 4096;

        interfaces = [ {
          type = "tap";
          id   = tapName;
          mac  = guestMac;
        } ];

        # posixAcl = false on every share — see the ZFS caveat in the header.
        shares = [
          {
            # The host's store, read-only.  Without this the guest's closure
            # would be built into a disk image on every change.
            tag = "ro-store";
            source = "/nix/store";
            mountPoint = "/nix/.ro-store";
            proto = "virtiofs";
            readOnly = true;
            posixAcl = false;
          }
          {
            # IDENTICAL PATH on both sides.  Not cosmetic: it is what lets a
            # torrent's path be handed to the arr stack verbatim in M4, with no
            # remote-path mapping to get wrong.
            tag = "downloads";
            source = downloadRoot;
            mountPoint = downloadRoot;
            proto = "virtiofs";
            posixAcl = false;
          }
          {
            # Profile + torrent state, on zdata (invariant #7).  Mounted at
            # upstream's default profileDir so the packaged unit needs no
            # overrides — the same trick containers/jellyfin.nix uses for
            # /var/lib/jellyfin.
            tag = "qbt-state";
            source = stateSource;
            mountPoint = "/var/lib/qBittorrent";
            proto = "virtiofs";
            posixAcl = false;
          }
          {
            tag = "secrets";
            source = hostSecretsDir;
            mountPoint = guestSecretsDir;
            proto = "virtiofs";
            readOnly = true;
            posixAcl = false;
          }
        ];
      };

      ########################################################################
      # Networking.
      ########################################################################

      # No IPv6 anywhere.  The provider's tunnel is v4-only as configured, and
      # a v6 default route the killswitch does not model is precisely how these
      # setups leak.  `table inet` below covers both families regardless.
      networking.enableIPv6 = false;

      # The interface is named eth0, and that is asserted rather than assumed.
      #
      # The nftables ruleset below matches `iifname "eth0"` / `oifname "eth0"`,
      # so the name is part of the killswitch, not a cosmetic detail — a NIC
      # that came up as enp0s7 would leave every LAN-side rule matching nothing
      # and the output chain's `policy drop` would take the guest off the
      # network entirely.  qemu's `microvm` machine type puts the virtio-net on
      # the MMIO bus, where udev has no PCI path to build a predictable name
      # from and would fall back to eth0 anyway — but "would fall back to" is
      # not a guarantee across systemd versions.  net.ifnames=0 makes it one.
      # There is exactly one NIC, so nothing is lost.
      networking.usePredictableInterfaceNames = false;

      networking.useNetworkd = true;
      # No local resolver.  resolvconf (openresolv, on by default) is left
      # enabled because wg-quick uses it to install the provider's DNS from the
      # DNS= line; nothing else writes /etc/resolv.conf, so before the tunnel is
      # up the guest cannot resolve at all.  That is the intended state.
      services.resolved.enable = false;

      # Nothing may talk to an NTP server outside the tunnel, and time-syncing
      # through it buys nothing here: kvm-clock keeps the guest in step with
      # ernst, which does sync.
      services.timesyncd.enable = false;

      systemd.network.networks."10-eth0" = {
        matchConfig.Name = "eth0";
        networkConfig = {
          DHCP         = "ipv4";
          IPv6AcceptRA = false;
        };
        dhcpV4Config = {
          # The lease supplies an address and a gateway and nothing else.  A
          # resolver from DHCP would be a LAN resolver, i.e. a name leak.
          UseDNS     = false;
          UseDomains = false;
          UseNTP     = false;
        };

        # The carve-out that keeps replies to management clients out of the
        # tunnel.  ROUTES, not routing policy rules — and the difference is the
        # whole point.
        #
        # With AllowedIPs = 0.0.0.0/0, wg-quick installs two rules:
        #
        #   from all lookup main suppress_prefixlength 0
        #   not from all fwmark 0xca6c lookup <wg table>
        #
        # Main is consulted first, but its DEFAULT route is suppressed, so a
        # reply to a client on 10.0.10.0/24 — a different subnet from the
        # guest's own — matches nothing in main, falls to the second rule, and
        # is routed into the tunnel.  The WebUI and SSH appear dead from exactly
        # the networks that are allowed to reach them.
        #
        # THE OBVIOUS FIX DOES NOT WORK, and it was tried first: a
        # [RoutingPolicyRule] per management network at priority 100.  wg-quick
        # runs AFTER networkd and adds its rules without an explicit priority,
        # and the kernel's fib_default_rule_pref() assigns "one less than the
        # second rule in the list" — so it landed at 99 and 98, ahead of ours,
        # *because* ours were at 100.  Measured on the running guest:
        #
        #   98:  from all lookup main suppress_prefixlength 0
        #   99:  not from all fwmark 0xca6c lookup 51820
        #   100: from all to 10.0.10.0/24 lookup main      ← never consulted
        #
        # Picking a lower number cannot win: wg-quick would take one lower
        # still.  Anything that competes on rule priority loses to a program
        # that chooses its priority at run time relative to whatever it finds.
        #
        # So compete on route specificity instead.  `suppress_prefixlength 0`
        # rejects only prefix length 0 — the default route — so an explicit
        # /24 in main is found by wg-quick's OWN first rule and wins there,
        # whatever the priorities end up being.  Nothing is widened: the
        # nftables output chain still drops everything to these networks except
        # replies on established flows.
        #
        # Gateway = _dhcp4 rather than a literal 10.0.90.1: the UDM-Pro owns
        # this subnet's gateway and a second copy here would be a fact that can
        # silently diverge — the same call M2b made about the address itself.
        #
        # Per network, never a supernet.  A provider's in-tunnel resolver can
        # live inside 10.0.0.0/16 — IVPN's AntiTracker DNS is 10.0.254.2/.3,
        # and the one actually in use here is 10.0.254.4 — and a /16 carve-out
        # would route every DNS query at eth0, where the killswitch correctly
        # drops it.  Tunnel up, `wg show` perfect, not one name resolving.
        routes = map (net: {
          Destination = net;
          Gateway     = "_dhcp4";
        }) mgmtNets;

        linkConfig.RequiredForOnline = "routable";
      };

      # 20 s: long enough for a DHCP lease, short enough that a missing
      # reservation leaves one obviously failed unit rather than a two-minute
      # stall in the middle of boot.  Same reasoning, at length, in
      # machines/ernst/containers/jellyfin.nix.
      systemd.network.wait-online.timeout = 20;

      ########################################################################
      # The killswitch.
      ########################################################################
      networking.firewall.enable = false;
      networking.nftables = {
        enable = true;
        ruleset = ''
          table inet killswitch {
            # Management networks: the only source allowed to reach the WebUI
            # and SSH.  Mirrored on the UDM-Pro; both must agree.
            set mgmt_nets {
              type ipv4_addr
              flags interval
              elements = { ${lib.concatStringsSep ", " mgmtNets} }
            }

            # The VPN endpoint, as address . port.  Deliberately EMPTY at load
            # time and filled in at boot by vpn-killswitch-endpoint.service from
            # the staged secret: the endpoint is a credential and does not
            # belong in a world-readable /etc/nftables ruleset.  An empty set
            # means the handshake itself is blocked — fail-closed, and the
            # symptom is a tunnel that never comes up rather than traffic that
            # quietly takes the wrong door.
            set vpn_endpoint {
              type ipv4_addr . inet_service
            }

            chain input {
              type filter hook input priority filter; policy drop;

              iif lo accept
              ct state established,related accept
              ct state invalid drop

              iifname "eth0" ip saddr @mgmt_nets tcp dport ${toString webuiPort} accept
              iifname "eth0" ip saddr @mgmt_nets tcp dport 22 accept
              iifname "eth0" ip saddr @mgmt_nets icmp type echo-request accept

              # DHCPv4 offers/acks.  networkd's initial exchange uses a raw
              # packet socket and bypasses this hook entirely; the rule is here
              # for the unicast renewal, which does not.
              iifname "eth0" udp sport 67 udp dport 68 accept

              # Incoming peer connections, in-tunnel only.  Useful solely if
              # the provider forwards a port; harmless when it does not.
              iifname "wg0" tcp dport ${toString torrentPort} accept
              iifname "wg0" udp dport ${toString torrentPort} accept
            }

            chain forward {
              type filter hook forward priority filter; policy drop;
            }

            chain output {
              type filter hook output priority filter; policy drop;

              oif lo accept

              # THE killswitch.  Three exceptions on the LAN side, and no
              # blanket `ct state established` — an established entry is not
              # bound to an interface, so a global accept here would let a flow
              # that was built through the tunnel continue out of eth0 the
              # moment wg0 disappeared.  Scoping the established rule to the
              # management networks keeps the WebUI and SSH answering without
              # opening that door.
              oifname "eth0" ip daddr @mgmt_nets ct state established,related accept
              oifname "eth0" ip daddr . udp dport @vpn_endpoint accept
              oifname "eth0" udp sport 68 udp dport 67 accept

              # Everything else — trackers, peers, DNS, the lot.
              oifname "wg0" accept
            }
          }
        '';
      };

      # Fill the endpoint set from the staged secret.
      #
      # partOf nftables.service so that reloading the ruleset — which flushes
      # every set — re-runs this instead of silently leaving the tunnel with no
      # way out.  Ordered before wg-quick for the obvious reason.
      systemd.services.vpn-killswitch-endpoint = {
        description = "Populate the killswitch's VPN endpoint set";
        after       = [ "nftables.service" ];
        partOf      = [ "nftables.service" ];
        before      = [ "wg-quick-wg0.service" ];
        requiredBy  = [ "wg-quick-wg0.service" ];
        serviceConfig = {
          Type            = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          ip=$(${pkgs.coreutils}/bin/cat ${guestSecretsDir}/endpoint-ip)
          port=$(${pkgs.coreutils}/bin/cat ${guestSecretsDir}/endpoint-port)
          ${pkgs.nftables}/bin/nft add element inet killswitch vpn_endpoint \
            "{ $ip . $port }"
        '';
      };

      ########################################################################
      # The tunnel.
      ########################################################################
      networking.wg-quick.interfaces.wg0.configFile = "${guestSecretsDir}/wg0.conf";

      ########################################################################
      # SSH — management networks only, and the reason it exists at all.
      #
      # M3's test plan requires running commands INSIDE the guest (the exit-IP
      # check through wg0).  The qemu runner wires the serial console to the
      # service's stdout, i.e. to ernst's journal: excellent for reading a boot,
      # useless for typing into.  Without sshd the milestone cannot be verified
      # and M4 has no way to look at the client it integrates with.
      #
      # Key-only, root-only, and reachable from mgmt_nets alone.  The key is the
      # YubiKey ed25519 that is already authorised across the fleet
      # (modules/users/admin.nix uses the same file), so this adds a host to
      # reach, not a credential to manage.
      ########################################################################
      services.openssh = {
        enable = true;
        settings = {
          PermitRootLogin        = "prohibit-password";
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
        };
        # Host key from the vars generator: root is a tmpfs, so a
        # self-generated key would be new on every boot.
        hostKeys = [ ];
        extraConfig = ''
          HostKey ${guestSecretsDir}/ssh_host_ed25519_key
        '';
      };
      users.users.root.openssh.authorizedKeys.keyFiles = [
        ../../miralda/yubikey_ed25519.pub
      ];

      ########################################################################
      # qBittorrent.
      ########################################################################

      # uid/gid pinned to match the host — see the file header.  media is the
      # PRIMARY group; PrivateUsers=true in the upstream unit would squash a
      # supplementary one.
      users.users.qbittorrent = {
        isSystemUser = true;
        uid          = qbtUid;
        group        = "media";
      };
      users.groups.media = { gid = mediaGid; };

      services.qbittorrent = {
        enable         = true;
        user           = "qbittorrent";
        group          = "media";
        webuiPort      = webuiPort;
        torrentingPort = torrentPort;

        # Reachability is the firewall's job, above; upstream's openFirewall
        # would also open torrentingPort on the LAN side, which is the one
        # thing this guest exists to prevent.
        openFirewall = false;

        # serverConfig is deliberately EMPTY, and the config is rendered by the
        # ExecStartPre below instead.  Upstream's serverConfig path installs a
        # store-built qBittorrent.conf on every start — which is the behaviour
        # we want — but it has no way to interpolate a secret, and the WebUI
        # password hash must not be in the store.  Setting both would mean two
        # ExecStartPre definitions of the same option, which is a merge
        # conflict, not an append.
        serverConfig = { };

        # --confirm-legal-notice as well as [LegalNotice] Accepted=true: the
        # conf covers the normal path, the flag covers the first start, when
        # the file is written after the check.
        extraArgs = [ "--confirm-legal-notice" ];
      };

      systemd.services.qbittorrent = {
        # Start after the tunnel, but do not depend on it: `wants`, not
        # `requires`.  If wg0 fails, qBittorrent should still come up so the
        # WebUI can say so — it is bound to wg0 at the application level and
        # will not move a byte regardless.
        wants = [ "wg-quick-wg0.service" ];
        after = [ "wg-quick-wg0.service" ];

        serviceConfig = {
          # THE line that makes M4's hardlinks possible.  0002 → files 0664,
          # so a host-side arr in group media has the write bit
          # fs.protected_hardlinks demands before it will link a file it does
          # not own.  With the systemd default 0022 the import silently copies.
          # The header explains this at length; do not "tidy" it away.
          UMask = "0002";

          # Renders the profile config, substituting the WebUI password hash.
          # Runs as qbittorrent:media inside the unit's own sandbox — no `+`
          # escape needed, because the staged hash is group-readable by media.
          #
          # THE TRADE, stated plainly: this file is authoritative on every
          # start, so anything changed in the WebUI that lives in
          # qBittorrent.conf is discarded at the next restart (i.e. at the next
          # deploy).  That is deliberate — same call as forceEncodingConfig in
          # containers/jellyfin.nix, and for the same reason: this is the
          # machine where the repo wins.  Torrent state, categories
          # (categories.json) and the resume data are separate files and are
          # NOT touched.
          ExecStartPre = [
            "${pkgs.writeShellScript "qbittorrent-render-config" ''
              set -euo pipefail
              conf=/var/lib/qBittorrent/qBittorrent/config/qBittorrent.conf

              # Read into a variable FIRST, and check it.  `sed "s|x|$(cat f)|"`
              # looks equivalent and is not: a command substitution that fails
              # inside an argument does not trip `set -e`, so an unreadable
              # secret becomes an EMPTY password rather than a failed unit.
              # That shipped once — the WebUI then rejected every login and
              # nothing anywhere said why.  A plain assignment DOES trip
              # `set -e`, and the explicit test covers the file being present
              # but empty.
              hash=$(${pkgs.coreutils}/bin/cat ${guestSecretsDir}/webui-password-pbkdf2)
              if [ -z "$hash" ]; then
                echo "webui-password-pbkdf2 is empty — refusing to start with no password" >&2
                exit 1
              fi

              ${pkgs.coreutils}/bin/install -Dm600 ${qbtConfTemplate} "$conf"
              ${pkgs.gnused}/bin/sed -i "s|@WEBUI_PASSWORD_PBKDF2@|$hash|" "$conf"
            ''}"
          ];
        };
      };

      # No host keys to generate — the one host key comes from the vars
      # generator, because the guest's root is a tmpfs and a self-generated key
      # would be new on every boot.  Without this, sshd-keygen.service is
      # emitted with an empty ExecStart and systemd refuses it noisily on the
      # console at every boot: "Service has no ExecStart=. Refusing."  Harmless,
      # but it is the only red line in an otherwise clean boot log, and a boot
      # log people learn to ignore is worse than no boot log.
      systemd.services.sshd-keygen.enable = false;

      # Minimal guest.  curl and wireguard-tools are the test plan's
      # instruments (exit-IP check through wg0, `wg show` for the handshake);
      # everything else stays out.
      environment.systemPackages = with pkgs; [ curl wireguard-tools ];
      documentation.enable = false;
      documentation.nixos.enable = false;
    };
  };
}
