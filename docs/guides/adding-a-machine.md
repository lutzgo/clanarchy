# Adding a new machine

This guide walks through adding a new machine to clanarchy — from declaring it in the flake to the first boot on real hardware.

---

## Overview

The full flow is:

1. Create the machine directory and config files
2. Declare the machine in `flake.nix`
3. Generate secrets (`clan vars generate`)
4. Install onto hardware (`clan machines install`)
5. Add the SSH `HostKeyAlgorithms` workaround for YubiKey signing
6. Ongoing updates via `deploy-<name>` or `clan machines update`

---

## 1. Create the machine directory

```
machines/<name>/
├── configuration.nix   # hostname, timezone, role activation, SSH, boot
├── disko.nix           # disk layout (ZFS recommended)
├── impermanence.nix    # paths to persist across ZFS rollbacks
└── stylix.nix          # theme, wallpaper, fonts
```

Use an existing machine as a template:

```bash
cp -r machines/biene machines/<name>
# then edit each file
```

### `configuration.nix` checklist

```nix
{...}: {
  networking.hostName = "<name>";
  networking.hostId   = "<8 hex digits>";  # head -c4 /dev/urandom | xxd -p
  time.timeZone       = "Europe/Berlin";

  # Activate the right roles and desktop
  clanarchy.roles.laptop.enable   = true;   # or server / vm / rpi
  clanarchy.desktop.niri.enable   = true;   # or labwc / kde

  # Users
  clanarchy.users.admin.enable  = true;
  clanarchy.users.<user>.enable = true;

  # WiFi (if applicable)
  clanarchy.wifi.networks = [{ ssid = "skynet"; varName = "wifi-home"; }];

  nix.settings.experimental-features = ["nix-command" "flakes"];

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin        = "prohibit-password";
  };

  boot.loader.systemd-boot.enable      = true;
  boot.loader.efi.canTouchEfiVariables = true;

  system.stateVersion = "25.11";
}
```

Generate a fresh `hostId`:

```bash
head -c4 /dev/urandom | xxd -p
```

---

## 2. Declare the machine in `flake.nix`

Add a `clan.machines.<name>` block. Copy the biene block and adjust the imports:

```nix
clan.machines.<name> = {
  imports = [
    { _module.args = {
        pkgs-unstable = import inputs.nixpkgs-unstable {
          system = "x86_64-linux";
          config.allowUnfree = true;
        };
        inherit inputs;
      };
    }

    inputs.impermanence.nixosModules.impermanence
    inputs.stylix.nixosModules.stylix
    inputs.home-manager.nixosModules.home-manager

    # Reusable modules — import every module whose option you reference
    ./modules/desktop/labwc.nix     # or niri.nix / kde.nix
    ./modules/desktop/niri.nix      # always import so the option exists
    ./modules/roles/laptop.nix      # or server / vm / rpi
    ./modules/roles/server.nix
    ./modules/roles/vm.nix
    ./modules/roles/rpi.nix
    ./modules/users/admin.nix
    ./modules/users/<user>.nix
    ./modules/wifi.nix

    # Machine-specific
    ./machines/<name>/configuration.nix
    ./machines/<name>/disko.nix
    ./machines/<name>/impermanence.nix
    ./machines/<name>/stylix.nix
  ];
};
```

Also add a `deploy-<name>` function to the `shellHook` in `perSystem.devShells.default`:

```bash
deploy-<name>() {
  local action=${1:-switch}
  nixos-rebuild "$action" \
    --flake .#<name> \
    --target-host root@<name>.skynet.lan \
    --no-reexec \
    -j auto \
    "${@:2}"
}
export -f deploy-<name>
```

---

## 3. Generate secrets

Generate all vars for the new machine. The YubiKey must be inserted:

```bash
clan vars generate <name>
```

This will prompt for any secrets that have `prompts` defined (user passwords, etc.) and encrypt outputs to the configured age recipients.

If using the shared `wifi-home` var, generate it once (it's shared across machines):

```bash
clan vars generate --group shared
```

---

## 4. Hardware detection (facter.json)

For accurate hardware-specific NixOS configuration, boot the target into a NixOS live system and run clan's hardware detection:

```bash
# From the live system, or remotely once sshd is accessible:
clan machines show-hardware --target-host root@<ip> <name> > machines/<name>/facter.json
git add machines/<name>/facter.json
```

This sets CPU microcode, kernel modules, and other hardware-specific options automatically.

---

## 5. Install onto hardware

Boot the target machine from the [NixOS minimal installer ISO](https://nixos.org/download). Get its IP address, then from the clanarchy devShell:

```bash
clan machines install <name> --target-host root@<ip>
```

This runs **nixos-anywhere** under the hood:
- Formats disks according to `disko.nix`
- Copies the built closure
- Reboots into the new system

!!! warning "Destructive"
    `clan machines install` wipes and reformats the target's disks. Only run it for initial provisioning. For subsequent config changes use `deploy-<name>` or `clan machines update <name>`.

After reboot, the machine is fully provisioned. The `admin` and user accounts are active, SSH keys are in place.

---

## 6. Fix YubiKey SSH signing for the new host

gnupg 2.4.x fails to sign with card-backed ed25519 keys when OpenSSH negotiates `publickey-hostbound-v00@openssh.com`. Add a `matchBlocks` entry in `modules/users/lgo.nix` for the new host:

```nix
matchBlocks."<name>.skynet.lan <ip>" = {
  extraOptions.HostKeyAlgorithms = "ssh-ed25519";
};
```

Then rebuild miralda to activate it:

```bash
deploy
```

---

## 7. Ongoing updates

```bash
deploy-<name>               # fast: nixos-rebuild, skips clan health check
clan machines update <name> # full: re-evaluates vars/secrets
```

See the [Updating machines](updating-machines.md) guide for details on when to use each.

---

## Checklist

- [ ] `machines/<name>/` directory with all four required files
- [ ] `clan.machines.<name>` block in `flake.nix` with correct imports
- [ ] `deploy-<name>` function added to devShell `shellHook`
- [ ] `networking.hostId` is unique (8 hex chars, not copied from another machine)
- [ ] `clan vars generate <name>` completed with YubiKey inserted
- [ ] `facter.json` generated from live hardware
- [ ] `clan machines install <name>` run once on blank hardware
- [ ] `HostKeyAlgorithms` matchBlock added to `modules/users/lgo.nix` and miralda rebuilt
- [ ] Machine added to the machines table in `docs/index.md`
