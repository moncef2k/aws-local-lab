#!/usr/bin/env bash
# Lab 07 test: the asynchronous pipeline (API -> Redis queue -> worker -> S3).
#  1. upload an image, submit a thumbnail job, poll until it is done, download the thumbnail from the
#     host with the presigned URL the API gives and check it is a PNG of the announced size;
#  2. a job that cannot work (the file is not an image) ends as "failed" with a reason, no result;
#  3. "docker compose stop worker" in the middle of a job lets the job finish (exit code 0);
#  4. a job left in the processing list by a dead worker is requeued and finished by the next worker.
# Needs the stack to be up (make up). Takes about 40 seconds. The test objects are deleted at the end.
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
if [ -z "$(docker compose ps --status running -q worker 2>/dev/null)" ]; then
  echo "  FAIL  the worker service is not running: start the lab with 'make up' first"
  exit 1
fi

echo "Lab 07 - queues and workers ($url)"

rcli() { docker compose exec -T redis sh -c 'REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli "$@"' sh "$@" 2>/dev/null | tr -d '\r'; }
field() { sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p"; }   # a string field of a JSON answer

# Work in a temporary folder with relative file names for curl (see Lab 06, troubleshooting).
tmp=$(mktemp -d)
keys=()      # bucket objects to delete at the end
job_ids=()   # job records to delete at the end
cleanup() {
  docker compose start worker >/dev/null 2>&1   # in case the test stopped it and failed half way
  for j in "${job_ids[@]}"; do rcli del "job:$j" >/dev/null; done
  rm -rf "$tmp"
  if [ "${#keys[@]}" -gt 0 ]; then
    docker compose run --rm --no-deps -T --entrypoint sh s3-init -c \
      'for k; do aws --endpoint-url http://s3:8333 s3 rm "s3://$S3_BUCKET/$k" >/dev/null; done' sh "${keys[@]}" >/dev/null 2>&1
  fi
}
trap cleanup EXIT

# upload FILE TYPE -> prints the key (the first upload after a fresh start can fail for a while: try 5 times)
upload() {
  local i body
  for i in 1 2 3 4 5; do
    body=$(cd "$tmp" && curl -s --max-time 20 -F "file=@$1;type=$2" "$url/upload")
    [ -n "$(echo "$body" | field key)" ] && break
  done
  echo "$body" | field key
}
# submit BODY -> sets $code (HTTP status) and $id (job id)
submit() {
  code=$(curl -s --max-time 10 -o "$tmp/job.json" -w '%{http_code}' -X POST "$url/jobs" -H 'Content-Type: application/json' -d "$1")
  id=$(field id < "$tmp/job.json")
  [ -n "$id" ] && job_ids+=("$id")
}
# wait_for ID SECONDS -> prints the status once it is done or failed (or the last one seen)
wait_for() {
  local s=""
  for _ in $(seq "$2"); do
    s=$(curl -s --max-time 5 "$url/jobs/$1" | field status)
    case "$s" in done|failed) break ;; esac
    sleep 1
  done
  echo "$s"
}
# png_size FILE -> WxH (the PNG header holds the width and height as two 4-byte numbers at bytes 16-23)
png_size() {
  set -- "$1" $(od -An -tu1 -j16 -N8 "$1" 2>/dev/null)
  [ "$#" = 9 ] || { echo "unknown"; return; }   # the file is missing or too short
  echo "$(( ($2 << 24) + ($3 << 16) + ($4 << 8) + $5 ))x$(( ($6 << 24) + ($7 << 16) + ($8 << 8) + $9 ))"
}

# 1. A 1200 x 800 image, made with Pillow in a throw-away container of the worker image.
docker run --rm --entrypoint python aws-local-lab-worker:0.1.0 -c "
import sys
from PIL import Image
im = Image.new('RGB', (1200, 800))
im.putdata([(x * 255 // 1200, y * 255 // 800, 128) for y in range(800) for x in range(1200)])
im.save(sys.stdout.buffer, 'PNG')" > "$tmp/big.png" 2>/dev/null
echo "just text, not an image" > "$tmp/notes.txt"
[ "$(png_size "$tmp/big.png")" = "1200x800" ] && ok "test image made: 1200x800" || { echo "  FAIL  could not make the test image (is the worker image built?)"; exit 1; }

# 2. Upload it, ask for a thumbnail, poll until done.
orig=$(upload big.png image/png)
[ -n "$orig" ] && keys+=("$orig") && ok "POST /upload: $orig" || { echo "  FAIL  upload failed"; exit 1; }
submit "{\"type\":\"thumbnail\",\"payload\":{\"key\":\"$orig\"}}"
[ "$code" = 202 ] && [ "$(field status < "$tmp/job.json")" = queued ] && ok "POST /jobs: 202 Accepted, status queued" || bad "POST /jobs: expected 202 + queued, got $code"
status=$(wait_for "$id" 30)
[ "$status" = done ] && ok "the worker finished the job: status done" || bad "job status after 30 s: '${status:-none}'"

# 3. The answer tells where the result is; download it from the host.
curl -s --max-time 5 "$url/jobs/$id" > "$tmp/done.json"
rkey=$(field result_key < "$tmp/done.json"); rsize=$(field result_size < "$tmp/done.json"); rurl=$(field result_url < "$tmp/done.json")
[ -n "$rkey" ] && keys+=("$rkey")
case "$rkey" in thumbnails/*) ok "result_key $rkey" ;; *) bad "unexpected result_key '$rkey'" ;; esac
[ "$rsize" = "128x85" ] && ok "result_size 128x85 (1200x800 shrunk to fit 128x128)" || bad "result_size: expected 128x85, got '$rsize'"
dcode=$(cd "$tmp" && curl -s --max-time 10 -o thumb.png -w '%{http_code}' "$rurl")
[ "$dcode" = 200 ] && ok "the thumbnail downloads from the host with the presigned URL: 200" || bad "thumbnail download: expected 200, got $dcode"
sig=$(od -An -tx1 -N8 "$tmp/thumb.png" 2>/dev/null | tr -d ' \n')
[ "$sig" = "89504e470d0a1a0a" ] && ok "it is a PNG" || bad "not a PNG (first bytes $sig)"
[ "$(png_size "$tmp/thumb.png")" = "$rsize" ] && ok "its real size is $rsize, as announced" || bad "real size $(png_size "$tmp/thumb.png"), announced $rsize"

# 4. A job that cannot work ends as failed, with a reason and no result.
txt=$(upload notes.txt text/plain); keys+=("$txt")
submit "{\"type\":\"thumbnail\",\"payload\":{\"key\":\"$txt\"}}"
status=$(wait_for "$id" 30)
curl -s --max-time 5 "$url/jobs/$id" > "$tmp/failed.json"
[ "$status" = failed ] && ok "a text file is not an image: status failed" || bad "bad job: expected failed, got '${status:-none}'"
grep -q 'UnidentifiedImageError' "$tmp/failed.json" && ok "the answer says why: $(field error < "$tmp/failed.json" | cut -c1-40)..." || bad "no error message in the answer"
grep -q 'result_url' "$tmp/failed.json" && bad "a failed job must not have a result_url" || ok "a failed job has no result_url"

# 5. docker compose stop in the middle of a job: the job finishes, the worker exits with code 0.
submit '{"type":"noop"}'
for _ in $(seq 20); do [ "$(curl -s --max-time 5 "$url/jobs/$id" | field status)" = processing ] && break; sleep 0.25; done
docker compose stop worker >/dev/null 2>&1
exitcode=$(docker inspect -f '{{.State.ExitCode}}' "$(docker compose ps -aq worker)" 2>/dev/null)
status=$(curl -s --max-time 5 "$url/jobs/$id" | field status)
[ "$status" = done ] && ok "stopped during a job: the job still finished (done)" || bad "stopped during a job: status '$status'"
[ "$exitcode" = 0 ] && ok "the worker exited with code 0 (graceful shutdown)" || bad "worker exit code '$exitcode'"

# 6. A worker died holding a job: simulate it (worker stopped, the id moved to the processing list by hand),
#    start a new worker: it requeues the id and finishes the job.
submit '{"type":"noop"}'
moved=$(rcli lmove queue:jobs queue:processing RIGHT LEFT)
[ "$moved" = "$id" ] && ok "job $id left in queue:processing by a 'dead' worker" || bad "could not set up the orphaned job (moved '$moved')"
docker compose start worker >/dev/null 2>&1
status=$(wait_for "$id" 30)
[ "$status" = done ] && ok "a new worker recovered the orphaned job: status done" || bad "orphaned job: status '${status:-none}'"
[ "$(rcli llen queue:jobs)" = 0 ] && [ "$(rcli llen queue:processing)" = 0 ] && ok "both lists are empty at the end" || bad "lists not empty: jobs=$(rcli llen queue:jobs) processing=$(rcli llen queue:processing)"

[ "$fail" = 0 ] && echo "07_async: all checks passed" || echo "07_async: FAILED"
exit "$fail"
