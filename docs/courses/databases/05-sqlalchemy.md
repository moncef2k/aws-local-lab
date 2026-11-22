# Databases 05 — ORMs and SQLAlchemy

> **Course:** [Databases](./README.md)  ·  **Time:** ~45 min  ·  **Needs:** [Databases 02](./02-sql.md) and [Databases 04](./04-schemas-and-migrations.md); [Docker 01](../docker/01-images-and-containers.md) for the exercise
> **Used in the labs:** [Lab 04, step 11](../../labs/04-database.md) (`api/db.py`, the `Note` model, `POST /notes` and `GET /notes`)

## What you will learn
- Say what an **ORM** is and what it saves you from (and what it hides).
- Read `api/db.py`: the **engine**, the **session**, the **model class** `Note`.
- Predict the **SQL** that `add`, `select`, `get` and an attribute change produce.
- Explain **commit** and **rollback**, and why the API opens one session per request.
- Explain why SQLAlchemy sends `INSERT ... RETURNING` and what the **identity map** is.

## Words you need
| Word | Plain-words meaning |
|---|---|
| **ORM** | *Object-Relational Mapper*: a library that lets your program work with Python **objects** (a `Note`) while it writes the **SQL** for the tables (rows) for you. |
| **SQLAlchemy** | The most used ORM and SQL toolkit for Python. The API uses it. |
| **Model** | A Python class that describes one table: its columns become the class's attributes. |
| **Engine** | The object that knows **where the database is** (`DATABASE_URL`) and keeps a small set of open connections ready. |
| **Connection pool** | A few database connections kept open and re-used, because opening one is slow ([Databases 08](./README.md), planned). |
| **Session** | A short conversation with the database: it collects the changes you make to objects and sends them inside one **transaction**. |
| **Transaction** | A group of statements that either **all** take effect (**commit**) or **none** do (**rollback**). |
| **Flush** | Send the pending changes to the database **without** ending the transaction yet. |
| **Identity map** | The session's memory of "row 1 of `notes` is *this* Python object", so asking twice gives the same object. |
| **`RETURNING`** | A Postgres feature: an `INSERT` can send back values the database filled in (the new `id`) in the same round trip. |
| **Server default** | A value the **database** fills in when you give none (`now()`), as opposed to one Python sends. |
| **Dependency (FastAPI)** | A function FastAPI calls for you and passes to a route, such as `get_db`, see [FastAPI 07](../fastapi/07-dependencies.md). |

## The idea
**Analogy.** You travel to a country whose language you do not speak. You can learn the language (write SQL yourself), or hire an **interpreter**: you speak your own language (Python objects), the interpreter says the right sentences to the locals (the database). The interpreter is convenient and usually right, but you should know roughly what they say on your behalf, because a wrong sentence still has your name on it.

**Precisely.** Without an ORM, saving a note means building a string `INSERT INTO notes ...`, passing the values safely, reading the row back and turning columns into variables. An ORM does this bookkeeping: you describe the table **once** as a class, then

- `session.add(Note(...))` becomes an `INSERT`,
- `select(Note).where(...)` becomes a `SELECT ... WHERE ...` and returns `Note` objects,
- changing `note.title = "x"` becomes an `UPDATE` at the next commit,
- the values are always sent as **parameters** (`%(title)s`), never pasted into the SQL text, which protects against **SQL injection** (a user typing SQL into a form field).

What the ORM does **not** do here is create or change tables for you: that is the job of migrations ([Databases 04](./04-schemas-and-migrations.md)).

```mermaid
flowchart LR
  code["your code<br/>note = Note(title='x')<br/>session.add(note)"] --> sess["Session<br/>collects the changes"]
  sess -->|"commit: INSERT INTO notes ..."| eng["Engine + connection pool"]
  eng --> pg[("PostgreSQL<br/>table notes")]
  pg -->|"RETURNING id, created_at"| sess
  sess -->|"note.id is now 1"| code
```

**One session per request.** The API wraps each request in its own session and closes it afterwards. Sessions are cheap and not meant to be shared between requests or threads:

```mermaid
sequenceDiagram
  participant C as client
  participant F as FastAPI route
  participant S as Session (get_db)
  participant P as Postgres
  C->>F: POST /notes {"title": "x"}
  F->>S: open (dependency get_db)
  F->>S: add(Note), commit()
  S->>P: BEGIN, INSERT ... RETURNING, COMMIT
  P-->>S: id = 7
  F-->>C: 201 {"id": 7, ...}
  F->>S: close (always, even after an error)
```

## The code, line by line
The real `api/db.py`, with a comment on each line:

```python
engine = create_engine(DATABASE_URL, pool_pre_ping=True)        # 1  where the database is + a pool of connections
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)  # 2  a factory of sessions

class Base(DeclarativeBase):                                      # 3  the common parent of all models
    pass

class Note(Base):                                                 # 4  one class = one table
    __tablename__ = "notes"                                       # 5  the table's name

    id: Mapped[int] = mapped_column(primary_key=True)             # 6  integer primary key (auto-numbered)
    title: Mapped[str] = mapped_column(String(200))               # 7  text, at most 200 characters
    body: Mapped[str] = mapped_column(Text, server_default="")    # 8  unlimited text; the database defaults to ''
    created_at: Mapped[datetime] = mapped_column(                 # 9  date and time with time zone ...
        DateTime(timezone=True), server_default=func.now())       # 10 ... filled in by the database (now())
```

| Line | What it does | If you change or remove it |
|---|---|---|
| 1 `create_engine(DATABASE_URL, pool_pre_ping=True)` | Builds the engine from the address in the environment. `pool_pre_ping` tests a pooled connection before using it. | Without `pool_pre_ping`, the first request after the database restarted fails on a dead connection. |
| 2 `expire_on_commit=False` | After `commit()`, objects keep their values instead of being marked "reload me". | With `True` (the default), reading `note.id` after a commit triggers one more `SELECT`, and fails if the session is already closed. |
| 3 `class Base(DeclarativeBase)` | Collects every model class in `Base.metadata` (the list of tables; Alembic reads it, see [Databases 04](./04-schemas-and-migrations.md)). | Models that do not inherit from `Base` are invisible to SQLAlchemy. |
| 5 `__tablename__` | The table the class maps to. | A different name maps to a table that may not exist: `relation "..." does not exist`. |
| 6 `primary_key=True` | Marks the key column ([Databases 01](./01-relational-basics.md)); an integer key gets auto-numbering. | Without a primary key SQLAlchemy refuses to map the class. |
| 7-8 `Mapped[str]` | The Python type; a plain `str` (not `Optional`) means "must not be NULL". | `Mapped[str \| None]` would allow NULL. |
| 10 `server_default=func.now()` | The **database** fills the value. Python sends nothing for it. | A Python-side default would be computed by the API server's clock instead of the database's. |

## The commands
This module runs one Python script (below) in a container that already has SQLAlchemy.

| Call | Meaning |
|---|---|
| `session.add(obj)` | Mark a new object to be inserted at the next flush or commit. |
| `session.commit()` | Send pending changes and **end the transaction successfully**. |
| `session.rollback()` | **Undo** everything since the transaction began. |
| `session.flush()` | Send pending changes to the database but keep the transaction open (so a rollback can still undo them). |
| `session.get(Note, 1)` | Fetch one row by primary key; **checks the identity map first**. |
| `session.scalars(select(Note).where(...)).all()` | Run a `SELECT` and return `Note` objects as a list. |
| `logging.getLogger("sqlalchemy.engine").setLevel(logging.INFO)` | Print every SQL statement SQLAlchemy sends. The best way to *see* what the interpreter says. |
| `docker cp FILE CONTAINER:PATH` | Copy a file from your computer into a container. |
| `docker exec CONTAINER python FILE` | Run the script inside the running container. |

## Hands-on
A throw-away Postgres (fake password) and a second container made from the **project's own API image** (so `db.py`, `Note` and SQLAlchemy are the real ones). They share one network namespace, so `localhost` in the second is the first. A prepared script, `orm_demo.py`, uses the real `Note` model with SQL logging on. Real output, trimmed (the timings in brackets and a few blank lines are left out).

**1. Start both and copy the script**
```bash
docker run -d --rm --name dbcourse-pg -e POSTGRES_PASSWORD=throwaway-fake postgres:18.7-alpine3.24
until docker exec dbcourse-pg pg_isready -U postgres -q; do sleep 1; done
docker run -d --name dbcourse-mig --network container:dbcourse-pg \
  -e DATABASE_URL=postgresql+psycopg://postgres:throwaway-fake@localhost:5432/postgres \
  aws-local-lab-api:0.1.0 sleep 900
docker cp orm_demo.py dbcourse-mig:/app/orm_demo.py
docker exec dbcourse-mig python orm_demo.py
```
Save this as `orm_demo.py` before the `docker cp` (the full script; `Base.metadata.create_all(engine)` creates the table directly, which is fine for a throw-away demo, the lab uses Alembic). Its sections are shown with their output below.

```python
"""Databases 05 demo: the project's own Note model, with the SQL it generates printed."""
import logging

from sqlalchemy import func, select

from db import Base, Note, SessionLocal, engine

logging.basicConfig(format="    SQL> %(message)s")
sql_log = logging.getLogger("sqlalchemy.engine")


def section(title, show_sql=True):
    sql_log.setLevel(logging.INFO if show_sql else logging.WARNING)
    print(f"\n== {title}")


section("0. the class describes a table", show_sql=False)
for col in Note.__table__.columns:
    print(f"   {col.name:<11} {col.type!s:<26} nullable={col.nullable}")
Base.metadata.create_all(engine)

section("1. add an object, then commit")
with SessionLocal() as session:
    note = Note(title="first", body="hello")
    session.add(note)
    print("   before commit: note.id =", note.id)
    session.commit()
    print("   after commit:  note.id =", note.id)

section("2. a query")
with SessionLocal() as session:
    found = session.scalars(select(Note).where(Note.title == "first")).all()
    print("   found:", [(n.id, n.title) for n in found])

section("3. get() twice: the second one does not touch the database")
with SessionLocal() as session:
    a = session.get(Note, 1)
    b = session.get(Note, 1)
    print("   same Python object:", a is b)

section("4. change an attribute, commit")
with SessionLocal() as session:
    note = session.get(Note, 1)
    note.title = "renamed"
    session.commit()

section("5. rollback: nothing is saved", show_sql=False)
with SessionLocal() as session:
    session.add(Note(title="oops"))
    session.flush()
    print("   inside the transaction:", session.scalar(select(func.count()).select_from(Note)), "rows")
    session.rollback()
    print("   after rollback:        ", session.scalar(select(func.count()).select_from(Note)), "rows")
```

**2. The class describes a table**
```text
== 0. the class describes a table
   id          INTEGER                    nullable=False
   title       VARCHAR(200)               nullable=False
   body        TEXT                       nullable=False
   created_at  DATETIME                   nullable=False
```
**How to read it:** SQLAlchemy turned the attributes of `Note` into columns, with the types and the `NOT NULL` rules from `Mapped[str]`. (`DATETIME` is SQLAlchemy's general name; Postgres stores it as `timestamp with time zone`.)

**3. Add an object, then commit**
```python
note = Note(title="first", body="hello")
session.add(note)
print("before commit: note.id =", note.id)
session.commit()
print("after commit:  note.id =", note.id)
```
```text
   before commit: note.id = None
    SQL> BEGIN (implicit)
    SQL> INSERT INTO notes (title, body) VALUES (%(title)s::VARCHAR, %(body)s::VARCHAR) RETURNING notes.id, notes.created_at
    SQL> {'title': 'first', 'body': 'hello'}
    SQL> COMMIT
   after commit:  note.id = 1
```
**How to read it:** nothing is sent by `add()`: before the commit the object has no `id`. At `commit()` SQLAlchemy opens a transaction (`BEGIN`), sends **one** `INSERT`, and asks Postgres to **return** the new `id` and `created_at` (the `RETURNING` part) so no second query is needed. The values travel as a **dictionary of parameters**, not inside the SQL text. Then `COMMIT`.

**4. A query**
```python
session.scalars(select(Note).where(Note.title == "first")).all()
```
```text
    SQL> SELECT notes.id, notes.title, notes.body, notes.created_at
FROM notes
WHERE notes.title = %(title_1)s::VARCHAR
    SQL> {'title_1': 'first'}
   found: [(1, 'first')]
    SQL> ROLLBACK
```
**How to read it:** the Python expression became a plain `SELECT ... WHERE`. The final `ROLLBACK` is just the session closing a transaction in which nothing changed.

**5. `get()` twice: the identity map**
```text
    SQL> SELECT notes.id, ... FROM notes WHERE notes.id = %(pk_1)s::INTEGER
    SQL> {'pk_1': 1}
   same Python object: True
```
**How to read it:** two calls to `session.get(Note, 1)`, but only **one** `SELECT`. The session remembered row 1 and handed back the **same object** (`a is b` is `True`). Inside one session an object is unique per row.

**6. Change an attribute, commit**
```text
    SQL> UPDATE notes SET title=%(title)s::VARCHAR WHERE notes.id = %(notes_id)s::INTEGER
    SQL> {'title': 'renamed', 'notes_id': 1}
    SQL> COMMIT
```
**How to read it:** the code only wrote `note.title = "renamed"`. SQLAlchemy noticed the change and sent an `UPDATE` that sets **only** the changed column (`title`). Before it, a `SELECT` loaded the object (`get`).

**7. Rollback**
```text
   inside the transaction: 2 rows
   after rollback:         1 rows
```
**How to read it:** after `add()` + `flush()` the new row is visible **inside** the transaction (2 rows) but was never committed. `rollback()` removed it (1 row).

**8. Clean up**
```bash
docker rm -f dbcourse-mig
docker stop dbcourse-pg        # started with --rm: it removes itself
```

## What if…?
**…you forget `commit()`?** Everything above `COMMIT` is still only **inside the transaction**: experiment 7 shows the row exists for the session that made it (2 rows) and vanishes on `rollback()`. Closing a session without committing does the same: the changes are silently discarded, which is the classic "my data does not appear" bug. In the API, every write route calls `db.commit()` before it returns.

## In short
1. An **ORM** lets you work with objects (`Note`) and writes the SQL for you; the model class describes the table, and migrations (not the ORM) change the real table.
2. The **engine** knows the database, a **session** is one short transaction-scoped conversation: nothing is saved until **`commit()`**, and `rollback()` throws it away.
3. Turn on SQL logging to **see** the generated SQL: it is the way to learn what your code really asks.

## Check your understanding
1. What does `session.add(note)` send to the database, and when does something get sent?
2. Why does the `INSERT` end with `RETURNING notes.id, notes.created_at`?
3. In experiment 5, why did two `get()` calls produce one `SELECT`?
4. A route changes `note.title` but never calls `commit()`. What does the client see in the database afterwards, and why?
5. Why does the API open a new session for each request instead of one global session?

<details><summary>Answers</summary>

1. Nothing at once. `add()` only marks the object as new; the `INSERT` is sent at the next `flush()` or `commit()`.
2. The `id` and `created_at` are filled in **by the database** (auto-numbering and `now()`). `RETURNING` brings them back in the same statement, so the object has them right after the commit without a second `SELECT`.
3. The session keeps an **identity map**: after the first `get()` it knows row 1 is that object, and the second `get()` returns it without asking the database.
4. Nothing: the `UPDATE` is in an open transaction that is rolled back when the session closes. Only `commit()` makes the change permanent for other connections.
5. A session holds a transaction and the objects it loaded, and is not safe to share between concurrent requests. One session per request keeps requests isolated, and the `with` block closes it even if the route fails.

</details>

## Official documentation
- [SQLAlchemy 2.1 ORM quick start](https://docs.sqlalchemy.org/en/21/orm/quickstart.html) and [Session basics](https://docs.sqlalchemy.org/en/21/orm/session_basics.html)
- [SQLAlchemy: engine configuration and pooling](https://docs.sqlalchemy.org/en/21/core/engines.html)
- [FastAPI: SQL (relational) databases](https://fastapi.tiangolo.com/tutorial/sql-databases/)
- [PostgreSQL: `INSERT ... RETURNING`](https://www.postgresql.org/docs/current/dml-returning.html)

## Where you use this in the project
- [Lab 04, step 11](../../labs/04-database.md): `api/db.py` (engine, session, `Note`) and the `get_db` dependency ([FastAPI 07](../fastapi/07-dependencies.md)).
- [Lab 04, step 12](../../labs/04-database.md): `POST /notes` (`add` + `commit`), `GET /notes` (`select`), `PUT` (attribute change) and `DELETE`.
- [Databases 04](./04-schemas-and-migrations.md): the same `Note` model is the target of the `0001` migration.
