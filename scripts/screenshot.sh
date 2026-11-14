#!/usr/bin/env bash
# Capture a PNG of a web page, using Playwright (Chromium) in a pinned Docker image.
# Nothing is installed on the host except Docker.
#
# Usage:  scripts/screenshot.sh <url> <out.png> [extra-wait-ms]
#   e.g.  scripts/screenshot.sh http://grafana.localhost/ docs/labs/images/lab-09/grafana.png 2000
#
# Pages served by the load balancer use names like grafana.localhost. Inside the container
# "localhost" is the container itself, so for every *.localhost host we add
# `--add-host <name>:host-gateway` (= the Docker host, where the LB listens on port 80/443).
# Chromium treats *.localhost as loopback by itself, so the browser is also told to use the
# address from /etc/hosts (--host-resolver-rules).
#
# Never screenshot secrets (passwords, tokens). Log in with throw-away values only.
set -euo pipefail

PLAYWRIGHT_VERSION="1.65.2"
IMAGE="mcr.microsoft.com/playwright/python:v$PLAYWRIGHT_VERSION-noble"
WIDTH=1280
HEIGHT=800

if [ $# -lt 2 ]; then
  echo "usage: $0 <url> <out.png> [extra-wait-ms]" >&2
  exit 1
fi
url="$1"
out="$2"
wait_ms="${3:-500}"

# Host part of the URL (strip scheme, path and port).
host="${url#*://}"
host="${host%%[/:?#]*}"

# Docker needs absolute host paths; Git Bash must not rewrite the container paths (/out, /dev/stdin).
export MSYS_NO_PATHCONV=1
mkdir -p "$(dirname "$out")"
out_dir="$(cd "$(dirname "$out")" && { pwd -W 2>/dev/null || pwd; })"
out_name="$(basename "$out")"

docker_args=(run --rm -i -v "$out_dir:/out" -e "SHOT_HOST=$host")
case "$host" in
  *.localhost) docker_args+=(--add-host "$host:host-gateway") ;;
  localhost | 127.0.0.1)
    # Plain localhost would be the container itself: reach the Docker host instead.
    url="${url/$host/host.docker.internal}"
    docker_args+=(--add-host "host.docker.internal:host-gateway")
    ;;
esac

# The image contains the browsers but not the Python package: install the matching pinned version
# inside the throw-away container (a small wheel; the browsers are not downloaded again).
docker "${docker_args[@]}" "$IMAGE" sh -c '
  pip install -q --disable-pip-version-check --root-user-action=ignore --break-system-packages "playwright==$0" >/dev/null &&
  python - "$@"' "$PLAYWRIGHT_VERSION" "$url" "/out/$out_name" "$WIDTH" "$HEIGHT" "$wait_ms" <<'PY'
import os, socket, sys
from playwright.sync_api import sync_playwright

url, out, width, height, wait_ms = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
host = os.environ.get("SHOT_HOST", "")

args = []
if host.endswith(".localhost"):
    args.append(f"--host-resolver-rules=MAP {host} {socket.gethostbyname(host)}")

with sync_playwright() as p:
    browser = p.chromium.launch(args=args)
    # Local mkcert certificates are not trusted inside the container.
    page = browser.new_page(viewport={"width": width, "height": height}, ignore_https_errors=True)
    page.goto(url, wait_until="networkidle", timeout=30000)
    page.wait_for_timeout(wait_ms)
    page.screenshot(path=out, full_page=True)
    browser.close()
print(f"saved {out}")
PY
echo "screenshot written to $out"
