# Databases 04 — Schemas, migrations and Alembic

> **Course:** [Databases](./README.md)  ·  **Time:** ~45 min  ·  **Needs:** [Databases 01](./01-relational-basics.md), [Databases 02](./02-sql.md) and [Databases 03](./03-postgresql.md); [Docker 01](../docker/01-images-and-containers.md) for the exercise
> **Used in the labs:** [Lab 04, step 11](../../labs/04-database.md) (the first migration and the `migrate` job)

## What you will learn
- Say what a **schema** is (the shape of the tables) and why changing it on a live database is risky.
- Explain what a **migration** is and why a database should be changed by numbered scripts, not by typing SQL by hand.
- Read an **Alembic** migration file (`revision`, `down_revision`, `upgrade`, `downgrade`) and the `alembic_version` table.
- Run `alembic history`, `current`, `upgrade` and `downgrade`, and predict what each prints.
- Explain why the lab runs the migration in a separate **one-shot** `migrate` service and not inside each API replica.

## Words you need
| Word | Plain-words meaning |
|---|---|
| **Schema** | The *shape* of a database: which tables exist, their columns, types and rules. (Postgres also uses "schema" for a folder of tables, `public`: [Databases 03](./03-postgresql.md). Here it means the shape.) |
| **Migration** | One small script that moves the schema from one version to the next (for example "add a column"). Kept in a file, numbered, and stored in git. |
| **Revision** | Alembic's word for one migration. It has an id such as `0001`. |
| **Upgrade / downgrade** | Applying a migration (move forward) / undoing it (move back). |
| **Head** | The newest revision in your migration files. `upgrade head` means "go to the newest". |
| **Base** | The starting point before any migration: an empty database. |
| **Alembic** | A Python tool that runs migrations and remembers which ones were already applied. It belongs to the same family as SQLAlchemy, the library the API uses ([Databases 05](./README.md), planned). |
| **`alembic_version`** | A tiny table Alembic creates in your database. It holds one row: the id of the last applied revision. |
| **Transactional DDL** | **DDL** (*data definition language*) is SQL that changes the shape (`CREATE TABLE`, `ALTER TABLE`). Postgres can run it inside a **transaction**, a group of statements that either all succeed or are all undone. So a failed migration leaves no half-finished change. |
| **One-shot job** | A container that does one task and exits (exit code 0 = success), instead of running for ever. |
| **Idempotent** | Safe to run again: the second run finds the work already done and changes nothing. |

## The idea
**Analogy.** A building has plans. When the owner wants a new room, nobody walks in with a hammer: an architect issues **numbered change orders** ("order 7: add a window on the north wall"), and a logbook at the door says *"changes up to order 6 are done"*. Any builder, on any copy of the building, can read the log, see what is missing and apply orders 7, 8, 9 in order. Alembic is the architect's folder (migration files) plus the logbook (`alembic_version`).

**Precisely.** Code changes with every release, and so does the shape of the data it needs. If you change the database by hand (a quick `ALTER TABLE` in `psql`), three things go wrong: nobody remembers it, your colleague's copy and the production copy do not get it, and you cannot repeat it. A migration tool fixes this:

1. each change is a **file** with an id and a pointer to the previous one (so the files form a chain),
2. the tool compares the chain with the `alembic_version` table and runs only what is **missing**, in order,
3. each file also says how to **undo** the change (`downgrade`).

```mermaid
flowchart LR
  base(["base<br/>empty database"]) -->|"0001 create notes table"| r1(["0001"])
  r1 -->|"0002 add done column"| r2(["0002 (head)"])
  r2 -. "downgrade" .-> r1
  v[("alembic_version<br/>one row: the current id")] -. "remembers where we are" .- r1
```

**Who runs it, and when.** If three API replicas started together and each ran the migration, they would race to create the same table. So the lab uses **one** extra service, `migrate`, that runs once and exits; the API waits for it to finish.

```mermaid
sequenceDiagram
  participant C as docker compose up
  participant P as postgres
  participant M as migrate (one-shot)
  participant A as api (3 replicas)
  C->>P: start
  P-->>C: healthy (pg_isready)
  C->>M: start (depends_on: postgres healthy)
  M->>P: alembic upgrade head
  P-->>M: tables created, alembic_version = 0001
  M-->>C: exit code 0 (service_completed_successfully)
  C->>A: start (depends_on: migrate completed)
  A->>P: normal queries
```

## The code, line by line
The first migration of the lab (`api/migrations/versions/0001_create_notes.py`), with a comment on each line, and the `migrate` service from `docker-compose.yml`:

```python
"""create notes table"""                      # 1  the message: shown by "alembic history"
from alembic import op                         # 2  "op" = the operations: create_table, add_column, ...
import sqlalchemy as sa                        # 3  column types: sa.Integer(), sa.Text(), ...

revision = "0001"                              # 4  this migration's id
down_revision = None                           # 5  the previous one; None = this is the first (it follows "base")
branch_labels = None                           # 6  advanced (parallel histories): unused
depends_on = None                              # 7  advanced: unused

def upgrade():                                 # 8  how to move forward
    op.create_table(                           # 9  CREATE TABLE notes (...)
        "notes",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("title", sa.String(200), nullable=False),
        sa.Column("body", sa.Text(), nullable=False, server_default=""),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )

def downgrade():                               # 10 how to move back
    op.drop_table("notes")                     # 11 DROP TABLE notes
```
```yaml
  migrate:
    build: ./api                               # 12 same image as the API
    image: aws-local-lab-api:0.1.0
    command: ["alembic", "upgrade", "head"]    # 13 the only thing this container does
    environment:
      <<: *db-env                              # 14 DATABASE_URL (same as the API)
    networks: [private]                        # 15 can reach postgres, like the API
    depends_on:
      postgres: { condition: service_healthy } # 16 wait until the database accepts connections
    restart: "no"                              # 17 a job: do not restart it when it exits
```

| Line | What it does | If you change or remove it |
|---|---|---|
| 4 `revision = "0001"` | The id Alembic writes into `alembic_version` once this migration is applied. | Two files with the same id make Alembic refuse to run. |
| 5 `down_revision = None` | Chain link: "I come right after base". The next file will say `down_revision = "0001"`. | A wrong value breaks the chain: Alembic reports multiple heads or a missing revision. |
| 8 `upgrade()` | The change itself, written with `op.*` calls that Alembic turns into SQL for the database in use. | An empty `upgrade` still records the revision, but nothing changes. |
| 10 `downgrade()` | The exact reverse, so you can go back. | Leave it empty and `downgrade` records the move without undoing anything: the database and the id disagree. |
| 13 `command: [alembic, upgrade, head]` | "Apply every revision not yet applied, up to the newest." | `downgrade -1` would undo the last one at every start: never do that. |
| 16 `depends_on: postgres healthy` | The job starts only once Postgres answers. | Without it the job races the database start and fails with "connection refused". |
| 17 `restart: "no"` | A finished job must stay finished. | With `always` it would run again and again. |

## The commands
All run inside the project image (`docker exec ... alembic ...`); Alembic finds the database through `DATABASE_URL`.

| Command | Meaning |
|---|---|
| `alembic history` | Print the chain of revision files, newest first: `previous -> this (head), message`. Does **not** look at the database. |
| `alembic current` | Print the revision stored in `alembic_version` (nothing if no migration was ever applied). |
| `alembic upgrade head` | Run all missing revisions, in order, up to the newest. Also written `upgrade +1` (one step) or `upgrade 0001` (up to that id). |
| `alembic downgrade -1` | Undo the last applied revision (runs its `downgrade()`). `downgrade base` undoes everything. |
| `alembic revision -m "msg"` | Create a new, empty revision file with the right ids (you fill in `upgrade` and `downgrade`). |
| `INFO [alembic.runtime.migration] ...` | Alembic's own log lines: which migration it runs. Read them like a diary. |

## Hands-on
A throw-away Postgres (fake password) and a second container made from the **project's own API image** (`aws-local-lab-api:0.1.0`, which contains Alembic and the real `0001` migration). They share one network namespace (`--network container:...`), so `localhost` in the second is the first. Real output, trimmed.

**1. Start both**
```bash
docker run -d --rm --name dbcourse-pg -e POSTGRES_PASSWORD=throwaway-fake postgres:18.7-alpine3.24
until docker exec dbcourse-pg pg_isready -U postgres -q; do sleep 1; done
docker run -d --name dbcourse-mig --network container:dbcourse-pg \
  -e DATABASE_URL=postgresql+psycopg://postgres:throwaway-fake@localhost:5432/postgres \
  aws-local-lab-api:0.1.0 sleep 900
```
(`sleep 900` keeps the container alive for 15 minutes so we can run several commands in it.)

**2. Before any migration**
```bash
docker exec dbcourse-mig alembic history
docker exec dbcourse-pg psql -U postgres -c '\dt'
```
```text
<base> -> 0001 (head), create notes table
Did not find any tables.
```
The chain has one file; the database is empty (no tables, not even `alembic_version`).

**3. Upgrade, then look at the result**
```bash
docker exec dbcourse-mig alembic upgrade head
docker exec dbcourse-mig alembic current
docker exec dbcourse-pg psql -U postgres -c '\dt' -c 'select * from alembic_version'
```
```text
INFO  [alembic.runtime.migration] Running upgrade  -> 0001, create notes table
0001 (head)
 public | alembic_version | table | postgres
 public | notes           | table | postgres
 version_num
-------------
 0001
```
(The two `Context impl PostgresqlImpl` / `Will assume transactional DDL` lines, printed before every command, are left out.) Alembic ran one migration, created `notes` **and** its own `alembic_version` table, and wrote `0001` in it.

**4. Run it again: nothing happens (idempotent)**
```bash
docker exec dbcourse-mig alembic upgrade head; echo "exit=$?"
```
```text
exit=0
```
No `Running upgrade` line: the database is already at head. This is why `docker compose up` can run the `migrate` job on every start.

**5. Add a second migration.** Create `0002_add_done.py` (here by copying a prepared file into the container) with `revision = "0002"`, `down_revision = "0001"` and:
```python
def upgrade():
    op.add_column("notes", sa.Column("done", sa.Boolean(), nullable=False, server_default=sa.false()))

def downgrade():
    op.drop_column("notes", "done")
```
```bash
docker exec dbcourse-mig alembic history
docker exec dbcourse-mig alembic upgrade head
docker exec dbcourse-pg psql -U postgres -c 'select * from alembic_version' -c '\d notes'
```
```text
0001 -> 0002 (head), add done column
<base> -> 0001, create notes table
INFO  [alembic.runtime.migration] Running upgrade 0001 -> 0002, add done column
 version_num: 0002
 done       | boolean                  |           | not null | false
```
(The psql output is filtered to the interesting lines.) The history now has two links, and **only** `0002` ran (Alembic knew `0001` was done). The table has the new `done` column and `alembic_version` says `0002`.

**6. Undo it**
```bash
docker exec dbcourse-mig alembic downgrade -1
```
```text
INFO  [alembic.runtime.migration] Running downgrade 0002 -> 0001, add done column
```
`alembic_version` is `0001` again and the `done` column is gone (a count of columns named `done` printed `0`). **Warning:** `drop_column` deletes the data in that column. A downgrade is a tool for development; on production data the usual way back is a new forward migration.

**7. Clean up**
```bash
docker rm -f dbcourse-mig
docker stop dbcourse-pg        # started with --rm: it removes itself
```

## What if…?
**…someone had already changed the database by hand?** Same throw-away database, back at `0001`. A colleague adds the column directly, then you run the migration:
```bash
docker exec dbcourse-pg psql -U postgres -c 'alter table notes add column done boolean not null default false'
docker exec dbcourse-mig alembic upgrade head; echo "exit=$?"
docker exec dbcourse-pg psql -U postgres -c 'select * from alembic_version'
```
```text
ALTER TABLE
INFO  [alembic.runtime.migration] Running upgrade 0001 -> 0002, add done column
psycopg.errors.DuplicateColumn: column "done" of relation "notes" already exists
[SQL: ALTER TABLE notes ADD COLUMN done BOOLEAN DEFAULT false NOT NULL]
exit=1
 version_num
-------------
 0001
```
The migration **failed** (exit code 1) because the column exists. Two lessons. First, hand edits make the real schema drift away from the files: that is the exact problem migrations exist to prevent. Second, Postgres ran the change inside a transaction (*transactional DDL*), so the failure left `alembic_version` at `0001`: the database and the logbook still agree. In the lab, a failed `migrate` job exits non-zero, and the API (which waits for `service_completed_successfully`) **does not start**, which is exactly what you want.

## In short
1. A **schema** is the shape of the data; a **migration** is a numbered file that changes it, with an `upgrade` and a `downgrade`.
2. Alembic keeps the current revision in the `alembic_version` table, so `upgrade head` applies only what is missing and is safe to run twice.
3. In the lab one **one-shot `migrate` service** runs it before the API starts; never change the shape by hand.

## Check your understanding
1. Why is typing `ALTER TABLE` in `psql` on a shared database a bad habit, even when it works?
2. What does `alembic upgrade head` print when the database is already up to date, and why is that useful at every `docker compose up`?
3. In a migration file, what are `revision` and `down_revision`, and what happens if `down_revision` is wrong?
4. Why does the lab have a separate `migrate` service instead of running the migration in each API replica?
5. In the experiment, why was `alembic_version` still `0001` after the failed migration?

<details><summary>Answers</summary>

1. Nobody can see or repeat the change: the other copies of the database (your colleague's, test, production) will not get it, and the code that expects the new shape breaks there. Migration files are in git, reviewed, ordered and repeatable.
2. Nothing except two `INFO` lines, and exit code 0: it compares `alembic_version` with the files, finds nothing missing, and stops. That makes the job safe to run on every start.
3. `revision` is the id of this migration; `down_revision` is the id of the one before it (`None` for the first). Together they form a chain. A wrong `down_revision` breaks the chain: Alembic reports a missing revision or several "heads" and refuses to run.
4. Three replicas starting together would race to create the same table, and a failed migration would leave some replicas running on the wrong shape. One job, run once and finished before the API starts (`service_completed_successfully`), avoids both, and matches how real deployments run a migration task first.
5. Postgres can run schema changes inside a transaction. The `ALTER TABLE` failed, so the whole migration was undone, including the final step "write `0002` in `alembic_version`". The logbook still says `0001`, which is true.

</details>

## Official documentation
- [Alembic tutorial](https://alembic.sqlalchemy.org/en/latest/tutorial.html) and [the `op` operations](https://alembic.sqlalchemy.org/en/latest/ops.html)
- [Alembic: running and generating migrations](https://alembic.sqlalchemy.org/en/latest/tutorial.html#running-our-first-migration)
- [PostgreSQL: `ALTER TABLE`](https://www.postgresql.org/docs/current/sql-altertable.html) and [transactions](https://www.postgresql.org/docs/current/tutorial-transactions.html)
- [Docker Compose: `depends_on` conditions](https://docs.docker.com/reference/compose-file/services/#depends_on)

## Where you use this in the project
- [Lab 04, step 11](../../labs/04-database.md): the `migrate` service, `api/migrations/versions/0001_create_notes.py` and the `alembic_version` table.
- [Lab 04, section 10 (exercises)](../../labs/04-database.md): "Add a second migration" is the exercise above, done on the real lab.
- [Docker 09 (Compose)](../docker/09-compose.md): `depends_on` and `service_completed_successfully`.
