# @clanarchy/haos — Home Assistant OS as a KVM guest.
#
# One role, `host`.  Every property that differs between machines — cpus,
# memory, the disk, the NICs and which wire each sits on, the USB devices
# handed to the guest, whether a metrics token is wanted — is a per-machine
# SETTING in clan.nix's inventory, not a constant in this module.  ernst is
# the first host; nothing here names it.
#
# What this service owns and what it does not is the whole design, and it is
# written out in ./haos.md.  In one line: the repo owns the VM's SHELL, Home
# Assistant OS owns everything inside it.
{lib, ...}: {
  _class = "clan.service";
  manifest.name = "@clanarchy/haos";
  manifest.description = "Home Assistant OS (Supervisor, add-ons) in a declaratively-shelled KVM guest.";
  manifest.readme = builtins.readFile ./haos.md;

  roles.host = import ./haos/host.nix {inherit lib;};
}
