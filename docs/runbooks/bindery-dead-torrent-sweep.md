# Bindery dead-torrent sweep

Bindery's queue fills with releases nobody is seeding, shows them as
`Failed — stalled: no peers / no download progress`, and leaves the dead
torrents in qBittorrent forever. This is the sweep that clears them, plus the
diagnosis that tells you when the sweep is the *wrong* answer.

Run it when the Queue page is mostly red, or when
`/srv/media/torrents/{books,audiobooks}` has grown a tail of 0% torrents.

## First: confirm it really is dead releases

**Do not start with the VPN or the download client.** Both look guilty and
both are usually innocent. The measurement that settles it is the *swarm*
seed count — `num_complete`, what the tracker reports — and not `num_seeds`,
which is only how many you are currently connected to and reads `0` on
perfectly healthy completed torrents.

```bash
ssh root@10.0.50.10
C=$(mktemp)
curl -s -c "$C" -d 'username=admin&password=<qbt password>' \
  http://10.0.90.11:8080/api/v2/auth/login >/dev/null
for cat in books audiobooks; do
  curl -s -b "$C" "http://10.0.90.11:8080/api/v2/torrents/info?category=$cat"
done | jq -s 'add | [.[] | select(.progress < 1)]
  | {stuck: length,
     swarm0:    ([.[] | select(.num_complete <= 0)] | length),
     swarm1_2:  ([.[] | select(.num_complete > 0 and .num_complete < 3)] | length),
     swarm3plus:([.[] | select(.num_complete >= 3)] | length)}'
```

Measured 2026-10-03, which is the shape to expect:

```json
{"stuck": 77, "swarm0": 66, "swarm1_2": 10, "swarm3plus": 1}
```

66 of 77 had **zero** seeds in the swarm, and every torrent that had completed
had 4–34. That is a release-selection problem and the sweep below is the right
response.

If instead you see a healthy `swarm3plus` and nothing is moving, **stop** —
that is a different fault and this runbook will not fix it. Check qBittorrent's
`transfer/info` (`connection_status`, `dht_nodes`) and whether other categories
are downloading at all.

## Why it keeps happening

**Bindery has no minimum-seeders filter.** Grepping the 1.33.2 binary, the only
seed-related configuration is `seed_ratio`, which is the *upload* side. Nothing
ranks or rejects a release by swarm health, so a 0-seed release and a 25-seed
release of the same book are equally grabbable.

Prowlarr's `torrentBaseSettings.appMinimumSeeders` does **not** rescue this.
That field is only propagated to \*arr applications during app sync; Bindery
reads `seedRatio` from Prowlarr and ignores the rest. Setting it looks like a
fix and changes nothing.

So there is no configuration that stops the dead grabs. The two levers that do
work are indirect:

1. **More and better indexers**, so good releases outnumber bad in the result
   set. See [The reading stack](../guides/reading-stack.md).
2. **This sweep**, run periodically.

A third factor, worth knowing and not worth chasing: qBittorrent has **no
inbound port**. IVPN does not forward ports, so `nc -vz <exit-ip> 6881` from
outside times out. The `wg0` accept rule in
`machines/ernst/microvms/wg-qbittorrent.nix` is correct — nothing arrives to
match it. This only costs the thin swarms (the `swarm1_2` column above), so it
is not the cause of a red queue.

## The sweep

Removing a queue row through Bindery's API **also removes the torrent from
qBittorrent**, so this is one call and not two. Bindery auto-blocklists every
release it fails as stalled, so the same dead torrents are not re-grabbed —
verify with `select count(*) from blocklist;` if you want to be sure before
starting.

`unmonitorBooks: false` is load-bearing: it keeps the books monitored so
Bindery searches again for a *different* release. Setting it true would quietly
abandon them.

```bash
ssh root@10.0.50.10
API=$(sqlite3 'file:/srv/state/bindery/bindery.db?mode=ro' \
  "select value from settings where key='auth.api_key';")

# 1. everything already marked failed
sqlite3 'file:/srv/state/bindery/bindery.db?mode=ro' \
  "select id from downloads where status='failed';" > /root/failed.txt

# 2. plus rows still called 'downloading' whose torrent is dead —
#    these are the ones Bindery has not given up on yet
C=$(mktemp)
curl -s -c "$C" -d 'username=admin&password=<qbt password>' \
  http://10.0.90.11:8080/api/v2/auth/login >/dev/null
for cat in books audiobooks; do
  curl -s -b "$C" "http://10.0.90.11:8080/api/v2/torrents/info?category=$cat"
done | jq -s -r 'add | .[] | select(.progress == 0 and .num_complete <= 0) | .hash' \
  > /root/dead.txt

sqlite3 'file:/srv/state/bindery/bindery.db?mode=ro' \
  "select id || ' ' || torrent_id from downloads
   where status='downloading' and torrent_id is not null;" > /root/dl.txt
awk 'NR==FNR{d[$1];next} ($2 in d){print $1}' /root/dead.txt /root/dl.txt \
  > /root/dl_dead.txt

cat /root/failed.txt /root/dl_dead.txt | sort -un > /root/sweep.txt
wc -l < /root/sweep.txt

# 3. delete in batches of 40
split -l 40 /root/sweep.txt /root/sw_
for f in /root/sw_??; do
  jq -R -s -c '{ids: (split("\n") | map(select(length>0) | tonumber)),
                deleteFiles: true, unmonitorBooks: false}' "$f" > "$f.json"
  systemd-run -q --collect --pipe --machine=arr \
    /run/current-system/sw/bin/curl -s -m 300 -X POST \
    -H "X-Api-Key: $API" -H 'Content-Type: application/json' \
    --data-binary @- http://127.0.0.1:8787/api/v1/queue/bulk-delete < "$f.json" \
  | jq -r '"\(input_filename // "batch"): ok=\([.results[] | select(.ok == true)] | length)"'
done
```

Batch in 40s. A single call with 150+ ids is slow enough to hit the curl
timeout, and a timed-out call that *did* apply server-side is indistinguishable
from one that did not.

### Verify

```bash
sqlite3 'file:/srv/state/bindery/bindery.db?mode=ro' \
  "select status, count(*) from downloads group by status;"
```

`failed` should be gone entirely. `imported` must not have moved.

## Expect a re-grab wave, and budget for it

This is the part that surprises people. Clearing the queue unblocks Bindery's
scheduler, which immediately works through the ~1500 monitored books — and
because of the missing seeders filter, a large fraction of what it grabs is
dead on arrival all over again.

Measured across one afternoon on 2026-10-03:

| | after first sweep | ~2h later |
|---|---|---|
| imported | 56 | 103 |
| failed | 0 | 134 |
| qBT books / audiobooks | 48 / 26 | 122 / 145 |

So the sweep is genuinely productive — imports nearly doubled — but it is a
cycle, not a fix. Run it, let the wave land, run it again. Do not run it
unattended on a timer expecting the number to stay at zero.

**Do not mass-search to speed this up.** `POST /api/v1/wanted/bulk` over all
~1500 wanted books will rate-limit the indexers; The Pirate Bay auto-disables
on HTTP 429 and stays disabled for hours. Batches of ~10 are safe.

## What Cleanuparr does and does not do here

Cleanuparr's dead-torrent rule covers `books` and `audiobooks` since
2026-10-03, but understand its limits before relying on it:

- It **tags** dead torrents `cleanuparr-dead` after 48 strikes. It does not
  delete them (`use_tag = 1`).
- Its queue cleaner works through registered \*arr instances — Sonarr and
  Radarr. **Bindery is not an \*arr and is not registered**, so nothing in
  Cleanuparr can blocklist a Bindery release or trigger a Bindery re-search.

It gives you visibility. The sweep above is still the thing that reclaims the
queue.

Its configuration lives in SQLite with the API behind auth, so changes are made
with the service stopped:

```bash
systemctl --machine=arr stop cleanuparr
sqlite3 /srv/state/cleanuparr/cleanuparr.db \
  "select categories from dead_torrent_configs;"      # save this first
systemctl --machine=arr start cleanuparr
```

## Related gotchas

**Changing a qBittorrent category's save path flips its torrents to manual
TMM**, so they do not follow the new path. Re-enable auto-TMM on exactly those
hashes afterwards:

```bash
H=$(curl -s -b "$C" 'http://10.0.90.11:8080/api/v2/torrents/info?category=audiobooks' \
    | jq -r '[.[].hash] | join("|")')
curl -s -b "$C" -d "hashes=$H" -d 'enable=true' \
  http://10.0.90.11:8080/api/v2/torrents/setAutoManagement
```

**The category save path and `BINDERY_AUDIOBOOK_DOWNLOAD_DIR` must agree.**
Bindery's download-client health check compares them and reports `error` when
they disagree. The env var is set in `machines/ernst/containers/arr.nix`; the
category is runtime state in qBittorrent, so a deploy can move one without the
other. Check with Settings → Download Clients → Test, or:

```bash
systemd-run -q --collect --pipe --machine=arr /run/current-system/sw/bin/curl \
  -s -X POST -H "X-Api-Key: $API" -H 'Content-Type: application/json' \
  http://127.0.0.1:8787/api/v1/downloadclient/1/test \
| jq -r 'to_entries[] | select(.value | type == "object")
         | "\(.key): \(.value.status)"'
```

**`importBlocked` is not `failed` and the sweep skips it.** It means
qBittorrent still calls the download complete while none of its files are on
this host — a path problem, not a swarm problem. Read `error_message` and
`import_path` on the row before doing anything to it.
