# service-modules/haos/registry.nix
#
# A read-mostly registry each HAOS instance writes its host-global names into,
# so machine-level assertions can see them next to the containers'.
#
# WHY IT EXISTS.  machines/ernst/networking.nix asserts that no two things on
# the host claim the same interface name, that every MAC matches its
# allocations.nix row, and that every loopback bridge (service-modules/
# local-ai/bridges.nix) listens on an address some leg actually carries.  It
# used to read all three from `config.containers` alone — which is exactly
# what Home Assistant stopped being.  Without this, moving `ai3` from a veth
# to a tap would fail the bridge assertion, and a tap colliding with a
# container veth would pass every check and fail at runtime.
#
# Imported BY PATH from ./host.nix, so the module system deduplicates it: two
# instances on one machine declare the option once.
{lib, ...}: {
  options.clanarchy.haos.instances = lib.mkOption {
    internal = true;
    default = {};
    description = "Per-instance facts published for host-wide assertions. Written by @clanarchy/haos, not by hand.";
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        taps = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = "Every tap name the instance creates.";
        };
        hostAddresses6 = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          description = "Host ends of the instance's point-to-point legs.";
        };
        macs = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          description = "Guest MAC per VLAN (as a string, e.g. \"90\"), for bridged NICs only.";
        };
        hugepages = lib.mkOption {
          type = lib.types.bool;
          description = "Whether the instance reserves hugepages; at most one per machine may.";
        };
      };
    });
  };
}
