#!/usr/bin/env bash
# Lab 02 test: kill one API replica and no request fails; restart it and it rejoins.
# Needs the stack to be up (make up). The replica is always restarted at the end.
set -u
cd "$(dirname "$0")/.."

fail=0
ok()  { echo "  PASS  $1"; }
bad() { echo "  FAIL  $1"; fail=1; }

addr=$(docker compose port lb 80 2>/dev/null)
if [ -z "$addr" ] || [ "$addr" = ":0" ]; then
  echo "  FAIL  the lb service is not running: start the lab with 'make up' first"
  exit 1
fi
url="http://${addr/0.0.0.0/127.0.0.1}"

# The victim: the first api container, and the hostname it answers with (its container id).
victim=$(docker compose ps --status running -q api | head -n 1)
[ -n "$victim" ] || { echo "  FAIL  no running api container: start the lab with 'make up' first"; exit 1; }
victim_host=$(docker inspect -f '{{.Config.Hostname}}' "$victim")
trap 'docker start "$victim" >/dev/null 2>&1' EXIT

echo "Lab 02 - failover ($url, killing replica $victim_host)"

# Hostnames answered by the load balancer, over n requests (one per line).
hostnames() { for _ in $(seq "$1"); do { curl -s --max-time 5 "$url/whoami"; echo; } | sed -n 's/.*"hostname":"\([^"]*\)".*/\1/p'; done; }

# 0. Before: the victim is in rotation.
hostnames 30 | grep -q "$victim_host" && ok "replica $victim_host answers before the kill" || bad "replica $victim_host never answered before the kill"

# 1. Kill it, then send 60 requests: every one must be a 200.
docker kill "$victim" >/dev/null
codes=$(for _ in $(seq 60); do curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 "$url/whoami"; done | sort | uniq -c)
echo "$codes" | sed 's/^/        /'
nok=$(echo "$codes" | awk '$2==200 {n=$1} END {print n+0}')
[ "$nok" = "60" ] && ok "60 of 60 requests succeeded with one replica dead" || bad "only $nok of 60 requests succeeded with one replica dead"

# 2. Restart it: within 60 seconds it must answer requests again, without touching nginx.
docker start "$victim" >/dev/null
rejoined=no
for _ in $(seq 30); do
  if hostnames 10 | grep -q "$victim_host"; then rejoined=yes; break; fi
  sleep 2
done
[ "$rejoined" = yes ] && ok "replica $victim_host rejoined the rotation" || bad "replica $victim_host did not rejoin within 60 seconds"

[ "$fail" = 0 ] && echo "02_failover: all checks passed" || echo "02_failover: FAILED"
exit "$fail"
