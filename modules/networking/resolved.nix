# Fleet-wide systemd-resolved defaults.
#
# Primary DNS is intentionally per-link, not global:
#   - NM machines pick up 10.0.5.3 (Technitium) via DHCP on the home LAN,
#     with routing hints attached in ./skynet-dns-nm.nix so it wins as the
#     catch-all resolver.
#   - ernst pins DNS on its enp13s0 networkd unit directly.
# Setting `services.resolved.settings.Resolve.DNS` here would break miralda
# off-LAN (10.0.5.3 unreachable), so we leave Global DNS empty and only
# configure the FallbackDNS safety net below.
#
# FallbackDNS kicks in ONLY when no link-specific DNS is available at all
# (rare — briefly during boot before DHCP, or on a broken profile).
{ ... }:
{
  services.resolved.settings.Resolve.FallbackDNS = "1.1.1.1 9.9.9.9";
}
