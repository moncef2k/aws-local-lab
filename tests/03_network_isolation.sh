#!/usr/bin/env bash
# Lab 03 test: the network layout behaves like a VPC. Only the load balancer is exposed,
# the API lives on an internal (private) network and cannot reach the internet.
# Needs the stack to be up (make up).
set -u
cd "$(dirname "$0")/.."

fail=0
ok()   { echo "  PASS  $1"; }
bad()  { echo "  FAIL  $1"; fail=1; }
skip() { echo "  SKIP  $1"; }

addr=$(docker compose port lb 80 2>/dev/null)
if [ -z "$addr" ] || [ "$addr" = ":0" ]; then
  echo "  FAIL  the lb service is not running: start the lab with 'make up' first"
  exit 1
fi
url="http://${addr/0.0.0.0/127.0.0.1}"

echo "Lab 03 - network isolation ($url)"

# 1. Only the load balancer publishes a port on the host, and it is port 80 inside.
published=$(docker compose ps --format '{{.Service}} {{.Ports}}' | grep -- '->' || true)
if [ "$(echo "$published" | grep -c .)" = "1" ] && echo "$published" | grep -Eq '^lb .*->80/tcp'; then
  ok "only lb publishes a port ($(echo "$published" | cut -d' ' -f2-))"
else
  bad "expected only lb to publish a port, got: $published"
fi

# 2. The private network is internal; the API is on it and nowhere else; the lb is on both.
nets_of() { docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$1"; }
private=$(docker compose ps -q lb | head -1 | xargs docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' | tr ' ' '\n' | grep '_private$')
internal=$(docker network inspect -f '{{.Internal}}' "$private" 2>/dev/null)
[ "$internal" = "true" ] && ok "network $private is internal" || bad "network ${private:-private} is not internal (Internal=$internal)"

api_ids=$(docker compose ps -q api)
wrong=0
for id in $api_ids; do
  [ "$(nets_of "$id" | xargs)" = "$private" ] || wrong=1
done
[ -n "$api_ids" ] && [ "$wrong" = 0 ] && ok "every api replica is on $private only" || bad "an api replica is on another network than $private"

lb_nets=$(nets_of "$(docker compose ps -q lb | head -1)" | wc -w | tr -d ' ')
[ "$lb_nets" = "2" ] && ok "lb is attached to 2 networks (public + private)" || bad "lb is attached to $lb_nets network(s), expected 2"

# 3. The API cannot be reached from the host, neither on a published port nor on its container address.
if curl -s -o /dev/null --max-time 2 http://127.0.0.1:8000/health; then
  bad "the API answers on 127.0.0.1:8000"
else
  ok "127.0.0.1:8000 does not answer"
fi
api_ip=$(docker inspect -f "{{(index .NetworkSettings.Networks \"$private\").IPAddress}}" "$(echo "$api_ids" | head -1)")
if curl -s -o /dev/null --max-time 2 "http://$api_ip:8000/health"; then
  bad "the API answers from the host on its container address $api_ip"
else
  ok "the API container address ($api_ip) is not reachable from the host"
fi

# 4. ...but it is reachable through the load balancer (the lb is the bridge between the networks).
body=$(curl -s --max-time 5 "$url/health")
[ "$body" = '{"status":"ok"}' ] && ok "the API answers through the load balancer" || bad "GET /health through the lb returned: $body"

# 5. The API has no way to the internet. The lb is the control: if it cannot get out either
#    (no internet on this machine), the result would prove nothing, so the check is skipped.
if ! docker compose exec -T lb wget -q -O /dev/null -T 5 http://example.com 2>/dev/null; then
  skip "no internet from the lb either: cannot prove the API is cut off"
elif docker compose exec -T --index 1 api python -c \
  "import urllib.request; urllib.request.urlopen('http://example.com', timeout=5)" >/dev/null 2>&1; then
  bad "the API container can reach the internet"
else
  ok "the API container cannot reach the internet (the lb can)"
fi

# 6. The database (Lab 04): no published port, on the private network only, not reachable from
#    the host, but reachable from an API replica (the control that proves "not reachable" means something).
pg_id=$(docker compose ps -q postgres | head -1)
if [ -z "$pg_id" ]; then
  skip "the postgres service is not running"
else
  [ "$(docker compose port postgres 5432 2>/dev/null)" = ":0" ] && ok "postgres publishes no port" || bad "postgres publishes a port"
  [ "$(nets_of "$pg_id" | xargs)" = "$private" ] && ok "postgres is on $private only" || bad "postgres is on another network than $private"
  if [ -n "$(docker compose --profile admin ps --status running -q db-proxy 2>/dev/null)" ]; then
    skip "the admin profile is on (db-proxy running): 127.0.0.1:5432 is open on purpose"
  elif timeout 3 bash -c '</dev/tcp/127.0.0.1/5432' 2>/dev/null; then
    bad "127.0.0.1:5432 accepts connections"
  else
    ok "127.0.0.1:5432 is closed"
  fi
  pg_ip=$(docker inspect -f "{{(index .NetworkSettings.Networks \"$private\").IPAddress}}" "$pg_id")
  if timeout 3 bash -c "</dev/tcp/$pg_ip/5432" 2>/dev/null; then
    bad "postgres answers from the host on its container address $pg_ip"
  else
    ok "the postgres container address ($pg_ip) is not reachable from the host"
  fi
  if docker compose exec -T --index 1 api python -c \
    "import socket; socket.create_connection(('postgres', 5432), timeout=3)" >/dev/null 2>&1; then
    ok "an API replica reaches postgres:5432 on the private network"
  else
    bad "an API replica cannot reach postgres:5432"
  fi
fi

[ "$fail" = 0 ] && echo "03_network_isolation: all checks passed" || echo "03_network_isolation: FAILED"
exit "$fail"
