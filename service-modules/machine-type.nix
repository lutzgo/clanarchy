{ lib, ... }:
#
# @clanarchy/machine-type — assign each machine to a hardware/role archetype.
#
# Replaces the previous pattern of importing all modules/roles/*.nix into every
# machine in flake.nix and toggling them with clanarchy.roles.*.enable options.
# Now the inventory declares which machines belong to which role and the service
# applies only the relevant module.
#
# Roles:
#   laptop  — GPU drivers, power management, lid-switch, optional Framework hw
#   server  — SSH hardening, nix GC, store optimisation
#   vm      — QEMU/KVM guest tools on top of the server baseline
#   rpi     — Raspberry Pi redistributable firmware
#
{
  _class = "clan.service";
  manifest.name = "@clanarchy/machine-type";
  manifest.description = "Assign each machine to a hardware/role archetype (laptop, server, vm, rpi).";
  manifest.readme = builtins.readFile ./machine-type.md;

  roles.laptop = {
    description = "GPU drivers, power management, lid-switch handling, optional Framework hardware.";
    interface.options.framework.enable =
      lib.mkEnableOption "Framework laptop hardware (fprintd, fwupd, backpack-wake udev rule)";

    perInstance =
      { settings, ... }:
      {
        nixosModule =
          { ... }:
          {
            imports = [ ../modules/roles/laptop.nix ];
            clanarchy.roles.laptop.enable = true;
            clanarchy.roles.laptop.framework.enable = settings.framework.enable;
          };
      };
  };

  roles.server = {
    description = "Headless server: SSH hardening, nix store optimisation, weekly GC.";
    perInstance =
      { ... }:
      {
        nixosModule =
          { ... }:
          {
            imports = [ ../modules/roles/server.nix ];
            clanarchy.roles.server.enable = true;
          };
      };
  };

  roles.vm = {
    description = "QEMU/KVM guest: server baseline + SPICE/qemu-guest tools.";
    perInstance =
      { ... }:
      {
        nixosModule =
          { ... }:
          {
            imports = [ ../modules/roles/vm.nix ];
            clanarchy.roles.vm.enable = true;
          };
      };
  };

  roles.rpi = {
    description = "Raspberry Pi: non-free redistributable firmware. Boot loader must be configured per machine.";
    perInstance =
      { ... }:
      {
        nixosModule =
          { ... }:
          {
            imports = [ ../modules/roles/rpi.nix ];
            clanarchy.roles.rpi.enable = true;
          };
      };
  };
}
