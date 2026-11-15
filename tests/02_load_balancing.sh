#!/usr/bin/env bash
# Lab 02 test: the load balancer answers, spreads requests over the 3 API replicas,
# and is the only way in. Needs the stack to be up (make up).
set -u
cd "$(dirname "$0")/.."

fail=0
ok()  { echo "  PASS  $1"; }
bad() { echo "  FAIL  $1"; fail=1; }

# Where the load balancer is published (follows LB_HOST_PORT without reading .env).
addr=$(docker compose port lb 80 2>/dev/null)
if [ -z "$addr" ] || [ "$addr" = ":0" ]; then
  echo "  FAIL  the lb service is not running: start the lab with 'make up' first"
  exit 1
fi
url="http://${addr/0.0.0.0/127.0.0.1}"

echo "Lab 02 - load balancing ($url)"

# 1. The API answers through the load balancer.
body=$(curl -s --max-time 5 "$url/health")
[ "$body" = '{"status":"ok"}' ] && ok "GET /health through the load balancer" || bad "GET /health returned: $body"

# 2. Three API replicas are running.
replicas=$(docker compose ps --status running -q api | wc -l | tr -d ' ')
[ "$replicas" = "3" ] && ok "3 api replicas running" || bad "expected 3 api replicas, found $replicas"

# 3. 30 requests are spread over all 3 replicas (round-robin: about 10 each).
hosts=$(for _ in $(seq 30); do
  { curl -s --max-time 5 "$url/whoami"; echo; } | sed -n 's/.*"hostname":"\([^"]*\)".*/\1/p'
done | sort | uniq -c)
echo "$hosts" | sed 's/^/        /'
distinct=$(echo "$hosts" | grep -c .)
min=$(echo "$hosts" | awk 'NR==1 || $1<m {m=$1} END {print m+0}')
if [ "$distinct" = "3" ] && [ "$min" -ge 5 ]; then
  ok "30 requests reached 3 different replicas (fewest: $min)"
else
  bad "expected 3 replicas with at least 5 requests each, got $distinct replicas (fewest: $min)"
fi

# 4. The API is not published on the host: the load balancer is the only way in.
api_port=$(docker compose port api 8000 2>/dev/null)
if [ -z "$api_port" ] || [ "$api_port" = ":0" ]; then
  ok "api has no published port"
else
  bad "api is published on $api_port"
fi

[ "$fail" = 0 ] && echo "02_load_balancing: all checks passed" || echo "02_load_balancing: FAILED"
exit "$fail"
