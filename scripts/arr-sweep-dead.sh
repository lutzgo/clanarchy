#!/usr/bin/env bash
# arr-sweep-dead.sh — remove dead downloads that hold qBittorrent's download slots,
# through the *arr that grabbed them: queue DELETE with removeFromClient=true
# and blocklist=true, so the torrent goes, the release is blocklisted, and the
# *arr searches for another.  See docs/runbooks/bindery-dead-torrent-sweep.md.
#
# Run ON THE ERNST HOST (the qBittorrent password and nixos-container are there):
#   scp scripts/arr-sweep-dead.sh root@ernst-zt:/root/
#   ssh root@ernst-zt DRY=1 bash /root/arr-sweep-dead.sh   # list only
#   ssh root@ernst-zt DRY=0 bash /root/arr-sweep-dead.sh   # remove
#
# "Dead" = all of:
#   - state stalledDL or metaDL (actively trying, not merely queued: a queuedDL
#     torrent reports stale swarm counts, so it is never judged here)
#   - num_complete <= 0  (the TRACKER's swarm seed count, not peers we reach)
#   - time_active > MIN_HOURS (default 24)
set -euo pipefail
DRY=${DRY:-1}; MIN_HOURS=${MIN_HOURS:-24}
B=http://10.0.90.11:8080; J=$(mktemp); trap 'rm -f "$J"' EXIT
pw=$(head -1 /run/microvm-*-secrets/webui-password)
curl -sf -c "$J" --data-urlencode username=admin --data-urlencode "password=$pw" "$B/api/v2/auth/login" >/dev/null

# category -> "app port apiver"
declare -A APP=( [lidarr]="lidarr 8686 v1" [tv]="sonarr 8989 v3" [radarr]="radarr 7878 v3" )

arr() { # app port apiver method path
  nixos-container run arr -- sh -c "curl -sf -X $4 -H \"X-Api-Key: \$(cat /run/arr-api-keys/$1-api-key)\" 'http://localhost:$2/api/$3/$5'"
}

dead=$(curl -sf -b "$J" "$B/api/v2/torrents/info" | jq -c --argjson h "$MIN_HOURS" '
  [.[] | select((.state=="stalledDL" or .state=="metaDL") and .num_complete<=0
                and .time_active > ($h*3600))
       | {hash: (.hash|ascii_upcase), category, name: .name[0:70], progress: (.progress*100|floor)}]')
echo "dead torrents: $(jq length <<<"$dead")"

for cat in "${!APP[@]}"; do
  read -r app port ver <<<"${APP[$cat]}"
  mine=$(jq -c --arg c "$cat" '[.[]|select(.category==$c)]' <<<"$dead")
  [ "$(jq length <<<"$mine")" = 0 ] && continue
  queue=$(arr "$app" "$port" "$ver" GET "queue?pageSize=1000")
  jq -c '.[]' <<<"$mine" | while read -r t; do
    h=$(jq -r .hash <<<"$t"); n=$(jq -r .name <<<"$t"); p=$(jq -r .progress <<<"$t")
    # One torrent can be several queue records (an album = many tracks); delete each id once.
    ids=$(jq -r --arg h "$h" '[.records[]|select(.downloadId==$h)|.id]|unique|.[]' <<<"$queue")
    if [ -z "$ids" ]; then echo "  [$app] NOT IN QUEUE (left alone): $p% $n"; continue; fi
    for id in $ids; do
      if [ "$DRY" = 0 ]; then
        arr "$app" "$port" "$ver" DELETE "queue/$id?removeFromClient=true&blocklist=true" >/dev/null \
          && echo "  [$app] removed+blocklisted: $p% $n" || echo "  [$app] FAILED: $n"
      else
        echo "  [$app] would remove+blocklist (queue id $id): $p% $n"
      fi
      break   # removing one record removes the torrent; the rest go with it
    done
  done
done
