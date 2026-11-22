# Databases 08 — Connection pooling

> **Course:** [Databases](./README.md)  ·  **Time:** ~45 min  ·  **Needs:** [Databases 05](./05-sqlalchemy.md) (the engine and the session) and [Databases 03](./03-postgresql.md) (the server); [Docker 01](../docker/01-images-and-containers.md) for the exercise
> **Used in the labs:** [Lab 04, step 11](../../labs/04-database.md) (`create_engine(DATABASE_URL, pool_pre_ping=True)` in `api/db.py`, three API replicas sharing one Postgres)

## What you will learn
- Say what a **database connection** costs and why programs **reuse** them through a **pool**.
- Read a pool's settings (`pool_size`, `max_overflow`, `pool_timeout`) and what happens when every connection is busy.
- Explain the **limit on the server side**, `max_connections`, and why it must be shared between all your replicas.
- Do the sum for the lab (3 replicas) and see what an overload looks like.
- Name the tools that pool on the server side: PgBouncer and RDS Proxy.

## Words you need
| Word | Plain-words meaning |
|---|---|
| **Connection** | An open line between your program and the database: a network connection plus a login. PostgreSQL starts **one server process per connection**. |
| **Connection pool** | A box of already-open connections that your program **borrows** and gives back, instead of opening a new one each time. |
| **Checkout / check in** | Borrow a connection from the pool / give it back. In SQLAlchemy `engine.connect()` is a checkout; closing it is a check in (the real connection stays open). |
| **`pool_size`** | How many connections the pool keeps open (default 5). |
| **`max_overflow`** | How many **extra** connections it may open in a burst, beyond `pool_size` (default 10); they are closed again after use. |
| **`pool_timeout`** | How long a program waits for a free connection when all are borrowed (default 30 s) before giving up. |
| **`NullPool`** | "No pool": every checkout opens a new connection and every check in closes it. |
| **`max_connections`** | The most connections one PostgreSQL server accepts at once (default 100). |
| **Reserved slots** | A few of those connections (3 by default) are kept for superusers, so an administrator can always get in. |
| **Replica** | One copy of the application. The lab runs three API replicas, **each with its own pool**. |
| **Pooler** | A separate program or service (PgBouncer, **RDS Proxy** in AWS) that sits between the applications and the database and shares a small number of real connections among many clients. |

## The idea
**Analogy.** A **taxi rank** against a **new car for every trip**. Buying and registering a car for each journey would be absurd; a rank keeps a few taxis waiting. Passengers take one, ride, and the taxi returns to the rank. When all taxis are out, passengers queue for a while and then give up. And the city only has so many parking spaces (the database's limit) for all taxi companies together.

**Precisely.** Opening a connection to PostgreSQL costs a network handshake, a login and the creation of a **server process**, a few milliseconds each time: far more than a small query. A **pool** keeps connections open: `engine.connect()` borrows one that is idle, and the `with` block gives it back. The pool is **per Python process**, so a pool of at most `pool_size + max_overflow` connections, in each of R replicas, can reach `R × (pool_size + max_overflow)` at the server, and that product must stay below `max_connections` minus the reserved slots. Default SQLAlchemy numbers (5 + 10) with the lab's 3 replicas: `3 × 15 = 45`, under the server's 100.

```mermaid
flowchart LR
  subgraph api1["api replica 1"]
    p1["pool: 5 (+10 overflow)"]
  end
  subgraph api2["api replica 2"]
    p2["pool: 5 (+10 overflow)"]
  end
  subgraph api3["api replica 3"]
    p3["pool: 5 (+10 overflow)"]
  end
  p1 --> pg[("PostgreSQL<br/>max_connections = 100<br/>3 reserved for superusers")]
  p2 --> pg
  p3 --> pg
```

## The code or config, line by line
The lab's own line, in `api/db.py` ([Lab 04, step 11](../../labs/04-database.md)):
```python
engine = create_engine(DATABASE_URL, pool_pre_ping=True)   # one engine = one pool, shared by the whole process
```
| Part | What it does | If you change or remove it |
|---|---|---|
| `create_engine(DATABASE_URL, ...)` | Creates the engine **and its pool** (a `QueuePool`: 5 connections, 10 overflow, 30 s timeout). Opens nothing until the first use. | Creating an engine **per request** would defeat the pool: a new pool each time. |
| `pool_pre_ping=True` | Tests a pooled connection with a tiny query before lending it, so one that died (database restarted) is replaced silently. | Without it, the first request after a database restart fails with a broken connection. |

The experiment, `pool_demo.py`. It runs with the API image, so `from db import engine` is the lab's real engine:
```python
"""Connection pooling: the project's engine (api/db.py) against a throw-away PostgreSQL."""
import os
import time

import psycopg
from sqlalchemy import create_engine, text
from sqlalchemy.pool import NullPool

from db import engine  # the engine of the lab's API: it owns a pool

URL = os.environ["DATABASE_URL"]
APP_URL = "postgresql://app:app-pass@localhost:5432/postgres"  # an ordinary role, not a superuser


def backend_ids(eng, uses):
    """The PostgreSQL process id behind each of `uses` successive connections."""
    ids = []
    for _ in range(uses):
        with eng.connect() as conn:
            ids.append(conn.scalar(text("select pg_backend_pid()")))
    return ids


print("1. the lab's engine and its pool")
print("  ", engine.pool.status())

print("2. five uses in a row: how many PostgreSQL processes served them?")
print("   pooled engine :", len(set(backend_ids(engine, 5))), "process")
print("   no pool       :", len(set(backend_ids(create_engine(URL, poolclass=NullPool), 5))), "processes")

print("3. 300 tiny queries, one connection checkout each")
for label, eng in (("pooled", engine), ("no pool", create_engine(URL, poolclass=NullPool))):
    start = time.perf_counter()
    for _ in range(300):
        with eng.connect() as conn:
            conn.execute(text("select 1"))
    print(f"   {label:8}: {time.perf_counter() - start:.2f} s")

print("4. a pool of 2, no overflow, 2 s patience: a third client has to wait")
small = create_engine(URL, pool_size=2, max_overflow=0, pool_timeout=2)
held = [small.connect(), small.connect()]  # both connections are checked out and kept
start = time.perf_counter()
try:
    small.connect()
except Exception as exc:
    print(f"   after {time.perf_counter() - start:.1f} s: {type(exc).__name__}: {str(exc).split(' (Background')[0]}")
for conn in held:
    conn.close()

print("5. PostgreSQL itself only accepts max_connections clients")
with engine.connect() as conn:
    print("   max_connections =", conn.scalar(text("show max_connections")))
    print("   already open, held by the idle pools of this script (this one included):",
          conn.scalar(text("select count(*) from pg_stat_activity where backend_type = 'client backend'")))
opened = []
try:
    while True:
        opened.append(psycopg.connect(APP_URL))
except psycopg.OperationalError as exc:
    print(f"   {len(opened)} connections open, the next one is refused:", str(exc).strip().splitlines()[0])
for conn in opened:
    conn.close()
```
| Line(s) | What it does | If you change or remove it |
|---|---|---|
| `from db import engine` | Imports the lab's engine (`DATABASE_URL` comes from the environment). | |
| `select pg_backend_pid()` | Asks PostgreSQL for the id of **the server process** serving this connection: the same id means the same connection was reused. | |
| `poolclass=NullPool` | An engine **without** a pool: each checkout opens a real connection. | |
| `for ... in range(300)` | 300 checkouts of the tiny query `select 1`, timed with `perf_counter`. | |
| `pool_size=2, max_overflow=0, pool_timeout=2` | A deliberately tiny pool. | With a bigger `max_overflow` the third client would get an extra connection instead of waiting. |
| `held = [small.connect(), small.connect()]` | Borrows both connections and keeps them: the pool is empty. | |
| `small.connect()` (third) | Has to wait; gives up after `pool_timeout` with `TimeoutError`. | |
| `show max_connections` | The server's own limit. | |
| `psycopg.connect(APP_URL)` in a loop | Opens plain connections as an ordinary role (`app`) until the server refuses one. A **superuser** would still get through, because of the reserved slots. | |

## The commands
| Command / flag | Meaning |
|---|---|
| `docker run -d --rm --name course-pg8 -e POSTGRES_PASSWORD=... postgres:18.7-alpine3.24 -c max_connections=10` | A throw-away PostgreSQL. Everything after the image name goes to the server: `-c max_connections=10` sets the limit to 10 so the experiment can reach it. |
| `docker exec course-pg8 psql -U postgres -q -c "create role app login password 'app-pass'"` | Creates an ordinary (non-superuser) role `app` that may log in. |
| `docker run -d --name course-pool8 --network container:course-pg8 -e DATABASE_URL=... aws-local-lab-api:0.1.0 sleep 900` | A second container from the project's API image that **shares the database container's network**, so `localhost:5432` is the database ([Databases 05](./05-sqlalchemy.md)). |
| `docker cp pool_demo.py course-pool8:/app/pool_demo.py` | Copy the script into the container (into `/app`, next to `db.py`). |
| `docker exec course-pool8 python pool_demo.py` | Run it. |

## Hands-on
Throw-away containers (`postgres:18.7-alpine3.24` and the project's `aws-local-lab-api:0.1.0`). Save `pool_demo.py`, then:
```bash
export MSYS_NO_PATHCONV=1
docker run -d --rm --name course-pg8 -e POSTGRES_PASSWORD=demo-only-not-a-secret postgres:18.7-alpine3.24 -c max_connections=10
until docker exec course-pg8 pg_isready -U postgres -q; do sleep 1; done; sleep 2
docker exec course-pg8 psql -U postgres -q -c "create role app login password 'app-pass'"
docker run -d --name course-pool8 --network container:course-pg8 \
  -e DATABASE_URL=postgresql+psycopg://postgres:demo-only-not-a-secret@localhost:5432/postgres \
  aws-local-lab-api:0.1.0 sleep 900
docker cp pool_demo.py course-pool8:/app/pool_demo.py
docker exec course-pool8 python pool_demo.py
```
```text
1. the lab's engine and its pool
   Pool size: 5  Connections in pool: 0 Current Overflow: -5 Current Checked out connections: 0
2. five uses in a row: how many PostgreSQL processes served them?
   pooled engine : 1 process
   no pool       : 5 processes
3. 300 tiny queries, one connection checkout each
   pooled  : 0.22 s
   no pool : 1.43 s
4. a pool of 2, no overflow, 2 s patience: a third client has to wait
   after 2.0 s: TimeoutError: QueuePool limit of size 2 overflow 0 reached, connection timed out, timeout 2.00
5. PostgreSQL itself only accepts max_connections clients
   max_connections = 10
   already open, held by the idle pools of this script (this one included): 3
   4 connections open, the next one is refused: connection failed: connection to server at "127.0.0.1", port 5432 failed: FATAL:  remaining connection slots are reserved for roles with the SUPERUSER attribute
```
**How to read it:**
- **1:** the lab's engine has a pool of 5 and nothing open yet (`Connections in pool: 0`): connections are made on first use.
- **2:** five uses in a row were served by **1** PostgreSQL process with the pool (the same connection, borrowed again and again), against **5** without it (five connections opened and closed).
- **3:** 300 tiny queries took `0.22 s` pooled and `1.43 s` without a pool: the time is the cost of **opening connections**, about 0.7 ms against 4.8 ms per query here. On a database across a network (RDS) the difference is bigger.
- **4:** with both connections of a 2-connection pool borrowed, the third client waited its 2 seconds and got `TimeoutError: QueuePool limit of size 2 overflow 0 reached`. In an API this is a request that hangs and then fails: the pool was too small, or connections are held too long.
- **5:** the server says `max_connections = 10`; it keeps 3 for superusers, so ordinary roles get **7**. **3** were already taken by this script's own idle pools (the lab engine's one, and the 2 of the small pool that had been closed but stayed open), so only **4** more got in, and the next failed with `FATAL: remaining connection slots are reserved for roles with the SUPERUSER attribute`. Idle pooled connections **count** against the server's limit.

**The lab itself.** In the running lab, `show max_connections` in the real Postgres answers `100`, and after 30 sequential requests through the three replicas `pg_stat_activity` shows `4` client connections (1 is the query itself): one pooled connection per replica, because sequential requests reuse the same one.

## What if…?
**…the sum is wrong?** Step 5 is a small version of it: more connection slots wanted than the server has, and the newcomer is refused at once. In the lab, 3 replicas with the default pool can open up to 45 of the 100. At 10 replicas the worst case is 150: some pools could not fill, and requests would fail with `too many clients` in a busy moment. Three ways out: **lower** `pool_size` and `max_overflow`, **raise** `max_connections` (each connection costs memory on the server), or put a **pooler** such as PgBouncer or **RDS Proxy** in between, which multiplexes many application connections onto few real ones.

## In short
1. Opening a connection is expensive; a **pool** keeps connections open and lends them. `engine = create_engine(...)` creates the pool once per process; request code borrows and returns.
2. A pool has limits (`pool_size`, `max_overflow`, `pool_timeout`): when all are busy, callers wait and may time out.
3. The server also has a limit, `max_connections`, shared by **all** replicas and their idle connections: check `replicas × (pool_size + max_overflow)` against it.

## Check your understanding
1. Why are five queries on a pooled engine served by one PostgreSQL process, and by five without a pool?
2. What happened to the third client of the 2-connection pool, and after how long?
3. With `max_connections = 10` and 3 reserved slots, how many connections can an ordinary role open? Why did the experiment manage only 4 more?
4. The lab has 3 API replicas with SQLAlchemy's default pool. What is the worst-case number of connections to Postgres, and is it under the default limit?
5. What does RDS Proxy (or PgBouncer) change?

<details><summary>Answers</summary>

1. With a pool, the connection is returned to the pool after each use and borrowed again, so the same server process answers; without a pool each checkout opens a new connection (a new server process) and each check in closes it.
2. It waited for a free connection and gave up after the `pool_timeout` of 2 seconds with a `TimeoutError` (`QueuePool limit of size 2 overflow 0 reached`).
3. 10 − 3 = **7**. Three were already open, held by the idle pools of the script (the lab engine's 1 and the small pool's 2), so 4 more fitted. Idle pooled connections count against the limit.
4. `3 × (5 + 10) = 45`, under the default 100 (and the real lab shows `max_connections = 100`).
5. Applications connect to the **pooler**, which keeps a small number of real connections to the database and shares them among many clients. The database sees few connections even with many replicas or short-lived clients (such as serverless functions).

</details>

## Official documentation
- [SQLAlchemy: connection pooling](https://docs.sqlalchemy.org/en/20/core/pooling.html) (including `QueuePool`, `NullPool`, `pool_pre_ping`)
- [PostgreSQL: connection settings (`max_connections`, `superuser_reserved_connections`)](https://www.postgresql.org/docs/current/runtime-config-connection.html)
- [AWS: Amazon RDS Proxy](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy.html) and [PgBouncer](https://www.pgbouncer.org/)

## Where you use this in the project
- [Lab 04, step 11](../../labs/04-database.md): `api/db.py` creates one engine, hence one pool, per API process; the lab runs three of them.
- [Databases 05](./05-sqlalchemy.md): the engine and the `Session` that borrows a connection per request (`get_db` in `api/main.py`).
- [AWS 06 - RDS](../aws/06-rds.md): RDS has its own `max_connections` (set by the instance size) and RDS Proxy as the managed pooler.
- Labs 11 and 12 (planned): when Kubernetes scales the API to many pods, every new pod brings its own pool.
