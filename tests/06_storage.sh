#!/usr/bin/env bash
# Lab 06 test: object storage. Uploads a random file through POST /upload, downloads it from the HOST
# with the presigned URL the API returned (through the load balancer, host name s3.localhost) and
# compares the SHA-256 checksums. Also checks what must NOT work: a tampered or missing signature,
# a URL signed for the wrong host, a PUT on the public door, an oversized file, a missing field and a
# hostile file name.
# Needs the stack to be up (make up). Takes about 15 seconds. The test objects are deleted at the end.
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

echo "Lab 06 - object storage ($url)"

# Work in a temporary folder and give curl relative file names: the Windows curl cannot read
# Git Bash paths such as /tmp/x (see Lab 06, troubleshooting).
tmp=$(mktemp -d)
keys=()
cleanup() {
  rm -rf "$tmp"
  # Delete the test objects with the AWS CLI of the s3-init service (same endpoint, same keys).
  if [ "${#keys[@]}" -gt 0 ]; then
    docker compose run --rm --no-deps -T --entrypoint sh s3-init -c \
      'for k; do aws --endpoint-url http://s3:8333 s3 rm "s3://$S3_BUCKET/$k" >/dev/null; done' sh "${keys[@]}" >/dev/null 2>&1
  fi
}
trap cleanup EXIT
in_tmp() { ( cd "$tmp" && "$@" ); }
field() { sed -n "s/.*\"$1\":\"\([^\"]*\)\".*/\1/p"; }   # a string field of the JSON answer

# 1. Upload 200,000 random bytes.
in_tmp sh -c 'head -c 200000 /dev/urandom > blob.bin'
sum_before=$(sha256sum "$tmp/blob.bin" | cut -d' ' -f1)
code=$(in_tmp curl -s --max-time 10 -o up.json -w '%{http_code}' -F "file=@blob.bin;type=application/octet-stream" "$url/upload")
resp=$(cat "$tmp/up.json")
key=$(echo "$resp" | field key)
link=$(echo "$resp" | field url)
if [ "$code" = 201 ] && [ -n "$key" ] && [ -n "$link" ]; then
  keys+=("$key")
  ok "POST /upload: 201, key $key"
else
  echo "  FAIL  upload failed (HTTP $code): $resp"
  exit 1
fi
case "$key" in originals/*) ok "the key is under the originals/ prefix" ;; *) bad "unexpected key prefix: $key" ;; esac

# 2. The link must be usable from the host: public name, not the Docker-only name "s3".
public_base=$(echo "$link" | cut -d/ -f1-3)
case "$public_base" in
  http://s3.localhost*) ok "the URL points at the public endpoint ($public_base)" ;;
  *) bad "the URL host is '$public_base': set S3_PUBLIC_ENDPOINT_URL (with the port of LB_HOST_PORT)" ;;
esac

# 3. Download with the presigned URL, from the host, and compare the bytes.
dcode=$(in_tmp curl -s --max-time 10 -o down.bin -w '%{http_code}' "$link")
sum_after=$(sha256sum "$tmp/down.bin" 2>/dev/null | cut -d' ' -f1)
[ "$dcode" = 200 ] && ok "GET of the presigned URL from the host: 200" || bad "GET of the presigned URL: expected 200, got $dcode"
[ -n "$sum_after" ] && [ "$sum_before" = "$sum_after" ] \
  && ok "downloaded bytes are identical (sha256 ${sum_before:0:16}...)" || bad "checksum differs: ${sum_before:0:16} vs ${sum_after:0:16}"

# 4. The signature protects the object.
last=${link: -1}; [ "$last" = 0 ] && new=1 || new=0
c=$(curl -s -o /dev/null --max-time 10 -w '%{http_code}' "${link%?}$new")
[ "$c" = 403 ] && ok "a modified signature is refused (403)" || bad "modified signature: expected 403, got $c"
c=$(curl -s -o /dev/null --max-time 10 -w '%{http_code}' "${link%%\?*}")
[ "$c" = 403 ] && ok "the object address without a signature is refused (403)" || bad "no signature: expected 403, got $c"
c=$(curl -s -o /dev/null --max-time 10 -w '%{http_code}' -X PUT "$link")
[ "$c" = 403 ] && ok "PUT on the public door is refused by the load balancer (403)" || bad "PUT: expected 403, got $c"

# 5. A link signed for the internal host (s3:8333) must not work on the public host: the signature covers the Host header.
internal=$(docker compose exec -T api python -c "
import main, sys
print(main.s3.generate_presigned_url('get_object', Params={'Bucket': main.S3_BUCKET, 'Key': sys.argv[1]}, ExpiresIn=60))" "$key" 2>/dev/null | tr -d '\r')
case "$internal" in
  http://s3:8333/*)
    c=$(curl -s -o /dev/null --max-time 10 -w '%{http_code}' "$public_base${internal#http://s3:8333}")
    [ "$c" = 403 ] && ok "a URL signed for s3:8333 is refused on $public_base (403)" || bad "URL signed for the wrong host: expected 403, got $c" ;;
  *) bad "could not create the internal URL: '$internal'" ;;
esac

# 6. Bad input.
c=$(curl -s -o /dev/null --max-time 10 -w '%{http_code}' -X POST "$url/upload" -F "other=x")
[ "$c" = 422 ] && ok "upload without the 'file' field: 422" || bad "missing field: expected 422, got $c"
in_tmp sh -c 'head -c 6000000 /dev/urandom > big.bin'
body=$(in_tmp curl -s --max-time 20 -w ' [%{http_code}]' -F "file=@big.bin" "$url/upload")
case "$body" in
  *"file too large"*"[413]") ok "a 6,000,000-byte file: 413 from the API (over its 5 MB limit)" ;;
  *) bad "6,000,000-byte file: expected the API's 413, got: ${body:0:120}" ;;
esac
in_tmp sh -c 'echo hello > hello.txt'
hkey=$(in_tmp curl -s --max-time 10 -F 'file=@hello.txt;filename=../../etc/pass wd.txt' "$url/upload" | field key)
[ -n "$hkey" ] && keys+=("$hkey")
case "$hkey" in
  originals/*-pass_wd.txt) ok "hostile file name cleaned: $hkey" ;;
  *) bad "hostile file name: unexpected key '${hkey:-none}'" ;;
esac

[ "$fail" = 0 ] && echo "06_storage: all checks passed" || echo "06_storage: FAILED"
exit "$fail"
