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
{ lib, config, ... }:
{
  config = lib.mkIf config.networking.networkmanager.enable {
    networking.networkmanager.ensureProfiles.profiles.home.ipv4 = {
      dns-search   = "~. skynet.lan";
      dns-priority = -100;
    };
  };
}
