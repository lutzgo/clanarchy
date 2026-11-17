#!/usr/bin/env bash
# bindery-sweep-dead.sh — clear Bindery's failed and dead downloads, so qBittorrent's
# queue and Bindery's scheduler move again.  The scripted form of
# docs/runbooks/bindery-dead-torrent-sweep.md ("The sweep").
#
# Run ON THE ERNST HOST:
#   ssh root@ernst-zt DRY=1 bash /root/bindery-sweep-dead.sh    # counts + sample only
#   ssh root@ernst-zt DRY=0 bash /root/bindery-sweep-dead.sh    # delete
# (copy it there first: scp scripts/bindery-sweep-dead.sh root@ernst-zt:/root/)
#
# Swept:
#   - every download Bindery already marked `failed`
#   - `downloading` rows whose torrent is dead: progress 0 and no seeds in the
#     swarm (num_complete <= 0).  This includes magnets that never fetched
#     metadata; with INCLUDE_QUEUED=0 those still sitting in qBittorrent's queue
#     (never given a slot, so their swarm count means nothing) are left alone.
#
# Bindery's bulk-delete also removes the torrent from qBittorrent, and Bindery
# blocklists what it fails, so the same release is not re-grabbed.
# `unmonitorBooks: false` keeps the books wanted, so Bindery searches for a
# DIFFERENT release.  Expect a re-grab wave afterwards (see the runbook).
set -euo pipefail
DRY=${DRY:-1}; INCLUDE_QUEUED=${INCLUDE_QUEUED:-1}; BATCH=40
DB=/srv/state/bindery/bindery.db
B=http://10.0.90.11:8080; J=$(mktemp); W=$(mktemp -d); trap 'rm -rf "$J" "$W"' EXIT

sq() { nix shell nixpkgs#sqlite -c sqlite3 "file:$DB?mode=ro" "$@" 2>/dev/null; }

pw=$(head -1 /run/microvm-*-secrets/webui-password)
# qBittorrent 5.x answers a good login with 204 and an EMPTY body (4.x said "Ok."),
# so check the status code, not the text.
r=$(curl -s -o /dev/null -w '%{http_code}' -c "$J" --data-urlencode username=admin \
      --data-urlencode "password=$pw" "$B/api/v2/auth/login")
case "$r" in 200|204) ;; *) echo "qBittorrent login failed: HTTP $r" >&2; exit 1 ;; esac

API=$(sq "select value from settings where key='auth.api_key';")
[ -n "$API" ] || { echo "no Bindery API key in $DB" >&2; exit 1; }

# Dead torrents in Bindery's categories, lower-case hashes.
for c in books audiobooks; do curl -s -b "$J" "$B/api/v2/torrents/info?category=$c"; done \
  | jq -s -r --argjson q "$INCLUDE_QUEUED" 'add | .[]
      | select(.progress == 0 and .num_complete <= 0)
      | select($q == 1 or .state != "queuedDL")
      | .hash | ascii_downcase' > "$W/dead"

sq "select id from downloads where status='failed';" > "$W/failed"
sq "select id || ' ' || lower(torrent_id) from downloads
    where status='downloading' and torrent_id is not null;" > "$W/dl"
awk 'NR==FNR{d[$1];next} ($2 in d){print $1}' "$W/dead" "$W/dl" > "$W/dl_dead"
sort -un "$W/failed" "$W/dl_dead" > "$W/sweep"

echo "dead torrents in qBittorrent (books+audiobooks): $(wc -l < "$W/dead")"
echo "Bindery failed: $(wc -l < "$W/failed")   downloading-but-dead: $(wc -l < "$W/dl_dead")   to sweep: $(wc -l < "$W/sweep")"
echo "sample:"
ids=$(head -8 "$W/sweep" | paste -sd,)
[ -n "$ids" ] && sq "select '  ' || status || '  ' || substr(title,1,70) from downloads where id in ($ids);"

if [ "$DRY" != 0 ]; then echo "(dry run — DRY=0 to delete)"; exit 0; fi

split -l "$BATCH" "$W/sweep" "$W/sw_"
for f in "$W"/sw_??; do
  body=$(jq -R -s -c '{ids: (split("\n") | map(select(length>0) | tonumber)),
                       deleteFiles: true, unmonitorBooks: false}' "$f")
  out=$(nixos-container run arr -- curl -s -m 300 -X POST \
          -H "X-Api-Key: $API" -H 'Content-Type: application/json' \
          --data "$body" http://127.0.0.1:8787/api/v1/queue/bulk-delete)
  echo "batch $(basename "$f"): ok=$(jq '[.results[]? | select(.ok == true)] | length' <<<"$out" 2>/dev/null || echo "?: $out")"
done
echo "after:"; sq "select '  ' || status || ' ' || count(*) from downloads group by status;"
