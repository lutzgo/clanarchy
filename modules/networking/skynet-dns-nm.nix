# Home-LAN DNS routing for NetworkManager-managed clan machines.
#
# The clan-core wifi service (clan.nix → inventory.instances.wifi) creates
# an NM connection profile named "home" for our home wifi.  We extend that
# profile here via module merging on `ensureProfiles.profiles.home`.
#
# Why this matters: without a routing hint, resolved treats every link with
# a DHCP-supplied DNS as a "default route" resolver and load-balances /
# races them.  With `Global Domains=skynet.lan` set (via
# `networking.search`) queries for *.skynet.lan were being sent to
# Global's FallbackDNS (Cloudflare) → NXDOMAIN.  Dropping
# `networking.search` alone fixes the routing bug; this module goes further
# and *enforces* Technitium as the sole resolver on the home LAN.
#
#   ipv4.method      = "auto"
#     DHCP.  See THE BUG below — this line is not decoration, it is the
#     difference between a profile NetworkManager loads and one it silently
#     throws away.
#   ipv4.dns-search  = "~. skynet.lan"
#     ~.          — routing catch-all: while this profile is active, ALL
#                   DNS queries route through this link's DHCP-supplied
#                   resolver (Technitium at 10.0.5.3), so its blocklists
#                   and logging apply to every lookup — not just *.skynet.lan.
#     skynet.lan  — search suffix (no `~`) so bare hostnames like
#                   `ssh ernst` resolve as ernst.skynet.lan.
#   ipv4.dns-priority = -100
#     Pins this link's DNS to win against any other active NM connection
#     (e.g. a wired dock or tethered phone) that also supplies DNS.
#
# Off-LAN (any wifi profile other than "home") is untouched: DHCP-supplied
# DNS from a coffee-shop / hotel network works normally.
#
# ── THE BUG THIS FILE SHIPPED WITH, 2026-08-24 ───────────────────────────────
#
#   THIS MODULE HAD NEVER WORKED ON MIRALDA, AND IT BROKE THE PROFILE IT WAS
#   MEANT TO EXTEND.  It was not a name mismatch, a priority problem, or
#   anything to do with resolved.  `ipv4.method` was missing.
#
#   NixOS renders `ensureProfiles.profiles.home` into a NetworkManager keyfile
#   with a `[ipv4]` section holding ONLY the two keys above.  NM's settings
#   verifier rejects an `[ipv4]` section without a `method`, and it rejects the
#   WHOLE CONNECTION rather than the section.  Measured, offline, with the real
#   rendered file:
#
#     $ nmcli --offline connection modify connection.id skynet < home.nmconnection
#     Error: Error writing connection: ipv4.method: property is missing
#
#   Adding `method=auto` makes the identical file parse and keeps both DNS keys.
#   That is the entire fix.
#
#   BEFORE THIS MODULE EXISTED the profile had no `[ipv4]` section at all, which
#   is valid — NM defaults an absent section to DHCP.  So adding two DNS keys to
#   a working profile is what destroyed it.  The section is all-or-nothing: the
#   moment you write one key into it, you own `method` as well.
#
#   ── WHAT IT COST, which is more than DNS ──────────────────────────────────
#
#   NixOS writes declarative profiles to /run/NetworkManager/system-connections
#   (volatile, rewritten by NetworkManager-ensure-profiles.service on every
#   activation).  A rejected profile therefore leaves the machine with NO wifi
#   profile at all.  On an impermanent host that is not a one-time annoyance:
#   /etc/NetworkManager/system-connections lives on `zroot/root`, which rolls
#   back on every boot and is NOT in the persist set — so a profile created by
#   hand in the GUI to get online survives exactly until the next reboot.
#
#   The evidence on miralda, 2026-08-24:
#
#     uptime                                            4 days
#     /etc/NetworkManager/system-connections/skynet.nmconnection
#                                        created 2026-08-20 16:25, ~25 min
#                                        after that boot, by hand, no DNS keys
#     nmcli -f NAME,FILENAME connection show
#                                        lists ONLY that hand-made profile
#                                        — never the declarative one
#
#   So every reboot silently cost a hand-made wifi profile, and each one came
#   back without the DNS routing this module exists to set.  `resolvectl status
#   wlp1s0` showed a DNS server and no DNS Domain; the global scope fell back to
#   1.1.1.1, and `*.goclan.org` names resolved only by luck of link ordering.
#
#   ── WHY NOTHING CAUGHT IT ─────────────────────────────────────────────────
#
#   Nothing fails.  NetworkManager-ensure-profiles.service runs envsubst, calls
#   `nmcli connection reload`, and EXITS 0 — reload does not report per-file
#   rejections.  NM logs the rejection below its default level.  The deploy is
#   green, the unit is green, and the user has wifi (the one they made by hand),
#   so the only symptom is a DNS routing domain that is quietly absent.
#
#   Same shape as M6's discovery that the zfs-ntfy zedlet had never worked on
#   ernst: an output nobody validated, a caller that discards the error, and a
#   green deploy on top.
#
#   ── THE CLEANUP THAT IS NOT IN THIS FILE ──────────────────────────────────
#
#   Fixing the module makes the declarative profile valid, but it does NOT
#   remove a hand-made profile already sitting in /etc for the same SSID — that
#   one is persistent-until-reboot and will keep autoconnecting. Delete it once,
#   on any machine that has one:
#
#     sudo rm /etc/NetworkManager/system-connections/<ssid>.nmconnection
#     sudo nmcli connection reload
#
#   Deliberately not automated: a module that deletes NM profiles is a module
#   that can take a laptop off the network from a typo, and the correct
#   long-term state (no hand-made profile, because the declarative one works)
#   is reached by a reboot anyway.
#
#   ── HOW TO NOT REPEAT IT ──────────────────────────────────────────────────
#
#   `nmcli --offline connection modify … < keyfile` parses a keyfile with no
#   daemon, no root and no side effects. It is the check that would have caught
#   this at the time, and it is worth running against any future change to an
#   `ensureProfiles` profile before deploying it.
#   ── THE SECOND BUG: IPv4 WAS ONLY HALF THE LINK ───────────────────────────
#
#   Everything above concerns `[ipv4]`, and for a year that looked sufficient
#   because Technitium is reached at 10.0.5.3. It is not sufficient, because
#   the UDM-Pro also advertises ITSELF as a DNS server over IPv6 RA — and
#   systemd-resolved will happily prefer that one.
#
#   Measured on miralda, 2026-08-26, with the declarative profile active and
#   the hand-made one deleted:
#
#     resolvectl status wlp1s0
#       Current DNS Server: fd93:8550:36e6:2:2e91:abff:fe73:3f35   ← IPv6
#              DNS Servers: 10.0.5.3                               ← Technitium
#                           fd93:8550:36e6:2:2e91:abff:fe73:3f35
#                           2002:25c9:20fe:2:2e91:abff:fe73:3f35
#
#     dig @fd93:…:3f35 example.com              → 104.20.23.154   (works)
#     dig @fd93:…:3f35 jellyseerr.goclan.org    → NOTHING
#     dig @fd93:…:3f35 ernst.skynet.lan         → NOTHING
#     dig @10.0.5.3    jellyseerr.goclan.org    → 10.0.90.12
#     dig @10.0.5.3    ernst.skynet.lan         → 10.0.50.10
#
#   So the IPv6 server is a working recursive resolver that knows NEITHER
#   split-horizon zone — it is the gateway, not Technitium. Every internal
#   name fails while public browsing looks perfectly healthy, which is why
#   this presents as "the *arr are down" rather than as a DNS fault.
#
#   `ipv4.dns-priority = -100` cannot help: priority orders servers WITHIN a
#   family, and the RA-supplied IPv6 servers arrive on the same link through a
#   channel `[ipv4]` does not govern at all.
#
#   THE FIX HERE IS `ipv6.ignore-auto-dns`. It tells NetworkManager not to
#   accept router-advertised resolvers on this profile, which leaves 10.0.5.3
#   as the only nameserver on the link. The routing domain and priority are
#   mirrored into `[ipv6]` as well, so the two families cannot disagree about
#   which link owns "~.".
#
#   ── WHAT THIS DOES *NOT* FIX, AND WHO OWNS THAT ───────────────────────────
#
#   PHONES, TABLETS, TVs AND EVERY OTHER CLIENT. This module only reaches
#   machines in this flake. The same measurement was reproduced from a Fairphone
#   5 on the same LAN, and no NixOS module can help it: it takes the UDM-Pro's
#   advertised IPv6 resolver and loses every internal name too.
#
#   The real fix is on the UDM-Pro — either stop advertising an IPv6 DNS
#   server on the client networks, or point it at Technitium — and it is
#   lgo's, not this file's. This module is defence in depth for the machines it
#   can reach, not the cure.
{ lib, config, ... }:
{
  config = lib.mkIf config.networking.networkmanager.enable {
    networking.networkmanager.ensureProfiles.profiles.home = {
      ipv4 = {
        # NOT optional, and not a default. See THE BUG above: an [ipv4] section
        # without `method` makes NM reject the entire connection, and the only
        # visible symptom is a machine with no declarative wifi profile.
        method       = "auto";
        dns-search   = "~. skynet.lan";
        dns-priority = -100;
      };

      # See THE SECOND BUG above. `method` is required here for the same
      # all-or-nothing reason it is required in [ipv4]: a section without it is
      # rejected, and the rejection is silent.
      #
      # "auto" keeps SLAAC addressing — this turns off only the DNS half.
      ipv6 = {
        method          = "auto";
        ignore-auto-dns = true;
        dns-search      = "~. skynet.lan";
        dns-priority    = -100;
      };
    };
  };
}
