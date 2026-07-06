# Testing a pull request in a VM

Two commands. Boot the branch in QEMU. Merge or reject.

## Testing a PR someone opened

```bash
nix develop
test-pr <PR#>            # defaults to biene
test-pr <PR#> miralda    # or miralda / ernst
```

`test-pr` runs `gh pr checkout <PR#>`, builds the machine's VM, and launches it. Close the QEMU window when done.

## Testing the branch you already have checked out

```bash
nix develop
test-vm             # defaults to biene
test-vm miralda     # or miralda / ernst
```

## Which machine?

- **biene** — default. Fastest, labwc + regreet render in the VM.
- **miralda** — Niri desktop; YubiKey flows can't be tested (autologin bypasses them).
- **ernst** — headless server; you'll get a login prompt, no GUI.

## What the VM catches

Evaluation errors, module conflicts, boot-time systemd failures, compositor bring-up, missing packages.

## What it doesn't catch

Anything hardware-specific: ZFS rollback, YubiKey/SOPS, Framework fprintd, Fritz!Box wifi. For those you still need `deploy … boot` on real hardware — see [accepting-pull-requests.md](accepting-pull-requests.md).

## When something breaks

- **`gh pr checkout` refuses:** you have uncommitted changes. Stash or commit them first.
- **QEMU won't start:** you need to be in the `kvm` group (already the case on both clanarchy machines).
- **VM disk fills up:** delete `./biene.qcow2` (or `miralda.qcow2` / `ernst.qcow2`) next to the `result` symlink.

## How it works (one paragraph)

`modules/vm-variant.nix` provides a `virtualisation.vmVariant` block that disables disko, ZFS, and impermanence, and enables root autologin. It only applies to `config.system.build.vm` — the real `deploy` path is untouched.
