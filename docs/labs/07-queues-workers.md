# Lab 07 — Queues and workers (SQS)

> **AWS equivalent:** Amazon SQS (queues, messages, visibility timeout, dead-letter queues) + a worker on ECS or Lambda  ·  **Time:** ~90 min  ·  **Difficulty:** ★★★
> **Builds on:** [Lab 06](./06-object-storage.md)  ·  **Reference solution:** commits `b436700` (step 22), `89a7d7c` and `0e475a9` (step 23), `3a81ef1` (step 24) on `dev`

> **Status:** in progress. Steps 22–24 are written. Step 25 (async test) and the closing sections (5–11) come next.

## 1. What you will learn
- Tell a **synchronous** request from an **asynchronous** one, and say when a queue is the right tool.
- Use the queue vocabulary: **producer**, **consumer (worker)**, **message**, **job**, **acknowledgement**, **at-least-once delivery**.
- Answer a request with **`202 Accepted`** and give the client an id to poll, instead of making it wait.
- Build a queue on a **Redis list** and keep each job's **status** in a Redis **hash** with an expiry.
- Explain why the two writes of an enqueue must be **atomic** (`MULTI`/`EXEC`), and what a queue on a cache-style Redis can lose.
- Write a **worker** with the **reliable-queue pattern** (`BLMOVE` to a processing list, acknowledge with `LREM`), and show that a killed worker loses no job.
- Handle **`SIGTERM`** so `docker stop` finishes the current job, and explain what a restart policy does and does not do.
- Write a real **job handler**: read an image from the bucket, make a thumbnail with Pillow, write it back, and turn every failure into a `failed` status instead of a crash.

## 2. Theory

### 2.1 The concept
Some work is too slow to do while the user waits: making a thumbnail of a photo, sending an email, generating a report. If the API did it inside the request, the user would stare at a spinner, the request could time out, and a burst of uploads would overload the API. The answer is to **separate asking from doing**: the API writes a note saying "please do this" and answers at once; another program does the work later, at its own pace.

Think of a **restaurant kitchen**. The waiter (the API) does not cook: he clips an **order ticket** on the **rail** (the queue) and goes back to the customers. The cooks (the **workers**) take tickets from the rail one by one. When the restaurant is busy, tickets pile up on the rail instead of the waiters collapsing; if you hire two more cooks, the pile shrinks faster.

The vocabulary:
- A **queue** holds **messages** in order. The first message in is, normally, the first out (**FIFO**: first in, first out).
- The **producer** puts messages in (here, the API). The **consumer** (or **worker**) takes them out and does the work.
- A **job** is the unit of work. The message says which job; a **job record** says what it is and how it is going (`queued`, `processing`, `done`, `failed`).
- The consumer **acknowledges** (acks) a message when the work is done, so the queue can forget it. If the worker crashes before that, the message must come back, so another worker can try again. This is **at-least-once delivery**: a job runs *at least* once, possibly twice, so the work should be **idempotent** (running it twice does no harm).
- The client does not get the result in the answer, so it asks again later with the job's id (**polling**).

**Why it helps:** the API stays fast, spikes are absorbed by the queue (**load levelling**), the API and the worker can be scaled, deployed and fail **independently** (**decoupling**), and a failed job can be retried.

### 2.2 How AWS does it
**Amazon SQS** (*Simple Queue Service*) is the AWS queue: fully managed, nothing to run.

| SQS piece | What it is |
|---|---|
| **Queue** | The container, with a name and an URL. **Standard** queues: very high throughput, at-least-once delivery, order not guaranteed. **FIFO** queues: strict order and no duplicates, lower throughput. |
| **Message** | The body (text, often JSON) plus attributes. The producer calls `SendMessage`. |
| **Receive and delete** | A consumer calls `ReceiveMessage` (with **long polling**, waiting up to 20 s instead of asking in a loop), does the work, then `DeleteMessage`. |
| **Visibility timeout** | When a message is received it is not deleted, only **hidden** for a while (30 s by default). If the consumer does not delete it in time (it crashed), the message becomes visible again and another consumer receives it. This is how SQS gives at-least-once delivery. |
| **Dead-letter queue (DLQ)** | A second queue where a message goes after it failed too many times (`maxReceiveCount`), so one bad message does not loop forever and you can inspect it. |
| **Retention** | How long an unprocessed message is kept (4 days by default, up to 14). |
| **Consumers** | Your own worker (a container on **ECS** or **EKS** polling the queue), or **Lambda** with an event source mapping that calls your function for each batch. |

SQS has **no job status**: a message is either waiting, hidden or gone. When the client needs to ask "is my job done?", the status is usually kept in a database such as **DynamoDB**, keyed by the job id. In the console: **SQS → Queues**.

### 2.3 How we reproduce it locally
| Concept | AWS | This lab |
|---|---|---|
| The queue | SQS queue | the Redis list `queue:jobs` (the ids of the waiting jobs) |
| Send a message | `SendMessage` | `LPUSH queue:jobs <id>` (inside `POST /jobs`) |
| Receive and hide | `ReceiveMessage` + visibility timeout | `BLMOVE queue:jobs queue:processing` (step 23): the id moves to a second list instead of disappearing |
| Delete after success | `DeleteMessage` | `LREM queue:processing` (step 23) |
| The job's status | DynamoDB item | the Redis hash `job:<id>` (`status`, `type`, `payload`, `created_at`) with an expiry |
| The consumer | ECS task / Lambda | the `worker` container (step 23) |
| Dead-letter queue, retention, FIFO guarantees, encryption | built in | not simulated |

The message in the list is only the **id**: the job's data lives in the hash. That keeps the queue small and gives the status a home. Redis is a fair stand-in for learning the pattern, but it is **not** a managed queue: see "What just happened" in step 22 for what it can lose. In Lab 13 (Terraform against an emulator) the worker learns to use SQS through a setting.

### 2.4 Diagram
```mermaid
flowchart LR
  you((You)) -->|"1. POST /jobs"| lb["lb: Nginx"]
  lb --> api["api x3<br/>(producer)"]
  api -->|"2. HSET job:id + LPUSH id<br/>(one MULTI/EXEC)"| redis[("redis<br/>list queue:jobs<br/>hash job:id")]
  api -->|"3. 202 Accepted + id"| you
  you -.->|"4. GET /jobs/id (poll)"| api
  worker["worker"] -->|"5. BLMOVE an id, work, update status, LREM"| redis
  worker -->|"6. step 24: read the image, write the thumbnail"| s3[("s3: SeaweedFS")]
```
Solid arrows exist after step 24; dashed ones are the polling.

## 3. Prerequisites
- [Lab 06](./06-object-storage.md) completed: `make up` runs, `make test` is green (six scripts).
- Nothing new in `.env`: the queue uses the Redis of [Lab 05](./05-caching.md), reached with the same `REDIS_URL`.
- If port 80 is busy on your machine, `LB_HOST_PORT` (and `S3_PUBLIC_ENDPOINT_URL`) in `.env`, as in Lab 06. The commands below use port **8088**: replace it by yours.

## 4. Steps

> Try each step yourself first, then compare with the reference commit.

### Step 22 — `POST /jobs` and `GET /jobs/{id}`
**Why:** the lab has a queue in theory and nothing to put in it. This step builds the **producer** side: an API route that accepts a job, stores it and answers immediately, and a second route to ask how it is going. There is no worker yet, so every job stays `queued`: that is exactly what the step checks.

**Which Redis structures.** Two, each for what it is good at:
- a **list**, `queue:jobs`, for the **order**: `LPUSH` adds an id at the head, and (step 23) the worker will take ids from the tail, so the oldest job goes first;
- a **hash**, `job:<id>`, for the **record**: a set of fields (`type`, `status`, `payload`, `created_at`) that the worker can update one by one. It gets an **expiry** (`EXPIRE`) so records do not pile up forever.

The three Redis commands of an enqueue run in one **`MULTI`/`EXEC`** block (a Redis *transaction*): Redis runs the three as one block with no other client's command in between, and runs none of them if the connection breaks before `EXEC`. (It is not a SQL-style rollback: if one command fails by itself, the others still run.) Without it, a crash between "write the record" and "push the id" would leave a record nobody will ever process, and the reverse order would leave an id with no record.

**Do it.** Four changes, all in `api/main.py` (nothing in `docker-compose.yml`: `REDIS_URL` is already there).

1. Imports (merge with the existing ones): `json` at the top, `timezone` next to `datetime`, `Path` next to the other FastAPI names:
   ```python
   import json
   from datetime import datetime, timezone
   from fastapi import Depends, FastAPI, File, HTTPException, Path, Response, UploadFile, status
   ```

2. The queue client and its settings, just before `MAX_UPLOAD_BYTES = ...`:
   ```python
   # The job queue (SQS in AWS). Same Redis server as the cache, but here Redis is a hard dependency:
   # a job that could not be queued must never be reported as accepted (the routes answer 503).
   queue = redis.Redis.from_url(
       os.environ["REDIS_URL"], decode_responses=True, socket_connect_timeout=1, socket_timeout=2
   )
   QUEUE_KEY = "queue:jobs"  # a Redis list: the ids of the jobs waiting for a worker
   JOB_TTL = int(os.environ.get("JOB_TTL_SECONDS", "86400"))  # how long a job record is kept (24 h)
   ```

3. The models and two small helpers, before `get_note_or_404`:
   ```python
   class JobIn(BaseModel):
       """What a client sends to ask for a job."""

       type: str = Field(min_length=1, max_length=50)  # what to do, e.g. "thumbnail" (step 24)
       payload: dict[str, str] = Field(default_factory=dict, max_length=10)  # its inputs


   class JobOut(BaseModel):
       id: str
       type: str
       status: str  # "queued" now; a worker will move it on (step 23)
       created_at: datetime
       payload: dict[str, str]


   def job_key(job_id: str) -> str:
       return f"job:{job_id}"  # the Redis hash that holds one job's record


   def job_out(job_id: str, record: dict[str, str]) -> dict:
       return {
           "id": job_id,
           "type": record["type"],
           "status": record["status"],
           "created_at": record["created_at"],
           "payload": json.loads(record["payload"]),
       }
   ```

4. The two routes, at the end of the file:
   ```python
   @app.post("/jobs", response_model=JobOut, status_code=status.HTTP_202_ACCEPTED)
   def create_job(data: JobIn):
       """Queue a job and answer at once. 202 means "accepted", not "done": a worker does the work later."""
       job_id = uuid4().hex
       record = {
           "type": data.type,
           "status": "queued",
           "payload": json.dumps(data.payload),
           "created_at": datetime.now(timezone.utc).isoformat(),
       }
       try:
           pipe = queue.pipeline(transaction=True)  # MULTI/EXEC: sent and run as one block, nothing in between
           pipe.hset(job_key(job_id), mapping=record)  # the record first ...
           pipe.expire(job_key(job_id), JOB_TTL)  # ... that disappears by itself after a day ...
           pipe.lpush(QUEUE_KEY, job_id)  # ... then the id joins the queue
           pipe.execute()
       except redis.RedisError as exc:
           log.error("could not queue job %s: %s", job_id, exc)
           raise HTTPException(status_code=503, detail="job queue unavailable")
       log.info("queued job %s (%s)", job_id, data.type)
       return job_out(job_id, record)


   @app.get("/jobs/{job_id}", response_model=JobOut)
   def get_job(job_id: Annotated[str, Path(pattern=r"^[0-9a-f]{32}$")]):
       """The current state of a job: poll this until the status is "done"."""
       try:
           record = queue.hgetall(job_key(job_id))
       except redis.RedisError as exc:
           log.error("could not read job %s: %s", job_id, exc)
           raise HTTPException(status_code=503, detail="job queue unavailable")
       if not record:
           raise HTTPException(status_code=404, detail="job not found")
       return job_out(job_id, record)
   ```

| Line | What it does | If you change or remove it |
|---|---|---|
| `queue = redis.Redis.from_url(os.environ["REDIS_URL"], ...)` | A second client for the same server as `cache`, kept apart because the two have different rules. Timeouts: 1 s to connect, 2 s per command. | Reusing `cache` works, but mixes a "may fail silently" client with a "must not fail silently" one. |
| `QUEUE_KEY = "queue:jobs"` | The name of the list. The `queue:` prefix keeps queue keys apart from the cache's `note:<id>` keys. | Another name works as long as the API and the worker agree. |
| `JOB_TTL` (86400 s) | How long a job record lives. Redis deletes the hash by itself afterwards. The value is a default in the code: `docker-compose.yml` does not pass `JOB_TTL_SECONDS` to the API yet. | No expiry: finished jobs stay in memory forever. |
| `class JobIn` / `type`, `payload` | The body clients send. `type` is required (1–50 characters); `payload` is optional, at most 10 entries, **strings only**. | Without `max_length` a client could store a huge record in Redis. |
| `status_code=status.HTTP_202_ACCEPTED` | `202`: "I accepted your request, the work is not done". | `201 Created` or `200 OK` would suggest the work exists or is finished. |
| `uuid4().hex` | A random, unique 32-character id; the client cannot guess or choose one. | Sequential ids (`1`, `2`, ...) let anyone read other people's jobs by counting. |
| `json.dumps(data.payload)` | A Redis hash stores flat strings, so the payload dict is stored as a JSON text and decoded in `job_out`. | |
| `queue.pipeline(transaction=True)` | Collects the commands and sends them wrapped in `MULTI` ... `EXEC`: Redis runs them as one block, with nothing in between. | `transaction=False` still batches them but without that guarantee (other commands could slip in between, and a broken connection could leave only some of them applied). |
| `hset`, `expire`, `lpush` | Write the record, set its expiry, push the id on the queue's head. The record goes **first**. | If the id were pushed first, a very fast worker could look up a record that does not exist yet. |
| `except redis.RedisError` → `503` | When Redis is down, the route answers `503 Service Unavailable` and logs the cause. | Without it the client would get an ugly `500`. A `202` without a queued job would be worse: a lie. |
| `Path(pattern=r"^[0-9a-f]{32}$")` | `GET /jobs/{job_id}` accepts only 32 lower-case hex characters, the shape of our ids. Anything else is `422` ([FastAPI 03](../courses/fastapi/03-parameters.md)). | Without it, any string would be turned into a Redis key. |
| `queue.hgetall(...)` / `if not record` | Reads the whole hash; a missing hash comes back as an empty dict, which means `404`. | |

**Rebuild and restart:**
```bash
docker compose up -d --build --wait api
```
(Re-creates the three `api` containers. Give Nginx about 5 seconds to pick up their new addresses, see [Lab 06](./06-object-storage.md) troubleshooting.)

**Check 1 — the step's check: a job id is returned and the status is `queued`.**
```bash
curl -s -w ' [HTTP %{http_code}]\n' -X POST localhost:8088/jobs -H 'Content-Type: application/json' \
  -d '{"type":"thumbnail","payload":{"key":"originals/demo.png"}}'
curl -s -w ' [HTTP %{http_code}]\n' localhost:8088/jobs/<the id>
```
```text
{"id":"a1633017d8cb4ad0ab100e6abe71feb5","type":"thumbnail","status":"queued","created_at":"2026-11-22T16:12:28.456738Z","payload":{"key":"originals/demo.png"}} [HTTP 202]
{"id":"a1633017d8cb4ad0ab100e6abe71feb5","type":"thumbnail","status":"queued","created_at":"2026-11-22T16:12:28.456738Z","payload":{"key":"originals/demo.png"}} [HTTP 200]
```
The first call answers **`202`** with the job's id and `"status":"queued"`; the second, a moment later, still reads `queued`, because nobody is processing jobs yet. The `id` is the handle the client keeps.

**Check 2 — what Redis really holds.** `redis-cli` inside the container, authenticated with the password the container already has (as in Lab 05):
```bash
rcli() { docker compose exec -T redis sh -c 'REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli "$@"' sh "$@" | tr -d '\r'; }
rcli llen queue:jobs
rcli lrange queue:jobs 0 -1
rcli ttl job:<the id>
rcli hgetall job:<the id>
```
```text
LLEN queue:jobs = 1
LRANGE queue:jobs 0 -1 = a1633017d8cb4ad0ab100e6abe71feb5
TTL job:a1633017d8cb4ad0ab100e6abe71feb5 = 86399
type thumbnail
status queued
payload {"key": "originals/demo.png"}
created_at 2026-11-22T16:12:28.456738+00:00
```
(The `LLEN ... =` labels were added with `echo`, and `hgetall`'s name/value lines were paired with `paste` to save space.) The **list** holds the id, the **hash** holds the record, and the record's **TTL** is about a day (86399 s, one second after creation).

**Check 3 — the order of the queue.** Three more jobs through the load balancer (so several API replicas), then the list:
```bash
for i in 1 2 3; do curl -s -X POST localhost:8088/jobs -H 'Content-Type: application/json' -d "{\"type\":\"noop\",\"payload\":{\"n\":\"$i\"}}"; done
rcli llen queue:jobs
rcli lrange queue:jobs 0 3
```
```text
LLEN = 4
first 4 entries (newest first): a2ac3fe0 6cb601ce 8553077e a1633017
```
(Ids cut to 8 characters.) `LPUSH` puts each new id at the **head**, so the list reads newest first: the oldest job, `a1633017`, is at the **tail**. The worker of step 23 will take from the tail, which gives first in, first out. The three requests went through the load balancer, which spreads requests over the three replicas, and all the jobs landed in one queue: it is **shared**, like the cache.

**Check 4 — bad input.**
```bash
curl -s -w ' [HTTP %{http_code}]\n' localhost:8088/jobs/00000000000000000000000000000000      # a well-formed id that does not exist
curl -s -w ' [HTTP %{http_code}]\n' localhost:8088/jobs/not-an-id
curl -s -w ' [HTTP %{http_code}]\n' -X POST localhost:8088/jobs -H 'Content-Type: application/json' -d '{"payload":{}}'
curl -s -w ' [HTTP %{http_code}]\n' -X POST localhost:8088/jobs -H 'Content-Type: application/json' -d '{"type":"x","payload":{"n":1}}'
```
```text
{"detail":"job not found"} [HTTP 404]
{"detail":[{"type":"string_pattern_mismatch","loc":["path","job_id"],"msg":"String should match pattern '^[0-9a-f]{32}$'","input":"not-an-id","ctx":{"pattern":"^[0-9a-f]{32}$"}}]} [HTTP 422]
{"detail":[{"type":"missing","loc":["body","type"],"msg":"Field required","input":{"payload":{}}}]} [HTTP 422]
{"detail":[{"type":"string_type","loc":["body","payload","n"],"msg":"Input should be a valid string","input":1}]} [HTTP 422]
```
An unknown id is `404`; a malformed id, a body without `type` and a payload value that is a number (`"n": 1`) are all `422` with the exact place (`loc`). After these four requests `LLEN` was still 4: **rejected requests queue nothing**.

**Check 5 — Redis goes away: the queue is a hard dependency.**
```bash
docker compose stop redis
curl -s -m 10 -w ' [HTTP %{http_code}]\n' -X POST localhost:8088/jobs -H 'Content-Type: application/json' -d '{"type":"noop"}'
curl -s -m 10 -w ' [HTTP %{http_code}]\n' localhost:8088/jobs/<the id>
curl -s -o /dev/null -w 'GET /notes [HTTP %{http_code}]\n' localhost:8088/notes
docker compose logs api | grep -E 'could not (queue|read) job' | tail -2
docker compose start redis
```
```text
{"detail":"job queue unavailable"} [HTTP 503]
{"detail":"job queue unavailable"} [HTTP 503]
GET /notes [HTTP 200]
api-2  | ERROR:    could not read job a1633017d8cb4ad0ab100e6abe71feb5: Error -3 connecting to redis:6379. Temporary failure in name resolution.
api-3  | ERROR:    could not read job a1633017d8cb4ad0ab100e6abe71feb5: Error -3 connecting to redis:6379. Temporary failure in name resolution.
```
Compare with Lab 05: the **cache** failing made the API *slower* (`X-Cache: BYPASS`, still `200`). The **queue** failing makes the job routes answer **`503`**, because there is no sensible fallback: pretending to accept a job that was never queued would lose it silently. Other routes (`GET /notes`) are not affected. The same `Temporary failure in name resolution` as in Lab 05: Docker's DNS stops answering for a stopped container.

**Check 6 — what a restart does to a queue on this Redis.** After `docker compose start redis` (Check 5):
```bash
rcli llen queue:jobs
curl -s -w ' [HTTP %{http_code}]
' localhost:8088/jobs/<the first id>
rcli config get maxmemory-policy; rcli config get appendonly; rcli config get save
```
```text
LLEN queue:jobs after the restart = 0
{"detail":"job not found"} [HTTP 404]
redis settings: maxmemory-policy allkeys-lru  appendonly no  save
```
The four queued jobs and the job record are **gone**. The Redis of this lab was configured in Lab 05 as a **cache**: no snapshot, no append-only file (`appendonly no`, `save ""`), and `allkeys-lru`, which may evict **any** key, jobs included, when the 64 MB are full. See "What just happened".

**Clean up the test jobs** (so the worker of step 23 does not start on them): the restart above already emptied Redis here; otherwise `redis-cli del queue:jobs` and delete the `job:*` keys.

**Regression check — the whole suite:**
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
(Trimmed to the headings and summary lines; `make` exited with code 0.)

**What just happened:**
- The API is now a **producer**: `POST /jobs` takes a few milliseconds, whatever the job will cost later, and answers `202` with an id. That is the whole point of a queue: the client's wait no longer depends on the work.
- A job lives in **two** places that must stay consistent: an id in a **list** (the order) and a record in a **hash** (the details). One `MULTI`/`EXEC` writes both, or neither.
- The **status** is the contract with the client: `queued` now, `processing` and `done` or `failed` once the worker of step 23 exists. The client polls `GET /jobs/{id}`; AWS would typically keep that status in DynamoDB, since SQS has none.
- **A queue on a cache-style Redis can lose jobs.** Three ways, all caused by the Lab 05 settings: a restart empties it (Check 6), a full memory may evict a job (`allkeys-lru`), and a crash in the middle of a job loses it unless the worker uses the reliable pattern of step 23. SQS stores messages durably in several zones and never evicts them. For a real project the queue would get its **own** Redis with a persistence file and the `noeviction` policy (or simply use SQS); here the plan keeps one Redis to stay small, and the limit is part of the lesson. The API also says it plainly: a job is only `queued` once Redis has accepted it, otherwise `503`.
- `job:<id>` records expire after 24 hours (the default of `JOB_TTL`; to change it, pass `JOB_TTL_SECONDS` to the `api` service in `docker-compose.yml`), so even a finished job's record is temporary: a client that polls late gets `404`.

### Step 23 — The worker container
**Why:** step 22 put jobs on a queue and nobody takes them off. This step adds the **consumer**: a separate container, `worker`, that takes job ids from the queue, does the work (a stub for now: it sleeps), and reports the status. Its job is not only to work, but to work **reliably**: if it dies in the middle of a job, the job must not be lost.

**The reliable-queue pattern.** The simplest way to take an id off a list is `RPOP` (remove and return). But then the id exists only in the worker's memory: if the worker crashes one second later, the job is gone for good. The reliable version **moves** the id instead of removing it:
1. `BLMOVE queue:jobs queue:processing RIGHT LEFT 2`: atomically take the id at the **tail** of `queue:jobs` (the oldest, since the API pushes at the head) and put it at the head of a second list, `queue:processing`. `BLMOVE` is the **blocking** version: if the queue is empty it waits up to 2 seconds for an id to arrive instead of asking in a loop.
2. Do the work, updating the status in the hash `job:<id>`.
3. `LREM queue:processing 1 <id>`: the **acknowledge**. Only now is the job finished for good.

An id that stays in `queue:processing` is a job being worked on, or one whose worker died. At start-up the worker moves such ids back to the queue. This is what SQS does with its **visibility timeout**: a received message is hidden, not deleted, and comes back if nobody deletes it. The price is **at-least-once** delivery: a job interrupted half way is done **again** from the start.

**Graceful shutdown.** `docker stop` sends the signal `SIGTERM` and, after a grace period, `SIGKILL` (which cannot be caught). A worker that ignores `SIGTERM` would be killed in the middle of a job, so it installs a handler that only sets a flag: the loop finishes the current job, sees the flag, and exits with code 0.

**Do it.** Three files.

1. `worker/worker.py` (the whole file, **as it is at the end of this step**; [step 24](#step-24--the-thumbnail-job) replaces the stub work by real jobs and changes it):
   ```python
   """Queue worker (the consumer of Lab 07): takes job ids from a Redis list, does the work, reports the status.

   Reliable-queue pattern (what SQS does with its visibility timeout):
     1. BLMOVE queue:jobs -> queue:processing : the id is MOVED, not removed, so a crash cannot lose it.
     2. do the work, update the status in the hash job:<id>
     3. LREM queue:processing                  : the "acknowledge": the job is finished for good.
   An id left in queue:processing means a worker died mid-job; at start-up it is put back in the queue.
   No local state: everything lives in Redis, and the settings come from the environment.
   """
   import logging
   import os
   import signal
   import socket
   import time
   from datetime import datetime, timezone

   import redis

   REDIS_URL = os.environ["REDIS_URL"]
   WORK_SECONDS = float(os.environ.get("WORK_SECONDS", "2"))  # how long the stub work lasts
   QUEUE_KEY = "queue:jobs"  # same names as in api/main.py
   PROCESSING_KEY = "queue:processing"
   POLL_SECONDS = 2  # one blocking wait lasts this long: also the longest a stop request waits

   logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
   log = logging.getLogger(socket.gethostname())  # the container id, to tell workers apart in the logs

   stopping = False


   def request_stop(signum, frame):
       """SIGTERM is what "docker stop" sends: do not stop now, stop between two jobs."""
       global stopping
       stopping = True
       log.info("signal %s received: finishing the current job, then stopping", signum)


   def now() -> str:
       return datetime.now(timezone.utc).isoformat()


   def requeue_unfinished(r: redis.Redis) -> None:
       """Put back the ids a dead worker left in the processing list, at the tail of the queue (taken next).

       Ids enter the processing list at its head, so the oldest is at the tail. Taking from the head and
       pushing on the queue's tail puts the oldest last, which is the first one a worker takes."""
       count = 0
       while r.lmove(PROCESSING_KEY, QUEUE_KEY, "LEFT", "RIGHT") is not None:
           count += 1
       if count:
           log.warning("requeued %s unfinished job(s) left by a previous worker", count)


   def process(r: redis.Redis, job_id: str) -> None:
       key = f"job:{job_id}"
       if not r.exists(key):  # the record expired while the id waited
           log.warning("job %s has no record any more: dropped", job_id)
           return
       r.hset(key, mapping={"status": "processing", "started_at": now()})
       log.info("picked up job %s (%s)", job_id, r.hget(key, "type"))
       try:
           time.sleep(WORK_SECONDS)  # the stub work: step 24 replaces it with a real task
       except Exception as exc:
           r.hset(key, mapping={"status": "failed", "error": str(exc)[:200], "finished_at": now()})
           log.error("job %s failed: %s", job_id, exc)
           return
       r.hset(key, mapping={"status": "done", "finished_at": now()})
       log.info("job %s done", job_id)


   def main() -> None:
       signal.signal(signal.SIGTERM, request_stop)
       signal.signal(signal.SIGINT, request_stop)
       # The socket timeout must be longer than the blocking wait of BLMOVE.
       r = redis.Redis.from_url(
           REDIS_URL, decode_responses=True, socket_connect_timeout=2, socket_timeout=POLL_SECONDS + 5
       )
       log.info("worker started (work takes %s s per job)", WORK_SECONDS)
       recovered = False
       while not stopping:
           try:
               if not recovered:
                   requeue_unfinished(r)
                   recovered = True
               job_id = r.blmove(QUEUE_KEY, PROCESSING_KEY, POLL_SECONDS, "RIGHT", "LEFT")
               if job_id is None:  # the wait timed out: nothing to do, check the stop flag and wait again
                   continue
               process(r, job_id)
               r.lrem(PROCESSING_KEY, 1, job_id)  # acknowledge
           except redis.RedisError as exc:
               log.error("redis problem: %s (retrying in 2 s)", exc)
               recovered = False  # an id may be stuck in the processing list: look again
               time.sleep(2)
       log.info("stopped")


   if __name__ == "__main__":
       main()
   ```

2. `worker/Dockerfile`:
   ```dockerfile
   FROM python:3.12.16-slim-trixie

   ENV PYTHONDONTWRITEBYTECODE=1 \
       PYTHONUNBUFFERED=1

   WORKDIR /app

   # The only dependency, pinned (same version as the API). Step 24 adds Pillow and boto3.
   RUN pip install --no-cache-dir redis==8.1.0

   COPY worker.py .

   # Never run as root inside the container.
   RUN useradd --system --uid 10001 --no-create-home app
   USER app

   # Exec form: Python is process 1 and receives SIGTERM from "docker stop" directly.
   CMD ["python", "worker.py"]
   ```

3. The service in `docker-compose.yml`, before the `db-proxy` service:
   ```yaml
     # The queue consumer (an ECS service or Lambda in AWS). It takes job ids from the Redis list, does
     # the work and updates the job's status. No port, no volume, no local state: everything is in Redis.
     worker:
       build: ./worker
       image: aws-local-lab-worker:0.1.0
       environment:
         REDIS_URL: redis://:${REDIS_PASSWORD:?set REDIS_PASSWORD in .env (see .env.example)}@redis:6379/0
         # How long the stub work of one job lasts, in seconds (step 24 replaces it with a real task).
         WORK_SECONDS: ${WORK_SECONDS:-2}
       depends_on:
         redis:
           condition: service_healthy
       networks:
         - private
       # Like an ECS service: if the worker dies, start another one (it puts unfinished jobs back in the queue).
       restart: unless-stopped
       # "docker stop" sends SIGTERM; the worker finishes its current job, then exits. Wait that long before SIGKILL.
       stop_grace_period: 30s
   ```

| Line | What it does | If you change or remove it |
|---|---|---|
| `REDIS_URL = os.environ["REDIS_URL"]`, `WORK_SECONDS` | The settings come from the **environment**, like the API: the same image works in any environment. `REDIS_URL` has no default: a missing one stops the worker at start with a `KeyError`. `WORK_SECONDS` is optional (2 unless set; `.env.example` shows it commented). | Hard-coded values would be baked into the image. |
| `QUEUE_KEY`, `PROCESSING_KEY` | The two list names, the same `queue:jobs` as in `api/main.py`. | If the API and the worker disagree, jobs are never found. |
| `POLL_SECONDS = 2` | The length of one blocking wait. It is also the longest a stop request can wait for an idle worker. | A large value makes `docker stop` slow for an idle worker. |
| `signal.signal(signal.SIGTERM, request_stop)` | Installs the handler. It only sets `stopping`: the loop decides when to stop. | Without it, Python as process 1 would ignore `SIGTERM` and `docker stop` would wait the whole grace period, then `SIGKILL` a job in progress. |
| `requeue_unfinished` / `lmove(PROCESSING, QUEUE, "LEFT", "RIGHT")` | Moves every id left in the processing list back to the **tail** of the queue (the next to be taken). Ids enter the processing list at its head, so taking from the **head** and pushing on the tail puts the oldest last pushed, hence first taken. | Without it, a job whose worker died would wait in `queue:processing` forever. With `"RIGHT", "RIGHT"` (the first version) several orphaned ids came back in reverse order: Check 3, second part. |
| `r.blmove(QUEUE_KEY, PROCESSING_KEY, POLL_SECONDS, "RIGHT", "LEFT")` | The reliable receive: move the oldest id to the processing list, wait up to 2 s if there is none. Returns `None` on timeout. | `brpop` would lose the job if the worker died right after. |
| `if not r.exists(key)` | The id of a job whose record has expired (24 h) is dropped with a warning, not retried forever. | |
| `hset(... "status": "processing", "started_at": ...)` | Tells the client the job has started (`GET /jobs/{id}` shows it). | |
| `time.sleep(WORK_SECONDS)` | The stub work. Step 24 replaces this one line by a real task. | |
| `except Exception` → `"status": "failed"` | A failing job is marked `failed` with a short error and acknowledged: it is not retried (no retry policy or dead-letter queue yet). | Without it, one bad job would crash the worker in a loop. The stub cannot fail, so this path is not exercised here. |
| `r.lrem(PROCESSING_KEY, 1, job_id)` | The acknowledge: remove the id from the processing list. | Without it, every job would be redone at the next start-up. |
| `except redis.RedisError` ... `recovered = False` | If Redis is unreachable, wait 2 s and try again. An id may be stuck in the processing list, so look again. | Without it, the first Redis restart would stop the worker. |
| `socket_timeout=POLL_SECONDS + 5` | The client must wait longer than `BLMOVE` does, or every empty wait would raise a timeout. | |
| `USER app`, `CMD ["python", "worker.py"]` | Non-root user; exec form, so Python is process 1 and receives `SIGTERM` directly. | The shell form (`CMD python worker.py`) would start a shell that does not pass the signal on. |
| `restart: unless-stopped` | Docker starts the worker again if its process exits, like an ECS service replacing a failed task. | Without it a crashed worker stays down. |
| `stop_grace_period: 30s` | How long `docker stop` waits for the worker to finish before `SIGKILL` (default 10 s). | A job longer than the grace period would be killed anyway. |
| `depends_on: redis: service_healthy` | The worker starts after Redis answers. | |

**Build and start:**
```bash
docker compose up -d --build --wait worker
docker compose logs worker
```
```text
worker-1  | 2026-11-22 16:28:35,092 INFO worker started (work takes 2.0 s per job)
```

**Check 1 — the step's check: the log shows the job picked up, and the status goes to `done`.**
```bash
rcli() { docker compose exec -T redis sh -c 'REDISCLI_AUTH="$REDIS_PASSWORD" redis-cli "$@"' sh "$@" | tr -d '\r'; }
curl -s -X POST localhost:8088/jobs -H 'Content-Type: application/json' -d '{"type":"noop","payload":{"hello":"worker"}}'
curl -s localhost:8088/jobs/<the id>              # once a second, a few times
docker compose logs worker
rcli hgetall job:<the id>
rcli llen queue:jobs; rcli llen queue:processing
```
```text
{"id":"63ca45aee00443218bad08d5c54b18a5","type":"noop","status":"queued","created_at":"2026-11-22T16:28:41.657742Z","payload":{"hello":"worker"}}
t+1s status=processing
t+2s status=processing
t+3s status=done
worker-1  | 2026-11-22 16:28:41,670 INFO picked up job 63ca45aee00443218bad08d5c54b18a5 (noop)
worker-1  | 2026-11-22 16:28:43,671 INFO job 63ca45aee00443218bad08d5c54b18a5 done
type noop
status done
payload {"hello": "worker"}
created_at 2026-11-22T16:28:41.657742+00:00
started_at 2026-11-22T16:28:41.669720+00:00
finished_at 2026-11-22T16:28:43.670606+00:00
queue:jobs=0 queue:processing=0
```
(The `t+Ns status=` lines come from a small shell loop around the `GET`; the hash's name/value lines were paired with `paste`.) The job was created at `…41.657`, **picked up 12 ms later** (`started_at`), worked on for 2 seconds and finished at `…43.670`: the status went `queued` → `processing` → `done`, and both lists are empty at the end.

**Check 2 — first in, first out, and the job in flight.** `WORK_SECONDS=4` (`WORK_SECONDS=4 docker compose up -d --wait worker`), three jobs submitted at once, and a look at the lists 1.5 s later:
```text
job 1 = 7ca7f753
job 2 = 4d42d7f0
job 3 = e537b911
--- while the first one is being worked on:
queue:jobs=2 queue:processing=1 (processing holds: 7ca7f753)
--- worker log, in order:
16:28:59,489 picked up job 7ca7f753... (noop)
16:29:03,490 job 7ca7f753... done
16:29:03,492 picked up job 4d42d7f0... (noop)
16:29:07,493 job 4d42d7f0... done
16:29:07,494 picked up job e537b911... (noop)
16:29:11,495 job e537b911... done
queue:jobs=0 queue:processing=0
```
(Ids cut to 8 characters; the three first lines were printed side by side and are shown one per line here.) Jobs are processed **in the order they were submitted**. While job 1 is being worked on, its id sits in `queue:processing` (not in `queue:jobs`): that is the "received but not acknowledged" state.

**Check 3 — the worker is killed in the middle of a job.** `WORK_SECONDS=12`, one job submitted, then `docker kill` (a `SIGKILL`: the process gets no chance to clean up):
```bash
docker kill aws-local-lab-worker-1
```
```text
job 924d3add... submitted
--- 3 s later the worker is busy:
status=processing queue:jobs=0 queue:processing=1
--- docker kill (SIGKILL): no chance to clean up
right after the kill: status=processing queue:jobs=0 queue:processing=1  <- the id is still in the processing list
```
The worker is dead, the status says `processing`, and the id is **still in the processing list**: nothing was lost. (The restart policy did not start a new worker: see Check 5.) Now start one:
```bash
docker compose start worker
```
```text
the crashed job: 924d3add... status=processing worker running: 0
--- right after the start:
worker-1  | 2026-11-22 16:30:09,258 INFO worker started (work takes 12.0 s per job)
worker-1  | 2026-11-22 16:30:09,275 WARNING requeued 1 unfinished job(s) left by a previous worker
16:30:09,276 INFO picked up job 924d3add... (noop)
--- 12 s later:
status=done queue:jobs=0 queue:processing=0
16:30:21,275 INFO job 924d3add... done
```
The new worker found the orphaned id, **requeued** it (`WARNING requeued 1 unfinished job(s)`), picked it up again 1 ms later and finished it: `done`. The job was started **twice** (once by each worker), finished once: that is **at-least-once delivery**.

**Check 3, second part — two orphaned jobs: which one first?** A worker that died while holding **two** ids (simulated by stopping the worker, submitting an older and a newer job, and moving both ids to the processing list by hand with `LMOVE queue:jobs queue:processing RIGHT LEFT`), then a new worker. With the **first version** of the recovery (`"RIGHT", "RIGHT"`):
```text
older job = e7a0d120, newer job = 71443419; both sit in queue:processing (left=head): 71443419 e7a0d120
worker-1  | 2026-11-22 16:50:36,406 WARNING requeued 2 unfinished job(s) left by a previous worker
16:50:36,407 picked up job 71443419 (noop)
16:50:37,409 picked up job e7a0d120 (noop)
```
The **newer** job ran first: moving from the tail of one list to the tail of the other reverses the order of several ids. (A single worker holds at most one id, so this could not happen in normal use, but the code claimed to keep the order.) The fix is the `LMOVE ... "LEFT", "RIGHT"` of the file above (found by the reviewer of this step, commit `0e475a9`); the same experiment afterwards:
```text
older job = c5558780, newer job = bb17e28c; both sit in queue:processing (left=head): bb17e28c c5558780
worker-1  | 2026-11-22 16:50:59,651 WARNING requeued 2 unfinished job(s) left by a previous worker
16:50:59,652 picked up job c5558780 (noop)
16:51:00,654 picked up job bb17e28c (noop)
```
The **older** job is picked up first. (`WORK_SECONDS=1` for this test; ids are 8-character prefixes.)

**Check 4 — a graceful stop in the middle of a job** (`WORK_SECONDS=6`; `docker compose stop` while the job is running):
```bash
docker compose stop worker
docker inspect -f '{{.State.ExitCode}}' aws-local-lab-worker-1
```
```text
status before the stop: processing
docker compose stop took about 5 s
worker-1  | 2026-11-22 16:30:47,292 INFO signal 15 received: finishing the current job, then stopping
16:30:50,796 INFO job 5d9c2a05... done
worker-1  | 2026-11-22 16:30:50,796 INFO stopped
exit code: 0
status after: done queue:jobs=0 queue:processing=0
```
On `SIGTERM` (signal 15) the worker did **not** stop at once: it finished the job it had (about 3.5 s of the 6 were left), logged `stopped` and exited with code **0**. The stop took 5 s, well inside the 30 s grace period, and nothing was left in either list. Compare with Check 3: a `SIGKILL` loses the work in progress (recovered later), a `SIGTERM` does not.

**Check 5 — what the restart policy does.** After the `docker kill` of Check 3 nobody restarted the worker: `docker compose ps worker` printed nothing. Docker applies a restart policy to a container whose **process exits by itself**, once the container has started successfully (Docker counts a start as successful after 10 seconds of running); a `docker kill` or `docker stop` is a deliberate stop. A throw-away container shows the difference:
```bash
docker run -d --name restart-demo --restart unless-stopped alpine:3.24 sh -c 'sleep 12; exit 1'
docker inspect -f '{{.RestartCount}}' restart-demo          # at once, then 18 s later
docker rm -f restart-demo
```
```text
restart count at start: 0
after the process exited with code 1 (18 s later): restart count = 1, running = true
```
The process ended with exit code 1 (a crash), and Docker started it again: this is the case `restart: unless-stopped` protects against (an unhandled exception, the kernel killing the process for memory). The worker's own recovery (Check 3) then puts unfinished jobs back.

**Regression check — the whole suite:**
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
  wait  upload attempt 1 answered HTTP 502, trying again
06_storage: all checks passed
```
(Trimmed to the headings and summary lines; `make` exited with code 0.) The `wait` line is new, and comes from a real failure met in this step: the first run of `make test` after adding the worker failed in `tests/06_storage.sh` with `upload failed (HTTP 000)`, twice in a row. After `04_persistence.sh` has stopped and started the whole stack, the **first** upload to the S3 server can answer `502` after about 10 seconds (the API log says `Read timeout on endpoint URL`), and the test's 10 s limit turned that into `000`. It is the "first upload right after a start" problem of Lab 06, and the extra container made the start busier. `tests/06_storage.sh` now tries the first upload up to 5 times (commit `dec7783`; see Lab 06, step 21 and its Troubleshooting).

**An honest caveat about this run.** The `make test` shown above was green, but the suite is **not reliably green** on this machine: `tests/02_failover.sh` fails in roughly one run out of three with `only 59 of 60 requests succeeded with one replica dead` (one `502`). It is a known intermittent failure of Lab 02 (see its Troubleshooting) that has become more frequent. To check that the new worker is not the cause, the test was run 8 times with the worker running (2 failures), 8 times with it stopped (2 failures) and 8 times with the load balancer's `nginx.conf` from before Lab 06 (2 failures). So it is **not caused by this step**, and not fixed by it either: the cause is still open.

**What just happened:**
- The lab now has a complete **asynchronous pipeline**: `POST /jobs` returns in milliseconds, the worker does the work later, `GET /jobs/{id}` shows the progress. The API and the worker share **nothing but Redis**: they are different images, can be scaled and deployed separately, and one can fail without the other.
- **A crash does not lose a job** (Check 3), and a **graceful stop does not interrupt one** (Check 4). The cost of the crash case is **at-least-once** delivery: a job can run twice, so real work must be **idempotent** (running it twice must do no harm; a thumbnail that overwrites the same key is).
- The worker has **no local state** and takes its settings from the environment: it could run on ECS, Kubernetes or Lambda unchanged. Its identity in the logs is the container id.
- **Limits of this version, on purpose:** (1) the recovery at start-up moves **every** id in the processing list back, which is right for one worker but would steal the jobs other running workers are busy with if you started several (they would then be done twice); SQS avoids this with a per-message visibility timeout, a per-worker processing list with a heartbeat would be the Redis answer. (2) A failing job is marked `failed` and not retried, and there is no dead-letter queue; and only errors raised **inside** the `try` of `process()` are handled: any other exception would end the process, and with `restart: unless-stopped` plus the start-up requeue that becomes a crash loop on one bad job, so the real work of step 24 must stay inside that `try`. (3) The queue still lives in the cache-style Redis of Lab 05 (restart = empty queue, see step 22): the status hash and the lists are lost together, so a restart loses jobs **consistently**, but it does lose them.

### Step 24 — The thumbnail job
**Why:** until now the worker only slept. This step gives it a **real job**, the classic one for object storage and queues: someone uploads a large image, the API answers at once, and in the background a worker makes a small **thumbnail** and stores it next to the original. In AWS the same pipeline is usually: S3 (upload) → an event message in SQS → a Lambda function or an ECS worker (resize) → S3 (thumbnail).

**How a job names its input.** `POST /jobs` already takes a `type` and a `payload` (a dictionary of strings, step 22). A thumbnail job is:
```json
{"type": "thumbnail", "payload": {"key": "originals/<id>-big.png", "size": "128"}}
```
`key` is the object to shrink (the `key` that `POST /upload` returned), `size` is optional (the longest side in pixels, 128 by default, between 16 and 1024). The worker looks the `type` up in a small table of **handlers** (`thumbnail`, and the old `noop` that sleeps), so a new kind of job is one more function.

**What the handler does.** It reads the original from the bucket, opens it with **Pillow** (the standard Python imaging library), shrinks it so that it fits in `size × size` **keeping its proportions**, saves it as a PNG and writes it under `thumbnails/`. The prefix `originals/` promised in [step 19](./06-object-storage.md#step-19--post-upload-and-the-presigned-url) is now used: the worker only accepts keys under `originals/`, so it cannot be asked to make thumbnails of thumbnails or to read other objects.

**When it goes wrong.** The input comes from a user, so many things can fail: the object does not exist, it is not an image, the payload is invalid, the job type is unknown. Any error inside the job ends it with the status **`failed`** and a short `error` message in the job's record; the id is still acknowledged (no retry, no dead-letter queue yet) and the worker carries on with the next job. A worker that crashes on one bad job would be restarted by Docker, requeue the same job at start-up, and crash again: all the work of a job therefore lives **inside** one `try` block.

**Do it.** Three files (the new `Dockerfile` line, the S3 settings of the service, and the worker).

1. `worker/Dockerfile`: boto3 and Pillow join `redis`, pinned (boto3 at the version of the API):
   ```dockerfile
   RUN pip install --no-cache-dir redis==8.1.0 boto3==1.44.6 Pillow==13.0.0
   ```

2. The worker needs the S3 settings, like the API (`docker-compose.yml`, the `worker` service now reads):
   ```yaml
     # The queue consumer (an ECS service or Lambda in AWS). It takes job ids from the Redis list, does
     # the work and updates the job's status. No port, no volume, no local state: everything is in Redis.
     worker:
       build: ./worker
       image: aws-local-lab-worker:0.1.0
       environment:
         REDIS_URL: redis://:${REDIS_PASSWORD:?set REDIS_PASSWORD in .env (see .env.example)}@redis:6379/0
         # How long a "noop" job lasts, in seconds.
         WORK_SECONDS: ${WORK_SECONDS:-2}
         # The object store, like the api service: the worker reads the uploads and writes the thumbnails.
         S3_ENDPOINT_URL: http://s3:8333
         S3_BUCKET: ${S3_BUCKET:-uploads}
         S3_ACCESS_KEY: ${S3_ACCESS_KEY:?set S3_ACCESS_KEY in .env (see .env.example)}
         S3_SECRET_KEY: ${S3_SECRET_KEY:?set S3_SECRET_KEY in .env (see .env.example)}
       depends_on:
         redis:
           condition: service_healthy
         s3-init:
           condition: service_completed_successfully
       networks:
         - private
       # Like an ECS service: if the worker dies, start another one (it puts unfinished jobs back in the queue).
       restart: unless-stopped
       # "docker stop" sends SIGTERM; the worker finishes its current job, then exits. Wait that long before SIGKILL.
       stop_grace_period: 30s
   ```

3. `worker/worker.py`. New imports and the S3 client, after the existing settings (same options as the client of `api/main.py`):
   ```python
   import io
   import json
   import logging
   import os
   import signal
   import socket
   import time
   from datetime import datetime, timezone

   import boto3
   import redis
   from botocore.config import Config
   from PIL import Image, ImageOps

   REDIS_URL = os.environ["REDIS_URL"]
   WORK_SECONDS = float(os.environ.get("WORK_SECONDS", "2"))  # how long a "noop" job lasts
   QUEUE_KEY = "queue:jobs"  # same names as in api/main.py
   PROCESSING_KEY = "queue:processing"
   POLL_SECONDS = 2  # one blocking wait lasts this long: also the longest a stop request waits
   MAX_PIXELS = 25_000_000  # refuse bigger images before decoding: a small PNG can hold billions of pixels

   # The object store (S3 in AWS): same settings and same client options as the API (api/main.py).
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
           connect_timeout=3,
           read_timeout=10,
           retries={"max_attempts": 2},
       ),
   )
   ```
   The handlers, and the new `process()`, in place of the old stub work:
   ```python
   def make_thumbnail(payload: dict) -> dict:
       """Read the image payload["key"] from the bucket, shrink it to fit in size x size, write it back."""
       key = payload.get("key", "")
       if not key.startswith("originals/"):
           raise ValueError("payload.key must be an object under originals/")
       size = int(payload.get("size", "128"))
       if not 16 <= size <= 1024:
           raise ValueError("payload.size must be between 16 and 1024")
       data = s3.get_object(Bucket=S3_BUCKET, Key=key)["Body"].read()
       with Image.open(io.BytesIO(data)) as img:  # raises UnidentifiedImageError if it is not an image
           if img.width * img.height > MAX_PIXELS:  # the size is known from the header: nothing decoded yet
               raise ValueError(f"image too large: {img.width}x{img.height} pixels (max {MAX_PIXELS})")
           img = ImageOps.exif_transpose(img)  # apply the camera's rotation flag, if any
           if img.mode not in ("RGB", "RGBA", "L", "LA", "P"):
               img = img.convert("RGB")  # modes PNG cannot store (CMYK, ...)
           img.thumbnail((size, size))  # shrink in place, keeping the proportions
           width, height = img.size
           out = io.BytesIO()
           img.save(out, format="PNG")
       name = os.path.splitext(os.path.basename(key))[0]
       out_key = f"thumbnails/{name}-{size}.png"  # the size is in the name; a redo of the same job overwrites
       s3.put_object(Bucket=S3_BUCKET, Key=out_key, Body=out.getvalue(), ContentType="image/png")
       return {"result_key": out_key, "result_size": f"{width}x{height}"}


   def do_noop(payload: dict) -> dict:
       time.sleep(WORK_SECONDS)  # pretend to work
       return {}


   HANDLERS = {"thumbnail": make_thumbnail, "noop": do_noop}


   def process(r: redis.Redis, job_id: str) -> None:
       key = f"job:{job_id}"
       if not r.exists(key):  # the record expired while the id waited
           log.warning("job %s has no record any more: dropped", job_id)
           return
       r.hset(key, mapping={"status": "processing", "started_at": now()})
       job_type = r.hget(key, "type")
       log.info("picked up job %s (%s)", job_id, job_type)
       try:  # everything that can go wrong with the job itself happens inside this block
           handler = HANDLERS.get(job_type)
           if handler is None:
               raise ValueError(f"unknown job type {job_type!r}")
           result = handler(json.loads(r.hget(key, "payload") or "{}"))
       except Exception as exc:
           message = f"{type(exc).__name__}: {exc}"[:200]
           r.hset(key, mapping={"status": "failed", "error": message, "finished_at": now()})
           log.error("job %s failed: %s", job_id, message)
           return
       r.hset(key, mapping={"status": "done", "finished_at": now(), **result})
       log.info("job %s done %s", job_id, result or "")
   ```
   (`main()` only changes in its log line: `worker started (job types: thumbnail, noop)`.)

| Line | What it does | If you change or remove it |
|---|---|---|
| `S3_BUCKET`, `s3 = boto3.client(...)` | The same endpoint, bucket and keys as the API, from the environment. `path` addressing and a few timeouts, as in step 19. | Without `endpoint_url` boto3 would talk to the real AWS. |
| `MAX_PIXELS` and `if img.width * img.height > MAX_PIXELS` | Refuses images of more than 25 million pixels **before** decoding them: the size is read from the file's header. A 315 KB PNG can hold 100 million pixels (about 300 MB once decoded) and the 5 MB upload limit does not bound that. | Without it one small upload could use hundreds of megabytes of the worker's memory (Pillow only *warns* above about 89 million pixels, and raises above twice that). |
| `if not key.startswith("originals/")` | Only objects under `originals/` can be thumbnailed. | A key like `thumbnails/x.png` would produce thumbnails of thumbnails. |
| `size = int(payload.get("size", "128"))` and the range test | A string payload value is turned into a number, and must be sensible. | Without the limit a client could ask for a 100,000-pixel "thumbnail". |
| `s3.get_object(...)["Body"].read()` | Downloads the whole original (at most 5 MB: the upload limit of step 19) into memory. | |
| `Image.open(io.BytesIO(data))` | Opens the image from memory. A file that is not an image raises `UnidentifiedImageError`. | |
| `ImageOps.exif_transpose(img)` | Applies the "rotate me" flag that phones put in photos, so thumbnails are not sideways. | |
| `img.convert("RGB")` when the mode is unusual | PNG cannot store some modes (CMYK from some JPEGs). | Those images would fail with `cannot write mode CMYK as PNG`. |
| `img.thumbnail((size, size))` | Shrinks the image **in place** so that it fits in the box, keeping the proportions. It never enlarges. | |
| `img.save(out, format="PNG")` | Encodes to PNG in memory. | |
| `out_key = f"thumbnails/{name}-{size}.png"` | The result goes under `thumbnails/`, named after the original **and the size**. The same job run twice writes the same key: a redo **overwrites** instead of piling up copies, so redoing a job is harmless (it is **idempotent**). | Without the size in the name, two sizes of one image would overwrite each other (found while testing, see below). |
| `s3.put_object(..., ContentType="image/png")` | Stores the thumbnail with its type. | |
| `return {"result_key": ..., "result_size": ...}` | The handler returns what to record in the job's hash. | |
| `HANDLERS = {"thumbnail": ..., "noop": ...}` | The table from `type` to function. An unknown type is refused. | |
| `try: ... except Exception as exc:` in `process()` | Everything that can fail with **this** job is inside: the job becomes `failed` with `error`, and the worker survives. | Outside the `try`, one bad job would crash the worker, again and again (restart policy + start-up requeue). |
| `**result` in the final `hset` | Adds `result_key` and `result_size` to the record next to `status` and `finished_at`. | |
| `S3_*` in the compose file, `s3-init: service_completed_successfully` | The settings, and the worker starts only after the bucket exists. | |

**A test image.** The host has no Pillow, so a throw-away container made from the **worker image** (which has it) creates two images in your current folder:
```bash
D=$(pwd -W)
MSYS_NO_PATHCONV=1 docker run --rm -v "$D:/out" --entrypoint python aws-local-lab-worker:0.1.0 -c "
from PIL import Image
big = Image.new('RGB', (1200, 800))
big.putdata([(x * 255 // 1200, y * 255 // 800, 128) for y in range(800) for x in range(1200)])
big.save('/out/big.png')
Image.new('RGB', (100, 60), (200, 40, 40)).save('/out/small.png')
print('made big.png', big.size, 'and small.png (100, 60)')
"
echo "just text, not an image" > notes.txt
```
```text
made big.png (1200, 800) and small.png (100, 60)
```
(`-v "$D:/out"` shows your folder to the container as `/out`; `--entrypoint python` replaces the worker's normal start command by a Python one-liner.)

**Rebuild and start:**
```bash
docker compose up -d --build --wait worker
docker compose exec -T worker python -c "import PIL, boto3, redis; print('Pillow', PIL.__version__, '| boto3', boto3.__version__, '| redis', redis.__version__)"
```
```text
worker-1  | 2026-11-22 21:34:08,320 INFO worker started (job types: thumbnail, noop)
Pillow 13.0.0 | boto3 1.44.6 | redis 8.1.0
```

**Check 1 — the step's check: the thumbnail object exists in the bucket.** Upload the big image through the API, ask for a thumbnail with the returned key, poll, then look at the worker's log, the job's record and the bucket:
```bash
curl -s -F "file=@big.png;type=image/png" localhost:8088/upload               # note the "key"
curl -s -X POST localhost:8088/jobs -H 'Content-Type: application/json' -d '{"type":"thumbnail","payload":{"key":"<the key>"}}'
curl -s localhost:8088/jobs/<the id>                                           # until "done"
docker compose logs worker
rcli hgetall job:<the id>
docker compose run --rm --no-deps -T --entrypoint sh s3-init -c 'aws --endpoint-url http://s3:8333 s3 ls "s3://$S3_BUCKET/" --recursive'
```
```text
key=originals/b0a9fa9c1bf64d9eb432bb16e1717ac2-big.png (4870 bytes)
{"id":"705a6c7a460e4c25a83041355654dcef","type":"thumbnail","status":"queued","created_at":"2026-11-22T21:34:35.797283Z","payload":{"key":"originals/b0a9fa9c1bf64d9eb432bb16e1717ac2-big.png"}}
poll 1: done
worker-1  | 2026-11-22 21:34:35,843 INFO picked up job 705a6c7a460e4c25a83041355654dcef (thumbnail)
worker-1  | 2026-11-22 21:34:35,885 INFO job 705a6c7a460e4c25a83041355654dcef done {'result_key': 'thumbnails/b0a9fa9c1bf64d9eb432bb16e1717ac2-big.png', 'result_size': '128x85'}
status done
started_at 2026-11-22T21:34:35.842813+00:00
finished_at 2026-11-22T21:34:35.884847+00:00
result_key thumbnails/b0a9fa9c1bf64d9eb432bb16e1717ac2-big.png
result_size 128x85
   4870 originals/b0a9fa9c1bf64d9eb432bb16e1717ac2-big.png
    295 thumbnails/b0a9fa9c1bf64d9eb432bb16e1717ac2-big.png
```
(The `rcli` helper is the one of step 22; `hgetall` lines paired and filtered; the bucket listing is cut to the two objects of this test, and ids are shown in full where they matter. **This first run used the first version of the code, whose thumbnail key had no size in it**: the key became `…-big-128.png` after the fix described in Check 4. Nothing else differs.) The job went `queued` → `done` in **under 50 ms** (`started_at` to `finished_at`), the 1200 × 800 image became **128 × 85**, and a new object `thumbnails/…` of 295 bytes sits in the bucket next to the 4,870-byte original.

**Check 2 — read the thumbnail back and open it.** A throw-away container from the worker image (it has boto3 and Pillow, and the S3 settings) downloads the object and opens it with Pillow:
```bash
docker compose run --rm --no-deps -T --entrypoint python worker -c "
import io, os, boto3
from botocore.config import Config
from PIL import Image
s3 = boto3.client('s3', endpoint_url=os.environ['S3_ENDPOINT_URL'], aws_access_key_id=os.environ['S3_ACCESS_KEY'], aws_secret_access_key=os.environ['S3_SECRET_KEY'], region_name='us-east-1', config=Config(s3={'addressing_style': 'path'}))
obj = s3.get_object(Bucket=os.environ['S3_BUCKET'], Key='<the result_key of the job>')
img = Image.open(io.BytesIO(obj['Body'].read()))
print('format', img.format, '| size', img.size, '| mode', img.mode, '| content-type', obj['ContentType'], '| bytes', obj['ContentLength'])
"
```
```text
format PNG | size (128, 85) | mode RGB | content-type image/png | bytes 295
```
It is a valid **PNG** of **128 × 85** pixels (1200 × 800 shrunk by a factor 9.375, proportions kept), stored with the right content type.

**Check 3 — other sizes, and everything that can go wrong.** A small shell helper submits a job, polls until it is `done` or `failed` and prints the result or the error from the record:
```bash
job() { local id=$(curl -s -X POST localhost:8088/jobs -H 'Content-Type: application/json' -d "$2" | sed -n 's/.*"id":"\([0-9a-f]*\)".*/\1/p'); for i in $(seq 10); do s=$(curl -s localhost:8088/jobs/$id | sed -n 's/.*"status":"\([a-z]*\)".*/\1/p'); [ "$s" = done ] || [ "$s" = failed ] && break; sleep 1; done; printf '%-34s -> %s | %s\n' "$1" "$s" "$(rcli hmget job:$id result_size error | tr '\n' ' ')"; }
```
```text
thumbnail, default size (128)      -> done | 128x85
thumbnail, size 64                 -> done | 64x43
image smaller than the size        -> done | 100x60
a text file, not an image          -> failed |  UnidentifiedImageError: cannot identify image file <_io.BytesIO object at 0x7bbda280be70>
a key that does not exist          -> failed |  NoSuchKey: An error occurred (NoSuchKey) when calling the GetObject operation: The specified key does not exist.
a key outside originals/           -> failed |  ValueError: payload.key must be an object under originals/
size out of range (5000)           -> failed |  ValueError: payload.size must be between 16 and 1024
unknown job type                   -> failed |  ValueError: unknown job type 'resize'
noop still works                   -> done | 
--- the worker is still running after the failures: Up About a minute; queues: jobs=0 processing=0
```
(The `echo` of the last line was added by hand.)
Reading it: size 64 gives **64 × 43**; the 100 × 60 image is **not enlarged** (`thumbnail()` only shrinks); and **every** failure ends as `failed` with a message that says why (an uploaded text file, a missing object, a rejected payload, an unknown type). The worker was still running afterwards, with both lists empty: a bad job costs one job, not the worker. This is the first time the `failed` path of step 23 was exercised.

**Check 3, second part — an image with too many pixels** (added after the review of this step). Two PNGs made with Pillow: `large.png`, 5000 × 4000 (20 million pixels, 67 KB) and `huge.png`, 10000 × 10000 (**100 million** pixels, but only 315 KB, well under the 5 MB upload limit). With `MAX_PIXELS = 25_000_000`:
```text
1200x800 (as before)           -> done | 128x85
5000x4000 (20 million pixels)  -> done | 128x102
10000x10000 (100 million pixels) -> failed |  ValueError: image too large: 10000x10000 pixels (max 25000000)
worker: Up 22 seconds, restarts: 0; queues: jobs=0 processing=0
```
The 20-million-pixel image is shrunk normally (to 128 × 102); the 100-million-pixel one is refused **before** being decoded, with a clear message, and the worker is unaffected (no restart, both lists empty). (The first version of the worker had no such limit: the reviewer pointed out that a small compressed PNG can need hundreds of megabytes when decoded.)

**Check 4 — a design flaw, found by this check.** In the run above the first two jobs concerned the same image, with sizes 128 and 64. In the **first version** the result key was `thumbnails/<name>.png` for both, so the second **overwrote** the first. After adding the size to the key (the code shown above), three jobs for one image (128, then 64, then 128 again) give:
```text
    295 521ea3eb34cb4ba8b59025da7868fd32-big-128.png
    196 521ea3eb34cb4ba8b59025da7868fd32-big-64.png
21:35:36,590 job 442c9944... done {'result_key': 'thumbnails/521ea3eb34cb4ba8b59025da7868fd32-big-128.png', 'result_size': '128x85'}
21:35:36,619 job 1983e6ed... done {'result_key': 'thumbnails/521ea3eb34cb4ba8b59025da7868fd32-big-64.png', 'result_size': '64x43'}
21:35:36,663 job 708564c5... done {'result_key': 'thumbnails/521ea3eb34cb4ba8b59025da7868fd32-big-128.png', 'result_size': '128x85'}
```
(Listing of `thumbnails/` filtered to this image; ids cut.) **Two** thumbnails exist for three jobs: the repeated 128-pixel job wrote to the same key as the first one and replaced it. Different jobs give different keys, the **same** job always the same key: that is what makes a redo (at-least-once delivery, [step 23](#step-23--the-worker-container)) harmless.

**Clean up the test files** (the bucket held 22 test objects from this and earlier tests): `aws s3 rm "s3://$S3_BUCKET/" --recursive` through the `s3-init` service, as in the Clean up of Lab 06.

**Regression check — the whole suite:**
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
(Trimmed to the headings and summary lines; `make` exited with code 0 on this run. As noted in step 23, `02_failover` is intermittent on this machine and may show its `59 of 60` failure on another run.)

**What just happened:**
- The lab now has a **complete asynchronous pipeline with a real task**: upload → queue → worker → thumbnail in the bucket, and none of the three programs waits for another.
- The worker is **generic**: it dispatches on the job's `type`, so the next kind of job is one function and one entry in `HANDLERS`.
- **Untrusted input means a failure path is part of the feature.** Five different bad jobs each ended as `failed` with a readable reason, and the worker kept going.
- **Idempotent output keys** turn at-least-once delivery from a risk into a non-issue: running a job again rewrites the same object.
- **Open points for step 25:** (1) `GET /jobs/{id}` does not show `result_key` yet: the API builds its answer from a fixed set of fields and ignores the extra ones the worker adds, so a client cannot learn where the thumbnail is without reading Redis; step 25 (the test) will need that, or the convention `thumbnails/<name>-<size>.png`. (2) The worker reads each original fully into memory (at most 5 MB) and refuses images of more than 25 million pixels, but the worker service has **no memory limit** of its own (`mem_limit`). (3) The `failed` jobs are not retried: a temporary S3 outage ends the job as `failed` instead of trying again.

## 5–11. To be completed at the end of Lab 07
Verify, Troubleshooting, Going to real AWS, Clean up, Check your understanding, Exercises and Further reading are written when the lab ends (step 25). The problems met so far:

| Symptom | Cause | Fix |
|---|---|---|
| After `docker kill` the worker is **not** started again by `restart: unless-stopped` (`docker compose ps worker` prints nothing, `RestartCount` stays 0) | Docker applies a restart policy when the container's process exits by itself, once it has started successfully (a start counts as successful after 10 seconds of running). `docker kill` and `docker stop` are deliberate stops. | Start it yourself (`docker compose start worker`). A real crash (exit code 1, out of memory) is restarted: see step 23, Check 5. |
| `make test` fails in `tests/06_storage.sh` with `upload failed (HTTP 000)` after the worker was added | Right after `04_persistence.sh` restarts the stack, the first upload can answer `502` after about 10 s (`Read timeout on endpoint URL` in the API log) and the test's 10 s curl limit gave up. | `tests/06_storage.sh` tries the first upload up to 5 times (commit `dec7783`). |
| A job stays `processing` forever | Its worker died and no worker has started since: the id waits in `queue:processing`. | Start a worker: at start-up it requeues the id and redoes the job (step 23, Check 3). |
