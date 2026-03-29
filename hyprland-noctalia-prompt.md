# Implementation Prompt: Hyprland + Noctalia + UWSM + greetd for `miralda`

## Context

This is a **clan-based NixOS config** using `flake-parts`. The existing structure is:

```
flake.nix                          # flake-parts + clan-core (nixpkgs follows 25.11)
clan.nix                           # clan inventory
machines/miralda/
  configuration.nix                # base system config (ZFS, impermanence, SSH, boot)
  disko.nix                        # ZFS disk layout
  impermanence.nix                 # /persist persistence rules
  stylix.nix                       # Stylix theming (base16 + wallpaper)
  users/admin.nix                  # user definition
  secrets/admin.nix                # clan secrets
```

The machine `miralda` is a **Framework laptop (12" or 13")** running NixOS.

Already present in `flake.nix` inputs:
- `clan-core` (nixpkgs follows 25.11 stable)
- `home-manager`
- `stylix`
- `impermanence`

Already imported in `clan.machines.miralda`:
- `inputs.impermanence.nixosModules.impermanence`
- `inputs.stylix.nixosModules.stylix`
- `inputs.home-manager.nixosModules.home-manager`
- `./machines/miralda/configuration.nix`
- `./machines/miralda/disko.nix`
- `./machines/miralda/impermanence.nix`
- `./machines/miralda/stylix.nix`
- `./machines/miralda/users/admin.nix`
- `./machines/miralda/secrets/admin.nix`

---

## Goal

Implement a **Hyprland + Noctalia (Quickshell) desktop** for `miralda` (Framework 13 AMD) with:

1. **Hyprland** launched via **UWSM** (systemd-managed session)
2. **greetd + tuigreet** as the display manager/greeter
3. **Noctalia** as the Quickshell UX shell, integrated with **Stylix**
4. Clean modular file layout following the existing `machines/miralda/` convention

---

## Step 1 — Update `flake.nix` inputs

### Critical nixpkgs note
Noctalia and Quickshell **require nixpkgs-unstable**. The existing `nixpkgs` follows `clan-core/nixpkgs` (stable 25.11). You **must** add a separate `nixpkgs-unstable` input. Noctalia and its overlay must use this unstable input. Do NOT change `nixpkgs` itself — that would break clan-core.

### Add these inputs to `flake.nix`:

```nix
nixpkgs-unstable = {
  url = "github:NixOS/nixpkgs/nixos-unstable";
  # intentionally NOT following clan-core/nixpkgs
};

noctalia = {
  url = "github:noctalia-dev/noctalia-shell";
  inputs.nixpkgs.follows = "nixpkgs-unstable";
};

quickshell = {
  url = "git+https://git.outfoxxed.me/quickshell/quickshell";
  inputs.nixpkgs.follows = "nixpkgs-unstable";
};

```

### Add the new modules to `clan.machines.miralda` imports in `flake.nix`:

```nix
./machines/miralda/desktop.nix         # new: Hyprland + greetd + UWSM
./machines/miralda/noctalia.nix        # new: Noctalia shell config
```

**Important**: pass `pkgs-unstable` through to the modules that need it. Before writing any code, **read `clan-core`'s `flakeModules.default` output to check whether `clan.machines.<name>` accepts a `specialArgs` key**. Based on what you find, use exactly one of these two approaches and do not mix them:

**Option A — if `clan.machines` supports `specialArgs`:**
```nix
clan.machines.miralda = {
  specialArgs = {
    pkgs-unstable = import inputs.nixpkgs-unstable { system = "x86_64-linux"; };
  };
  imports = [ ... ]; # as before, plus new modules
};
```

**Option B — if `specialArgs` is not available (preferred fallback):** add an inline module as the *first* entry in the imports list that sets `_module.args`. This is always safe regardless of how clan-core is structured:
```nix
clan.machines.miralda = {
  imports = [
    { _module.args.pkgs-unstable = import inputs.nixpkgs-unstable {
        system = "x86_64-linux";
        config.allowUnfree = true;
      };
    }
    # ... rest of imports as before, plus new modules
  ];
};
```

Do not attempt both approaches simultaneously — they will conflict.

---

## Step 2 — Create `machines/miralda/desktop.nix`

This file handles: Hyprland, UWSM, greetd/tuigreet, and related system-level settings.

```nix
{ pkgs, ... }:
{
  # Hyprland with UWSM integration (NixOS 24.11+)
  programs.hyprland = {
    enable = true;
    withUWSM = true;   # generates hyprland-uwsm.desktop for greetd
    xwayland.enable = true;
  };

  # greetd with tuigreet — works flawlessly with Hyprland per upstream docs
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --cmd 'uwsm start hyprland-uwsm.desktop'";
        user = "greeter";
      };
    };
  };

  # Required for UWSM — uses dbus-broker by default
  programs.uwsm = {
    enable = true;
    waylandCompositors.hyprland = {
      prettyName = "Hyprland";
      comment = "Hyprland managed by UWSM";
      binPath = "/run/current-system/sw/bin/Hyprland";
    };
  };

  # Wayland / Portal support
  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-hyprland ];
    config.common.default = "*";
  };

  # Power management — use power-profiles-daemon (NOT TLP — they conflict on Framework AMD)
  services.power-profiles-daemon.enable = true;

  # Framework-specific hardware support
  services.fprintd.enable = true;        # fingerprint reader
  services.fwupd.enable = true;          # firmware updates via LVFS

  # udev rule: prevent backpack-wake (screen flex triggers lid sensor on bag pressure)
  # nixfacter generates the hardware config, but this quirk needs an explicit rule
  services.udev.extraRules = ''
    SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="LID*", ATTRS{phys}=="PNP0C0D*", TAG-="power-switch"
  '';

  # HiDPI cursor
  environment.variables = {
    XCURSOR_SIZE = "24";
    XCURSOR_THEME = "Adwaita";
    NIXOS_OZONE_WL = "1";     # Chromium/Electron Wayland flag
  };

  # Pipewire for audio
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # NetworkManager
  networking.networkmanager.enable = true;

  # UPower — required by Noctalia for battery display
  services.upower.enable = true;

  # Fonts for the shell UI
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    noto-fonts
    noto-fonts-emoji
  ];
  fonts.fontconfig.defaultFonts = {
    monospace = [ "JetBrainsMono Nerd Font" ];
    sansSerif = [ "Noto Sans" ];
  };
}
```

---

## Step 3 — Create `machines/miralda/noctalia.nix`

This file handles only what must be at the NixOS system level. The `noctalia-shell` package itself belongs in the shared HM module (Step 4) since only graphical users need it — not the system.

```nix
{ ... }:
{
  # PAM entry required by Noctalia's lockscreen (PamContext in QML)
  # Must be system-level — cannot be set from Home Manager
  security.pam.services.noctalia = {};
}
```

---

## Step 4 — Create `machines/miralda/home-modules/desktop.nix`

Since you plan to have multiple graphical users, extract all desktop-related Home Manager config into a **shared module** that each user imports. This avoids duplication and ensures all graphical users get the same consistent environment.

Create the directory `machines/miralda/home-modules/` and add `desktop.nix`:

```nix
# machines/miralda/home-modules/desktop.nix
# Shared Home Manager module for any graphical user on miralda.
# Import this in each user's HM config that should have the desktop environment.
{ pkgs, inputs, ... }:
{
  imports = [
    inputs.noctalia.homeModules.default  # Noctalia HM module from the flake
  ];

  # Hyprland HM module — declarative config
  wayland.windowManager.hyprland = {
    enable = true;
    systemd.enable = false;   # CRITICAL: must be false when using UWSM

    settings = {
      monitor = [
        # Framework 13 AMD — 2256x1504 panel at 1.5 scale
        "eDP-1,2256x1504@60,0x0,1.5"
      ];

      "$mod" = "SUPER";

      exec-once = [
        "uwsm app -- noctalia-shell"   # launch the shell as a systemd unit
      ];

      bind = [
        "$mod, Return, exec, uwsm app -- ghostty"
        "$mod, Q, killactive"
        "$mod, Space, exec, uwsm app -- rofi -show drun"
        "$mod SHIFT, E, exec, uwsm stop"
      ];

      general = {
        gaps_in = 4;
        gaps_out = 8;
        border_size = 2;
      };

      decoration.rounding = 8;

      input = {
        touchpad = {
          natural_scroll = true;
          disable_while_typing = true;
        };
        follow_mouse = 1;
      };
    };
  };

  # Noctalia shell — configured declaratively
  # See: https://docs.noctalia.dev/getting-started/nixos/
  programs.noctalia-shell.enable = true;

  # Stylix Noctalia target — applies base16 colors + fonts to Noctalia
  stylix.targets.noctalia-shell.enable = true;

  # Common graphical packages available to all desktop users
  home.packages = with pkgs; [
    pkgs-unstable.noctalia-shell  # from unstable — quickshell dependency pulled automatically
    ghostty         # terminal
    rofi-wayland    # launcher
    grim slurp      # screenshot tools
    wl-clipboard
    playerctl       # media key support
  ];
}
```

## Step 4b — Update `machines/miralda/users/admin.nix`

Since all HM users on `miralda` get the graphical environment, wire the shared module in once at the system level using `home-manager.sharedModules` rather than repeating an import in every user file. This means new users get the desktop automatically with no risk of forgetting the import.

Add this to `desktop.nix` (or any NixOS module that runs after home-manager is imported):

```nix
home-manager.sharedModules = [ ./home-modules/desktop.nix ];
```

With this in place, `users/admin.nix` stays minimal — only user-specific additions belong there:

```nix
{ pkgs, ... }:
{
  home-manager.users.admin = { ... }: {
    home.stateVersion = "25.11";
    # Admin-specific additions only (dev tools, ssh keys, etc.)
  };
}
```

When you add a second user (e.g. `users/alice.nix`), the same applies — no desktop import needed:

```nix
{ pkgs, ... }:
{
  home-manager.users.alice = { ... }: {
    home.stateVersion = "25.11";
    # Alice-specific additions only
  };
}
```

**Note on `inputs` and `pkgs-unstable` availability in HM modules**: For `inputs.noctalia.homeModules.default` and `pkgs-unstable.noctalia-shell` to be accessible inside `home-modules/desktop.nix`, both must be passed via `extraSpecialArgs`:

```nix
home-manager.extraSpecialArgs = {
  inherit inputs;
  inherit pkgs-unstable;  # or however pkgs-unstable is named in your module args
};
```

Check how clan-core surfaces `extraSpecialArgs` for home-manager — it may be via `_module.args` instead. If `inputs` is already available in your existing user modules, verify `pkgs-unstable` is also reachable before assuming it works.

---

## Step 5 — Update `machines/miralda/stylix.nix`

Add HiDPI-appropriate font sizes and ensure the cursor theme is set. Your existing `stylix.nix` probably already sets wallpaper and base16 scheme — just extend it:

```nix
{
  # existing wallpaper / scheme config ...

  stylix.fonts.sizes = {
    applications = 11;
    terminal = 13;
    desktop = 11;
    popups = 11;
  };

  stylix.cursor = {
    package = pkgs.adwaita-icon-theme;
    name = "Adwaita";
    size = 24;
  };
}
```

---

## Step 6 — Review `machines/miralda/impermanence.nix`

The existing impermanence config already persists `.config` and `.local/share` wholesale for `users.admin`. This covers all of Noctalia's and Hyprland's state paths — no changes are needed for admin.

The only path **not** covered is `~/Pictures/Wallpapers`, which Noctalia uses for its wallpaper switcher. If you want wallpapers to persist across reboots, add it:

```nix
users.admin = {
  directories = [
    ".ssh"
    ".gnupg"
    ".config"
    ".local/share"
    "Pictures/Wallpapers"   # add this if using Noctalia's wallpaper manager
  ];
};
```

When adding a new graphical user, give them the same `directories` block — `.config` and `.local/share` are the minimum required for Noctalia and Hyprland state to survive rollback.

---

## Validation checklist

After implementing, verify:

- [ ] `nix flake check` passes (no eval errors)
- [ ] `nixpkgs-unstable` input is present and NOT following clan-core's nixpkgs
- [ ] `pkgs-unstable` is threaded through to `noctalia.nix` and the HM module
- [ ] `wayland.windowManager.hyprland.systemd.enable = false` in HM config
- [ ] All Hyprland `exec-once` entries are prefixed with `uwsm app --`
- [ ] `security.pam.services.noctalia = {}` is set for the lockscreen
- [ ] `services.upower.enable = true` (Noctalia battery widget depends on it)
- [ ] greetd `tuigreet` command references `hyprland-uwsm.desktop`
- [ ] `stylix.targets.noctalia-shell.enable = true` is in the HM config (not NixOS config)

---

## References

- Noctalia NixOS docs: https://docs.noctalia.dev/getting-started/nixos/
- Noctalia Stylix module: https://nix-community.github.io/stylix/options/modules/noctalia-shell.html
- NixOS UWSM wiki: https://wiki.nixos.org/wiki/UWSM
- NixOS Hyprland wiki: https://wiki.nixos.org/wiki/Hyprland
- Hyprland UWSM wiki: https://wiki.hypr.land/Useful-Utilities/Systemd-start/
