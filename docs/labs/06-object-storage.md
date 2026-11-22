# Lab 06 — Object storage (S3)

> **AWS equivalent:** Amazon S3 (buckets, objects, access keys, presigned URLs)  ·  **Time:** ~75 min  ·  **Difficulty:** ★★☆
> **Builds on:** [Lab 05](./05-caching.md)  ·  **Reference solution:** commits `0cc9b19` (step 18), `b2872f7` (step 19), `4d7933c` (step 20) and `c2a4afb` (step 21) on `dev`

> **Status:** done. Steps 18–21 and the closing sections are written.

## 1. What you will learn
- Explain what **object storage** is, and how it differs from a disk and from a database.
- Name the parts of S3 (bucket, key, object, access key, endpoint) and their local counterparts.
- Run an S3-compatible server in a container on the private network, with its files in a volume and fake credentials from `.env`.
- Write a **one-shot bootstrap job** that creates the bucket, and make it safe to run twice.
- Use the real **AWS CLI** against a local endpoint, and see that a wrong secret key is refused.
- Accept an upload through the API (boto3) and hand out a **presigned URL** that works from your machine, through a public name routed by the load balancer.
- Explain why the signature covers the `Host` header, and write a test that checks both what must work and what must be refused.

## 2. Theory

### 2.1 The concept
Some data is not rows in a table: photos, PDF files, videos, backups, exported reports. They are big, they are written once and read many times, and you almost never change them in place; you replace the whole file. A database is a poor home for them, and a normal disk attached to one server does not scale and disappears with the server.

**Object storage** is a service that keeps such files for you. Think of a **left-luggage office**: you hand over a bag (the file), you get a ticket with a name (the *key*), and later you give the ticket back to get the same bag. There are no folders you walk through and no "edit the middle of the bag": you put a whole bag in, take a whole bag out, or throw it away. In exchange the office can hold a nearly unlimited number of bags and never loses one.

The vocabulary:
- A **bucket** is a named container for objects (the office). Its name is unique and it holds the settings (who may access it).
- An **object** is one file plus its metadata (size, type, date).
- A **key** is the object's name inside the bucket, such as `photos/2026/cat.jpg`. The slashes are only part of the name: there are no real folders, tools just show them as if there were.
- Access is by **HTTP**: you `PUT` an object to upload it and `GET` it to download it, signed with an **access key** (an id and a secret). This HTTP interface is called the **S3 API**.

### 2.2 How AWS does it
**Amazon S3** (*Simple Storage Service*) is the AWS object store:

| S3 piece | What it is |
|---|---|
| **Bucket** | The container; the name is unique across all of AWS. Lives in one **region**. |
| **Object / key** | The file and its name. One object can be up to 5 TB. |
| **Access keys / IAM** | An **access key id** plus a **secret access key** identify a user or application; **IAM policies** say which buckets and actions it may use. |
| **Endpoint** | The address of the API, such as `https://s3.eu-west-3.amazonaws.com`. SDKs and the CLI use it automatically. |
| **Presigned URL** | A temporary link that lets someone **without credentials** download or upload one object (the subject of the next steps). |
| **Durability** | S3 stores each object on several devices in several zones: 99.999999999% ("eleven nines") durability. |

In the console: **S3 → Buckets**. In the CLI: `aws s3 ls`, `aws s3 mb`, `aws s3 cp`.

### 2.3 How we reproduce it locally
> **A change from the plan.** The usual local S3 is **MinIO**, but it no longer publishes container images (the official `quay.io/minio/minio` has no manifest, and Docker Hub answers `denied`; see Troubleshooting). On 2026-11-19 you chose **SeaweedFS** instead (decision D5 in `PLAN.md`). It is a different program with the **same S3 protocol**, so everything you learn about buckets, keys, access keys and presigned URLs is the same.

| Concept | AWS | This lab |
|---|---|---|
| The service | S3 | the `s3` service (image `chrislusf/seaweedfs:4.54`, running `weed server -s3`) |
| Where the files live | AWS-managed storage in several zones | a named volume, `s3data` |
| Endpoint | `https://s3.<region>.amazonaws.com` | `http://s3:8333` inside Docker (Docker DNS, see [Docker 07](../courses/docker/07-networks.md)) |
| Access key id / secret | IAM user keys | `S3_ACCESS_KEY` / `S3_SECRET_KEY` in `.env` (fake, gitignored) |
| Private by default | block public access, bucket policy | `private` (internal) network and no `ports:`; keys required |
| Creating the bucket | Console, CLI or infrastructure-as-code | the one-shot `s3-init` job (AWS CLI image) |
| The client | AWS CLI / SDK (boto3) | the same AWS CLI, with `--endpoint-url` pointing at `s3` |
| Replication across zones, versioning, encryption, lifecycle rules | built in | not simulated |

### 2.4 Diagram
```mermaid
flowchart LR
  you((You)) -->|127.0.0.1:80| lb
  subgraph public["public network"]
    lb["lb: Nginx"]
  end
  subgraph private["private network (internal)"]
    api["api x3"]
    s3[("s3: SeaweedFS<br/>bucket 'uploads'")]
    init["s3-init<br/>(one-shot job)"]
  end
  lb --> api
  lb -->|"step 20: Host s3.localhost (GET/HEAD only)"| s3
  api -. "step 19: upload / download" .-> s3
  init -->|"create the bucket, then exit"| s3
  you -. "direct: no route, no published port" .-> s3
```

## 3. Prerequisites
- [Lab 05](./05-caching.md) completed: `make up` runs, `make test` is green.
- Two S3 settings in your `.env`. Like the other secrets they have **no default** on purpose, so from this step on **every** `docker compose` command (and `make test`) needs them. Append a fake key id and a random fake secret without printing it:
  ```bash
  printf '\nS3_ACCESS_KEY=lab-access-key\nS3_SECRET_KEY=%s\n' "$(openssl rand -hex 16)" >> .env
  ```
  (or add the two lines by hand; `.env.example` shows them). `.env` is gitignored and never committed.
- If port 80 is busy on your machine (step 20), also set `LB_HOST_PORT` and the matching `S3_PUBLIC_ENDPOINT_URL` in `.env`, for example `LB_HOST_PORT=8088` and `S3_PUBLIC_ENDPOINT_URL=http://s3.localhost:8088` (same port in both).

## 4. Steps

> Try each step yourself first, then compare with the reference commit.

### Step 18 — The S3 server and the bucket bootstrap job
**Why:** this is the architecture's "S3": a place for uploaded files that lives on the private network, keeps its data in a volume and asks for credentials. A second, short-lived container creates the bucket, so a fresh checkout always ends with the same bucket.

**Do it.** Add two services after `redis` in `docker-compose.yml`, and a volume at the bottom:

```yaml
  s3:
    image: chrislusf/seaweedfs:4.54
    environment:
      # Fake root credentials of the S3 API (SeaweedFS reads these two standard names).
      AWS_ACCESS_KEY_ID: ${S3_ACCESS_KEY:?set S3_ACCESS_KEY in .env (see .env.example)}
      AWS_SECRET_ACCESS_KEY: ${S3_SECRET_KEY:?set S3_SECRET_KEY in .env (see .env.example)}
    # "server -s3" runs the whole store in one container (master, volume server, filer, S3 gateway).
    # Small volumes (64 MB, at most 20) so the lab does not reserve gigabytes on your disk.
    command: [server, -dir=/data, -s3, -master.volumeSizeLimitMB=64, -volume.max=20]
    volumes:
      - s3data:/data
    networks:
      - private
    healthcheck:
      # The S3 gateway answers 200 on /healthz once it can talk to the rest of the store.
      test: ["CMD", "wget", "-q", "-O", "/dev/null", "http://127.0.0.1:8333/healthz"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 10s

  # One-shot job: creates the bucket once the store is healthy, then exits (like the "migrate" job).
  # It checks first, so running it again changes nothing.
  s3-init:
    image: amazon/aws-cli:2.41.1
    environment:
      AWS_ACCESS_KEY_ID: ${S3_ACCESS_KEY:?set S3_ACCESS_KEY in .env (see .env.example)}
      AWS_SECRET_ACCESS_KEY: ${S3_SECRET_KEY:?set S3_SECRET_KEY in .env (see .env.example)}
      AWS_DEFAULT_REGION: us-east-1
      S3_BUCKET: ${S3_BUCKET:-uploads}
    entrypoint: [sh, -c]
    command:
      - |
        aws --endpoint-url http://s3:8333 s3api head-bucket --bucket "$$S3_BUCKET" 2>/dev/null \
          && echo "bucket $$S3_BUCKET already exists" \
          || aws --endpoint-url http://s3:8333 s3 mb "s3://$$S3_BUCKET"
    networks:
      - private
    depends_on:
      s3:
        condition: service_healthy
    restart: "no"
```
```yaml
volumes:
  pgdata:
  # The object store's files (like the storage behind an S3 bucket).
  s3data:
```
and the placeholders in `.env.example`:
```bash
# Object storage (Lab 06). Fake local values, no defaults: put your own in .env.
S3_ACCESS_KEY=change-me-local-access-key
S3_SECRET_KEY=change-me-local-only-secret
# Name of the bucket created at start-up (optional, "uploads" if unset)
# S3_BUCKET=uploads
```

| Line | What it does | If you change or remove it |
|---|---|---|
| `image: chrislusf/seaweedfs:4.54` | The SeaweedFS image, **pinned** to release 4.54. | `:latest` changes under you (forbidden here). |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` (from `S3_ACCESS_KEY` / `S3_SECRET_KEY`) | SeaweedFS uses these two standard variable names as its **root credentials** when no config file is given. `:?message` stops Compose if one is missing. | Without credentials the store would accept anyone on the network. A default here would put a secret in the repository. |
| `command: [server, -dir=/data, -s3, ...]` | `server` runs master, volume server, filer and S3 gateway in one process; `-dir` is where it stores data; `-s3` switches the S3 API on (port **8333**). | Without `-s3` there is no S3 API, only SeaweedFS's own interface. |
| `-master.volumeSizeLimitMB=64`, `-volume.max=20` | SeaweedFS stores files inside big **volumes**. Here each is at most 64 MB and there are at most 20. | The defaults are tuned for big disks; on a laptop they can reserve far more space than a lab needs. |
| `volumes: - s3data:/data` | A **named volume**: the files survive `docker compose down` and container re-creation. | Without it every `down` deletes your uploads. |
| `networks: - private`, no `ports:` | Only containers on the internal network can reach it. | `ports: ["8333:8333"]` would open the store to your machine (and cannot work on an internal network anyway, see [Lab 04, step 13](./04-database.md)). |
| `healthcheck: wget .../healthz` | `healthy` means the S3 gateway answers `200` on `/healthz`. | A port-only check (`nc -z`) can be true while the store is still starting (its logs show the master electing a leader after the port is open), so the bucket job could race it. |
| `image: amazon/aws-cli:2.41.1` | The **real AWS command-line tool**, pinned, as the client. | Another client (MinIO's `mc`) is no longer available as an image. |
| `AWS_DEFAULT_REGION: us-east-1` | The region the CLI signs its requests for. Set explicitly so the job does not depend on any default configuration (the lab server accepts it). | Without it the CLI may stop with a "region" error, depending on the command. |
| `entrypoint: [sh, -c]` and the `command:` script | The image's entrypoint is `aws`; we replace it with a shell so one container can run "check, then create". `$$` is a literal `$` for Compose, so the **container's** shell expands the variable. | Keeping `aws` as entrypoint cannot do "check then create". |
| `--endpoint-url http://s3:8333` | Tells the CLI to talk to our server instead of `amazonaws.com`. This one option is the whole difference between real AWS and the lab. | Without it the CLI would try to reach real AWS with fake keys. |
| `s3api head-bucket ... && echo ... \|\| aws s3 mb ...` | "If the bucket exists, say so; otherwise create it." Makes the job **idempotent**: safe to run on every `up`. | A bare `s3 mb` fails on the second run, which would stop services that wait for the job. |
| `depends_on: s3: service_healthy` and `restart: "no"` | Start only when the store is healthy; run once and stay finished. | Without the wait the job races the store start. |

**Check the file first.** Before the two variables are in `.env` (or the shell), you get:
```bash
docker compose config -q
```
```text
error while interpolating services.s3-init.environment.AWS_ACCESS_KEY_ID: required variable S3_ACCESS_KEY is missing a value: set S3_ACCESS_KEY in .env (see .env.example)
```
(In the runs below the two variables were set in the shell for the session, with throw-away fake values, so `.env` was not touched.)

Start the stack and look at the result:
```bash
docker compose up -d                       # add LB_HOST_PORT=8081 in front if port 80 is busy
docker compose ps -a --format 'table {{.Service}}\t{{.Status}}\t{{.Ports}}'
```
```text
SERVICE    STATUS                     PORTS
api        Up 53 minutes (healthy)    8000/tcp
lb         Up 53 minutes (healthy)    127.0.0.1:8081->80/tcp
migrate    Exited (0) 8 seconds ago
postgres   Up 53 minutes (healthy)    5432/tcp
redis      Up 46 minutes (healthy)    6379/tcp
s3         Up 11 seconds (healthy)    7333/tcp, 8080/tcp, 8333/tcp, 8888/tcp, 9333/tcp, 18080/tcp, 18888/tcp, 19333/tcp
s3-init    Exited (0) 3 seconds ago
```
(Two of the three `api` rows left out.) `s3` is **healthy** and publishes nothing: the ports without an arrow are "exposed inside Docker only". `s3-init` is `Exited (0)`: the job ran and succeeded, like `migrate`.

**Check 1 — the step's check: the bucket exists.** The first line is the job's own log; the second command lists buckets with the real AWS CLI, from a throw-away container on the same network:
```bash
docker compose logs s3-init
docker compose run --rm --no-deps --entrypoint aws s3-init --endpoint-url http://s3:8333 s3 ls
```
```text
make_bucket: uploads
2026-11-19 14:31:21 uploads
```
`make_bucket: uploads` is the job creating the bucket; `s3 ls` (list buckets) shows `uploads` with its creation date. `--no-deps` keeps Compose from starting the other services, and `--entrypoint aws` puts the image's normal command back.

**Check 2 — the job is safe to run again:**
```bash
docker compose up s3-init
```
```text
s3-init-1  | bucket uploads already exists
s3-init-1 exited with code 0
```
The check found the bucket, so nothing was created and the job still succeeded (exit code 0).

**Check 3 — it is private, and the keys are required:**
```bash
docker compose port s3 8333
timeout 3 bash -c '</dev/tcp/127.0.0.1/8333' 2>/dev/null && echo "OPEN on host" || echo "127.0.0.1:8333 closed"
docker compose run --rm --no-deps -e AWS_SECRET_ACCESS_KEY=wrong --entrypoint aws s3-init --endpoint-url http://s3:8333 s3 ls
```
```text
:0
127.0.0.1:8333 closed
aws: [ERROR]: An error occurred (SignatureDoesNotMatch) when calling the ListBuckets operation: The request signature we calculated does not match the signature you provided. Check your key and signing method.
```
`:0` means no published port, and the host cannot connect. The third command is the same listing with a **wrong secret key**: the server refuses it with `SignatureDoesNotMatch`. (In S3, every request is *signed* with the secret key; the server recomputes the signature with the secret it knows, and the two must match. The secret itself is never sent.)

**Check 4 — the files survive a new container.** Upload a small object, re-create the `s3` container (a new container on the **same volume**), and read it back:
```bash
echo "hello from the lab" | docker compose run --rm --no-deps -T --entrypoint aws s3-init --endpoint-url http://s3:8333 s3 cp - s3://uploads/hello.txt
docker compose up -d --force-recreate s3
docker compose run --rm --no-deps -T --entrypoint aws s3-init --endpoint-url http://s3:8333 s3 ls s3://uploads
docker compose run --rm --no-deps -T --entrypoint aws s3-init --endpoint-url http://s3:8333 s3 cp s3://uploads/hello.txt -
docker volume ls --format '{{.Name}}' | grep s3data
```
```text
 Container aws-local-lab-s3-1 Recreate
 Container aws-local-lab-s3-1 Recreated
 Container aws-local-lab-s3-1 Started
2026-11-19 14:31:47         19 hello.txt
hello from the lab
aws-local-lab_s3data
```
(The upload printed nothing in this capture; the listing after the re-creation is the proof.) The container was replaced, yet `hello.txt` (19 bytes) is still there with its content: the data lives in the volume `aws-local-lab_s3data`, not in the container. The test object was deleted afterwards with `aws s3 rm`.

**Regression check — the whole suite:**
```bash
make test                                  # add LB_HOST_PORT=8081 in front if port 80 is busy
```
```text
== tests/02_failover.sh
02_failover: all checks passed
== tests/02_load_balancing.sh
02_load_balancing: all checks passed
== tests/03_network_isolation.sh
03_network_isolation: all checks passed
== tests/04_persistence.sh
04_persistence: all checks passed
== tests/05_cache.sh
05_cache: all checks passed
```
(Trimmed to the summary lines; `make` exited with code 0.)

**What just happened:**
- You added the architecture's "S3": an object store on the private network, behind access keys, with its data in a volume.
- You met the **bootstrap job** pattern for the second time (after `migrate`): one-shot, idempotent, and other services can wait for it. Real deployments create buckets the same way, from a pipeline or infrastructure-as-code.
- You used the **real AWS CLI** against a local server. Only `--endpoint-url` differs from what you would type against AWS, which is why the same boto3 code will work in step 19.
- The store is a stand-in, not S3: it has no regions, replication or IAM policies, and a single container with a single volume is a single point of failure.

### Step 19 — `POST /upload` and the presigned URL
**Why:** the bucket exists, but nothing uses it. This step teaches the API to accept a file, store it in the bucket with the S3 SDK (**boto3**, the same library you would use against real AWS) and answer with the object's **key** and a **presigned URL**: a temporary download link that works without credentials.

**What is a presigned URL?** The bucket is private, so downloading an object needs the secret key. But you do not want to hand the secret to a browser. Instead the API **signs** a URL: it computes a signature from the secret key, the object, the expiry time and the address, and puts it in the URL's query string. Whoever holds that URL can download **that one object** until it expires; the secret never leaves the API, and changing any part of the URL breaks the signature.

**Do it.** Four small changes.

1. Two new libraries, `api/requirements.txt` (the second is what FastAPI needs to read file uploads, which arrive as `multipart/form-data`):
   ```text
   boto3==1.44.6
   python-multipart==0.0.34
   ```

2. Give the API the endpoint, the bucket and the keys, and make it wait for the bucket, in `docker-compose.yml` (`api` service; only the new lines are shown):
   ```yaml
     api:
       environment:
         # ... existing variables unchanged ...
         # The object store (like an S3 endpoint plus an IAM user) and the bucket the API writes to.
         S3_ENDPOINT_URL: http://s3:8333
         S3_BUCKET: ${S3_BUCKET:-uploads}
         S3_ACCESS_KEY: ${S3_ACCESS_KEY:?set S3_ACCESS_KEY in .env (see .env.example)}
         S3_SECRET_KEY: ${S3_SECRET_KEY:?set S3_SECRET_KEY in .env (see .env.example)}
       depends_on:
         # ... migrate and redis unchanged ...
         # ... and once the bucket exists.
         s3-init:
           condition: service_completed_successfully
   ```

3. The upload route in `api/main.py`. New imports at the top (merge with the existing ones):
   ```python
   import re
   from uuid import uuid4

   import boto3
   from botocore.config import Config
   from botocore.exceptions import BotoCoreError, ClientError
   from fastapi import Depends, FastAPI, File, HTTPException, Response, UploadFile, status
   ```
   The S3 client, after the `CACHE_TTL = ...` line:
   ```python
   # Object storage (S3 in AWS). Same boto3 code as against real AWS: only the endpoint differs.
   # "path" addressing = http://s3:8333/<bucket>/<key>; real S3 uses <bucket>.s3.amazonaws.com, which a
   # container name cannot imitate.
   S3_BUCKET = os.environ["S3_BUCKET"]
   s3 = boto3.client(
       "s3",
       endpoint_url=os.environ["S3_ENDPOINT_URL"],
       aws_access_key_id=os.environ["S3_ACCESS_KEY"],
       aws_secret_access_key=os.environ["S3_SECRET_KEY"],
       region_name="us-east-1",
       config=Config(
           signature_version="s3v4",
           s3={"addressing_style": "path"},
           connect_timeout=2,
           read_timeout=5,
           retries={"max_attempts": 1},
       ),
   )
   MAX_UPLOAD_BYTES = 5 * 1024 * 1024
   PRESIGN_SECONDS = int(os.environ.get("PRESIGN_SECONDS", "300"))
   ```
   The answer model, before `get_note_or_404`:
   ```python
   class UploadOut(BaseModel):
       key: str
       size: int
       content_type: str
       url: str  # a presigned GET link: valid for expires_in seconds, no credentials needed
       expires_in: int
   ```
   And the route, at the end of the file:
   ```python
   @app.post("/upload", response_model=UploadOut, status_code=status.HTTP_201_CREATED)
   def upload(file: Annotated[UploadFile, File()]):
       """Store the file in the bucket and answer with its key and a temporary download link."""
       data = file.file.read(MAX_UPLOAD_BYTES + 1)
       if len(data) > MAX_UPLOAD_BYTES:
           raise HTTPException(status_code=413, detail=f"file too large (max {MAX_UPLOAD_BYTES} bytes)")
       # The client's file name is untrusted: keep letters, digits, dot, dash, underscore only.
       name = re.sub(r"[^A-Za-z0-9._-]", "_", os.path.basename(file.filename or "file"))[:100]
       key = f"originals/{uuid4().hex}-{name}"  # the uuid makes the key unique: no overwriting
       content_type = file.content_type or "application/octet-stream"
       try:
           s3.put_object(Bucket=S3_BUCKET, Key=key, Body=data, ContentType=content_type)
           url = s3.generate_presigned_url(
               "get_object", Params={"Bucket": S3_BUCKET, "Key": key}, ExpiresIn=PRESIGN_SECONDS
           )
       except (BotoCoreError, ClientError) as exc:
           log.error("storage error on %s: %s", key, exc)
           raise HTTPException(status_code=502, detail="object storage unavailable")
       log.info("uploaded %s (%s bytes)", key, len(data))
       return UploadOut(key=key, size=len(data), content_type=content_type, url=url, expires_in=PRESIGN_SECONDS)
   ```

4. Let the load balancer pass bigger bodies, in `lb/nginx.conf` (inside `server { ... }`, after `listen 80;`). Why is explained in Check 5 below:
   ```nginx
           # Nginx refuses request bodies over 1 MB by default (413). The API accepts uploads up to
           # 5 MB (MAX_UPLOAD_BYTES in api/main.py); a little more here for the multipart overhead.
           client_max_body_size 6m;
   ```

| Line | What it does | If you change or remove it |
|---|---|---|
| `boto3==1.44.6` / `python-multipart==0.0.34` | The AWS SDK for Python, and the parser FastAPI uses for `multipart/form-data` bodies. Pinned. | Without `python-multipart`, FastAPI refuses to start a route that takes a file. |
| `S3_ENDPOINT_URL: http://s3:8333` | The address of the S3 API: the service name `s3` (Docker DNS, see [Networking 02](../courses/networking/02-dns.md)). | Remove it and boto3 talks to the real `amazonaws.com` with fake keys. |
| `depends_on: s3-init: service_completed_successfully` | The API starts after the bucket job exited with code 0. | Without it a very early upload could find no bucket. |
| `boto3.client("s3", endpoint_url=..., aws_access_key_id=..., ...)` | One client for the whole process, created at start-up. The keys come from the environment, never from the code. | Keys written in the code would end up in git. |
| `signature_version="s3v4"` | The current signing method (**Signature Version 4**), used by real S3 and by the lab server. | An old signing method may be rejected. |
| `s3={"addressing_style": "path"}` | The bucket goes in the **path** (`http://s3:8333/uploads/...`), not in the host name. Real S3 uses the host name (`uploads.s3.amazonaws.com`), which a container name cannot imitate. | With the default style boto3 may try `http://uploads.s3:8333`, a host name that does not exist. |
| `connect_timeout=2, read_timeout=5, retries={"max_attempts": 1}` | A dead store makes the request fail after a few seconds, not a minute (same idea as the cache's 1-second timeouts). | Default values wait much longer and retry several times. |
| `MAX_UPLOAD_BYTES` and `file.file.read(MAX + 1)` | Reads at most one byte more than allowed: if that extra byte is there, the file is too big (`413`). | Without a limit one client could fill the API's memory. |
| `re.sub(r"[^A-Za-z0-9._-]", "_", os.path.basename(...))` | Keeps only safe characters in the file name and drops any directory part. | Keys built from raw names could contain `../` or odd characters. |
| `key = f"originals/{uuid4().hex}-{name}"` | A unique key per upload: a random id plus the cleaned name. The `originals/` prefix groups the files (step 24 will put thumbnails elsewhere). | A key made only from the file name would overwrite an earlier upload with the same name. |
| `put_object(...)` | Stores the bytes under the key, with the content type. | Without `ContentType` the object would be served as a generic binary. |
| `generate_presigned_url("get_object", ..., ExpiresIn=300)` | Builds the signed link, valid 300 seconds. **No network call**: it is computed locally from the secret key. | A long expiry means a leaked link works for longer. |
| `except (BotoCoreError, ClientError)` → `502` | Any storage problem becomes a clean `502`, with the details in the log, not in the answer. | Without it a stopped store would give the client an ugly `500`. |
| `client_max_body_size 6m;` | Nginx's limit for a request body (default 1 MB). 6 MB leaves room above the API's 5 MB. | At the default, any file over about 1 MB is refused by Nginx before the API sees it. |

**Rebuild and restart:**
```bash
docker compose up -d --build                  # add LB_HOST_PORT=8081 in front if port 80 is busy
docker compose exec -T lb nginx -s reload     # only needed when you change nginx.conf alone
```
(The first command re-creates the three `api` containers with the new image and waits for `s3-init` to have finished.)

**Check 1 — the step's check: upload returns a key and a URL.**
```bash
echo "hello from the upload test" > hello.txt
curl -s -w '\n[HTTP %{http_code}]\n' -F "file=@hello.txt;type=text/plain" localhost:8081/upload
```
```text
{"key":"uploads/ff7d5231be0148e4912ad1374dae5f33-hello.txt","size":27,"content_type":"text/plain","url":"http://s3:8333/uploads/uploads/ff7d5231be0148e4912ad1374dae5f33-hello.txt?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=lab-access-key%2F20261119%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20261119T145008Z&X-Amz-Expires=300&X-Amz-SignedHeaders=host&X-Amz-Signature=4e5776fea9f8f6ccea3e34f980450c841922405b69e0db61469d2cf5695d45a9","expires_in":300}
[HTTP 201]
```
`-F "file=@hello.txt"` sends the file as a multipart form field named `file`. The answer is `201 Created` with the object's key and the URL. (This run was made **before** the key prefix was renamed from `uploads/` to `originals/`: the repeated `uploads/uploads/` in the path, bucket then prefix, is why the prefix was changed; the code above is the final version.) Read the URL:

| Part of the URL | Meaning |
|---|---|
| `http://s3:8333/uploads/<key>` | endpoint, then bucket, then key (path-style) |
| `X-Amz-Algorithm=AWS4-HMAC-SHA256` | the signing method (Signature Version 4) |
| `X-Amz-Credential=lab-access-key/20261119/us-east-1/s3/aws4_request` | **who** signed (the access key id, never the secret), the date and the scope |
| `X-Amz-Expires=300` | the link is valid for 300 seconds |
| `X-Amz-SignedHeaders=host` | the signature covers the `Host` header |
| `X-Amz-Signature=...` | the signature itself |

The host in the URL is `s3`, a name that only exists **inside** Docker. So this link works from other containers but not yet from your browser: making it work from the host is [step 20](#step-20--a-public-s3-address-s3localhost-through-the-load-balancer).

**Check 2 — the link really downloads the object (from inside the private network), and the bytes match.** A throw-away container on the lab network fetches the URL; for a binary file the SHA-256 checksums are compared:
```bash
# the 27-byte text file, with the final code (key prefix "originals/")
docker run --rm --network aws-local-lab_private alpine:3.24 wget -qO- "$URL"
# a 200,000-byte random file
head -c 200000 /dev/urandom > rnd.bin
curl -s -F "file=@rnd.bin" localhost:8081/upload        # note the "url" field, put it in $URL2
sha256sum rnd.bin | cut -c1-16
docker run --rm --network aws-local-lab_private alpine:3.24 sh -c "wget -qO- '$URL2' | sha256sum" | cut -c1-16
```
```text
hello from the upload test
originals/20ba04a0d9c24b4e81396c86d516419f-rnd.bin 200000 application/octet-stream
17ff2c737f957c74
17ff2c737f957c74
```
(`$URL` and `$URL2` are the `url` values of the two uploads; the key line comes from a small Python snippet that printed the answer's fields, and the checksums are cut to 16 characters.) The text comes back unchanged, and the two checksums are **identical**: the object in the bucket is byte for byte the file you uploaded. `application/octet-stream` is the content type curl sends for a file it cannot recognise.

**Check 3 — the signature protects the object:**
```bash
docker run --rm --network aws-local-lab_private alpine:3.24 wget -S -qO- "<the URL with its last character changed>"
docker run --rm --network aws-local-lab_private alpine:3.24 wget -S -qO- "<the URL without the query string>"
```
```text
  HTTP/1.1 403 Forbidden
wget: server returned error: HTTP/1.1 403 Forbidden
  HTTP/1.1 403 Forbidden
wget: server returned error: HTTP/1.1 403 Forbidden
```
A link with a **modified signature**, and the plain object address **without** any signature, are both refused with `403 Forbidden`. Only the exact signed URL works: that is what makes a presigned URL safe to hand out.

**Check 4 — bad input.**
```bash
curl -s -w ' [HTTP %{http_code}]\n' -X POST localhost:8081/upload -F "other=x"
curl -s -F 'file=@hello.txt;filename=../../etc/pass wd.txt' localhost:8081/upload     # a hostile file name
```
```text
{"detail":[{"type":"missing","loc":["body","file"],"msg":"Field required","input":null}]} [HTTP 422]
originals/f966e2ac0dfb4a6f873a5cdef68d9403-pass_wd.txt
```
A request without the `file` field gets `422` from FastAPI's validation. The hostile name `../../etc/pass wd.txt` was stored as `pass_wd.txt`: the directory part is dropped and the space becomes `_`. (The second line is the `key` of the answer, extracted.)

**Check 5 — two size limits, one in front of the other.** With files of 2,000,000, 6,000,000 and 7,000,000 bytes:
```bash
curl -s -w ' [HTTP %{http_code}]\n' -F "file=@six.bin" localhost:8081/upload
curl -s -o /dev/null -w '[HTTP %{http_code}]\n' -F "file=@seven.bin" localhost:8081/upload
```
```text
--- 2 MB
{"key":"originals/3bc1561151594d7ab52aa56b6a2ecc73-two.bin","size":2000000,"cont ...  [HTTP 201]
--- 6 MB (6,000,000 bytes: passes nginx, over the API limit)
{"detail":"file too large (max 5242880 bytes)"} [HTTP 413]
--- 7 MB (over nginx limit)
[HTTP 413]
```
(The 2 MB line is cut after 80 characters: the answer was the usual `201` with key and URL. The `---` labels were added with `echo`.) The 6 MB file reaches the API, which refuses it with its own JSON message. The 7 MB file never reaches the API: **Nginx** answers `413` first (an HTML page, not JSON). The same `413` code, two different layers: the answer's body tells you which. Before the `client_max_body_size` line was added, the **2 MB** file was also refused by Nginx (`413 Request Entity Too Large`, with `nginx/1.30.6` in the page): the default limit is 1 MB.

**Check 6 — the store goes away, the API keeps working.**
```bash
docker compose stop s3
curl -s -m 20 -w ' [HTTP %{http_code}]\n' -F "file=@hello.txt" localhost:8081/upload
curl -s -o /dev/null -w 'GET /notes [HTTP %{http_code}]\n' localhost:8081/notes
docker compose logs api | grep "storage error" | tail -1
docker compose start s3
```
```text
{"detail":"object storage unavailable"} [HTTP 502]
GET /notes [HTTP 200]
api-2  | ERROR:    storage error on originals/7fce4e8b19f64eedbc86418d5f0e0295-hello.txt: Could not connect to the endpoint URL: "http://s3:8333/uploads/originals/7fce4e8b19f64eedbc86418d5f0e0295-hello.txt"
```
With the store stopped, the upload fails fast with a clean `502` (details only in the log), while the other routes keep working. (Right after `docker compose start s3` the first upload also answered `502`; the next attempt, a few seconds later, was `201`: see Troubleshooting.)

**Regression check — the whole suite:**
```bash
make test                                 # add LB_HOST_PORT=8081 in front if port 80 is busy
```
```text
== tests/02_failover.sh
02_failover: all checks passed
== tests/02_load_balancing.sh
02_load_balancing: all checks passed
== tests/03_network_isolation.sh
03_network_isolation: all checks passed
== tests/04_persistence.sh
04_persistence: all checks passed
== tests/05_cache.sh
05_cache: all checks passed
```
(Trimmed to the summary lines; `make` exited with code 0.) The test objects were deleted afterwards with `aws s3 rm s3://uploads --recursive`.

**What just happened:**
- The API can now **write to S3**, with the same boto3 code you would use in production: only `endpoint_url` and the path-style option are specific to the lab.
- You generated a **presigned URL** and saw that it carries its own proof (the signature) and its own deadline (`X-Amz-Expires`); the secret key stays inside the API.
- Uploads are **untrusted input**: the size is capped (twice, at Nginx and in the API), the file name is cleaned and the key is generated, not chosen by the client.
- Storage is a **soft dependency of one route**: if it fails, `POST /upload` answers `502` and everything else keeps working.
- Two limits of this step, on purpose left for later: FastAPI has already received (and, for big bodies, spooled to a temporary file) the whole upload **before** the route runs, so the `read(MAX + 1)` check protects the object store but not the API's memory or disk; the **Nginx 6 MB limit** is the real cap on how much one request can bring. And the client's `Content-Type` is stored as sent, so a file declared `text/html` would be served as HTML: step 20 now lets browsers open these URLs, so before exposing this beyond your laptop, consider forcing a download (`ResponseContentDisposition=attachment` when signing) or an allow-list of types.
- The URL is signed for the host `s3`, so only containers can use it. [Step 20](#step-20--a-public-s3-address-s3localhost-through-the-load-balancer) fixes that.

### Step 20 — A public S3 address, `s3.localhost`, through the load balancer
**Why:** the link from step 19 starts with `http://s3:8333/...`. The name `s3` only exists inside Docker, so your browser cannot open it. In AWS the same problem does not exist: the bucket is reachable at a public name (`<bucket>.s3.amazonaws.com`) that anyone can resolve, and the signature is made for that name. Here we give the object store a **second, public name** that goes through the load balancer, and we make the API sign links for *that* name.

**Two ideas first.**
1. **Name-based routing.** One Nginx on one port can serve several "sites": it reads the `Host` header of each request (see [Networking 03](../courses/networking/03-http.md)) and picks the `server` block whose `server_name` matches. `s3.localhost` goes to the object store, everything else goes to the API. (`*.localhost` names always point at your own machine, so there is nothing to add to a hosts file; `curl` resolved it on its own here.)
2. **A presigned URL signs the host.** In step 19 you saw `X-Amz-SignedHeaders=host`: the signature is computed over the `Host` the client will send. If the API signs for `s3:8333` and the client then calls `s3.localhost`, the server recomputes the signature with a different host and rejects it. So the API must sign for the address the *client* will use, and Nginx must pass the `Host` header on **unchanged**.

```mermaid
sequenceDiagram
  participant B as You (curl / browser)
  participant LB as lb (Nginx)
  participant API as api
  participant S3 as s3 (SeaweedFS)
  B->>LB: POST /upload (Host: localhost)
  LB->>API: forwarded (default_server block)
  API->>S3: put_object via http://s3:8333 (inside Docker)
  API-->>B: key + URL signed for http://s3.localhost
  B->>LB: GET /uploads/... (Host: s3.localhost)
  LB->>S3: same request, Host unchanged (s3.localhost block)
  S3-->>B: the bytes (signature checked against the Host)
```

**Do it.** Three small changes.

1. Add the object store as an upstream and a second `server` block, in `lb/nginx.conf` (inside `http { ... }`, before the existing `server`), and mark the existing block `default_server`:
   ```nginx
       # The object store, reachable by service name like the API (same Docker DNS trick).
       upstream s3 {
           zone s3 64k;
           resolver 127.0.0.11 valid=5s;
           server s3:8333 resolve;
       }

       # Public S3 endpoint: requests for the host name s3.localhost go to the object store, so that a
       # presigned URL works from your machine. Nginx picks the server block by the Host header.
       server {
           listen 80;
           server_name s3.localhost;

           location / {
               # Read-only door: presigned download links only need GET and HEAD.
               limit_except GET HEAD {
                   deny all;
               }
               proxy_pass http://s3;
               # Keep the Host header exactly as the client sent it (with its port, if any): the
               # signature of a presigned URL covers it, and the store refuses the request if it changes.
               proxy_set_header Host $http_host;
           }
       }

       server {
           # default_server: every Host that is not s3.localhost (localhost, 127.0.0.1, ...) lands here.
           listen 80 default_server;
           # ... rest of the API server block unchanged ...
   ```

2. Give the API the public address, in `docker-compose.yml` (`api` service, right under `S3_ENDPOINT_URL`):
   ```yaml
         # The address clients outside Docker use (through the load balancer): presigned links are signed
         # for it. If you change LB_HOST_PORT from 80, add the port here, for example http://s3.localhost:8080.
         S3_PUBLIC_ENDPOINT_URL: ${S3_PUBLIC_ENDPOINT_URL:-http://s3.localhost}
   ```

3. Sign with a second client, in `api/main.py`. The client of step 19 becomes a small function used twice (replace the `s3 = boto3.client(...)` block):
   ```python
   S3_BUCKET = os.environ["S3_BUCKET"]


   def make_s3_client(endpoint_url: str):
       return boto3.client(
           "s3",
           endpoint_url=endpoint_url,
           aws_access_key_id=os.environ["S3_ACCESS_KEY"],
           aws_secret_access_key=os.environ["S3_SECRET_KEY"],
           region_name="us-east-1",
           config=Config(
               signature_version="s3v4",
               s3={"addressing_style": "path"},
               connect_timeout=2,
               read_timeout=5,
               retries={"max_attempts": 1},
           ),
       )


   # Two addresses for the same store. The API reaches it inside the private network (http://s3:8333),
   # but a browser on your machine cannot resolve "s3": the link we hand out must use the public name
   # (http://s3.localhost, served by the load balancer). A presigned URL signs the host name, so it has
   # to be created for the address the client will really call. Signing is local maths: no network call.
   s3 = make_s3_client(os.environ["S3_ENDPOINT_URL"])
   s3_public = make_s3_client(os.environ.get("S3_PUBLIC_ENDPOINT_URL", os.environ["S3_ENDPOINT_URL"]))
   ```
   In the `upload` route only the signing line changes: `url = s3_public.generate_presigned_url(` (the `put_object` above it still uses `s3`).

| Line | What it does | If you change or remove it |
|---|---|---|
| `upstream s3 { ... server s3:8333 resolve; }` | The "target group" of the object store, found by Docker DNS like `api`. | Without it, `proxy_pass` has nothing to point at. |
| `server_name s3.localhost;` | This block answers only requests whose `Host` is `s3.localhost`. | Remove it and this block (the first in the file) would also catch requests meant for the API. |
| `limit_except GET HEAD { deny all; }` | Every method except GET and HEAD gets `403`: this public door is download-only. | Without it, other methods (`PUT`, `DELETE`, ...) would be passed on to the store, which would then judge them by their signature alone. |
| `proxy_set_header Host $http_host;` | Sends the request on with the `Host` exactly as received (including `:8088` when there is a port). | With the default (the upstream's own address, `s3:8333`) the store sees another host than the signed one: `SignatureDoesNotMatch`. `$host` would also break it when a port is used: it drops the port. |
| `listen 80 default_server;` | Says which block serves requests that match no `server_name`. | Without it the **first** block of the file is the default: see the first row of the Troubleshooting table below. |
| `S3_PUBLIC_ENDPOINT_URL` | The address put in the links; defaults to `http://s3.localhost`. | If it does not match what the client really types (port included), the link points to a closed port or fails the signature. |
| `make_s3_client(...)` and the two clients | One client talks to the store (`s3`), one only signs (`s3_public`). | With a single client on `http://s3:8333`, the links are the unusable ones of step 19. |

**Rebuild and restart.** On this machine port 80 was taken by another project's container, and 8080 refused the bind (see Troubleshooting), so the checks below run on **8088**, and the public address says so:
```bash
export LB_HOST_PORT=8088 S3_PUBLIC_ENDPOINT_URL=http://s3.localhost:8088   # leave both out if port 80 is free
docker compose up -d --build --wait
docker compose exec lb nginx -t
```
```text
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```
(`nginx -t` checks the file without applying it. After a change to `nginx.conf` alone, `docker compose restart lb` applies it.)

**Check 1 — the step's check: upload, then download the presigned URL from the host, and compare the bytes.**
```bash
head -c 200000 /dev/urandom > blob.bin                    # random bytes: no way to match by luck
sha256sum blob.bin | cut -c1-16
curl -s -X POST -F "file=@blob.bin;type=application/octet-stream" localhost:8088/upload -o up.json -w 'upload: %{http_code}\n'
# put the "url" field of up.json in $URL, then:
curl -s -o down.bin -w '%{http_code}, %{size_download} bytes\n' "$URL"
sha256sum down.bin | cut -c1-16
cmp blob.bin down.bin && echo "bytes identical"
```
```text
cc36db0034aab472
upload: 201
{"key":"originals/5100e59fa6c440c7a79a6e68f39bac20-blob.bin","size":200000,"content_type":"application/octet-stream","url":"http://s3.localhost:8088/uploads/originals/5100e59fa6c440c7a79a6e68f39bac20-blob.bin?<signature params>" ...}
200, 200000 bytes
cc36db0034aab472
bytes identical
```
(The `url` is shortened here; its query string holds the six `X-Amz-*` parameters of step 19.) Compared with step 19, the host is now `s3.localhost:8088`, a name your machine can reach: the request goes *host → Nginx → s3* and the object comes back byte for byte (the two checksums are equal and `cmp` found no difference). The secret key never left the API.

**Check 2 — the signature still protects the object, through the new door.**
```bash
curl -s -w ' -> %{http_code}\n' "${URL%?}0"                 # last character of the signature changed
curl -s -o /dev/null -w '%{http_code}\n' "${URL%%\?*}"       # no query string: no signature
curl -s -o /dev/null -w '%{http_code}\n' -X PUT "$URL"       # a method other than GET / HEAD
```
```text
<?xml version="1.0" encoding="UTF-8"?>
<Error><Code>SignatureDoesNotMatch</Code><Message>The request signature we calculated does not match the signature you provided. Check your key and signing method.</Message><Resource>/uploads/originals/5100e59fa6c440c7a79a6e68f39bac20-blob.bin</Resource><Reques ...
403
403
```
A modified signature is rejected by the store (`SignatureDoesNotMatch`), the bare object address too (`403`), and a `PUT` is refused by **Nginx** itself (`403` from `limit_except`: it never reaches the store). The first output is cut after 300 characters.

**Check 3 — why the signing address matters.** Sign a link for the *internal* address, as step 19 did, and send it to the public door:
```bash
docker compose exec -T api python -c "import main; print(main.s3.generate_presigned_url('get_object', Params={'Bucket':'uploads','Key':'<the key>'}, ExpiresIn=60))"
# take that URL, replace "s3:8333" by "s3.localhost:8088" and curl it
```
```text
internal URL host: s3:8333
<Code>SignatureDoesNotMatch</Code>
```
(The first line was printed by a small `echo` of the URL's host.) Same object, same secret, same expiry, and a valid signature for the host `s3:8333`: it is still rejected, because the request arrives with another `Host`. That is the whole point of `S3_PUBLIC_ENDPOINT_URL`.

**Regression check — the rest of the lab still works:**
```bash
make test            # with LB_HOST_PORT=8088 exported
```
```text
03_network_isolation: all checks passed
04_persistence: all checks passed
05_cache: all checks passed
```
(Only the end of the `make test` output was kept, so `tests/02_load_balancing.sh` and `tests/02_failover.sh` were also run on their own: both ended with `all checks passed`. Requests with the default `Host` still reach the API: that is what `default_server` is for.)

**What just happened:**
- The object store now has a **public address**, `s3.localhost`, in front of which sits the same load balancer as the API. One entry point, two names: the `Host` header decides.
- A presigned URL is only valid for the **host it was signed for**. The API keeps two views of the store: an internal one to read and write, a public one to sign.
- The public door is **read-only** (`GET`/`HEAD`) and every link still carries its own signature and deadline.
- Compare with AWS: there is nothing to configure there, because `s3.amazonaws.com` is already public DNS; the lab has to recreate a public name and a route to get the same effect.

### Step 21 — The storage test
**Why:** steps 19 and 20 were checked by hand. A test turns those checks into one command that anyone (and you, in six months) can re-run, and that goes **red** when something breaks. It also keeps the promises that are easy to break by accident: the link must work from the host, a changed signature must be refused, a link signed for the wrong host must be refused. Like the other tests (`tests/02` to `tests/05`) it needs the lab to be up and finds the load balancer's port by itself with `docker compose port lb 80`.

**What the test does**, in order: upload 200,000 random bytes → check the key and that the URL uses the **public** host → download the URL **from the host** and compare SHA-256 checksums → refuse a changed signature, no signature, and a `PUT` → refuse a URL signed for the internal host → refuse bad input (no `file` field, a 6,000,000-byte file, a hostile file name). At the end it deletes its own objects from the bucket.

**Do it:** create `tests/06_storage.sh` (the whole file):
```bash
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
```

| Line(s) | What it does | If you change or remove it |
|---|---|---|
| `set -u`, `ok()` / `bad()`, `fail=0` | Same helpers as the other tests: `PASS`/`FAIL` lines, and a final exit code that is `1` if any check failed. | Without `fail`, a failed check would still end with exit code 0 and `make test` would stay green. |
| `addr=$(docker compose port lb 80)` | Asks Compose where the load balancer is published, so the test follows `LB_HOST_PORT` without reading `.env`. | A hard-coded `localhost:80` breaks as soon as you change the port. |
| `tmp=$(mktemp -d)`, `in_tmp`, relative file names | Works in a temporary folder and gives `curl` **relative** names: the Windows `curl.exe` cannot read Git Bash paths like `/tmp/x` (Troubleshooting). | With `-F "file=@$tmp/blob.bin"` the upload fails with `curl: (26)`. |
| `field() { sed ... }` | Pulls one string field out of the JSON answer (`key`, `url`), like the other tests do for `id`. No `jq` needed. | |
| `head -c 200000 /dev/urandom`, `sha256sum` | Random bytes cannot match by luck; the checksum identifies them exactly. | A text file such as `hello` could hide a mix-up that only shows on binary data. |
| `case "$public_base" in http://s3.localhost*)` | Fails with a hint if the URL still carries the Docker-only host. | Without it, a wrong `S3_PUBLIC_ENDPOINT_URL` only shows up as a confusing download error. |
| `curl ... "$link"` then `sha256sum` | The real check of the step: the host downloads the object with only the URL and gets the same bytes. | |
| `last=${link: -1}` ... `${link%?}$new` | Changes the last character of the URL (the signature) to a different one. | Always writing `0` would not change a signature that already ends in `0`. |
| `${link%%\?*}` | The URL without its query string: the object address with no signature. | |
| `-X PUT "$link"` | A method the public door does not allow: Nginx's `limit_except` answers `403`. | |
| `docker compose exec -T api python -c "... main.s3.generate_presigned_url ..."` | Builds a link signed for `http://s3:8333` with the API's own client, then sends it to the public host. | Without this check nobody would notice if the API went back to signing with one client for both addresses. |
| `-F "other=x"`, `big.bin`, `filename=../../etc/pass wd.txt` | The three bad inputs of step 19: `422`, the API's own `413` (6,000,000 bytes pass Nginx's 6 MB but not the API's 5 MB limit) and a cleaned file name. | |
| `trap cleanup EXIT`, `keys=()`, `docker compose run --rm --no-deps -T --entrypoint sh s3-init ...` | Whatever happens, deletes the test objects with the AWS CLI of the `s3-init` service (same endpoint and keys) and the temporary folder. | Every run would leave objects in the bucket. |

**Run it:**
```bash
bash tests/06_storage.sh
```
```text
Lab 06 - object storage (http://127.0.0.1:8088)
  PASS  POST /upload: 201, key originals/accd2059d54640acae3f7eb8067bf26b-blob.bin
  PASS  the key is under the originals/ prefix
  PASS  the URL points at the public endpoint (http://s3.localhost:8088)
  PASS  GET of the presigned URL from the host: 200
  PASS  downloaded bytes are identical (sha256 fff9073ed1a34505...)
  PASS  a modified signature is refused (403)
  PASS  the object address without a signature is refused (403)
  PASS  PUT on the public door is refused by the load balancer (403)
  PASS  a URL signed for s3:8333 is refused on http://s3.localhost:8088 (403)
  PASS  upload without the 'file' field: 422
  PASS  a 6,000,000-byte file: 413 from the API (over its 5 MB limit)
  PASS  hostile file name cleaned: originals/c260a1efa4cb42f6bfeb26bed34a0b63-pass_wd.txt
06_storage: all checks passed
```
The run took about 8 seconds (`time`: `real 0m8.395s`). Afterwards the bucket holds none of the test's objects (`aws s3 ls` through `s3-init`, see Clean up).

**Make it fail on purpose** (a test that cannot fail proves nothing). Make the API sign for the internal name again, then run the test:
```bash
S3_PUBLIC_ENDPOINT_URL=http://s3:8333 docker compose up -d --wait api
sleep 8                                  # let Nginx pick up the new API addresses (see Troubleshooting)
bash tests/06_storage.sh
```
```text
  PASS  POST /upload: 201, key originals/75a5c4e2f93c4166aa717a14399045c6-blob.bin
  FAIL  the URL host is 'http://s3:8333': set S3_PUBLIC_ENDPOINT_URL (with the port of LB_HOST_PORT)
  FAIL  GET of the presigned URL: expected 200, got 000
  FAIL  checksum differs: d127ec44a3e2b7d1 vs 
  FAIL  modified signature: expected 403, got 000
  FAIL  no signature: expected 403, got 000
  FAIL  PUT: expected 403, got 000
  FAIL  URL signed for the wrong host: expected 403, got 000
06_storage: FAILED
```
(Lines filtered to `FAIL` and the upload line.) Seven checks go red, and the first one says what to fix. `000` means curl could not connect at all: the host `s3` does not exist on your machine. Put it back (`docker compose up -d --wait api` without the variable, wait a few seconds) and the test is green again.

**Regression check, the step's check: `make test`:**
```bash
make test
```
```text
== tests/02_failover.sh
02_failover: all checks passed
== tests/02_load_balancing.sh
02_load_balancing: all checks passed
== tests/03_network_isolation.sh
03_network_isolation: all checks passed
== tests/04_persistence.sh
04_persistence: all checks passed
== tests/05_cache.sh
05_cache: all checks passed
== tests/06_storage.sh
06_storage: all checks passed
```
(Lines filtered to the headings and the summaries; `make` exited with code 0. `make test` runs every `tests/*.sh`, so the new file was picked up without touching the Makefile.)

**What just happened:**
- The lab now has a **repeatable proof** that storage works end to end **from the outside**: not "the API says it stored the file" but "a client with only a URL got the same bytes back".
- The test checks the **refusals** as much as the success: a storage feature that also serves the wrong requests is a security bug.
- The test cleans up after itself, so you can run it as often as you like.
- It would not catch everything: it does not wait for a link to **expire** (300 s; see the exercises), and it does not check the `Content-Type` the object is served with (see "What this lab does not simulate").

## 5. Verify it works
With the lab up (`make up`; if port 80 is busy, set `LB_HOST_PORT` **and** `S3_PUBLIC_ENDPOINT_URL` in `.env`, for example `8088` and `http://s3.localhost:8088`):
```bash
make test
```
All six scripts must print `all checks passed`, and `make` must exit with code 0. To look by hand as well (replace `8088` by your port):
```bash
docker compose ps --format 'table {{.Service}}\t{{.Status}}'                          # api x3, lb, postgres, redis, s3: healthy; s3-init and migrate: exited
curl -s -F "file=@some.png" localhost:8088/upload                                     # key + a url on s3.localhost
curl -s -o out.png "<the url>" && cmp some.png out.png && echo identical              # the host downloads it with the URL alone
docker compose run --rm --no-deps -T --entrypoint sh s3-init -c 'aws --endpoint-url http://s3:8333 s3 ls "s3://$S3_BUCKET/" --recursive'   # the object is in the bucket
docker compose port s3 8333                                                           # prints :0, the store has no published port
```
(In PowerShell, write `curl.exe`.)

## 6. Troubleshooting
| Symptom | Cause | Fix |
|---|---|---|
| `no such manifest: quay.io/minio/minio:latest` (also `...:RELEASE.2025-09-07T16-13-09Z`), and `denied: requested access to the resource is denied` for `minio/minio` on Docker Hub | MinIO stopped publishing community container images and archived the project. | Use another S3-compatible server. This lab uses SeaweedFS (decision D5 in `PLAN.md`). |
| `Check Meta Folder (-mdir="C:/Program Files/Git/data") Writable: stat C:/Program Files/Git/data: no such file or directory` when running the image with `docker run ... server -dir=/data` from Git Bash | Git Bash rewrites an argument that looks like a Unix path (`/data`) into a Windows path before Docker sees it. Compose files are not affected. | Prefix the command with `MSYS_NO_PATHCONV=1`, or use `docker compose` with the path inside the YAML. |
| `required variable S3_ACCESS_KEY is missing a value` on **any** `docker compose` command | The S3 keys have no default and Compose checks the whole file. | Add `S3_ACCESS_KEY` and `S3_SECRET_KEY` to `.env` (section 3). |
| `502 object storage unavailable` for the **first** upload right after `docker compose start s3` (the next one, a few seconds later, works) | The `s3` container reports `healthy` slightly before the first upload can succeed; the exact cause was not investigated. | Retry after a few seconds. For a script, retry a few times with a pause. |
| `curl: (26)` and `HTTP 000` when uploading with `-F "file=@/tmp/hello.txt"` from Git Bash | The Windows `curl.exe` cannot read the Git Bash path `/tmp/...`: it is not a Windows path. | Run `curl` from the folder that holds the file and use a relative name (`-F "file=@hello.txt"`), or a Windows path. |
| `413 Request Entity Too Large` with a small HTML page that ends in `nginx/1.30.6`, for a file of 2 MB | Nginx's default `client_max_body_size` is 1 MB, below the API's 5 MB limit. A JSON `413` (`file too large`) comes from the API instead. | `client_max_body_size 6m;` in `lb/nginx.conf`, then `docker compose exec -T lb nginx -s reload`. |
| `SignatureDoesNotMatch` from the AWS CLI | The secret key used by the client is not the one the server was started with. | Use the same `S3_SECRET_KEY`. If you changed it in `.env`, run `docker compose up -d` again so `s3` restarts with the new value. |
| `lb` stays `unhealthy` and `curl localhost:<port>/health` answers `403 Forbidden` right after adding the `s3.localhost` block | Nginx uses the **first** `server` block of a port as the default for unknown `Host` values. The new `s3.localhost` block was written first, so `localhost` and `127.0.0.1` (the health check) were sent to it and refused. | Mark the API block `listen 80 default_server;`, then `docker compose restart lb`. |
| `Bind for 0.0.0.0:80 failed: port is already allocated` when starting `lb` | Another container (here `docker-nginx-1`, from another Compose project that restarted with Docker Desktop) already publishes port 80. | Pick another port: `LB_HOST_PORT=8088`, and put it in the public address too: `S3_PUBLIC_ENDPOINT_URL=http://s3.localhost:8088`. Do not stop projects that are not yours. |
| `ports are not available: ... 127.0.0.1:8080 ... bind: An attempt was made to access a socket in a way forbidden by its access permissions` | On Windows a port can be reserved or used by another program; the cause of the refusal of 8080 here was not investigated. | Choose another free port (8088 worked). `netsh int ipv4 show excludedportrange protocol=tcp` lists the ranges Windows reserves. |
| `SignatureDoesNotMatch` when fetching a presigned URL through `s3.localhost` | The link was signed for another host (for example `s3:8333`), or the port is missing from `S3_PUBLIC_ENDPOINT_URL`: the signature covers the `Host` header. | Make `S3_PUBLIC_ENDPOINT_URL` equal to what the client types, port included, and keep `proxy_set_header Host $http_host;`. |
| `error during connect: ... open //./pipe/dockerDesktopLinuxEngine: The system cannot find the file specified` | Docker Desktop is not running, so the Docker engine is not reachable. | Start Docker Desktop and wait until `docker version` shows a Server section. |
| `502 Bad Gateway` (HTML page) right after `docker compose up -d` re-created the `api` containers, a few seconds later it works | Most likely Nginx still held the old addresses of the replaced containers: it asks Docker DNS again only every 5 seconds (`valid=5s`). Not investigated further. | Wait 5 to 10 seconds. A script should retry a few times (this is why the "fail on purpose" check above has a `sleep 8`). |

## 7. Going to real AWS
- **What changes:** a real **S3 bucket** (name unique across AWS, in one region), reached through the SDK's default endpoint, so `S3_ENDPOINT_URL` and the `path` addressing option disappear. **IAM**: the API gets an **IAM role** (on ECS, a task role) with a policy limited to that bucket (`s3:PutObject`, `s3:GetObject` on `arn:aws:s3:::my-bucket/originals/*`), instead of access keys in `.env`. **Block Public Access** stays on: the bucket is private and downloads go through presigned URLs, as here.
- **Presigned URLs:** the code is the same boto3 call. Two differences: the URL host is the real S3 address (no `s3.localhost`, no second client, no `Host` trick), and a URL signed with **temporary role credentials** stops working when those credentials expire, even if `ExpiresIn` is longer.
- **Browsers:** to let a web page upload or fetch directly, the bucket needs a **CORS** configuration. Serving files to many users usually puts **CloudFront** in front of the bucket (Lab 08).
- **Good habits you get for free there:** default **encryption at rest** (SSE-S3), optional **versioning**, **lifecycle rules** (move old objects to cheaper storage or delete them), **access logs**, and **event notifications** (an upload can trigger a queue message or a Lambda: the idea of Lab 07's thumbnail job).
- **What this lab does not simulate:** durability across zones, IAM and bucket policies, versioning, encryption, lifecycle rules, event notifications, CORS, storage classes and the real S3 behaviour under load. SeaweedFS speaks the same API for the basic calls used here, but it is not S3. Also not handled yet: the **`Content-Type`** is stored as the client sent it, so a file declared `text/html` would be served as a web page; forcing a download (`ResponseContentDisposition=attachment` when signing) or an allow-list of types is the next hardening.
- **Rough cost:** S3 bills for **storage** (a few US cents per GB per month for the standard class, region-dependent), for **requests** (per thousand `PUT`/`GET`) and for **data transferred out** to the internet (some free allowance, then a price per GB; check the page). A lab-sized bucket costs cents. See the [S3 pricing page](https://aws.amazon.com/s3/pricing/); prices change.

## 8. Clean up
```bash
# delete the objects (the tests already delete their own)
docker compose run --rm --no-deps -T --entrypoint sh s3-init -c 'aws --endpoint-url http://s3:8333 s3 rm "s3://$S3_BUCKET/" --recursive'
make down          # removes the containers and networks; the files stay in the s3data volume
make up            # starts again: the bucket and any files are still there, s3-init finds the bucket and does nothing
make clean         # deletes ALL volumes (Postgres and s3data); it asks you to type "yes" first - run it yourself
```
The files live in the named volume `s3data` (step 18), so they survive `make down`; only `make clean` removes them.

## 9. Check your understanding
1. Why is a file better stored in object storage than in a database table? Name two differences between a bucket and a disk.
2. What does a presigned URL contain, and why can the API hand it to a browser without giving away its secret key?
3. The API creates two boto3 clients, `s3` and `s3_public`. What does each do, and what happens if the links are signed with `s3` instead?
4. Why must the `s3.localhost` block of Nginx use `proxy_set_header Host $http_host;` rather than the default?
5. The test checks that a `PUT` on the public door is refused and that a link signed for `s3:8333` is refused. Why test things that must **not** work?

<details><summary>Answers</summary>

1. Files are large, written once and read many times; a database is built for small structured rows, and big values slow it, bloat its backups and cost more per GB. A bucket has **no folders** (keys are just names with slashes), it is reached by **HTTP** with an access key, and it scales without you managing space; a disk has a real directory tree, is attached to one machine and has a fixed size.
2. The object's address plus query parameters: the algorithm, who signed (the access key **id**), the date, the expiry, the signed headers and the **signature**. The signature is computed from the secret key, which never appears in the URL: the server recomputes it and compares. Changing any part (the object, the host, the expiry) breaks the match.
3. `s3` talks to the store inside Docker (`http://s3:8333`) to write the object; `s3_public` only **signs** links for the public address (`http://s3.localhost:8088`). If links were signed with `s3`, they would carry the host `s3:8333`, a name that only exists inside Docker: no host or browser could use them.
4. The signature covers the `Host` header. The default would send `Host: s3:8333` (Nginx's own destination) instead of the `s3.localhost:8088` the client signed for, so the store would answer `SignatureDoesNotMatch`. `$host` also fails when a port is used, because it drops the port; `$http_host` keeps it.
5. A feature is not finished when it works for the right request; it must also **refuse the wrong ones**. These two checks protect the design: the public door stays read-only, and the API keeps signing for the host the client will really use. If either rule is broken by a later change, the test goes red.

</details>

## 10. Exercises (optional)
- Make a link expire: add `PRESIGN_SECONDS=5` to `.env`, run `docker compose up -d`, upload, download at once (200), wait 6 seconds, download again. What status and error code does the store answer? Put the setting back.
- Make the test catch a bug: in `lb/nginx.conf` change `proxy_set_header Host $http_host;` to `proxy_set_header Host $host;` while using `S3_PUBLIC_ENDPOINT_URL=http://s3.localhost:8088`, restart `lb`, run `tests/06_storage.sh`. Which checks fail? Put the line back.
- Force a download: add `"ResponseContentDisposition": "attachment"` to the `Params` of `generate_presigned_url` in `api/main.py`, rebuild, and look at the response headers of the link with `curl -sI`. What is new? Extend the test to check it.
- Upload from the browser side: write a tiny HTML page that `fetch`es a presigned **PUT** URL (generate it with `generate_presigned_url("put_object", ...)`). What does the public door answer, and why? What would you change in `nginx.conf` to allow it, and what do you lose?
- Use the AWS CLI like a user: `aws --endpoint-url http://s3:8333 s3 cp` a file into the bucket from the `s3-init` service, then fetch it with a presigned URL made by `aws s3 presign`.

## 11. Further reading
- [Amazon S3: what it is](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Welcome.html) and [sharing objects with presigned URLs](https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-presigned-url.html) (AWS)
- [Blocking public access to S3](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html) (AWS)
- [boto3: `generate_presigned_url`](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/s3/client/generate_presigned_url.html) (Python SDK)
- [SeaweedFS: Amazon S3 API](https://github.com/seaweedfs/seaweedfs/wiki/Amazon-S3-API) (the local server)
- [Nginx: `proxy_set_header`](https://nginx.org/en/docs/http/ngx_http_proxy_module.html#proxy_set_header) and [`limit_except`](https://nginx.org/en/docs/http/ngx_core_module.html#limit_except) (Nginx)
