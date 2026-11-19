#!/usr/bin/env bash
# Lab 05 test: cache-aside on GET /notes/{id}. Checks the X-Cache header (MISS, HIT, MISS after an
# update, 404 not cached), the TTL stored in Redis, the Redis password, and that the API keeps
# working (X-Cache: BYPASS) while Redis is stopped.
# Needs the stack to be up (make up). Takes about 20 seconds. The test note is deleted at the end.
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

echo "Lab 05 - cache ($url)"

# Value of the X-Cache header of GET /notes/<id> (empty if there is none), and the HTTP code.
xcache() { curl -s -o /dev/null -D - --max-time 5 "$url/notes/$1" | tr -d '\r' | sed -n 's/^[Xx]-[Cc]ache: *//p'; }
code_of() { curl -s -o /dev/null --max-time 5 -w '%{http_code}' "$url/notes/$1"; }
# redis-cli inside the redis container, authenticated with the password the container already has.
rcli() { docker compose exec -T redis sh -c 'REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli "$@"' sh "$@" 2>/dev/null | tr -d '\r'; }

# 1. Create a note.
title="cache-test-$(date +%s)"
resp=$(curl -s --max-time 5 -X POST "$url/notes" -H 'Content-Type: application/json' \
  -d "{\"title\":\"$title\",\"body\":\"v1\"}")
id=$(echo "$resp" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
if [ -z "$id" ]; then
  echo "  FAIL  could not create a note: $resp"
  exit 1
fi
cleanup() {
  docker compose start redis >/dev/null 2>&1   # in case the test stopped it and failed half way
  curl -s -o /dev/null --max-time 5 -X DELETE "$url/notes/$id"
}
trap cleanup EXIT
ok "created note $id"

# 2. The first read goes to the database (MISS), the next ones are served by Redis (HIT).
#    The load balancer spreads the requests over 3 replicas: a HIT on all of them proves the
#    cache is shared, not kept inside one replica.
first=$(xcache "$id")
[ "$first" = "MISS" ] && ok "first read: X-Cache: MISS" || bad "first read: expected MISS, got '${first:-no header}'"
hits=0
for _ in 1 2 3 4 5 6; do [ "$(xcache "$id")" = "HIT" ] && hits=$((hits + 1)); done
[ "$hits" = 6 ] && ok "next 6 reads (different replicas): all X-Cache: HIT" || bad "next 6 reads: only $hits of 6 were HIT"

# 3. The entry has a time to live in Redis.
ttl=$(rcli ttl "note:$id")
max=$(docker compose exec -T api printenv CACHE_TTL_SECONDS 2>/dev/null | tr -d '\r')   # the TTL the API really uses
if [ -n "$ttl" ] && [ "$ttl" -gt 0 ] 2>/dev/null && [ "$ttl" -le "${max:-60}" ]; then
  ok "key note:$id has a TTL of ${ttl}s (it expires by itself)"
else
  bad "key note:$id: unexpected TTL '${ttl:-none}'"
fi

# 4. An update removes the entry: the next read is a MISS and shows the new text, then HIT again.
curl -s -o /dev/null --max-time 5 -X PUT "$url/notes/$id" -H 'Content-Type: application/json' \
  -d "{\"title\":\"$title\",\"body\":\"v2\"}"
after=$(xcache "$id")
[ "$after" = "MISS" ] && ok "read after PUT: X-Cache: MISS (entry was invalidated)" || bad "read after PUT: expected MISS, got '${after:-no header}'"
if curl -s --max-time 5 "$url/notes/$id" | grep -q '"body":"v2"'; then ok "the cached copy holds the new body (v2)"; else bad "the cached copy is stale"; fi

# 5. A missing note is never cached.
curl -s -o /dev/null --max-time 5 -X DELETE "$url/notes/$id"
[ "$(code_of "$id")" = "404" ] && ok "deleted note: 404 (not served from the cache)" || bad "deleted note: expected 404"
[ "$(rcli exists "note:$id")" = "0" ] && ok "no cache entry left for the deleted note" || bad "a cache entry is left for the deleted note"

# 6. Redis asks for a password.
noauth=$(docker compose exec -T redis redis-cli ping 2>&1 | tr -d '\r')
echo "$noauth" | grep -q 'NOAUTH' && ok "redis-cli without a password is refused (NOAUTH)" || bad "redis answered without a password: $noauth"

# 7. Redis down is a slower API, not a broken one: reads still work and say BYPASS.
resp=$(curl -s --max-time 5 -X POST "$url/notes" -H 'Content-Type: application/json' -d "{\"title\":\"$title-bypass\"}")
id2=$(echo "$resp" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
if [ -n "$id2" ]; then
  docker compose stop redis >/dev/null 2>&1
  b=$(xcache "$id2"); c=$(code_of "$id2")
  [ "$b" = "BYPASS" ] && [ "$c" = "200" ] && ok "Redis stopped: HTTP 200 with X-Cache: BYPASS" || bad "Redis stopped: expected 200 + BYPASS, got $c + '${b:-no header}'"
  docker compose start redis >/dev/null 2>&1
  for _ in $(seq 20); do [ "$(rcli ping)" = "PONG" ] && break; sleep 1; done
  [ "$(rcli ping)" = "PONG" ] && ok "Redis started again" || bad "Redis did not come back"
  curl -s -o /dev/null --max-time 5 -X DELETE "$url/notes/$id2"
else
  bad "could not create the note for the BYPASS check: $resp"
fi

[ "$fail" = 0 ] && echo "05_cache: all checks passed" || echo "05_cache: FAILED"
exit "$fail"
