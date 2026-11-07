# Postgres collation refresh (after a glibc bump)

## Symptom

Every `psql`, and every `nextcloud-occ` call, prints:

```
WARNING:  database "nextcloud" has a collation version mismatch
DETAIL:  The database was created using collation version 2.42, but the operating system provides version 2.44.
```

A nixpkgs update moved glibc, and glibc's collation rules decide the order of
text indexes. An index built under the old rules can return wrong results for
text comparisons under the new ones. It isn't an outage, but don't leave it.

Last done on ernst on **2026-11-07** (2.42 → 2.44). Affected: every
PostgreSQL in the fleet's containers (`nextcloud`, `immich`, `paperless`,
`miniflux`), each with three databases (`<app>`, `postgres`, `template1`).
Whole run: under 20 s; Immich's vector indexes are the slowest part, at about 13 s.

## Find them

```bash
for c in nextcloud immich miniflux paperless; do
  echo "$c: $(nixos-container run $c -- su postgres -s /bin/sh -c \
    "psql -Atc \"select count(*) filter (where datcollversion <> pg_database_collation_actual_version(oid)) from pg_database where datallowconn\"") mismatched"
done
```

A new container with a PostgreSQL belongs in that list.

## Fix one container

Snapshot first — the database lives on `zdata/state`:

```bash
zfs snapshot zdata/state@pre-collation-$(date +%F)
```

Stop the app (not postgres), rebuild, record, start:

```bash
c=immich; units="immich-server immich-machine-learning"
systemctl -M $c stop $units
for db in $(nixos-container run $c -- su postgres -s /bin/sh -c \
    "psql -Atc \"select datname from pg_database where datallowconn\""); do
  nixos-container run $c -- su postgres -s /bin/sh -c \
    "psql -q -v ON_ERROR_STOP=1 -d $db -c \"REINDEX DATABASE $db\" -c \"ALTER DATABASE $db REFRESH COLLATION VERSION\""
done
systemctl -M $c start $units
```

| Container | App units to stop |
|---|---|
| `nextcloud` | none. Use `nextcloud-occ maintenance:mode --on` / `--off` instead |
| `immich` | `immich-server immich-machine-learning` |
| `paperless` | `paperless-web paperless-consumer paperless-scheduler paperless-task-queue` |
| `miniflux` | `miniflux` |

**`REINDEX` before `REFRESH`, always.** `REFRESH COLLATION VERSION` only
records the new version and fixes nothing. Run on its own, it silences the
warning and leaves the indexes built under the old rules.

Then re-run the check above (expect `0 mismatched` everywhere) and
`systemctl -M <c> --failed`.
