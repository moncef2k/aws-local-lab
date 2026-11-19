# Lab 04 — Database (RDS)

> **AWS equivalent:** Amazon RDS for PostgreSQL, DB subnet groups, security groups, snapshots  ·  **Time:** ~75 min  ·  **Difficulty:** ★★☆
> **Builds on:** [Lab 03](./03-networking.md)  ·  **Reference solution:** commits `b29c466` (step 10), `cc957ec` (step 11), `d7ac631` (step 12), `bde01cf` (step 13) and `2f14ada` (step 14) on `dev`

> **Status:** complete (steps 10–14).

## 1. What you will learn
- Explain why an application keeps its data in a **database** and not in its own files or memory.
- Name the parts of an AWS RDS database (instance, engine, storage, subnet group, security group, endpoint) and their local counterparts.
- Run PostgreSQL in a container: private network only, data in a **named volume**, password from `.env`, with a healthcheck.
- Prove that the database is not reachable from your machine, and that its data outlives its container.
- Describe a **migration** (a versioned change to the database structure), write one with **Alembic**, and run it as a one-shot job before the API starts.
- Give yourself **admin access** to a private database safely: a side door that is off by default (a Compose **profile**), local-only and still password-protected.
- Write **tests** that prove the two promises that matter most: the data survives a full restart, and the database stays unreachable from outside.
- Build a **CRUD** API (create, read, update, delete) that stores its data in the database, with validated input and one database session per request.
- Explain what an **ORM** (SQLAlchemy) does: you describe tables as Python classes and the library writes the SQL.

## 2. Theory

### 2.1 The concept
So far the API remembers nothing: ask it the same question twice and it answers from scratch, and if a replica restarts, whatever it knew is gone.
That is deliberate (**stateless** apps are easy to copy and replace, see Lab 01), but real applications must remember: users, notes, orders.

A **database** is a specialised program whose only job is to store data safely and answer questions about it quickly. Think of a **filing room with a
clerk**: the clerk (the database server) keeps the folders in order, finds any folder in milliseconds, makes sure two people never write on the same page
at once, and does not lose a folder when the lights go out. The application never opens the cabinets itself; it asks the clerk.

This lab uses a **relational** database, **PostgreSQL**: data lives in *tables* (rows and columns) that can be linked to each other, and you ask questions in the
SQL language. The course module [Databases 01](../courses/README.md) explains the vocabulary from zero.

A new database is empty: someone must create the tables. And later, when the application changes (a new column, a new table), every copy of the database must change
in the **same order**. A **migration** is a small numbered script that makes one such change ("0001: create the `notes` table"); the database remembers which numbers it has
already seen, so running the migrations twice is harmless. Think of the **numbered renovation orders** of a building: order 7 is only carried out once, after order 6.
Writing the SQL by hand for every table is tedious, so the application uses an **ORM** (*object-relational mapper*, here **SQLAlchemy**): a Python class `Note` stands for the
table `notes`, one object for one row, and the library produces the SQL. **Alembic** is the migration tool of the SQLAlchemy family.

To expose the data, the API offers **CRUD** operations: **C**reate, **R**ead, **U**pdate, **D**elete, the four things you can do with a stored record. Over HTTP each one has its
usual *verb* and *status code*: `POST` creates (answer `201 Created`), `GET` reads (`200`, or `404 Not Found` if it does not exist), `PUT` replaces (`200`), `DELETE` removes (`204 No Content`,
"done, nothing to send back"). Think of the clerk's **counter**: you can file a new folder, ask to see one, hand in a corrected version, or have one shredded. The API also
**checks what you hand in** before it reaches the database (a note needs a title): a *validation* library, **Pydantic**, does that, and answers `422` when the input is wrong.

Two consequences shape the architecture:
- The database is the one place that **must not lose data**, so it gets its own protected storage (a *volume*) and is never thrown away casually.
- It holds everything valuable, so it lives on the **private** network and nothing outside may talk to it except the API ([Lab 03](./03-networking.md)).

### 2.2 How AWS does it
**Amazon RDS** (Relational Database Service) runs databases for you. You choose an engine (PostgreSQL, MySQL…), a size, and AWS handles installation, patches, backups and
failover:

| RDS piece | What it is |
|---|---|
| **DB instance** | The database server itself (engine + version + CPU/RAM size). |
| **Storage** | A disk (EBS) attached to the instance, with a size and a type; this is where the data lives and survives restarts. |
| **DB subnet group** | The list of **private** subnets where the instance may live (at least two zones). |
| **Security group** | The firewall: "allow 5432 only from the API's security group" ([Networking 07](../courses/networking/07-firewalls-and-security-groups.md)). |
| **Endpoint** | A DNS name (like `mydb.abc123.eu-west-1.rds.amazonaws.com`) that applications use; AWS repoints it on failover. |
| **Master user and password** | The first account; often stored in AWS Secrets Manager rather than in a file. |
| **Backups / snapshots** | Automatic daily backups and manual snapshots, restorable to a new instance. |
| **Multi-AZ** | A standby copy in another zone that takes over automatically. |

In the console: **RDS → Databases**, plus **VPC → Security groups** for the firewall.

### 2.3 How we reproduce it locally
| Concept | AWS | This lab |
|---|---|---|
| DB instance | RDS DB instance (PostgreSQL) | the `postgres` service (official image `postgres:18.7-alpine3.24`) |
| Storage that survives | EBS volume | Docker **named volume** `pgdata` |
| Private placement | private subnets via the subnet group | the `private` (internal) Docker network, and **no** `ports:` |
| Who may connect | security group rule from the API's group | membership of `private`; later, the password |
| Endpoint | DNS name of the instance | the service name `postgres` (Docker DNS resolves it on `private`) |
| Master password | Secrets Manager | `POSTGRES_PASSWORD` in `.env` (gitignored) |
| Connection string given to apps | endpoint + credentials injected into the task (env var or secret) | `DATABASE_URL`, built in `docker-compose.yml` from the `POSTGRES_*` variables |
| Admin access to a private database | a bastion host, or Systems Manager Session Manager port forwarding, or a VPN; never a public database | the `db-proxy` service (socat), only with `--profile admin`, published on `127.0.0.1` |
| Running migrations | a task or pipeline step before the deployment (ECS run-task, CI job, Lambda) | the one-shot `migrate` service: `alembic upgrade head`, then it exits |
| Health | RDS status `Available` | Docker healthcheck with `pg_isready` |
| Snapshots, Multi-AZ, patching | managed by AWS | not simulated (backups: course module [Databases 09](../courses/README.md)) |

### 2.4 Diagram
```mermaid
flowchart LR
  you((You)) -->|127.0.0.1:80| lb
  subgraph public["public network"]
    lb["lb: Nginx"]
    proxy["db-proxy (socat)<br/>profile admin only"]
  end
  subgraph private["private network (internal)"]
    api["api x3"]
    mig["migrate<br/>(one-shot job)"]
    pg[("postgres<br/>:5432")]
    vol[("volume pgdata")]
  end
  lb --> api
  api --> pg
  mig -->|"alembic upgrade head"| pg
  mig -. "api starts after it succeeds" .-> api
  pg --- vol
  you -. "no route, no port: blocked" .-> pg
  you -. "127.0.0.1:5432, only with --profile admin" .-> proxy
  proxy -.-> pg
```

## 3. Prerequisites
- [Lab 03](./03-networking.md) completed: `make up` runs, `make test` is green.
- A database password in your `.env`. Compose refuses to start without one (on purpose). Generate a random fake one and append it without printing it:
  ```bash
  printf '\nPOSTGRES_PASSWORD=%s\n' "$(openssl rand -hex 12)" >> .env
  ```
  (or add any `POSTGRES_PASSWORD=...` line by hand). `.env.example` shows the variables; `.env` is gitignored and never committed.

## 4. Steps

> Try each step yourself first, then compare with the reference commit.

### Step 10 — The Postgres container
**Why:** this is the "RDS instance" of the architecture: a database server on the private network, with storage that outlives the container and a password
that is not in the repository.

**Do it.** Add the service and a volume to `docker-compose.yml`:

```yaml
services:
  # ... api and lb unchanged ...

  # The database (RDS in AWS). Private network only, and no "ports:" at all: nothing on the
  # host can reach it, only containers on "private" (the API will, from step 11 on).
  postgres:
    image: postgres:18.7-alpine3.24
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-lab}
      POSTGRES_DB: ${POSTGRES_DB:-lab}
      # No default on purpose: a missing password stops "docker compose" with a clear message.
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?set POSTGRES_PASSWORD in .env (see .env.example)}
    volumes:
      # Postgres 18 images keep the data in /var/lib/postgresql/18/docker and declare
      # /var/lib/postgresql as their volume: the named volume goes there.
      - pgdata:/var/lib/postgresql
    networks:
      - private
    healthcheck:
      # $$ stops Compose from replacing the variables: the shell inside the container does it.
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 10s
      timeout: 3s
      retries: 5
      start_period: 10s

# ... networks unchanged ...

volumes:
  # Survives "docker compose down" (like an RDS storage volume survives a reboot).
  pgdata:
```
And add the variables to `.env.example` (placeholders only):
```bash
# Database (Lab 04). Fake local values. POSTGRES_PASSWORD has no default: put your own in .env.
POSTGRES_USER=lab
POSTGRES_DB=lab
POSTGRES_PASSWORD=change-me-local-only
```

| Line | What it does | If you change or remove it |
|---|---|---|
| `image: postgres:18.7-alpine3.24` | The official PostgreSQL image, **pinned** to exact version 18.7 on Alpine 3.24 (small). | `postgres:latest` would change under you (forbidden in this project); another major version needs a data migration. |
| `POSTGRES_USER` / `POSTGRES_DB` with `:-lab` | Name of the first account and database, created **the first time** the container starts. `:-lab` = "use `lab` if the variable is not set". | A different name only takes effect on an *empty* volume. |
| `POSTGRES_PASSWORD: ${...:?message}` | The password, read from `.env`. `:?message` = "if it is missing, stop with this message". | A default value here would put a password in the repository; remove the `:?` and an empty password would be accepted. |
| `volumes: - pgdata:/var/lib/postgresql` | Mounts the named volume where the image keeps its data (Postgres 18: `/var/lib/postgresql/18/docker`). | Without it the data lives in the container's writable layer and disappears with the container ([Docker 01](../courses/docker/01-images-and-containers.md)). |
| `networks: - private` | Joins only the internal network. | Add `public` and the database sits next to the load balancer. |
| *(no `ports:`)* | Nothing is published on your machine. | `ports: ["5432:5432"]` would open the database to the host: step 13 adds that only behind an admin profile. |
| `healthcheck: pg_isready ...` | Docker runs it every 10 s; `healthy` means Postgres accepts connections. `$$` keeps the variables for the container's shell. | Without it, `depends_on: condition: service_healthy` (step 11) cannot wait for the database. |
| `start_period: 10s` | Failures during the first 10 s do not count (first start creates the database). | Too short and a slow first start shows `unhealthy`. |
| top-level `volumes: pgdata:` | Declares the named volume; Docker stores it as `aws-local-lab_pgdata`. | Without the declaration Compose rejects the file. |

**Check the file first** (`-q` prints nothing when it is valid and never prints values). Before you added the password to `.env`, this is what you get:
```bash
docker compose config -q
```
```text
error while interpolating services.postgres.environment.POSTGRES_PASSWORD: required variable POSTGRES_PASSWORD is missing a value: set POSTGRES_PASSWORD in .env (see .env.example)
```
With the password in `.env` it prints nothing and exits with code 0. Start the stack and wait until all five containers are `healthy`:
```bash
docker compose up -d --remove-orphans
docker compose ps --format 'table {{.Service}}\t{{.Status}}\t{{.Ports}}'
```
```text
SERVICE    STATUS                    PORTS
api        Up 55 minutes (healthy)   8000/tcp
api        Up 55 minutes (healthy)   8000/tcp
api        Up 55 minutes (healthy)   8000/tcp
lb         Up 55 minutes (healthy)   127.0.0.1:80->80/tcp
postgres   Up 5 seconds (healthy)    5432/tcp
```
`5432/tcp` without an arrow means "the image *exposes* it inside Docker", not "published on your machine" (compare `127.0.0.1:80->80/tcp` for the load balancer).

**Check 1 — `pg_isready`, the step's check:**
```bash
docker compose exec -T postgres pg_isready -U lab -d lab
```
```text
/var/run/postgresql:5432 - accepting connections
```
`pg_isready` asks the server "are you accepting connections?" and answers with its address (here the local socket) and the verdict.

**Check 2 — it is only on `private`, and nothing is published:**
```bash
docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}network: {{$k}}{{end}}' $(docker compose ps -q postgres)
docker compose port postgres 5432
```
```text
network: aws-local-lab_private
:0
```
`:0` is Docker's way of saying "no published port".

**Check 3 — the host cannot reach it, a container on `private` can:**
```bash
timeout 3 bash -c '</dev/tcp/127.0.0.1/5432' && echo OPEN || echo "closed / not reachable from the host"
docker compose exec -T --index 1 api python -c "import socket; socket.create_connection(('postgres', 5432), timeout=3); print('api -> postgres:5432 connected')"
```
```text
closed / not reachable from the host
api -> postgres:5432 connected
```
The first command tries to open a TCP connection to port 5432 on your machine (Bash's built-in `/dev/tcp`); it fails. The second runs inside an API replica: the
name `postgres` resolves through Docker DNS and the port answers. This is the private-subnet picture of [Lab 03](./03-networking.md) with a database in it.

**Check 4 — the password protects connections from other containers:**
```bash
docker run --rm --network aws-local-lab_private -e PGCONNECT_TIMEOUT=5 postgres:18.7-alpine3.24 psql -h postgres -U lab -d lab -w -tA -c "select 1"
```
```text
psql: error: connection to server at "postgres" (172.23.0.6), port 5432 failed: fe_sendauth: no password supplied
```
A throw-away client container on `private` reaches the server but is refused without a password (`-w` = never ask for one). Inside the database container itself, `psql`
connects without a password: the image trusts connections that come from the container itself (its local socket and `127.0.0.1`); everything arriving over the
network needs the password.

**Check 5 — the data lives in the volume, not in the container:**
```bash
docker compose exec -T postgres psql -U lab -d lab -tA -c "create table persist_check (id serial primary key, note text); insert into persist_check (note) values ('written before the container was re-created'); select id, note from persist_check;"
docker compose up -d --force-recreate postgres        # new container, same volume
docker compose exec -T postgres psql -U lab -d lab -tA -c "select id, note from persist_check;"
docker compose exec -T postgres psql -U lab -d lab -tA -c "drop table persist_check;"
```
```text
CREATE TABLE
INSERT 0 1
1|written before the container was re-created
 Container aws-local-lab-postgres-1 Recreated
 Container aws-local-lab-postgres-1 Started
1|written before the container was re-created
DROP TABLE
```
(The container id changed, `af686299626b` then `d88be49bd9ba`, yet the row is still there.) `--force-recreate` throws the old container away and starts a new one from the same image; the table was
kept because it lives in `aws-local-lab_pgdata`. The last command cleans up the demo table. Step 14 repeats this idea as a proper test with `down && up`.

**Regression check:** the earlier tests still pass with Postgres in the stack, including the isolation test (only the load balancer publishes a port, `postgres` does not).
```bash
make test
```
```text
02_failover: all checks passed
02_load_balancing: all checks passed
03_network_isolation: all checks passed
```
(Trimmed to the summary lines. `02_failover.sh` is occasionally red by itself, one request out of 60 failing: a known intermittent problem of the Lab 02 test, see the
[Lab 02 troubleshooting entry](./02-load-balancing.md#6-troubleshooting). Re-run it.)

**What just happened:**
- You added the architecture's "RDS instance": a database on the private network that nothing but the API will be able to reach.
- The password is the first real **secret**: it lives in `.env` (ignored by Git), the repository only has a placeholder, and Compose refuses to start without it.
- Postgres creates the user, database and password **only when it starts on an empty volume**. Changing `POSTGRES_PASSWORD` in `.env` afterwards does *not* change the
  password stored in the existing volume; to start over you must delete the volume (`make clean`, which asks first).
- The data directory moved in version 18: the image keeps it in `/var/lib/postgresql/18/docker` and declares `/var/lib/postgresql` as its volume, so that is where the named volume is
  mounted (older tutorials mount `/var/lib/postgresql/data`; we did not test that path with 18).

### Step 11 — The database layer, the first migration and the `migrate` job
**Why:** the database is running but empty, and the API cannot talk to it. This step gives the API a *database layer* (SQLAlchemy), creates the `notes` table with a
versioned *migration* (Alembic), and makes that migration run automatically, once, before any API replica starts. (This step is larger than the usual one, about 8 files:
it was kept in one piece on purpose; each file is small.)

**Do it.**

1. Pin the new libraries. `api/requirements.txt` becomes:
   ```text
   fastapi==0.163.0
   uvicorn==0.54.0
   sqlalchemy==2.1.9
   psycopg[binary]==3.3.9
   alembic==1.20.1
   ```
   `psycopg` is the driver that speaks the PostgreSQL protocol; `[binary]` ships it precompiled so the slim image needs no compiler.

2. The database layer, `api/db.py` (new):
   ```python
   """Database layer: one engine (connection pool) and the table definitions.

   The address of the database comes from the environment, never from the code,
   like the endpoint of an RDS instance.
   """
   import os
   from datetime import datetime

   from sqlalchemy import DateTime, String, Text, create_engine, func
   from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker

   DATABASE_URL = os.environ["DATABASE_URL"]

   # pool_pre_ping tests a connection before using it, so a restarted database is not a problem.
   engine = create_engine(DATABASE_URL, pool_pre_ping=True)
   SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)


   class Base(DeclarativeBase):
       pass


   class Note(Base):
       __tablename__ = "notes"

       id: Mapped[int] = mapped_column(primary_key=True)
       title: Mapped[str] = mapped_column(String(200))
       body: Mapped[str] = mapped_column(Text, server_default="")
       created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
   ```

3. Alembic configuration, `api/alembic.ini` (new). The top part is ours; the logging sections are the standard Alembic ones so migrations print what they do:
   ```ini
   [alembic]
   # Where the migration scripts live (relative to this file).
   script_location = migrations
   # Put /app on the import path so migrations/env.py can "import db".
   prepend_sys_path = .
   # No sqlalchemy.url here: env.py takes the address from DATABASE_URL, so no password in a file.

   [loggers]
   keys = root,sqlalchemy,alembic

   [handlers]
   keys = console

   [formatters]
   keys = generic

   [logger_root]
   level = WARNING
   handlers = console
   qualname =

   [logger_sqlalchemy]
   level = WARNING
   handlers =
   qualname = sqlalchemy.engine

   [logger_alembic]
   level = INFO
   handlers =
   qualname = alembic

   [handler_console]
   class = StreamHandler
   args = (sys.stderr,)
   level = NOTSET
   formatter = generic

   [formatter_generic]
   format = %(levelname)-5.5s [%(name)s] %(message)s
   datefmt = %H:%M:%S
   ```

4. How migrations connect, `api/migrations/env.py` (new):
   ```python
   """Alembic environment: how migrations connect to the database."""
   from logging.config import fileConfig

   from alembic import context

   from db import Base, engine

   config = context.config
   if config.config_file_name is not None:
       fileConfig(config.config_file_name)

   # Used by "alembic revision --autogenerate" to compare the models with the real database.
   target_metadata = Base.metadata


   def run_migrations_online():
       # Same engine as the API, so the same DATABASE_URL: one place to configure.
       with engine.connect() as connection:
           context.configure(connection=connection, target_metadata=target_metadata)
           with context.begin_transaction():
               context.run_migrations()


   # Only "online" mode (a live database) is used in this lab.
   run_migrations_online()
   ```

5. The template Alembic uses when you later run `alembic revision`, `api/migrations/script.py.mako` (new):
   ```text
   """${message}

   Revision ID: ${up_revision}
   Revises: ${down_revision | comma,n}
   Create Date: ${create_date}
   """
   from alembic import op
   import sqlalchemy as sa
   ${imports if imports else ""}

   revision = ${repr(up_revision)}
   down_revision = ${repr(down_revision)}
   branch_labels = ${repr(branch_labels)}
   depends_on = ${repr(depends_on)}


   def upgrade():
       ${upgrades if upgrades else "pass"}


   def downgrade():
       ${downgrades if downgrades else "pass"}
   ```

6. The first migration, `api/migrations/versions/0001_create_notes.py` (new). It is written by hand so you can see exactly what it does:
   ```python
   """create notes table

   Revision ID: 0001
   Revises:
   Create Date: 2026-11-18
   """
   from alembic import op
   import sqlalchemy as sa

   revision = "0001"
   down_revision = None
   branch_labels = None
   depends_on = None


   def upgrade():
       op.create_table(
           "notes",
           sa.Column("id", sa.Integer(), primary_key=True),
           sa.Column("title", sa.String(200), nullable=False),
           sa.Column("body", sa.Text(), nullable=False, server_default=""),
           sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
       )


   def downgrade():
       op.drop_table("notes")
   ```

7. Put the new files in the image. In `api/Dockerfile`, replace the line `COPY main.py .` with:
   ```dockerfile
   COPY main.py db.py alembic.ini ./
   COPY migrations ./migrations
   ```

8. In `docker-compose.yml`: add the shared connection string at the top, give `api` the variable and a dependency, and add the `migrate` service.
   ```yaml
   name: aws-local-lab

   # The address of the database, shared by the API and the migration job (like an RDS endpoint
   # given to every app). "postgres" is the service name: Docker DNS turns it into the container's IP.
   x-db-env: &db-env
     DATABASE_URL: postgresql+psycopg://${POSTGRES_USER:-lab}:${POSTGRES_PASSWORD:?set POSTGRES_PASSWORD in .env (see .env.example)}@postgres:5432/${POSTGRES_DB:-lab}

   services:
     api:
       # ... build, image, deploy unchanged ...
       environment:
         <<: *db-env
         # Uvicorn reads UVICORN_* variables, so the app is configured without changing the image.
         UVICORN_LOG_LEVEL: ${API_LOG_LEVEL:-info}
       depends_on:
         # The API starts only after the migration finished successfully (the table exists).
         migrate:
           condition: service_completed_successfully
       # ... networks and healthcheck unchanged ...

     # One-shot job: same image as the API, runs "alembic upgrade head" and exits. It is the
     # equivalent of a migration task run before a deployment (for example an ECS task or a CI step).
     migrate:
       build: ./api
       image: aws-local-lab-api:0.1.0
       command: ["alembic", "upgrade", "head"]
       environment:
         <<: *db-env
       networks:
         - private
       depends_on:
         postgres:
           condition: service_healthy
       restart: "no"
   ```

| Line | What it does | If you change or remove it |
|---|---|---|
| `DATABASE_URL = os.environ["DATABASE_URL"]` | Reads the address of the database from the environment; a missing variable stops the program at once with a `KeyError`. | A hard-coded URL would put the password in the repository and tie the image to one environment. |
| `create_engine(..., pool_pre_ping=True)` | The *engine* owns a **pool** of reusable connections (opening one is slow). `pool_pre_ping` tests a connection before handing it out. | Without it, after a database restart the first request fails on a dead connection. |
| `class Note(Base)` with `__tablename__ = "notes"` | One Python class = one table; each `Mapped[...]` attribute = one column, with its type. | Rename the table here and `alembic check` reports a difference with the database. |
| `server_default=...` | The **database** fills the value when the row is inserted without it (`''`, current time). | A Python-side `default=` would not appear in the table definition and rows inserted by other tools would get no value. |
| `script_location = migrations` | Tells Alembic where the numbered scripts are. | A wrong path gives `Path doesn't exist`. |
| no `sqlalchemy.url` in the `.ini` | `env.py` imports the engine from `db.py`, so the URL is configured in one place only. | A URL here would be a second place with a password. |
| `target_metadata = Base.metadata` | The list of tables the models describe; used to *compare* models and database (`alembic check`, `--autogenerate`). | `None` still runs migrations but disables the comparison. |
| `revision = "0001"` / `down_revision = None` | This script's id, and the id of the one before it (none: it is the first). Alembic follows this chain. | A broken chain gives "multiple heads" or "can't locate revision". |
| `op.create_table("notes", ...)` / `op.drop_table` | `upgrade` applies the change, `downgrade` undoes it. | Without `downgrade` you cannot go back. |
| `COPY main.py db.py alembic.ini ./` + `COPY migrations ./migrations` | Puts the new files in the image. | A missing file means the container fails at start (`No module named 'db'` or `No 'script_location'`). |
| `x-db-env: &db-env` and `<<: *db-env` | A YAML **anchor**: define the variable once, reuse it in two services. `x-` keys are ignored by Compose. | Copying the line twice works too, but the two copies can drift apart. |
| `${POSTGRES_PASSWORD:?...}` inside the URL | Same "stop if missing" rule as step 10. (A password with characters like `@` or `/` would have to be URL-encoded; the generated hex password has none.) | A default would put a password in the repository. |
| `@postgres:5432` | Host `postgres` = the service name, resolved by Docker DNS on `private`. | Use `localhost` and the container looks for a database in itself. |
| `migrate` service, `command: [...]` | Same image as the API, but runs `alembic upgrade head` ("bring the database to the latest version") instead of the web server. | Without `command` it would start a second web server. |
| `restart: "no"` | A job runs once and stays stopped. | `always` would re-run it forever in a loop. |
| `depends_on: postgres: service_healthy` | `migrate` waits until Postgres accepts connections. | Without it, `migrate` may start first and fail with "connection refused". |
| `api: depends_on: migrate: service_completed_successfully` | The API replicas start only after `migrate` exited with code 0. If it fails, the API never starts. | Remove it and a replica can answer before the table exists. |

**Check the file and build the image:**
```bash
docker compose config -q && echo "compose config OK"
docker compose build api
```
```text
compose config OK
 Image aws-local-lab-api:0.1.0 Built
```

**Start the stack and read what `migrate` did:**
```bash
docker compose up -d
docker compose ps -a --format 'table {{.Service}}\t{{.Status}}'
docker compose logs migrate
```
```text
 Container aws-local-lab-migrate-1 Exited
 Container aws-local-lab-api-2 Starting
 ...
SERVICE    STATUS
api        Up 6 seconds (healthy)
api        Up 6 seconds (healthy)
api        Up 6 seconds (healthy)
migrate    Exited (0) 7 seconds ago
postgres   Up 14 seconds (healthy)

migrate-1  | INFO  [alembic.runtime.migration] Context impl PostgresqlImpl.
migrate-1  | INFO  [alembic.runtime.migration] Will assume transactional DDL.
migrate-1  | INFO  [alembic.runtime.migration] Running upgrade  -> 0001, create notes table
```
(Trimmed.) Read the order: `migrate` shows `Exited`, **then** the API replicas start. `Exited (0)` is success for a job: the exit code 0 is what
`service_completed_successfully` waits for. `Running upgrade  -> 0001` means "from nothing to version 0001".

> In this run the `lb` container did not start: port 80 on the laptop was already taken by another project's container (see Troubleshooting). Here it was started on port 8081 for this run only with
> `LB_HOST_PORT=8081 docker compose up -d`. If port 80 is free on your machine, plain `docker compose up -d` is all you need.

**Check 1 — the step's check: the table and the version exist.**
```bash
docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "\dt" -c "SELECT * FROM alembic_version;" -c "\d notes"'
```
```text
              List of tables
 Schema |      Name       | Type  | Owner 
--------+-----------------+-------+-------
 public | alembic_version | table | lab
 public | notes           | table | lab
(2 rows)

 version_num 
-------------
 0001
(1 row)

                                       Table "public.notes"
   Column   |           Type           | Collation | Nullable |              Default              
------------+--------------------------+-----------+----------+-----------------------------------
 id         | integer                  |           | not null | nextval('notes_id_seq'::regclass)
 title      | character varying(200)   |           | not null | 
 body       | text                     |           | not null | ''::text
 created_at | timestamp with time zone |           | not null | now()
Indexes:
    "notes_pkey" PRIMARY KEY, btree (id)
```
`\dt` lists the tables. Two exist: `notes` (ours) and `alembic_version`, a one-row table Alembic keeps to remember the last migration applied (`0001`). `\d notes` shows the structure: the
`server_default`s appear as `Default` (`''` and `now()`), and `id` got an automatic counter (`nextval(...)`) from the primary key.

**Check 2 — running the migration again changes nothing, and models match the database:**
```bash
docker compose run --rm migrate
docker compose run --rm migrate alembic check
```
```text
INFO  [alembic.runtime.migration] Context impl PostgresqlImpl.
INFO  [alembic.runtime.migration] Will assume transactional DDL.
...
No new upgrade operations detected.
```
The first command prints no `Running upgrade` line: the database is already at `0001`, so there is nothing to do (that is why it can run on every start). `alembic check` compares the `Note` class
with the real table and finds no difference. (One extra `INFO` line about the `notes_id_seq` sequence is omitted.)

**Check 3 — an API replica reaches the database through the engine:**
```bash
docker compose exec -T --index 1 api python -c "
import db
from sqlalchemy import text
print(db.engine.url.render_as_string(hide_password=True))
with db.engine.connect() as c:
    print(c.execute(text('select count(*) from notes')).scalar_one(), 'rows in notes')
"
```
```text
postgresql+psycopg://lab:***@postgres:5432/lab
0 rows in notes
```
`render_as_string(hide_password=True)` prints the URL with the password hidden (`***`): never print the real one. The query went from the API container to `postgres` over the private network and
the table is empty, as expected.

**Check 4 — the API still answers through the load balancer:**
```bash
curl -s -w ' [HTTP %{http_code}]\n' localhost:8081/health
curl -s -w ' [HTTP %{http_code}]\n' localhost:8081/whoami
```
```text
{"status":"ok"} [HTTP 200]
{"hostname":"60b538aa9142"} [HTTP 200]
```
(Port 8081 because of the conflict above; use `localhost` on port 80 if yours is free.)

**What just happened:**
- The API now has a **database layer**: one engine with a pool of connections, configured by one environment variable, `DATABASE_URL`. No route uses it yet; step 12 adds the notes endpoints.
- The structure of the database is now **code in Git**, not something typed by hand. Anyone can rebuild an identical empty database by running the migrations.
- Order is guaranteed by Compose: Postgres healthy → `migrate` runs and exits 0 → the three API replicas start → the load balancer starts. In AWS the same thing is a deployment pipeline
  that runs a migration task before it switches traffic to the new version.
- Because three replicas share one image, the migration is **not** run by the API itself: three replicas starting together would race to create the same table. One job, run once, avoids that.

### Step 12 — The notes CRUD
**Why:** the database now has a `notes` table, but nothing writes to it. This step turns the API into a small notes service: create, read, update and delete notes, with the data stored in
Postgres and shared by all three replicas.

**Do it.** Replace `api/main.py` with this (only `/health` and `/whoami` existed before; they are unchanged):

```python
import socket
from datetime import datetime
from typing import Annotated, Iterator

from fastapi import Depends, FastAPI, HTTPException, Response, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from db import Note, SessionLocal

app = FastAPI(title="aws-local-lab API")


def get_db() -> Iterator[Session]:
    """One database session per request, always closed afterwards (even after an error)."""
    with SessionLocal() as session:
        yield session


DbSession = Annotated[Session, Depends(get_db)]


class NoteIn(BaseModel):
    """What a client sends: the body is optional."""

    title: str = Field(min_length=1, max_length=200)
    body: str = ""


class NoteOut(NoteIn):
    """What the API answers: the client's fields plus what the database added."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    created_at: datetime


def get_note_or_404(db: Session, note_id: int) -> Note:
    note = db.get(Note, note_id)
    if note is None:
        raise HTTPException(status_code=404, detail="note not found")
    return note


@app.get("/health")
def health():
    """Liveness probe: answers as long as the process is up."""
    return {"status": "ok"}


@app.get("/whoami")
def whoami():
    """Which container answered? Inside Docker the hostname is the container id."""
    return {"hostname": socket.gethostname()}


@app.post("/notes", response_model=NoteOut, status_code=status.HTTP_201_CREATED)
def create_note(data: NoteIn, db: DbSession):
    note = Note(title=data.title, body=data.body)
    db.add(note)
    db.commit()
    db.refresh(note)  # reload: the database filled in id and created_at
    return note


@app.get("/notes", response_model=list[NoteOut])
def list_notes(db: DbSession):
    return db.scalars(select(Note).order_by(Note.id)).all()


@app.get("/notes/{note_id}", response_model=NoteOut)
def read_note(note_id: int, db: DbSession):
    return get_note_or_404(db, note_id)


@app.put("/notes/{note_id}", response_model=NoteOut)
def update_note(note_id: int, data: NoteIn, db: DbSession):
    note = get_note_or_404(db, note_id)
    note.title = data.title
    note.body = data.body
    db.commit()
    return note


@app.delete("/notes/{note_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_note(note_id: int, db: DbSession):
    db.delete(get_note_or_404(db, note_id))
    db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
```

| Line | What it does | If you change or remove it |
|---|---|---|
| `from db import Note, SessionLocal` | Reuses the engine and the model from step 11. | Without the `DATABASE_URL` variable this import stops the app at start (`KeyError`): the container would be unhealthy. |
| `def get_db()` with `yield` | A **dependency**: FastAPI calls it before the route, passes the session in, and runs the code after `yield` when the request ends. `with ... as session` closes the session in all cases. | Without the `with`, connections would leak and the pool would run dry. |
| `DbSession = Annotated[Session, Depends(get_db)]` | A shortcut: "a parameter of this type is filled by `get_db`". | Writing `db: Session` alone would make FastAPI treat it as request input. |
| `class NoteIn(BaseModel)` | The shape of what clients may send. `Field(min_length=1, max_length=200)` rejects an empty or too long title; `body` defaults to `""`. | Remove the limits and a very long title would reach the database, which refuses it (`varchar(200)`) and the client would get a `500` instead of a clear `422`. |
| `class NoteOut(NoteIn)` + `from_attributes=True` | The shape of the answer: everything in `NoteIn` plus `id` and `created_at`. `from_attributes` lets Pydantic read the fields from a SQLAlchemy `Note` object. | Without it, returning a `Note` raises a validation error. |
| `response_model=NoteOut` | FastAPI converts the returned object to exactly these fields (and documents them in `/docs`). | Without it, a SQLAlchemy object cannot be turned into JSON. |
| `status_code=201` / `204` | The success codes for "created" and "deleted, no content". | The default `200` works but is less precise. |
| `db.add(note)` → `db.commit()` → `db.refresh(note)` | Stage the new row, write it to Postgres (`INSERT`), then reload it so `id` and `created_at` (filled by the database) are known. | Without `commit` nothing is saved: the session closes and the change is rolled back. |
| `db.get(Note, note_id)` | Fetch one row by primary key; `None` if it does not exist. | |
| `raise HTTPException(404)` | Stops the route and answers `404` with a JSON message. | Without it a missing note would crash the route with a `500`. |
| `update_note`: set attributes, `commit` | SQLAlchemy notices the changes and sends an `UPDATE`. | Forget `commit` and the update is lost. |
| `delete_note` | `DELETE` the row; answer `204` with an empty body. | |
| `order_by(Note.id)` | A list has no guaranteed order in SQL unless you ask for one. | Without it, rows may come back in any order. |

**Rebuild and restart** (the `migrate` job runs first, finds nothing to do, and exits; the API replicas are recreated):
```bash
docker compose up -d --build           # add LB_HOST_PORT=8081 in front if port 80 is busy
docker compose ps --format 'table {{.Service}}\t{{.Status}}'
```
```text
SERVICE    STATUS
api        Up 16 seconds (healthy)
api        Up 16 seconds (healthy)
api        Up 16 seconds (healthy)
lb         Up 16 minutes (healthy)
postgres   Up 17 minutes (healthy)
```
(`migrate` is not listed because `ps` hides stopped containers; `-a` shows it.)

**Check — the full cycle through the load balancer** (port 8081 here because port 80 was busy, see Troubleshooting; use your own port):
```bash
B=localhost:8081
curl -s -i -X POST $B/notes -H 'Content-Type: application/json' -d '{"title":"first note","body":"hello from curl"}'   # create
curl -s -w ' [HTTP %{http_code}]\n' $B/notes/1                                                                         # read
curl -s -w ' [HTTP %{http_code}]\n' -X PUT $B/notes/1 -H 'Content-Type: application/json' -d '{"title":"first note (edited)","body":"changed"}'   # update
curl -s -w ' [HTTP %{http_code}]\n' $B/notes                                                                            # list
curl -s -o /dev/null -w 'DELETE [HTTP %{http_code}]\n' -X DELETE $B/notes/1                                             # delete
curl -s -w ' [HTTP %{http_code}]\n' $B/notes/1                                                                         # read again
curl -s -w ' [HTTP %{http_code}]\n' -X POST $B/notes -H 'Content-Type: application/json' -d '{"title":""}'              # bad input
```
```text
HTTP/1.1 201 Created
{"title":"first note","body":"hello from curl","id":1,"created_at":"2026-11-18T22:17:36.598347Z"}
{"title":"first note","body":"hello from curl","id":1,"created_at":"2026-11-18T22:17:36.598347Z"} [HTTP 200]
{"title":"first note (edited)","body":"changed","id":1,"created_at":"2026-11-18T22:17:36.598347Z"} [HTTP 200]
[{"title":"first note (edited)","body":"changed","id":1,"created_at":"2026-11-18T22:17:36.598347Z"}] [HTTP 200]
DELETE [HTTP 204]
{"detail":"note not found"} [HTTP 404]
{"detail":[{"type":"string_too_short","loc":["body","title"],"msg":"String should have at least 1 character","input":"","ctx":{"min_length":1}}]} [HTTP 422]
```
(The `-i` output is trimmed to the status line and the body.) Read it step by step: `201` and the new note with `id: 1` and a `created_at` the **database** filled in; `200` on read; the update keeps
the same `id` and `created_at` and changes the text; the list shows one note; `204` on delete; reading it again gives `404 note not found`; and an empty title is refused with `422` before
anything touches the database (`loc` says which field, `msg` why).

**Check — the data is in Postgres, shared by all replicas:**
```bash
curl -s -o /dev/null -w 'POST [HTTP %{http_code}]\n' -X POST $B/notes -H 'Content-Type: application/json' -d '{"title":"seen in psql","body":"stored in postgres"}'
docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "select id, title, body from notes;"'
for i in $(seq 1 12); do curl -s $B/whoami; echo; done | sort | uniq -c
curl -s -o /dev/null -w 'cleanup DELETE [HTTP %{http_code}]\n' -X DELETE $B/notes/2
```
```text
POST [HTTP 201]
 id |    title     |        body        
----+--------------+--------------------
  2 | seen in psql | stored in postgres
(1 row)

      4 {"hostname":"35fca1572408"}
      4 {"hostname":"e399200f024d"}
      4 {"hostname":"fbe46390cca3"}
cleanup DELETE [HTTP 204]
```
The note created through the load balancer is a row in the `notes` table (`id` 2: the counter continues after the deleted note 1, ids are never reused). Twelve requests were spread
evenly over the three replicas (4 each), and any of them can read any note because the data is not in the replicas but in the database: the **stateless** API of [Lab 01](./01-containers.md) now has
somewhere to keep its state.

**What just happened:**
- The API became a real service: five routes on `/notes` and the same code in all three replicas.
- Each request gets its **own session** (a short conversation with the database) and closes it at the end; the engine's pool reuses the underlying connections.
- **Input is validated** at the edge (`422`) and **output is shaped** by `NoteOut`: clients only receive the fields you declared.
- Nothing changed in the network: the database is still only reachable from the `private` network; clients only ever talk to the load balancer.

### Step 13 — The admin profile: a door to the database, closed by default
**Why:** the database is deliberately unreachable from your machine, which is right for the running system but awkward when *you* want to look inside it (run a query, open a GUI client).
Real RDS has the same problem, and the answer is never "open the database to the internet": you go in through a controlled side door. This step adds that door, and keeps it **off** unless you ask for it.

**The problem, shown.** The obvious fix, `ports:` on `postgres`, cannot work: the `private` network is `internal`, and Docker does not publish the ports of a container that is only on an internal network. A throw-away
container proves it:
```bash
docker run --rm -d --name course-internal-test --network aws-local-lab_private -p 127.0.0.1:5999:80 nginx:1.30.6-alpine
echo "--- docker port:"; docker port course-internal-test
echo "--- curl from the host:"; curl -s -m 4 -o /dev/null -w 'HTTP %{http_code}\n' localhost:5999 || echo "no answer (curl exit $?)"
docker stop course-internal-test
```
```text
--- docker port:
--- curl from the host:
HTTP 000
no answer (curl exit 7)
```
`-p 127.0.0.1:5999:80` was requested, but `docker port` prints **nothing** (no port was published) and `curl` cannot connect (exit code 7 = connection refused). So the door has to be a **relay**: a tiny container that sits on both
networks, like the load balancer does. (`docker stop` removes the test container, which was started with `--rm`.)

**Do it.** Add this service to `docker-compose.yml`, after `postgres`:

```yaml
  # The "bastion host" for the database: off by default, started only with "--profile admin".
  # Postgres itself never publishes a port (it sits on the internal "private" network, which cannot
  # publish ports at all), so a tiny relay joins "public" (to publish) and "private" (to reach it).
  db-proxy:
    image: alpine/socat:1.8.1.3
    profiles: ["admin"]
    # Listen on 5432 and forward every connection to the database, by service name.
    command: ["TCP-LISTEN:5432,fork,reuseaddr", "TCP:postgres:5432"]
    ports:
      # Your machine only (127.0.0.1), never the network. Change the port if 5432 is taken.
      - "127.0.0.1:${ADMIN_DB_PORT:-5432}:5432"
    networks:
      - public
      - private
    depends_on:
      postgres:
        condition: service_healthy
```
and one line group in `.env.example`:
```bash
# Admin access (Lab 04, step 13): host port of "docker compose --profile admin up -d db-proxy"
ADMIN_DB_PORT=5432
```

| Line | What it does | If you change or remove it |
|---|---|---|
| `image: alpine/socat:1.8.1.3` | `socat` ("socket cat") is a small program that copies bytes between two network connections. Pinned to an exact version. | `:latest` is forbidden here; another tool (Nginx `stream`, HAProxy) would do the same job with more configuration. |
| `profiles: ["admin"]` | The service belongs to the **profile** `admin`: Compose ignores it unless you pass `--profile admin` (or name the service explicitly with that profile). | Remove it and `docker compose up` opens the database on every start. |
| `command: ["TCP-LISTEN:5432,fork,reuseaddr", "TCP:postgres:5432"]` | Two socat "addresses": listen on TCP 5432 (`fork` = handle each connection in its own process, `reuseaddr` = restart quickly) and connect each one to `postgres:5432`. | Without `fork`, only one client could connect at a time. |
| `ports: "127.0.0.1:${ADMIN_DB_PORT:-5432}:5432"` | Publishes the relay on your machine **only** (`127.0.0.1`), on port 5432 unless `ADMIN_DB_PORT` says otherwise. | `"5432:5432"` would publish on all interfaces: anyone on your network could try the password. |
| `networks: - public - private` | `public` lets Docker publish the port; `private` lets the relay reach `postgres` (same trick as the load balancer). | Only `private`: the port is not published (see above). Only `public`: it cannot find `postgres`. |
| `depends_on: postgres: service_healthy` | Starts the relay only once the database accepts connections. | Without it, the first connection right after start may fail. |

**Check 1 — off by default.** The service exists in the file but is not part of a normal run, and nothing listens on the host:
```bash
docker compose config -q && echo "compose config OK"
docker compose config --services | sort | tr '\n' ' '
docker compose --profile admin config --services | sort | tr '\n' ' '
docker compose up -d                       # a normal start (add LB_HOST_PORT=8081 if port 80 is busy)
docker compose ps -a --format 'table {{.Service}}\t{{.Status}}\t{{.Ports}}'
timeout 3 bash -c '</dev/tcp/127.0.0.1/5432' 2>/dev/null && echo OPEN || echo "closed (nothing listens on 127.0.0.1:5432)"
```
```text
compose config OK
api lb migrate postgres 
api db-proxy lb migrate postgres 
SERVICE    STATUS                    PORTS
lb         Up 56 minutes (healthy)   127.0.0.1:8081->80/tcp
postgres   Up 34 minutes (healthy)   5432/tcp
closed (nothing listens on 127.0.0.1:5432)
```
(The `api` and `migrate` rows are left out of the `ps` output.) Without the profile the services are `api lb migrate postgres`; with `--profile admin`, `db-proxy` joins the list. The normal start does not create it, and port 5432 is closed.
The last command opens a TCP connection with Bash's `/dev/tcp`; it fails.

**Check 2 — switch the door on, and connect with `psql`.**
```bash
docker compose --profile admin up -d db-proxy
docker compose --profile admin ps db-proxy --format 'table {{.Service}}\t{{.Status}}\t{{.Ports}}'
timeout 3 bash -c '</dev/tcp/127.0.0.1/5432' 2>/dev/null && echo "OPEN (127.0.0.1:5432 accepts connections)" || echo closed
```
```text
 Container aws-local-lab-postgres-1 Waiting 
 Container aws-local-lab-postgres-1 Healthy 
 Container aws-local-lab-db-proxy-1 Starting 
 Container aws-local-lab-db-proxy-1 Started 
SERVICE    STATUS                  PORTS
db-proxy   Up Less than a second   127.0.0.1:5432->5432/tcp
OPEN (127.0.0.1:5432 accepts connections)
```
`127.0.0.1:5432->5432/tcp` is the arrow that `postgres` never had: a published port, on your machine only. Now a real client. Your Windows machine probably has no `psql`, so use a throw-away client container that reaches your machine through
`host.docker.internal` (Docker Desktop's name for "the host") and reads the password from `.env` **without printing it** (`--env-file`):
```bash
docker run --rm --env-file .env postgres:18.7-alpine3.24 sh -c 'PGPASSWORD="$POSTGRES_PASSWORD" PGCONNECT_TIMEOUT=5 psql -h host.docker.internal -p 5432 -U "${POSTGRES_USER:-lab}" -d "${POSTGRES_DB:-lab}" -tA -c "select current_user, current_database(), inet_server_port();" -c "\dt"'
```
```text
lab|lab|5432
public|alembic_version|table|lab
public|notes|table|lab
```
It connected through the relay: user `lab`, database `lab`, server port `5432`, and `\dt` lists the two tables of step 11. (`${POSTGRES_USER:-lab}` repeats Compose's defaults, because `.env` does not necessarily define those two variables; see Troubleshooting.)
If you have `psql` or a GUI client (DBeaver, pgAdmin) on Windows, point it at host `127.0.0.1`, port `5432`, user and database `lab`, and your password.

**Check 3 — the password still protects the door.**
```bash
docker run --rm -e PGCONNECT_TIMEOUT=5 postgres:18.7-alpine3.24 psql -h host.docker.internal -p 5432 -U lab -d lab -w -tA -c "select 1"
```
```text
psql: error: connection to server at "host.docker.internal" (192.168.65.254), port 5432 failed: fe_sendauth: no password supplied
```
Reaching the port is not enough: without the password the server refuses (`-w` = never ask for one).

**Check 4 — switch it off again, and make sure nothing else broke.**
```bash
docker compose --profile admin stop db-proxy
timeout 3 bash -c '</dev/tcp/127.0.0.1/5432' 2>/dev/null && echo OPEN || echo "closed again"
bash tests/03_network_isolation.sh
bash tests/02_load_balancing.sh        # (with LB_HOST_PORT=8081 in front of each if port 80 is busy)
```
```text
 Container aws-local-lab-db-proxy-1 Stopped 
closed again
  PASS  the API answers through the load balancer
  PASS  the API container cannot reach the internet (the lb can)
03_network_isolation: all checks passed
  PASS  30 requests reached 3 different replicas (fewest: 10)
  PASS  api has no published port
02_load_balancing: all checks passed
```
(Test output trimmed to the last lines.) After `stop`, port 5432 is closed again. The existing tests still pass: with the proxy off, the stack is exactly as before. The stopped `db-proxy` container stays on disk, doing nothing, until you remove it (a plain `docker compose down` ignores it; see Troubleshooting).

**What just happened:**
- You added a **side door** with three safeguards: it only exists when you ask (`profile`), it only listens on your own machine (`127.0.0.1`), and the database password is still required.
- `postgres` itself still has no `ports:` and still sits only on `private`: the isolation you built in [Lab 03](./03-networking.md) is unchanged. The door is a separate, disposable container.
- In real AWS the same need is solved by a **bastion host** (a small server in a public subnet that you SSH into and hop from), or **AWS Systems Manager Session Manager** port forwarding, or a VPN: the database stays in a private subnet and its security group only
  accepts connections from the bastion's security group. Never "make the database publicly accessible".
- Remember to stop the proxy when you finish: an open port is an attack surface, even on `127.0.0.1`.

### Step 14 — Tests for the lab: the data survives, the database stays private
**Why:** everything in this lab so far was checked by hand. Two promises matter most and are easy to break by accident later: *the data outlives the containers* and *the database is not reachable from outside*. A test turns
each promise into a command that answers `PASS` or `FAIL`, so `make test` catches the day a change breaks one of them.

**Do it.** Two changes, both in `tests/`.

1. A new script, `tests/04_persistence.sh`: write a note, throw **all** containers away, start again, and check the note is still there.
```bash
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
```

2. A new section in the existing `tests/03_network_isolation.sh`, just before its last line (`[ "$fail" = 0 ] && echo "03_network_isolation: ...`). It reuses the helpers `ok`, `bad`, `skip`, `nets_of` and the variable `$private` that the script already defines:
```bash
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
```

| Line | What it does | If you change or remove it |
|---|---|---|
| `title="persistence-test-$(date +%s)"` | A unique title (seconds since 1970), so the test never mistakes an old note for its own. | A fixed title could match a leftover note and hide a failure. |
| `id=$(echo "$resp" \| sed -n 's/.*"id":\([0-9]*\).*/\1/p')` | Extracts the new note's `id` from the JSON answer. | Without the id the test cannot read the note back. |
| `trap '... -X DELETE ...' EXIT` | Runs when the script ends, **even on failure**: deletes the test note. | Without it a failed run leaves a note behind. |
| `docker compose down` (no `-v`) | Removes the containers and networks but **keeps the volumes**. | `down -v` would delete `pgdata`, and the test would (rightly) fail; it is also blocked in this project. |
| `docker volume ls -q \| grep -q '_pgdata$'` | The named volume still exists (Compose names it `aws-local-lab_pgdata`). | Removing it hides *why* a failure happened. |
| `for _ in $(seq 60); do ... sleep 2; done` | Waits up to two minutes for the **new** containers: healthy database, the `migrate` job, then the API. | A fixed `sleep` is either too short (flaky) or too long (slow). |
| `grep -q "\"title\":\"$title\""` | The note read back has the same title. | Checking only the status code would pass on any note. |
| `docker compose port postgres 5432` = `:0` | `:0` is Docker's answer for "no published port". | If it printed `127.0.0.1:5432`, someone added `ports:` to `postgres`. |
| `nets_of "$pg_id"` = `$private` | `postgres` is attached to the private network and nowhere else. | A second network would put the database next to the load balancer. |
| `docker compose --profile admin ps --status running -q db-proxy` | Detects the admin door of [step 13](#step-13--the-admin-profile-a-door-to-the-database-closed-by-default); if it is on, the "closed" check is skipped with a message. | Without it, switching the admin profile on would turn this check red for a good reason. |
| `bash -c '</dev/tcp/127.0.0.1/5432'` | Bash's built-in "open a TCP connection": succeeds only if something listens. `timeout 3` stops it hanging. | Remove `timeout` and a filtered port could block the test. |
| `docker compose exec -T --index 1 api python -c "...create_connection(('postgres', 5432)...)"` | The **control**: from inside an API replica the same port *is* reachable. | Without a positive control, "not reachable" could just mean "nothing runs". |

**Check — the isolation test, now with the database checks:**
```bash
bash tests/03_network_isolation.sh        # add LB_HOST_PORT=8081 in front if port 80 is busy
```
```text
Lab 03 - network isolation (http://127.0.0.1:8081)
  PASS  only lb publishes a port (127.0.0.1:8081->80/tcp)
  PASS  network aws-local-lab_private is internal
  PASS  every api replica is on aws-local-lab_private only
  PASS  lb is attached to 2 networks (public + private)
  PASS  127.0.0.1:8000 does not answer
  PASS  the API container address (172.23.0.4) is not reachable from the host
  PASS  the API answers through the load balancer
  PASS  the API container cannot reach the internet (the lb can)
  PASS  postgres publishes no port
  PASS  postgres is on aws-local-lab_private only
  PASS  127.0.0.1:5432 is closed
  PASS  the postgres container address (172.23.0.2) is not reachable from the host
  PASS  an API replica reaches postgres:5432 on the private network
03_network_isolation: all checks passed
```
The last five lines are new. **Can it fail?** Switch the admin door on and run it again (`docker compose --profile admin up -d db-proxy`, then the test, then `docker compose --profile admin stop db-proxy`); output filtered to the interesting lines:
```text
  FAIL  expected only lb to publish a port, got: db-proxy 127.0.0.1:5432->5432/tcp
  PASS  postgres publishes no port
  PASS  postgres is on aws-local-lab_private only
  SKIP  the admin profile is on (db-proxy running): 127.0.0.1:5432 is open on purpose
  PASS  the postgres container address (172.23.0.2) is not reachable from the host
  PASS  an API replica reaches postgres:5432 on the private network
03_network_isolation: FAILED
```
The test describes the lab in its **default** state: with the admin door open the original "only the load balancer publishes a port" check turns red (correctly: `db-proxy` publishes one), while the new port-5432 check says it is skipping on purpose. Stop the proxy and it is green again. (One more limit: the "`127.0.0.1:5432` is closed" check cannot tell *who* listens. If another program on your machine already uses port 5432, that check fails although the lab is fine.)

**Check — the persistence test:**
```bash
bash tests/04_persistence.sh              # add LB_HOST_PORT=8081 in front if port 80 is busy
```
```text
Lab 04 - persistence (http://127.0.0.1:8081)
  PASS  created note 3 ("persistence-test-1795043723")
  PASS  docker compose down: containers removed
  PASS  the pgdata volume is still there
  PASS  docker compose up -d: new containers started
  PASS  note 3 survived down + up, same title
04_persistence: all checks passed
```
The whole run took about 19 seconds (`real 0m19.480s`). Note the `id` is 3: the counter continued after the notes of the earlier steps (ids are never reused). The test deletes its note at the end; `curl localhost:8081/notes` afterwards printed `[]`.

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
```
(Trimmed to the summary lines; `make` exited with code 0.) `make test` now proves four things about the architecture: the load balancer spreads traffic, a dead replica costs no request, the network layout isolates the API **and the database**, and the data survives a full restart.

**What just happened:**
- The lab gained a **safety net**: the two most important database promises are now executable. They run in `make test` next to the earlier ones.
- The persistence test uses the **real thing**: it goes through the load balancer, the API and Postgres, restarts everything, and reads the note back. It does not test the volume in isolation, it tests the *behaviour* you care about.
- The isolation test has a **control** (an API replica *can* reach the database), so "not reachable from the host" is a meaningful result and not an accident.
- What the test cannot do here: prove the opposite (that data is lost without the volume). That needs `docker compose down -v`, which this project blocks on purpose; see the exercises.

## 5. Verify it works
With the lab up (`make up`; if port 80 is busy on your machine use `LB_HOST_PORT=8081 make up` and add the same prefix to the commands below):
```bash
make test
```
All four scripts must print `all checks passed`, and `make` must exit with code 0. To look by hand as well:
```bash
docker compose ps -a --format 'table {{.Service}}\t{{.Status}}'                                                    # api x3, lb, postgres healthy; migrate Exited (0)
docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "\dt"'                      # notes and alembic_version
curl -s -X POST localhost/notes -H 'Content-Type: application/json' -d '{"title":"hello"}'; curl -s localhost/notes   # create and list
docker compose port postgres 5432                                                                                  # prints :0, not published
```
(In PowerShell, write `curl.exe`, and put the JSON in a file or escape the quotes.)

## 6. Troubleshooting
| Symptom | Cause | Fix |
|---|---|---|
| `failed to connect to the docker API at npipe:////./pipe/dockerDesktopLinuxEngine ... The system cannot find the file specified` | Docker Desktop is not running, so the Docker engine is not there. | Start Docker Desktop, wait until `docker info` prints a version, then retry. |
| `Bind for 0.0.0.0:80 failed: port is already allocated` when `lb` starts | Another container (here `docker-nginx-1`, from a different Compose project) already publishes port 80 on your machine. Find it with `docker ps --format '{{.Names}}\t{{.Ports}}'`. | Stop the other project, or choose another port for the lab: `LB_HOST_PORT=8081` in `.env` (or on the command line for one run) and use `localhost:8081`. |
| `psql: error: ... FATAL:  password authentication failed for user "root"` when connecting from a client container with `--env-file .env` | `.env` does not define `POSTGRES_USER` (Compose silently uses the default `lab`), so inside the client container the variable is empty and `psql` falls back to the container's user, `root`. | Pass the user explicitly, with the same default Compose uses: `-U "${POSTGRES_USER:-lab}" -d "${POSTGRES_DB:-lab}"`. |
| `tests/03_network_isolation.sh` reports `FAIL  expected only lb to publish a port, got: db-proxy ...` | The admin door is open: `db-proxy` (profile `admin`) publishes `127.0.0.1:5432` on purpose, and the test describes the default state. | Stop it (`docker compose --profile admin stop db-proxy`) and run the test again. |
| `Error response from daemon: failed to set up container networking: network <id> not found` when starting `db-proxy` | A *stopped* `db-proxy` container from an earlier session is still on disk, and a plain `docker compose down` in between **ignored it** (Compose only handles services of the active profiles) while removing and re-creating the networks it pointed to. | Re-create it: `docker compose --profile admin up -d --force-recreate db-proxy`, or remove it for good with `docker compose --profile admin down`. |
| `docker compose down` prints `Network aws-local-lab_private Resource is still in use` (and `..._public`), yet exits with code 0, and `db-proxy` is still running | The admin door was open: `db-proxy` is attached to both networks and plain `down` does not stop it, so the networks cannot be removed. | Use `docker compose --profile admin down`, which includes `db-proxy`. (`tests/04_persistence.sh` calls the plain `down`: switch the admin door off before running it.) |

## 7. Going to real AWS
- **What changes:** an **RDS for PostgreSQL** instance (or Aurora PostgreSQL) in **private subnets** chosen through a **DB subnet group** spanning at least two availability zones. Its **security group** allows port 5432 **only from the API's security group**
  (not from the internet, not from your laptop). The application connects to the instance **endpoint** (a DNS name), with the credentials delivered by **Secrets Manager** or the task's IAM role, not by a file. The schema is created by the same kind of
  migration job, run as an ECS task or a pipeline step before each deployment.
- **Admin access:** never "publicly accessible". You go through a **bastion host** or **Systems Manager Session Manager** port forwarding, or a VPN: the local `db-proxy` with `--profile admin` is that idea in miniature.
- **Safety nets that RDS adds:** **Multi-AZ** (a synchronous standby in another zone and automatic failover, same endpoint), **automated backups** with point-in-time restore and manual **snapshots** (a restore always creates a **new** instance), **minor-version patching**
  in a maintenance window, **storage autoscaling**, **encryption at rest** (KMS) and **in transit** (TLS), and **CloudWatch** metrics. **Read replicas** are for read scaling, not for safety.
- **What this lab does not simulate:** failover and Multi-AZ, backups and snapshots (a `pg_dump` is the closest local tool, see [Databases 09](../courses/databases/README.md) once written), patching windows, instance sizing (the container may use all your RAM and CPU), storage limits,
  encryption, IAM authentication, parameter groups and the multi-zone network. The `postgres` container is a single process with a single disk: if the volume is deleted, the data is gone.
- **Rough cost:** an RDS instance bills per hour for its **instance class**, plus storage per GB-month, plus backup storage beyond the free allowance, plus data transfer; Multi-AZ roughly doubles the instance part. A small single-zone instance is typically in the range of
  tens of USD per month (check the [RDS pricing page](https://aws.amazon.com/rds/postgresql/pricing/); prices vary by region and change, and a free tier may apply to new accounts for a limited time). Stop or delete test instances, and delete manual snapshots you no longer need
  (they are billed until deleted).

## 8. Clean up
```bash
make down          # removes the containers and networks; the data volume pgdata is KEPT
make up            # starts again: the notes are still there
make clean         # deletes the volume too (ALL lab data); it asks you to type "yes" first - run it yourself
```
`make down` is `docker compose down`: it keeps named volumes, which is exactly what `tests/04_persistence.sh` proves. Only `make clean` (`down -v`) deletes `pgdata`. The admin door, if you used it: `docker compose --profile admin stop db-proxy`
(the stopped container stays on disk and uses nothing), or remove the door together with everything else with `docker compose --profile admin down`: a plain `docker compose down` ignores it. To see the volume: `docker volume ls`.

## 9. Check your understanding
1. Why does the `postgres` service have no `ports:` line, and why can it not simply get one?
2. What does `docker compose down` remove, and what does it keep? Which command would delete the data, and why does `tests/04_persistence.sh` not use it?
3. Why is the migration run by a separate one-shot `migrate` service and not by each API replica when it starts?
4. In `POST /notes`, what happens when the title is empty, and which layer rejects it before the database is touched?
5. Why does the isolation test check that an API replica **can** reach `postgres:5432` when its goal is to prove the database is hard to reach?

<details><summary>Answers</summary>

1. Nothing outside the lab network should be able to open a connection to the database. A `ports:` line would publish it on the laptop, and it cannot work anyway: the `private` network is internal, and Docker does not publish ports of containers that are only on an internal network. Admin access goes through the optional `db-proxy` (profile `admin`).
2. It removes the containers and the networks and **keeps the named volumes** (`pgdata`). `docker compose down -v` (`make clean`) deletes the volumes and the data. The test uses plain `down` because its job is to prove that a restart keeps the data; `down -v` would (correctly) lose it and is blocked in this project.
3. Three replicas starting together would race to create the same table. One job, run once and finished before the API starts (`service_completed_successfully`), avoids that, and it matches how real deployments run a migration task first.
4. Pydantic (`NoteIn`, `min_length=1`) rejects it with `422` and an error naming the field; nothing is sent to Postgres.
5. A "not reachable" result only means something if the same test method *can* succeed somewhere. The positive control (a replica on the private network connects) shows the database is running and the check works, so the failures from the host really come from the network layout.

</details>

## 10. Exercises (optional)
- Make the persistence test prove the opposite: copy `docker-compose.yml`, remove the `pgdata:/var/lib/postgresql` line from the `postgres` service in the copy, start it with `docker compose -f <copy> -p throwaway up -d`, write a note, `down` and `up` again, and see the note disappear. (Do it under another project name so your real data is untouched, and give it a different `LB_HOST_PORT` so it does not fight for the load balancer's host port.)
- Extend `04_persistence.sh`: also `PUT` an update before the restart and check the **updated** text after it.
- Run `make clean` yourself (type `yes`), then `make up`. Check with `\dt` that the `migrate` job recreated the tables, and with `GET /notes` that the data is gone. Which two things did `make clean` delete that `make down` keeps?
- Add a second migration (for example a `done boolean` column on `notes`), update the model, run `docker compose up -d --build`, and read the `migrate` log. What does `alembic_version` say now?
- Connect a graphical client (DBeaver, pgAdmin) through the admin door: `docker compose --profile admin up -d db-proxy`, host `127.0.0.1`, port `5432`, user `lab`. Stop the door when you finish.

## 11. Further reading
- [Amazon RDS: what it is](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Welcome.html) and [Multi-AZ deployments](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZ.html) (AWS)
- [Backing up and restoring an RDS instance](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_CommonTasks.BackupRestore.html) (AWS)
- [PostgreSQL documentation](https://www.postgresql.org/docs/current/) (PostgreSQL)
- [Alembic tutorial](https://alembic.sqlalchemy.org/en/latest/tutorial.html) and [SQLAlchemy documentation](https://docs.sqlalchemy.org/en/latest/) (SQLAlchemy)
- [FastAPI: SQL databases](https://fastapi.tiangolo.com/tutorial/sql-databases/) (FastAPI)
- [Docker volumes](https://docs.docker.com/engine/storage/volumes/) and [Compose profiles](https://docs.docker.com/compose/how-tos/profiles/) (Docker)

## Go deeper
- Course: [Docker 08 - Volumes and bind mounts](../courses/docker/08-volumes-and-bind-mounts.md)
- Course: [AWS 06 - RDS: managed databases](../courses/aws/06-rds.md)
- Course: [Databases 01 - Relational databases: tables, rows, keys](../courses/databases/01-relational-basics.md)
- Course: [Databases 02 - SQL basics](../courses/databases/02-sql.md)
- Course: [Databases 03 - PostgreSQL: server, roles, databases](../courses/databases/03-postgresql.md)
- Course: [FastAPI 07 - Dependencies and dependency injection](../courses/fastapi/07-dependencies.md)
- Course: [Databases 04 - Schemas, migrations and Alembic](../courses/databases/04-schemas-and-migrations.md)
- Course: [Databases 05 - ORMs and SQLAlchemy](../courses/databases/05-sqlalchemy.md)
- Course: [FastAPI 03 - Path, query and body parameters](../courses/fastapi/03-parameters.md)
