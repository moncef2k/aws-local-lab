# Nginx 03 — `proxy_pass` and proxy headers

> **Course:** [Nginx](./README.md)  ·  **Time:** ~45 min  ·  **Needs:** [Nginx 01](./01-web-server-and-reverse-proxy.md), [Nginx 02](./02-config-server-location.md) and [Networking 04](../networking/04-proxies.md)
> **Used in the labs:** [Lab 02, step 4](../../labs/02-load-balancing.md#step-4--nginx-in-front-of-the-api) (`proxy_pass http://api;` and the `proxy_set_header` lines of `lb/nginx.conf`) and [Lab 06, step 20](../../labs/06-object-storage.md#step-20--a-public-s3-address-s3localhost-through-the-load-balancer) (`Host $http_host`)

## What you will learn
- Write `proxy_pass` with and without a **URI** and predict the **path** the backend receives.
- Say which headers Nginx changes by default, and set `Host`, `X-Real-IP`, `X-Forwarded-For` and `X-Forwarded-Proto` on purpose.
- Tell `$host` from `$http_host`, and append (`$proxy_add_x_forwarded_for`) from overwrite (`$remote_addr`).
- Explain why a client can **forge** `X-Forwarded-For` and which part of it you can trust.
- Know the inheritance trap: a `location` with its own `proxy_set_header` loses the inherited ones.

## Words you need
| Word | Plain-words meaning |
|---|---|
| **`proxy_pass`** | The instruction that sends a request on to another server: `proxy_pass http://backend:8000;`. |
| **URI part of `proxy_pass`** | What comes after the address: in `http://backend:8000/v2/` it is `/v2/`; in `http://backend:8000` there is none. Its presence changes the path (see below). |
| **Variable** | A name starting with `$` that Nginx fills in for each request: `$host`, `$remote_addr`, `$scheme`... |
| **`$host`** | The host name of the request, **without** the port (taken from the `Host` header). |
| **`$http_host`** | The `Host` header **exactly as the client sent it**, port included. |
| **`$remote_addr`** | The IP address of whoever connected to Nginx. |
| **`$scheme`** | `http` or `https`: how the client connected. |
| **`$proxy_add_x_forwarded_for`** | The client's own `X-Forwarded-For` header (if any) followed by `, ` and `$remote_addr`: the list **grows** at each proxy. |
| **`proxy_set_header NAME value;`** | Sets or replaces a header on the request sent to the backend. |
| **Hop** | One stop in a chain of proxies. A request may cross several (a CDN, a load balancer, an app proxy). |
| **Spoofing / forging** | A client writing false values in headers, hoping the backend believes them. |

## The idea
**Analogy.** A **forwarding service at a post office**. Two things matter: the **address** the letter is sent on to (`proxy_pass`: the same room number, or a *different* room number written over the old one) and the **sticky notes** the clerk adds ("this came from Mr X", `proxy_set_header`). By default the clerk replaces the recipient name on the envelope by the new office's own name, and adds no note about the original sender: you must ask for the notes. And a sender may write a **false note** on the letter before it arrives, so a careful clerk either writes a note that **replaces** it or only trusts the part he wrote himself.

**Precisely.**
1. **The path.** `proxy_pass` takes an address and **optionally a URI**.
   - **No URI** (`proxy_pass http://backend:8000;`): the request path is sent **unchanged**.
   - **A URI**, even just `/` (`proxy_pass http://backend:8000/;`): the part of the path that matched the `location` prefix is **replaced** by that URI. One slash changes what the application sees.
2. **The headers.** By default Nginx passes the client's headers on, but **sets `Host` to the address in `proxy_pass`** (here `backend:8000`) and says nothing about the client's IP. So a backend behind a proxy sees the proxy as the client, and the wrong host name, unless you set the headers yourself.
3. **Trust.** Any client can send `X-Forwarded-For: 6.6.6.6`. If you **append** (`$proxy_add_x_forwarded_for`), the forged value stays on the **left** and your proxy adds the **real** address on the **right**: only the right-most entry, written by *your* proxy, can be trusted. If you **overwrite** (`$remote_addr`), the forged value disappears, which is right when your proxy is the first one the client reaches.

```mermaid
sequenceDiagram
  participant C as client
  participant N as Nginx
  participant B as backend
  C->>N: GET /strip/hello?x=1  (Host: localhost:18120, X-Forwarded-For: 6.6.6.6)
  Note over N: location /strip/ { proxy_pass http://backend:8000/; }
  N->>B: GET /hello?x=1  (Host: localhost, X-Forwarded-For: 6.6.6.6, 172.24.0.1)
  B-->>N: 200
  N-->>C: 200
```

## The code or config, line by line
`nginx.conf` of the experiment; each `location` is one case:
```nginx
events {}

http {
    server {
        listen 8080;
        proxy_set_header X-Server-Level "yes";      # set at the server level: inherited by locations with no proxy_set_header

        # --- what happens to the path ---
        location /keep/  { proxy_pass http://backend:8000; }         # no URI after the address: path sent unchanged
        location /strip/ { proxy_pass http://backend:8000/; }        # a URI (here "/"): the matched prefix is replaced by it
        location /api/   { proxy_pass http://backend:8000/v2/; }     # replaced by another prefix

        # --- what happens to the headers ---
        location /default-headers/ { proxy_pass http://backend:8000/; }

        location /with-headers/ {
            proxy_pass http://backend:8000/;
            proxy_set_header Host              $host;
            proxy_set_header X-Real-IP         $remote_addr;
            proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;   # append the client to the chain
            proxy_set_header X-Forwarded-Proto $scheme;
        }

        location /http-host/ {
            proxy_pass http://backend:8000/;
            proxy_set_header Host $http_host;                                # the Host exactly as sent, port included
        }

        location /overwrite-xff/ {
            proxy_pass http://backend:8000/;
            proxy_set_header X-Forwarded-For $remote_addr;                   # throw away what the client sent
        }
    }
}
```
| Line | What it does | If you change or remove it |
|---|---|---|
| `proxy_set_header X-Server-Level "yes";` (server level) | Sets a header for **every** location that sets no `proxy_set_header` of its own. | Used to show the inheritance rule below. |
| `location /keep/ { proxy_pass http://backend:8000; }` | **No URI**: `/keep/hello?x=1` reaches the backend as `/keep/hello?x=1`. | |
| `location /strip/ { proxy_pass http://backend:8000/; }` | The **URI `/`** replaces the prefix `/strip/`: the backend sees `/hello?x=1`. | Remove the final `/` and it behaves like `/keep/`: the backend would get `/strip/hello`. |
| `location /api/ { proxy_pass http://backend:8000/v2/; }` | The prefix `/api/` is replaced by `/v2/`: `/api/users` becomes `/v2/users`. This is how a public path is mapped to a different internal one. | |
| `location /default-headers/` | No `proxy_set_header` of its own: Nginx's defaults apply. | |
| `proxy_set_header Host $host;` | The backend receives the host name the **client** used (no port). | Without it the backend gets `backend:8000` (default). |
| `proxy_set_header X-Real-IP $remote_addr;` | A header carrying the client's IP, for the backend's logs. | |
| `proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;` | **Appends** the client's IP to the chain. | `$remote_addr` instead would overwrite the chain (last case). |
| `proxy_set_header X-Forwarded-Proto $scheme;` | Tells the backend whether the client used `http` or `https`. | |
| `proxy_set_header Host $http_host;` | The `Host` exactly as received, **with the port**. | `$host` would drop the port (needed in [Lab 06, step 20](../../labs/06-object-storage.md#step-20--a-public-s3-address-s3localhost-through-the-load-balancer), where the port is part of what is signed). |
| `proxy_set_header X-Forwarded-For $remote_addr;` | **Overwrites** whatever the client sent. | |

The backend, `echo.py`, answers with the path and the headers it received (it is the one of [Networking 04](../networking/04-proxies.md), plus `X-Real-IP` and `X-Server-Level`):
```python
"""A tiny backend that answers with what it received: the path and a few headers."""
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

SHOWN = ["Host", "X-Real-IP", "X-Forwarded-For", "X-Forwarded-Proto", "X-Server-Level"]


class Echo(BaseHTTPRequestHandler):
    def do_GET(self):
        seen = {"path": self.path, "peer_ip": self.client_address[0]}
        seen.update({name: self.headers.get(name) for name in SHOWN})
        body = (json.dumps({k: v for k, v in seen.items() if v is not None}) + "\n").encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


HTTPServer(("0.0.0.0", 8000), Echo).serve_forever()
```

## The commands
| Command / flag | Meaning |
|---|---|
| `docker network create nginx03` | A private network so the containers find each other by name. |
| `docker run -d --rm --name web --network nginx03 -p 127.0.0.1:18120:8080 -v "$D/nginx.conf:/etc/nginx/nginx.conf:ro" nginx:1.30.6-alpine` | Start Nginx: `-d` background, `--rm` delete when stopped, `--name`, `--network`, `-p` publish on your machine only, `-v ... :ro` mount your config read-only. |
| `docker run -d --rm --name backend ... -v "$D:/demo" -w /demo aws-local-lab-api:0.1.0 python echo.py` | The backend, from the project's API image (it has Python); `-w /demo` starts in the folder with `echo.py`. |
| `D=$(pwd -W)` and `MSYS_NO_PATHCONV=1` | Git Bash on Windows: the folder as a Windows path for `-v`, and no rewriting of `/etc/...` arguments. |
| `curl -s URL` / `curl -s -H 'Name: value' URL` | Quiet request / with an extra request header (here to forge `X-Forwarded-For` or `Host`). |
| `sed -E 's/.../\1/'` | Keep only the part of the answer I want to show (the matching text, captured by the parentheses). |

## Hands-on
Throw-away containers. Make a folder with `nginx.conf`, `echo.py` and this `run.sh`:
```bash
#!/usr/bin/env bash
D=$(pwd -W); export MSYS_NO_PATHCONV=1
docker network create nginx03 >/dev/null
docker run -d --rm --name backend --network nginx03 -v "$D:/demo" -w /demo aws-local-lab-api:0.1.0 python echo.py >/dev/null
docker run -d --rm --name web --network nginx03 -p 127.0.0.1:18120:8080 -v "$D/nginx.conf:/etc/nginx/nginx.conf:ro" nginx:1.30.6-alpine >/dev/null
sleep 2
echo "== 1. the path the backend receives"
for p in /keep/hello?x=1 /strip/hello?x=1 /api/users; do printf '%-18s -> ' "$p"; curl -s "localhost:18120$p" | sed -E 's/, "peer_ip".*//; s/^\{//'; done
echo "== 2. headers: nothing set (only the server-level one is inherited)"
curl -s localhost:18120/default-headers/x
echo "== 3. headers: Host, X-Real-IP, X-Forwarded-For, X-Forwarded-Proto set"
curl -s localhost:18120/with-headers/x
echo "-- the same with a made-up Host:"
curl -s -H 'Host: shop.example' localhost:18120/with-headers/x | sed -E 's/"X-Real.*//'
echo "== 4. Host: \$host drops the port, \$http_host keeps it"
printf '$host      : '; curl -s localhost:18120/with-headers/x | sed -E 's/.*("Host": "[^"]*").*/\1/'
printf '$http_host : '; curl -s localhost:18120/http-host/x | sed -E 's/.*("Host": "[^"]*").*/\1/'
echo "== 5. a client that lies about X-Forwarded-For"
printf 'append    ($proxy_add_x_forwarded_for): '; curl -s -H 'X-Forwarded-For: 6.6.6.6' localhost:18120/with-headers/x | sed -E 's/.*("X-Forwarded-For": "[^"]*").*/\1/'
printf 'overwrite ($remote_addr)              : '; curl -s -H 'X-Forwarded-For: 6.6.6.6' localhost:18120/overwrite-xff/x | sed -E 's/.*("X-Forwarded-For": "[^"]*").*/\1/'
docker stop web backend >/dev/null; docker network rm nginx03 >/dev/null
```
Run `bash run.sh`. Real output:
```text
== 1. the path the backend receives
/keep/hello?x=1    -> "path": "/keep/hello?x=1"
/strip/hello?x=1   -> "path": "/hello?x=1"
/api/users         -> "path": "/v2/users"
== 2. headers: nothing set (only the server-level one is inherited)
{"path": "/x", "peer_ip": "172.24.0.3", "Host": "backend:8000", "X-Server-Level": "yes"}
== 3. headers: Host, X-Real-IP, X-Forwarded-For, X-Forwarded-Proto set
{"path": "/x", "peer_ip": "172.24.0.3", "Host": "localhost", "X-Real-IP": "172.24.0.1", "X-Forwarded-For": "172.24.0.1", "X-Forwarded-Proto": "http"}
-- the same with a made-up Host:
{"path": "/x", "peer_ip": "172.24.0.3", "Host": "shop.example", 
== 4. Host: $host drops the port, $http_host keeps it
$host      : "Host": "localhost"
$http_host : "Host": "localhost:18120"
== 5. a client that lies about X-Forwarded-For
append    ($proxy_add_x_forwarded_for): "X-Forwarded-For": "6.6.6.6, 172.24.0.1"
overwrite ($remote_addr)              : "X-Forwarded-For": "172.24.0.1"
```
(Section 1 and the last lines of sections 3 to 5 are cut by `sed` to the part that matters.) **How to read it:**
- **1:** `/keep/hello?x=1` reaches the backend **unchanged**; `/strip/hello?x=1` loses its prefix (`/hello?x=1`); `/api/users` becomes `/v2/users`. The only difference between the first two is the **`/` at the end of the `proxy_pass` address**.
- **2:** with nothing set, the backend sees `Host: backend:8000` (Nginx's own destination), **no** client address (the peer `172.24.0.3` is Nginx), and `X-Server-Level: yes`, **inherited** from the `server` level.
- **3:** with the four `proxy_set_header` lines, the backend sees the client's host name (`localhost`, then `shop.example` for the made-up one), `X-Real-IP` and `X-Forwarded-For` `172.24.0.1`, and `X-Forwarded-Proto: http`. `172.24.0.1` is the client as Nginx sees it (the Docker network's gateway on Docker Desktop, see [Networking 05](../networking/05-nat-and-port-forwarding.md)). **`X-Server-Level` is gone**: this `location` sets its own `proxy_set_header`, so the one from the `server` level is **no longer inherited**.
- **4:** `$host` gives `localhost`, `$http_host` gives `localhost:18120`: the port survives only with `$http_host`.
- **5:** the client forged `X-Forwarded-For: 6.6.6.6`. With **append** the backend sees `6.6.6.6, 172.24.0.1`: the lie is on the left, the truth added by Nginx on the right. With **overwrite** it sees only `172.24.0.1`.

## What if…?
**…the backend trusts the whole `X-Forwarded-For`?** Then anyone can pretend to be `6.6.6.6` just by sending that header (section 5, "append"): an IP allow-list, a rate limit per client or an audit log would all be fooled. Rules of thumb: if your Nginx is the **first** proxy the client reaches, **overwrite** (`$remote_addr`); if there are proxies in front of yours that you trust (a CDN, a cloud load balancer), append and trust only the entries they and you added, never the left-most one. The lab's `lb/nginx.conf` appends, because in AWS an ALB would sit in front.

## In short
1. `proxy_pass` **with a URI** (even `/`) replaces the matched prefix; **without** one the path is passed unchanged. One slash changes what the application sees.
2. By default the backend gets `Host: <proxy_pass address>` and no client IP: set `Host`, `X-Real-IP`, `X-Forwarded-For` and `X-Forwarded-Proto` with `proxy_set_header`. `$host` drops the port, `$http_host` keeps it.
3. `X-Forwarded-For` can be forged: append and trust only your own proxy's entry, or overwrite. A `location` with any `proxy_set_header` loses the ones inherited from outer levels.

## Check your understanding
1. What path does the backend receive for `GET /strip/hello` with `location /strip/ { proxy_pass http://backend:8000/; }`? And with `proxy_pass http://backend:8000;`?
2. What `Host` does the backend see if you set no `proxy_set_header Host`, and why is that a problem for an application that serves several sites?
3. When do you use `$http_host` instead of `$host`?
4. A client sends `X-Forwarded-For: 6.6.6.6` and Nginx uses `$proxy_add_x_forwarded_for`. What does the backend receive, and which entry is trustworthy?
5. A `location` sets `proxy_set_header Host $host;`; the `server` block sets `proxy_set_header X-Env "prod";`. Does the backend receive `X-Env`?

<details><summary>Answers</summary>

1. `/hello` with the URI (`/`): the prefix `/strip/` is replaced. `/strip/hello` without a URI: the path is sent unchanged.
2. `backend:8000`, Nginx's own destination, not the name the client typed. An application that chooses a site or builds links from the `Host` would treat every request as the same site, with the wrong name.
3. When the **port** must be kept (it is part of the host the client used, as in a presigned URL signed for `s3.localhost:8088`); `$host` removes it.
4. `6.6.6.6, <the address Nginx saw>`. Only the right-most entry, added by your own Nginx, is trustworthy; the left part was written by the client.
5. No. A `location` that sets any `proxy_set_header` does **not** inherit those of the outer levels, so `X-Env` is lost unless you repeat it in that `location`.

</details>

## Official documentation
- [Nginx: `proxy_pass`](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_pass) (the URI rules) and [`proxy_set_header`](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_set_header) (defaults and inheritance)
- [Nginx: embedded variables](https://nginx.org/en/docs/http/ngx_http_core_module.html#variables) (`$host`, `$http_host`, `$remote_addr`, `$scheme`) and [`$proxy_add_x_forwarded_for`](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#var_proxy_add_x_forwarded_for)
- [MDN: `X-Forwarded-For`](https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-Forwarded-For) (including the trust warning)

## Where you use this in the project
- [Lab 02, step 4](../../labs/02-load-balancing.md#step-4--nginx-in-front-of-the-api): `proxy_pass http://api;` (no URI: paths pass unchanged) with `proxy_set_header Host $host;`, `X-Real-IP $remote_addr;` and `X-Forwarded-For $proxy_add_x_forwarded_for;`.
- [Lab 06, step 20](../../labs/06-object-storage.md#step-20--a-public-s3-address-s3localhost-through-the-load-balancer): `proxy_set_header Host $http_host;` for the object store, so the port is kept for the signature.
- [Networking 04](../networking/04-proxies.md): the first look at these headers; [Nginx 02](./02-config-server-location.md): which `location` handles a request in the first place.
