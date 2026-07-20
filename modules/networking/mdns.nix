# Avahi / mDNS — zero-conf hostname resolution for all clan machines.
#
# Each machine advertises itself as <hostname>.local and resolves other
# machines the same way.  The reflector bridges mDNS multicast between
# every network interface Avahi sees — including ZeroTier (zt…) — so
# <hostname>.local works across routed networks as well as on a local LAN.
{ ... }:
{
  services.avahi = {
    enable      = true;
    nssmdns4    = true;   # enable NSS module so glibc resolves *.local names
    openFirewall = true;  # open UDP 5353 for mDNS multicast
    reflector   = true;   # bridge mDNS between interfaces (LAN ↔ ZeroTier)
    publish = {
      enable    = true;
      addresses = true;   # advertise all interface addresses under <hostname>.local
    };
  };
}
