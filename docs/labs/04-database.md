# Lab 04 — Database (RDS)

> **AWS equivalent:** Amazon RDS for PostgreSQL, DB subnet groups, security groups, snapshots  ·  **Time:** ~75 min  ·  **Difficulty:** ★★☆
> **Builds on:** [Lab 03](./03-networking.md)  ·  **Reference solution:** commits `b29c466` (step 10), `cc957ec` (step 11) and `d7ac631` (step 12) on `dev`

> **Status:** in progress. Steps 10–12 are written; steps 13–14 (admin profile, tests) and the closing sections (5–11) come next.

## 1. What you will learn
- Explain why an application keeps its data in a **database** and not in its own files or memory.
- Name the parts of an AWS RDS database (instance, engine, storage, subnet group, security group, endpoint) and their local counterparts.
- Run PostgreSQL in a container: private network only, data in a **named volume**, password from `.env`, with a healthcheck.
- Prove that the database is not reachable from your machine, and that its data outlives its container.
- Describe a **migration** (a versioned change to the database structure), write one with **Alembic**, and run it as a one-shot job before the API starts.
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
| Running migrations | a task or pipeline step before the deployment (ECS run-task, CI job, Lambda) | the one-shot `migrate` service: `alembic upgrade head`, then it exits |
| Health | RDS status `Available` | Docker healthcheck with `pg_isready` |
| Snapshots, Multi-AZ, patching | managed by AWS | not simulated (backups: course module [Databases 09](../courses/README.md)) |

### 2.4 Diagram
```mermaid
flowchart LR
  you((You)) -->|127.0.0.1:80| lb
  subgraph public["public network"]
    lb["lb: Nginx"]
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
  you -. "no route, no port" .-x pg
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
(Trimmed to the summary lines. `02_failover.sh` is occasionally red by itself, one request out of 60 failing: a known intermittent problem of the Lab 02 test, see its
troubleshooting entry once the fix lands. Re-run it.)

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

## 6. Troubleshooting (so far)
| Symptom | Cause | Fix |
|---|---|---|
| `failed to connect to the docker API at npipe:////./pipe/dockerDesktopLinuxEngine ... The system cannot find the file specified` | Docker Desktop is not running, so the Docker engine is not there. | Start Docker Desktop, wait until `docker info` prints a version, then retry. |
| `Bind for 0.0.0.0:80 failed: port is already allocated` when `lb` starts | Another container (here `docker-nginx-1`, from a different Compose project) already publishes port 80 on your machine. Find it with `docker ps --format '{{.Names}}\t{{.Ports}}'`. | Stop the other project, or choose another port for the lab: `LB_HOST_PORT=8081` in `.env` (or on the command line for one run) and use `localhost:8081`. |

## 5, 7–11. To be completed in step 14
Verify, Going to real AWS, Clean up, Check your understanding, Exercises and Further reading are written when the lab ends (step 14). Troubleshooting above grows with each step.

## Go deeper
- Course: [Docker 08 - Volumes and bind mounts](../courses/docker/08-volumes-and-bind-mounts.md)
