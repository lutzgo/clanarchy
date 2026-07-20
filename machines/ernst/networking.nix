# ernst — static wired networking (systemd-networkd).
#
# Physical NICs on this AM5 / X870E board:
#   - enp13s0   Marvell AQtion AQC113CS 10G  (atlantic driver) — SFP+ to switch,
#               statically configured below.
#   - enp12s0   Intel I226-V 2.5G            (igc driver)      — intentionally
#               unplugged.  Never allowed to block wait-online (see below).
#
# The clan-wide `99-ethernet-default-dhcp` wildcard (from nixpkgs when
# networking.useNetworkd = true) still matches other ether NICs — USB
# tethering, PCIe passthrough guests handed a NIC, etc.  Our 50-* file
# sorts before it, so networkd picks our rule for enp13s0.
#
# DNS routing mirrors modules/networking/skynet-dns-nm.nix for the NM
# machines:
#   Domains = "~. skynet.lan"
#     ~.          — routing catch-all: every DNS query goes to 10.0.5.3
#                   (Technitium), so its blocklists / logging apply to
#                   every lookup ernst does.
#     skynet.lan  — search suffix for bare hostnames.
{ ... }:
{
  systemd.network.networks."50-enp13s0" = {
    matchConfig.Name = "enp13s0";
    networkConfig = {
      Address      = "10.0.50.10/24";
      Gateway      = "10.0.50.1";
      DNS          = "10.0.5.3";
      Domains      = "~. skynet.lan";
      MulticastDNS = true;
    };
    linkConfig.RequiredForOnline = "yes";
  };

  # systemd-networkd-wait-online.service is disabled fleet-wide by clan-core
  # defaults (verified: `nix eval .#nixosConfigurations.ernst.config.systemd
  # .network.wait-online.enable` → false), so the unplugged Intel 2.5G NIC
  # (enp12s0, igc) cannot block boot.  If wait-online is ever re-enabled,
  # add: `systemd.network.wait-online = { anyInterface = true;
  # ignoredInterfaces = [ "enp12s0" ]; };`
}
