{ lib, ... }:
#
# System-wide known_hosts for every clan machine, on every address it answers on.
#
# ── The bug this exists to prevent ───────────────────────────────────────
#
# `clan machines update <m>` probes reachability and connects over whichever
# path answers first.  When ZeroTier is up that is the ZeroTier IPv6 address,
# not the LAN name.  ssh verifies the host key against the address *it dialled*,
# so a known_hosts file that lists only `ernst,ernst.skynet.lan,10.0.50.10`
# fails on the ZeroTier path with:
#
#   ssh_askpass: exec(): No such file or directory
#   Host key verification failed.
#
# — which reads like a broken agent or a network fault, and is neither.  It is
# StrictHostKeyChecking=ask with no TTY to ask on.  Deploys then only work with
# `--target-host root@10.0.50.10`, i.e. by manually steering clan away from the
# path it chose.  This bit ernst on 2026-09-06.
#
# ── Why this is generated rather than written out ────────────────────────
#
# The list it replaces was hand-maintained in modules/hardware/yubikey.nix and
# carried ZeroTier entries for exactly the two machines that existed when it was
# written.  jens and ernst were added to the clan later and never got theirs, so
# the omission was invisible until ZeroTier happened to win a reachability race.
# A hand-maintained mirror of fleet state decays silently; that is the same
# failure the "THE RULE" comment in modules/users/lgo.nix is fighting on the
# ssh_config side, where every new alias for a machine must be added by hand.
#
# So both halves are read from the vars the fleet already commits:
#
#   vars/per-machine/<m>/openssh/ssh.id_ed25519.pub/value   host public key
#   vars/shared/zerotier-ip-<m>-zerotier/ip/value           ZeroTier IPv6
#
# Both are public by construction — a host *public* key and an overlay address
# — which is why they are committed in the clear and safe to read at eval time.
# Nothing secret is touched here.  A new machine gets its entries the moment
# `clan vars generate <m>` runs; nobody has to remember this file.
#
# Machines are discovered by requiring *both* files, which also filters out
# retired entries under vars/per-machine (e.g. `homeserver`, which still has a
# host key but no ZeroTier identity).
#
let
  varsRoot = ../../vars;

  hostKeyFile = m: "${varsRoot}/per-machine/${m}/openssh/ssh.id_ed25519.pub/value";
  zerotierFile = m: "${varsRoot}/shared/zerotier-ip-${m}-zerotier/ip/value";

  # These files are not consistently terminated: the host key ends with a
  # trailing SPACE then a newline, the ZeroTier address has no trailing newline
  # at all.  Trim rather than stripping a specific suffix, so neither the space
  # leaks into the generated line nor a future newline breaks the address.
  readTrimmed = f: lib.trim (builtins.readFile f);

  # Extra addresses that cannot be derived from vars: static LAN addresses.
  # The laptops are DHCP and are reached by name, so only ernst has one.
  extraHostNames = {
    ernst = [ "10.0.50.10" ];
  };

  candidates = lib.attrNames (
    lib.filterAttrs (_: type: type == "directory") (builtins.readDir "${varsRoot}/per-machine")
  );

  machines = lib.filter (
    m: builtins.pathExists (hostKeyFile m) && builtins.pathExists (zerotierFile m)
  ) candidates;

  # `clan machines update` defaults to <name>.<domain>, and the host certs are
  # issued for exactly that principal — but lgo's ssh_config forces
  # HostKeyAlgorithms=ssh-ed25519 (to stop GnuPG 2.4.x refusing to sign with the
  # card-backed key), which excludes ssh-ed25519-cert-v01 and so takes the
  # @cert-authority line in this same file out of play.  The plain key has to be
  # pinned for the goclan.org name too, or cert-verified names are unreachable
  # from the machine that does the deploying.
  entryFor = m: {
    name = "clanarchy-${m}";
    value = {
      hostNames =
        [
          m
          "${m}.local"
          "${m}.skynet.lan"
          "${m}.goclan.org"
          (readTrimmed (zerotierFile m))
        ]
        ++ (extraHostNames.${m} or [ ]);
      publicKey = readTrimmed (hostKeyFile m);
    };
  };
in
{
  programs.ssh.knownHosts = lib.listToAttrs (map entryFor machines);
}
