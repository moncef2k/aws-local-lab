# Databases 07 — Transactions

> **Course:** [Databases](./README.md)  ·  **Time:** ~50 min  ·  **Needs:** [Databases 02](./02-sql.md) (SQL) and [Databases 05](./05-sqlalchemy.md) (SQLAlchemy sessions); [Docker 01](../docker/01-images-and-containers.md) for the exercise
> **Used in the labs:** [Lab 04, step 12](../../labs/04-database.md) (`db.commit()` in the create, update and delete routes) and [Lab 07, step 22](../../labs/07-queues-workers.md) (the same idea in Redis: `MULTI`/`EXEC`)

## What you will learn
- Explain what a **transaction** is and why "all or nothing" matters.
- Use `BEGIN`, `COMMIT` and `ROLLBACK`, and see what happens when a step fails in the middle.
- Name the four **ACID** guarantees in plain words.
- See **isolation** at work: what a second session sees, and what it must wait for, while the first is still open.
- Read the lab's `db.commit()` and the session's behaviour when you **forget** it.

## Words you need
| Word | Plain-words meaning |
|---|---|
| **Transaction** | A group of database changes that succeed **together or not at all**. Others never see it half done. |
| **`BEGIN` / `COMMIT` / `ROLLBACK`** | Start a transaction / make all its changes permanent / throw them all away. |
| **Autocommit** | Without `BEGIN`, PostgreSQL treats **each statement** as its own tiny transaction and commits it at once. |
| **Atomicity** | The "all or nothing" guarantee: a transaction is never applied halfway. |
| **Consistency** | The rules of the database (types, `PRIMARY KEY`, `CHECK`) hold before and after every transaction; a change that would break one is refused. |
| **Isolation** | Concurrent transactions do not see each other's unfinished work. |
| **Durability** | Once `COMMIT` has answered, the change survives a crash (it is written to the disk log first). |
| **ACID** | The four words above together: **A**tomicity, **C**onsistency, **I**solation, **D**urability. |
| **Constraint** | A rule stored in the table, such as `check (balance >= 0)`. The database refuses any row that breaks it. |
| **Read committed** | PostgreSQL's default isolation level: a statement sees only what other sessions have **committed**. |
| **Row lock** | When a transaction changes a row, other transactions that want to change **the same row** wait until it finishes. |
| **Session (SQLAlchemy)** | Python's handle on one database connection and its current transaction ([Databases 05](./05-sqlalchemy.md)). |

## The idea
**Analogy.** Moving money at a bank counter: take 30 from Alice's account **and** add 30 to Bob's. If the clerk is interrupted after the first step, money has vanished. A transaction is the **pen that signs the form only when both lines are filled**: until the signature (`COMMIT`) nothing counts, and if anything goes wrong the whole form is torn up (`ROLLBACK`). Meanwhile, other clerks looking at the accounts see the old numbers, and a clerk who wants to change Alice's line waits until the first form is signed or torn.

**Precisely.** Statements between `BEGIN` and `COMMIT` form **one unit**. PostgreSQL keeps the new versions of the rows hidden from other sessions until the commit; at `COMMIT` they all become visible at the same moment; at `ROLLBACK`, or when a statement fails, they are discarded. The four **ACID** guarantees describe what you can rely on. In an application you rarely type `BEGIN`: the library starts a transaction with your first statement, and **you decide where it ends** with `commit()`. A session closed without a commit **rolls back**.

```mermaid
sequenceDiagram
  participant A as session A
  participant DB as PostgreSQL
  participant B as session B
  A->>DB: BEGIN; UPDATE alice -10
  Note over DB: new version hidden, row locked
  B->>DB: SELECT alice
  DB-->>B: 70 (the committed value)
  B->>DB: UPDATE alice -5
  Note over B,DB: B waits for the lock
  A->>DB: COMMIT
  DB-->>A: done: alice is 60
  DB-->>B: lock released, B's UPDATE runs: alice is 55
```

## The code or config, line by line
The whole bank experiment, `tx_demo.sql`:
```sql
-- Databases 07: transactions. A tiny bank: money moves between two accounts.
\pset footer off
create table accounts (
    id      int primary key,
    owner   text not null,
    balance int not null check (balance >= 0)   -- a rule: never below zero
);
insert into accounts values (1, 'alice', 100), (2, 'bob', 50);

\echo '== 1. a transfer of 30 inside one transaction, then COMMIT'
begin;
update accounts set balance = balance - 30 where id = 1;
update accounts set balance = balance + 30 where id = 2;
commit;
select * from accounts order by id;

\echo '== 2. a change we take back with ROLLBACK'
begin;
update accounts set balance = 0 where id = 1;
select balance as "alice inside the transaction" from accounts where id = 1;
rollback;
select balance as "alice after the rollback" from accounts where id = 1;

\echo '== 3. the second step breaks a rule: the first step is undone too'
begin;
update accounts set balance = balance + 500 where id = 2;      -- bob receives 500 ...
update accounts set balance = balance - 500 where id = 1;      -- ... alice has only 70: the CHECK refuses
select 1;                                                      -- the transaction is now "aborted"
commit;
select * from accounts order by id;

\echo '== 4. the same two steps WITHOUT a transaction (each statement commits by itself)'
update accounts set balance = balance + 500 where id = 2;
update accounts set balance = balance - 500 where id = 1;
select * from accounts order by id;
select sum(balance) as total_money from accounts;
```
| Line(s) | What it does | If you change or remove it |
|---|---|---|
| `check (balance >= 0)` | A **constraint**: the database refuses any row with a negative balance. | Without it, step 3 would succeed and alice would owe money. |
| `begin; ... commit;` (step 1) | Both updates become permanent **together**. | Remove `begin` and each update commits alone (step 4). |
| `rollback;` (step 2) | Discards everything since `begin`. Inside the transaction alice reads `0`; after, `70`. | |
| step 3: two updates, the second fails | The `CHECK` refuses the second update. The transaction is **aborted**: every later command is ignored until `commit`/`rollback`, and `commit` then rolls back. | |
| step 4: no `begin` | Each statement is its own transaction: the first one is already committed when the second fails. | |

And the two-session experiment, `concurrent.sh` (run on your machine, after `tx_demo.sql`):
```bash
#!/usr/bin/env bash
# Two sessions on the table of tx_demo.sql: A holds a change open for 5 s, B reads then changes the same row.
psql() { docker exec course-pg7 psql -U postgres -q -t -A "$@"; }

echo "balance before: $(psql -c 'select balance from accounts where id = 1')"

psql -c "begin; update accounts set balance = balance - 10 where id = 1; select pg_sleep(5); commit;" > /dev/null &
sleep 1.5                                    # A is now inside its transaction

echo "B reads while A is open:  $(psql -c 'select balance from accounts where id = 1')"
start=$(date +%s)
psql -c "update accounts set balance = balance - 5 where id = 1;"   # has to WAIT for A to finish
echo "B's UPDATE waited about $(( $(date +%s) - start )) seconds"

wait
echo "balance after both:       $(psql -c 'select balance from accounts where id = 1')"
```
| Line(s) | What it does | If you change or remove it |
|---|---|---|
| `begin; update ...; select pg_sleep(5); commit;` `&` | Session A changes alice, **holds the transaction open for 5 seconds** (`pg_sleep`), then commits. The `&` runs it in the background. | Without the sleep the transaction is too short to observe. |
| B's `select` | Reads alice's balance while A is open. | |
| B's `update` | Changes the **same row**: it must wait for A. The script measures how long. | |

Finally the same ideas from Python with the project's own `db.py`, `orm_demo.py`:
```python
"""Transactions seen from SQLAlchemy, with the project's own db.py (Note, SessionLocal)."""
from sqlalchemy import func, select

from db import Base, Note, SessionLocal, engine

Base.metadata.drop_all(engine)
Base.metadata.create_all(engine)


def how_many() -> int:
    with SessionLocal() as s:
        return s.scalar(select(func.count()).select_from(Note))


print("1. add a note but never commit, then close the session")
with SessionLocal() as s:
    s.add(Note(title="never committed"))
    s.flush()                                       # sent to the database, still inside the transaction
    print("   inside the session, the database sees:", s.scalar(select(func.count()).select_from(Note)))
print("   after closing, the table holds:", how_many())

print("2. add a note and commit")
with SessionLocal() as s:
    s.add(Note(title="committed"))
    s.commit()
print("   the table holds:", how_many())

print("3. two notes in one transaction, an error before the commit")
try:
    with SessionLocal() as s:
        s.add(Note(title="first of two"))
        s.add(Note(title="x" * 300))                # too long for String(200): the database refuses
        s.commit()
except Exception as exc:
    print("   error:", type(exc).__name__)
print("   the table holds:", how_many(), "(the first of the two was rolled back too)")

print("4. session.begin(): commit on success, rollback on any exception")
try:
    with SessionLocal() as s, s.begin():
        s.add(Note(title="inside begin()"))
        raise RuntimeError("something went wrong in my code")
except RuntimeError:
    pass
print("   the table holds:", how_many())
```
| Line(s) | What it does | If you change or remove it |
|---|---|---|
| `s.add(...)`, `s.flush()` | `add` only prepares the row; `flush` **sends** it to the database, still inside the open transaction. | |
| no `s.commit()` (step 1) | The session closes without a commit: PostgreSQL rolls the transaction back. | |
| `"x" * 300` (step 3) | A title longer than `String(200)`: the database refuses it, and the whole transaction, including the first note, is rolled back. | |
| `with SessionLocal() as s, s.begin():` (step 4) | An explicit transaction block: **commit** at the end if all went well, **rollback** if an exception leaves the block. | |

## The commands
| Command / flag | Meaning |
|---|---|
| `docker run -d --rm --name course-pg7 -e POSTGRES_PASSWORD=... postgres:18.7-alpine3.24` | A throw-away PostgreSQL (fake password). |
| `docker exec course-pg7 psql -U postgres -q -f /tmp/tx_demo.sql` | Run a SQL file: `-U` user, `-q` quiet, `-f` file. |
| `docker run -d --name course-orm7 --network container:course-pg7 -e DATABASE_URL=... aws-local-lab-api:0.1.0 sleep 900` | A second container from the project's API image **sharing the database container's network**, so `localhost:5432` is the database ([Databases 05](./05-sqlalchemy.md)). |

## Hands-on
Throw-away containers (`postgres:18.7-alpine3.24`, and the project's `aws-local-lab-api:0.1.0`). Save the three files above in a folder, then:
```bash
export MSYS_NO_PATHCONV=1
docker run -d --rm --name course-pg7 -e POSTGRES_PASSWORD=demo-only-not-a-secret postgres:18.7-alpine3.24
until docker exec course-pg7 pg_isready -U postgres -q; do sleep 1; done; sleep 2
docker cp tx_demo.sql course-pg7:/tmp/tx_demo.sql
docker exec course-pg7 psql -U postgres -q -f /tmp/tx_demo.sql
```
```text
== 1. a transfer of 30 inside one transaction, then COMMIT
 id | owner | balance 
----+-------+---------
  1 | alice |      70
  2 | bob   |      80

== 2. a change we take back with ROLLBACK
 alice inside the transaction 
------------------------------
                            0

 alice after the rollback 
--------------------------
                       70

== 3. the second step breaks a rule: the first step is undone too
psql:/tmp/tx_demo.sql:27: ERROR:  new row for relation "accounts" violates check constraint "accounts_balance_check"
DETAIL:  Failing row contains (1, alice, -430).
psql:/tmp/tx_demo.sql:28: ERROR:  current transaction is aborted, commands ignored until end of transaction block
 id | owner | balance 
----+-------+---------
  1 | alice |      70
  2 | bob   |      80

== 4. the same two steps WITHOUT a transaction (each statement commits by itself)
psql:/tmp/tx_demo.sql:34: ERROR:  new row for relation "accounts" violates check constraint "accounts_balance_check"
DETAIL:  Failing row contains (1, alice, -430).
 id | owner | balance 
----+-------+---------
  1 | alice |      70
  2 | bob   |     580

 total_money 
-------------
         650

```
**How to read it:**
- **1:** both updates applied together: alice 70, bob 80.
- **2:** inside the transaction alice reads `0`; after `rollback` she is back to `70`. The change never existed for anyone else.
- **3:** the first `UPDATE` succeeded (bob +500) and the second broke the `CHECK` (`Failing row contains (1, alice, -430)`). Everything after it is refused (`current transaction is aborted`), and the table shows **no change at all**: bob still has 80. The first update was undone with the failed one.
- **4:** the same two steps without `begin`: bob's +500 was committed on its own, then alice's update failed. Bob has **580**, alice still 70, and the total went from 150 to **650**. Money appeared from nowhere. This is what a transaction prevents.

**Isolation and locks: two sessions at once**
```bash
bash concurrent.sh
```
```text
balance before: 70
B reads while A is open:  70
B's UPDATE waited about 3 seconds
balance after both:       55
```
**How to read it:** while A held its change open, B still read **70** (A's `-10` was invisible: *read committed*). B's own update on the same row **waited about 3 seconds** (the rest of A's 5 seconds; another run printed 4, the exact number varies) and only then ran. The final balance, 55, is `70 - 10 - 5`: both changes applied, one after the other, none lost.

**From Python (the lab's own `db.py`)**
```bash
docker run -d --name course-orm7 --network container:course-pg7 \
  -e DATABASE_URL=postgresql+psycopg://postgres:demo-only-not-a-secret@localhost:5432/postgres \
  aws-local-lab-api:0.1.0 sleep 900
docker cp orm_demo.py course-orm7:/app/orm_demo.py
docker exec course-orm7 python orm_demo.py
```
```text
1. add a note but never commit, then close the session
   inside the session, the database sees: 1
   after closing, the table holds: 0
2. add a note and commit
   the table holds: 1
3. two notes in one transaction, an error before the commit
   error: DataError
   the table holds: 1 (the first of the two was rolled back too)
4. session.begin(): commit on success, rollback on any exception
   the table holds: 1
```
**How to read it:**
- **1:** after `flush` the database sees the note **inside** the transaction (`1`), but the session was closed without `commit`: afterwards the table holds **0**. A forgotten `commit()` loses the data silently, with no error.
- **2:** with `commit()` the row is there.
- **3:** the second note was refused (`DataError`: too long). The table still holds only the committed note from step 2: the **first note of the same transaction was undone too**.
- **4:** the exception inside `s.begin()` rolled the transaction back: still 1.

Clean up: `docker rm -f course-orm7; docker stop course-pg7` (the database container was started with `--rm`).

## What if…?
**…you skip the transaction?** Step 4 of the SQL experiment: bob has 580 and the total went from 150 to 650. Anything that must hold together (a transfer, an order with its lines, a job record **and** its queue entry) needs one transaction. In Lab 07 the producer does it in Redis with `MULTI`/`EXEC`.

## In short
1. A transaction groups changes so they apply **all together or not at all**: `BEGIN` ... `COMMIT`, or `ROLLBACK` (an error does it for you).
2. **ACID**: atomic, consistent (rules hold), isolated (others do not see unfinished work; same-row writers wait), durable (committed means safe).
3. In code, the transaction ends **where you write `commit()`**: a session closed without it rolls back, so a forgotten commit loses data without an error.

## Check your understanding
1. What does "atomic" mean for a transaction? Which line of the SQL experiment shows it?
2. In the two-session experiment, what did session B read while A was open, and why did B's `UPDATE` take several seconds?
3. What happens to a note added in a SQLAlchemy session that is closed without `commit()`?
4. In step 3 of the SQL experiment, bob's first update succeeded. Why does bob still have 80?
5. Name the four ACID letters with a one-line meaning each.

<details><summary>Answers</summary>

1. The whole group of changes is applied or none of it: never half. Step 3: the second update failed and the first one (bob +500) was undone too.
2. B read `70`, the committed value: A's change was not visible before its commit (isolation, *read committed*). B's `UPDATE` targeted the same row, which A had locked, so it waited until A committed (the rest of A's 5 seconds).
3. It is rolled back: the transaction is never committed, so the row never reaches the table (the table held 0 notes).
4. Because the transaction was aborted by the failed second update: PostgreSQL discards **all** the work of the transaction, including the first update that had succeeded.
5. **Atomicity**: all or nothing. **Consistency**: the rules (constraints) always hold. **Isolation**: concurrent transactions do not see each other's unfinished work. **Durability**: committed data survives a crash.

</details>

## Official documentation
- [PostgreSQL: Transactions (tutorial)](https://www.postgresql.org/docs/current/tutorial-transactions.html)
- [PostgreSQL: Transaction isolation](https://www.postgresql.org/docs/current/transaction-iso.html) and [explicit locking](https://www.postgresql.org/docs/current/explicit-locking.html)
- [SQLAlchemy: Session basics, transactions](https://docs.sqlalchemy.org/en/20/orm/session_basics.html)

## Where you use this in the project
- [Lab 04, step 12](../../labs/04-database.md): `create_note`, `update_note` and `delete_note` end with `db.commit()`; `get_db` closes the session after each request, so a route that forgets the commit loses its change.
- [Databases 05](./05-sqlalchemy.md): the session and the engine that this module's `SessionLocal` comes from.
- [Lab 07, step 22](../../labs/07-queues-workers.md): `POST /jobs` writes a record **and** pushes an id in one Redis `MULTI`/`EXEC`, the same all-or-nothing idea outside SQL.
