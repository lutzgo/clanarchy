# Testing a pull request in a VM

Before merging a PR — especially one that touches `machines/*`, `modules/desktop/*`, or anything that could break a boot — you can boot the PR's config in QEMU without touching any real disk. This is what the `test-pr` / `test-vm` devShell functions and `modules/vm-variant.nix` are for.

## Quick reference

| Command | What it does |
|---------|--------------|
| `test-pr <n> [machine]` | Check out PR `<n>` and boot it in QEMU (default machine: `biene`) |
| `test-vm [machine]` | Boot the currently-checked-out branch in QEMU |

Both functions run inside the devShell (`nix develop` or direnv).

## How it works

`test-pr <n>` runs three steps:

1. `gh pr checkout <n>` — fetches the PR branch and switches your working tree to it.
2. `nixos-rebuild build-vm --flake .#<machine>` — builds `./result/bin/run-<host>-vm`, applying the machine's `virtualisation.vmVariant` overrides.
3. `exec ./result/bin/run-<machine>-vm` — launches QEMU.

The `virtualisation.vmVariant` block lives in [`modules/vm-variant.nix`](../../modules/vm-variant.nix) and is imported by every machine in `flake.nix`. It neutralises the parts of the config that only make sense on bare metal:

- **disko**: `disko.enableConfig = mkForce false` — the VM gets a plain ext4 rootfs on `/dev/vda` provided by the qemu-vm NixOS module, not the disko-declared partition layout.
- **ZFS**: `boot.supportedFilesystems = mkForce [ "ext4" "vfat" ]` and the blank-rollback stage 1 unit is disabled — no `zroot` pool exists inside the VM.
- **impermanence**: `environment.persistence = mkForce {}` — nothing to bind-mount without `/persist`.
- **login**: root autologin with an empty password, so you land on a shell (or the compositor's greeter) without hunting for a password.

None of this affects `deploy` / `deploy-biene` / `deploy-ernst`. `virtualisation.vmVariant` only applies to `config.system.build.vm`.

## Choosing a machine

- **`biene`** is the natural default. No YubiKey, labwc + regreet renders in the VM, easy to see if a change breaks Sabine's desktop.
- **`miralda`** works too but YubiKey PIV / GnuPG smartcard flows are untestable in QEMU by design.
- **`ernst`** is a headless server; a VM boot shows you the base system + services but there's no GUI to interact with.

## What VM testing catches

- Evaluation errors, missing options, module conflicts.
- Boot-time systemd failures (units that fail to start).
- Desktop compositor bring-up (Niri, labwc) and greeter (regreet, greetd) sanity.
- Package availability across the closure.

## What it does not catch

- ZFS rollback semantics — the VM uses ext4.
- YubiKey / PIV / SOPS decryption paths that need real hardware.
- Framework laptop firmware/fprintd, Fritz!Box wifi, hardware-specific quirks.
- Any bug that only shows up under real user data on `/persist`.

For those you still need a real `deploy … boot` on the target machine as described in [accepting-pull-requests.md](accepting-pull-requests.md).

## Common gotchas

- If `gh pr checkout` refuses because of unstaged changes, stash or commit them first — `test-pr` will abort without touching the VM step.
- The VM disk image lives at `./<host>.qcow2` next to the `result` symlink and persists across runs. Delete it if you want a truly fresh boot (or if the disk fills up).
- QEMU needs KVM permission — the user running the devShell must be in the `kvm` group (already the case on both clanarchy machines).
