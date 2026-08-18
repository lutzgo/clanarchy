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

  roles.htpc = {
    description = "Couch machine: Steam Big Picture session + KDE Plasma, switchable at runtime. Stable channel, no Jovian.";
    interface.options = {
      user = lib.mkOption {
        type = lib.types.str;
        description = "The couch user (owns session state, may restart the display manager).";
        example = "htpc";
      };
      defaultSession = lib.mkOption {
        type = lib.types.enum [ "gamescope" "plasma" "bigscreen" ];
        default = "gamescope";
        description = "Session to land in before any choice has been made.";
      };
      autologin.enable =
        lib.mkEnableOption "passwordless autologin for the couch user (see modules/roles/htpc.nix for the tradeoff)";

      bigscreen = {
        enable =
          lib.mkEnableOption "Plasma Bigscreen mode in an nspawn container (see modules/desktop/bigscreen.nix)";

        gpu.pciAddress = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "PCI address of the GPU driving the TV, e.g. \"0000:03:00.0\". Required when bigscreen.enable is set.";
        };

        uid = lib.mkOption {
          type = lib.types.int;
          default = 0;
          description = "Numeric uid of the couch user; must match the host. Required when bigscreen.enable is set.";
        };

        gid = lib.mkOption {
          type = lib.types.int;
          default = 100;
          description = "Numeric primary gid of the couch user; must match the host.";
        };
      };
    };

    perInstance =
      { settings, ... }:
      {
        nixosModule =
          { ... }:
          {
            imports = [ ../modules/roles/htpc.nix ];
            clanarchy.roles.htpc = {
              enable = true;
              inherit (settings) user defaultSession;
              autologin.enable = settings.autologin.enable;
              bigscreen = {
                inherit (settings.bigscreen) enable gid;
              }
              // lib.optionalAttrs settings.bigscreen.enable {
                inherit (settings.bigscreen) uid;
                gpu.pciAddress = settings.bigscreen.gpu.pciAddress;
              };
            };
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
