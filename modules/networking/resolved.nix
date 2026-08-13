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
#
# DNSSEC: intentionally left at systemd-resolved's default (off).  The Arch
# wiki (systemd-resolved §DNSSEC) documents three modes but recommends
# nothing — it explicitly notes that DNSSEC in systemd-resolved is
# "experimental and incomplete" and that `allow-downgrade` has known bugs
# (systemd issues 21107, 36681) that may force falling back to `false`
# anyway.  For this fleet specifically:
#
#   - `true` (strict) would SERVFAIL on our unsigned internal zone
#     (skynet.lan via Technitium) and on most captive/hotel resolvers.
#   - `allow-downgrade` is downgrade-attackable by definition; against a
#     home LAN whose upstream we already trust, the marginal integrity
#     gain over `false` is thin, and it adds a persistent debug surface.
#
# Revisit if (a) systemd-resolved's DNSSEC support drops the "experimental"
# label upstream, (b) Technitium's DNSSEC posture is confirmed end-to-end,
# or (c) we want a per-machine pilot on ernst (fixed home LAN, easiest to
# reason about).
{ ... }:
{
  services.resolved.settings.Resolve.FallbackDNS = "1.1.1.1 9.9.9.9";
}
