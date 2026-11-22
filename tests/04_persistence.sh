#!/usr/bin/env bash
# Lab 04 test: data lives in the database volume, not in the containers. Writes one note,
# runs "docker compose down" then "up" (volumes are kept), and checks the note is still there.
# Needs the stack to be up (make up). Takes about a minute. The test note is deleted at the end.
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

echo "Lab 04 - persistence ($url)"

# 1. Write a note through the load balancer.
title="persistence-test-$(date +%s)"
resp=$(curl -s --max-time 5 -X POST "$url/notes" -H 'Content-Type: application/json' \
  -d "{\"title\":\"$title\",\"body\":\"written before down\"}")
id=$(echo "$resp" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
if [ -z "$id" ]; then
  echo "  FAIL  could not create a note: $resp"
  exit 1
fi
trap 'curl -s -o /dev/null --max-time 5 -X DELETE "$url/notes/$id"' EXIT
ok "created note $id (\"$title\")"

# 2. Throw every container away (down) and start again (up). No "-v": the volume stays.
docker compose down >/dev/null 2>&1 && ok "docker compose down: containers removed" || bad "docker compose down failed"
if docker volume ls -q | grep -q '_pgdata$'; then ok "the pgdata volume is still there"; else bad "the pgdata volume is gone"; fi
docker compose up -d >/dev/null 2>&1 && ok "docker compose up -d: new containers started" || bad "docker compose up failed"

# 3. Wait for the API to serve the note again (the new database container must be healthy
#    and the migrate job must have run), then compare.
code=000
for _ in $(seq 60); do
  code=$(curl -s -o /dev/null --max-time 3 -w '%{http_code}' "$url/notes/$id")
  [ "$code" = "200" ] && break
  sleep 2
done
body=$(curl -s --max-time 5 "$url/notes/$id")
if [ "$code" = "200" ] && echo "$body" | grep -q "\"title\":\"$title\""; then
  ok "note $id survived down + up, same title"
else
  bad "note $id is gone after down + up (HTTP $code): $body"
fi

[ "$fail" = 0 ] && echo "04_persistence: all checks passed" || echo "04_persistence: FAILED"
exit "$fail"
