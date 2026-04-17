# Impermanence

!!! note "Stub"
    This guide is a placeholder. Content will be added.

## Overview

Root (`/`) and home (`/home`) roll back to `@blank` ZFS snapshots on every boot. Only explicitly listed paths survive.

## Persisted paths

See [`machines/miralda/impermanence.nix`](https://github.com/lutzgo/clanarchy/blob/main/machines/miralda/impermanence.nix) for the full list.

Key system paths:

- `/var/lib/sops-nix` — age identity decrypted by sops-nix at activation
- `/var/lib/systemd` — systemd state (random seed, machine-id, …)
- `/var/lib/zerotier-one` — ZeroTier node identity
- `/persist/` — machine-specific persistent data (NM profiles, chromium first-run hash, …)

Key user paths (under `/home/lgo`):

- `.gnupg` — GPG keyring and trust database
- `.config` — application configuration
- `.local/share` — application data

## Adding a new persisted path

1. Add to `environment.persistence."/persist".directories` (system) or `home.persistence."/persist/lgo".directories` (user) in `impermanence.nix`.
2. Deploy: `deploy`.
3. The path will survive the next rollback.
