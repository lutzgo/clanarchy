# Runbook — opt existing machines into ZFS auto-snapshots

**Status: outstanding.** Applies to every machine installed before [#38](https://github.com/lutzgo/clanarchy/pull/38) landed — currently **miralda, biene, ernst**. Takes about a minute per machine and needs no reboot.

## Why this is needed

clan-core enables auto-snapshotting for the whole fleet — `nixosModules/clanCore/zfs.nix`, vendored from [srvos](https://github.com/nix-community/srvos):

```nix
services.zfs = lib.mkIf (config.boot.zfs.enabled) {
  autoSnapshot.enable  = true;
  autoSnapshot.monthly = lib.mkDefault 1;
  autoScrub.enable     = true;
};
```

But `zfs-auto-snapshot` only touches datasets carrying the **`com.sun:auto-snapshot`** property. From the nixpkgs option description:

> Note that you must set the `com.sun:auto-snapshot` property to `true` on the datasets you wish to auto-snapshot.

disko has never set that property, so all five timers — `frequent`, `hourly`, `daily`, `weekly`, `monthly` — have been running on schedule against **zero opted-in datasets**. Enabled, firing, snapshotting nothing.

#38 added the property to the disko templates, but **disko applies dataset properties at creation time only**. It does not reconcile a running pool. So new installs are covered and existing machines are not, until the commands below are run once.

## What to run

Per machine, as root:

```bash
# All machines — the two datasets that aren't disposable
zfs set com.sun:auto-snapshot=true zroot/home zroot/persist

# ernst only — service databases and config on the bulk pool
zfs set com.sun:auto-snapshot=true zdata/state
```

Or from a workstation:

```bash
ssh root@miralda.goclan.org 'zfs set com.sun:auto-snapshot=true zroot/home zroot/persist'
ssh root@biene.local        'zfs set com.sun:auto-snapshot=true zroot/home zroot/persist'
ssh root@ernst.skynet.lan   'zfs set com.sun:auto-snapshot=true zroot/home zroot/persist zdata/state'
```

## Verify

```bash
zfs get -r com.sun:auto-snapshot zroot zdata
```

`zroot/home`, `zroot/persist` and (on ernst) `zdata/state` should read `true`. Everything else should be `-`.

Snapshots appear on the next timer tick — `frequent` runs at :00/:15/:30/:45, so within 15 minutes:

```bash
zfs list -t snapshot -o name,used,creation | grep zfs-auto-snap
systemctl list-timers 'zfs-snapshot-*'
```

## What is deliberately excluded

| Dataset | Opted in | Reason |
|---|---|---|
| `zroot/home` | yes | user data |
| `zroot/persist` | yes | the entire point of impermanence — this is the machine's real state |
| `zdata/state` (ernst) | yes | *arr/immich databases and service config; irreplaceable |
| `zroot/root` | **no** | rolled back to `@blank` on every boot — a snapshot of it is worthless |
| `zroot/nix` | **no** | reproducible from the flake |
| `zroot/tmp` | **no** | scratch |
| `zdata/media` (ernst) | **no** | large and re-acquirable; snapshots would pin deleted media forever |
| `zdata/games` (ernst) | **no** | re-downloadable from Steam |

The exclusions matter as much as the inclusions. Opting in `zdata/media` on a 6×15.36 TB raidz1 would mean every deleted file stays on disk until its last snapshot expires — up to a month at the retention below.

## Retention you get

Fleet values, as evaluated from the running config:

| Interval | Kept |
|---|---|
| frequent (15 min) | 4 |
| hourly | 24 |
| daily | 7 |
| weekly | 4 |
| monthly | 1 |

`monthly = 1` is clan-core's override of the nixpkgs default of 12 — "a bit much given how much data is written", in their words. Scrubbing is separate and already active fleet-wide on a `monthly` interval.

## Related

- [Impermanence](../guides/impermanence.md) — the `@blank` rollback these snapshots sit alongside
- Pool health alerting is wired via ZED → ntfy (`modules/observability/zfs-ntfy.nix`). ZED *reports* errors; scrubs *find* them; snapshots let you *recover* from a bad write. The three are complementary.
