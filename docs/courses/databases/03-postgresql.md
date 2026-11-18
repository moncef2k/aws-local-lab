# Databases 03 — PostgreSQL: server, roles, databases

> **Course:** [Databases](./README.md)  ·  **Time:** ~45 min  ·  **Needs:** [Databases 01 — Relational databases: tables, rows, keys](./01-relational-basics.md), [Databases 02 — SQL basics](./02-sql.md)
> **Used in the labs:** [Lab 04, step 10](../../labs/04-database.md#step-10--the-postgres-container) (the `postgres` service, `pg_isready`, the password from `.env`) and [step 13](../../labs/04-database.md#step-13--the-admin-profile-a-door-to-the-database-closed-by-default) (connecting from outside)

## What you will learn
- Draw the hierarchy **server → database → schema → table**, and say what one connection is connected to.
- Create a **database** and a **role**, and give the role only the **privileges** it needs.
- Read `pg_hba.conf`, the file that decides **who may connect from where and with what proof**, and explain why `psql` inside the container needs no password while a connection from another container does.
- Read a connection address (host, port, user, database) and use `pg_isready` to test a server.

## Words you need
| Word | Plain-words meaning |
|---|---|
| **PostgreSQL server** | One running PostgreSQL program (here: one container). It listens on a port, `5432` by default, and holds several databases. |
| **Database** | A separate collection of tables inside a server. A connection is made to **one** database; databases do not see each other's tables. |
| **Schema** | A named folder of tables inside a database. Every database starts with one called `public`. |
| **Role** | An account (a user, or a group of users). Roles belong to the **whole server**, not to one database. |
| **Superuser** | A role that bypasses every permission check. The first account the container creates is one. |
| **Privilege** | A permission on an object: `SELECT` (read), `INSERT` (add), `UPDATE`, `DELETE`... on a table, for example. |
| **`GRANT`** | The SQL statement that gives a privilege to a role. |
| **`pg_hba.conf`** | "Host-based authentication": a file of rules saying which connections are accepted and how the client must prove who it is. |
| **Authentication method** | The proof required by a `pg_hba.conf` rule: `trust` (none) or `scram-sha-256` (a password, checked without sending it in clear). |
| **Connection address** | What a program needs to connect: host, port, user, database (and the password), often written as one text: `postgresql://user:password@host:5432/database`. |
| **Template database** | A database used as a pattern for new ones (`template0`, `template1`). You do not use them directly. |
| **Data directory** | The folder where the server keeps all its files: `/var/lib/postgresql/18/docker` in the official image. |

## The idea
**Analogy.** A PostgreSQL server is an **office building**. Each **database** is a separate office with its own door: once you are inside one, you cannot see into the others. Inside an office, **schemas** are rooms, and **tables** are filing cabinets in a room.
**Roles** are key cards, and each card opens only the cabinets it was programmed for. At the entrance sits a **security desk** with a list (`pg_hba.conf`): "people coming from inside the building: let them in; people coming from outside: they must show a password".

**Precisely.** The server holds databases; each database holds schemas; each schema holds tables. A client connects to a **database as a role**; the server first checks `pg_hba.conf`, top to bottom, and the **first matching rule** decides the authentication method; after that, every statement is
checked against the role's **privileges**. A new role can do nothing but connect until you `GRANT` it something (the principle of **least privilege**: give only what is needed).

```mermaid
flowchart TB
  s["PostgreSQL server (port 5432)"] --> d1["database lab"]
  s --> d2["database shop"]
  s --> d3["template0, template1, postgres"]
  d2 --> sc["schema public"]
  sc --> t["table products"]
  s -. "roles are server-wide" .- r["roles: postgres, reader, ..."]
```

**What happens when a client connects:**
```mermaid
sequenceDiagram
  participant C as client (psql or your API)
  participant S as PostgreSQL server
  C->>S: connect: host, port, user=reader, database=shop
  S->>S: look through pg_hba.conf: first matching rule wins
  alt rule says trust
    S-->>C: accepted, no password asked
  else rule says scram-sha-256
    S->>C: please prove it
    C->>S: password (proof)
    S-->>C: accepted, or FATAL: password authentication failed
  end
  C->>S: SELECT ... (checked against the role's privileges)
```

## The code, line by line
The active rules of `pg_hba.conf` in the official image (re-spaced, with my own numbered comments; the real lines are in exercise 4), and the three statements we use to create a database, a role and a permission:

```text
local   all   all                      trust            # 1  connections through the local socket, inside the container
host    all   all   127.0.0.1/32       trust            # 2  TCP connections from the container itself (IPv4)
host    all   all   ::1/128            trust            # 3  the same, IPv6
local   replication  all               trust            # 4-6 same three rules for replication (copying to another server)
host    replication  all  127.0.0.1/32 trust
host    replication  all  ::1/128      trust
host    all   all   all                scram-sha-256    # 7  everything else: a password is required
```
```sql
CREATE DATABASE shop;                                          -- a new, empty database (owned by the current role)
CREATE ROLE reader LOGIN PASSWORD 'demo-only-not-a-secret';    -- an account that may log in; it can do nothing else yet
GRANT SELECT ON products TO reader;                            -- now it may read this one table
```

| Line | What it does | If you change or remove it |
|---|---|---|
| rules 1 to 3 (`trust`) | Anyone already **inside the container** (through the socket or `127.0.0.1`) is accepted with no password. That is why `docker compose exec postgres psql` works without one. | Change to `scram-sha-256` and even `psql` inside the container asks for the password. |
| rule 7 (`host all all all scram-sha-256`) | Any other connection (another container, your machine) must give a password. This is the rule that protects the database on the network. | Change it to `trust` and the password no longer protects anything. |
| columns `all all` | "Any database, any role". Real servers restrict them (for example `shop` only for `reader`). | Narrowing them is how you limit a role to one database. |
| `CREATE DATABASE shop;` | Creates a database with its own `public` schema. | Without it there is nowhere to put the tables of a new application. |
| `CREATE ROLE reader LOGIN PASSWORD '...'` | Creates an account; `LOGIN` allows it to connect, the password is stored hashed. | Without `LOGIN` it is a "group" role that cannot connect. |
| `GRANT SELECT ON products TO reader;` | Gives exactly one privilege on one table. | Forget it and `reader` gets `permission denied`. Grant `ALL` and it can also change and delete. |

## The commands
| Command / flag | Meaning |
|---|---|
| `psql -U USER -d DB` | Connect to database `DB` as role `USER` (inside the container this uses the local socket). |
| `psql -h HOST -U USER -d DB -w` | Connect over the network to `HOST`; `-w` means "never ask for a password" (fail instead). |
| `\l` / `\du` / `\dn` / `\c DB` | psql commands: list databases / roles / schemas, and connect to another database. |
| `SHOW data_directory;` / `SHOW port;` | Print one server setting. |
| `SET ROLE reader;` | Continue the session **as** `reader`, so you feel exactly its permissions (a superuser may do this). |
| `pg_isready -U USER -d DB` | Ask a server "are you accepting connections?"; prints the address and the answer, exit code 0 means yes. |
| `PGPASSWORD=... psql ...` | Give `psql` the password through an environment variable (the safe way for scripts; fake values here). |
| `docker inspect -f '{{.NetworkSettings.Networks.bridge.IPAddress}}' NAME` | Print the container's address on the default `bridge` network (a Go template, see [Docker 03](../docker/03-dockerfile.md)). |

## Hands-on
A throw-away server (`course-pg3`) with a fake password, so nothing touches the lab. Real output, trimmed.

**1. Start it**
```bash
docker run --rm -d --name course-pg3 -e POSTGRES_PASSWORD=demo-only-not-a-secret postgres:18.7-alpine3.24
until docker exec course-pg3 pg_isready -U postgres -q; do sleep 1; done      # wait until it accepts connections
P() { docker exec -i course-pg3 psql -U postgres "$@"; }                     # a shortcut for the client
```
(No output: the loop ends silently when the server is ready, a few seconds after the start.)

**2. Create a database, connect to it, list the databases**
```bash
P -c 'CREATE DATABASE shop;'
docker exec -i course-pg3 psql -U postgres -d shop -tA -c "select current_database(), current_user;" -c '\dn'
P -tA -c 'SHOW data_directory;' -c 'SHOW port;'
P -tA -c "select datname from pg_database order by datname;"
```
```text
CREATE DATABASE
shop|postgres
public|pg_database_owner
/var/lib/postgresql/18/docker
5432
postgres
shop
template0
template1
```
One server, several databases: the fresh server had `postgres`, `template0` and `template1`, and now `shop` as well. Connected to `shop` as `postgres`; the new database has one schema, `public`. The server's files live in `/var/lib/postgresql/18/docker` (the folder the `pgdata` volume of [Lab 04](../../labs/04-database.md#step-10--the-postgres-container) keeps), and it listens on 5432.

**3. A role that can do nothing, then a little, then not more**
```bash
docker exec -i course-pg3 psql -U postgres -d shop -q <<'SQL'
CREATE TABLE products (id serial PRIMARY KEY, name text NOT NULL);
INSERT INTO products (name) VALUES ('pencil'), ('notebook');
CREATE ROLE reader LOGIN PASSWORD 'demo-only-not-a-secret';
\du
SET ROLE reader;
SELECT * FROM products;
SQL
```
```text
                             List of roles
 Role name |                         Attributes                         
-----------+------------------------------------------------------------
 postgres  | Superuser, Create role, Create DB, Replication, Bypass RLS
 reader    | 

ERROR:  permission denied for table products
```
`\du` shows two roles: `postgres` (a superuser) and `reader` (no special attributes). As `reader`, reading the table is refused: a new role has **no** privileges. Now the grant:
```bash
docker exec -i course-pg3 psql -U postgres -d shop -q <<'SQL'
GRANT SELECT ON products TO reader;
SET ROLE reader;
SELECT * FROM products;
SQL
```
```text
 id |   name   
----+----------
  1 | pencil
  2 | notebook
(2 rows)
```
With one `GRANT SELECT`, `reader` can read.

**4. Who may come in: `pg_hba.conf`**
```bash
docker exec course-pg3 sh -c "grep -v '^#' /var/lib/postgresql/18/docker/pg_hba.conf | grep -v '^\$'"
```
```text
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 trust
local   replication     all                                     trust
host    replication     all             127.0.0.1/32            trust
host    replication     all             ::1/128                 trust
host all all all scram-sha-256
```
These are the seven rules explained above (the last line was appended by the image because we set a password). Rules 1 to 3 trust connections from inside the container; rule 7 asks everyone else for a password.

**5. Coming from outside: another container over the network**
```bash
IP=$(docker inspect -f '{{.NetworkSettings.Networks.bridge.IPAddress}}' course-pg3)
docker run --rm postgres:18.7-alpine3.24 psql -h "$IP" -U reader -d shop -w -tA -c "select 1"
docker run --rm -e PGPASSWORD=demo-only-not-a-secret postgres:18.7-alpine3.24 psql -h "$IP" -U reader -d shop -tA -c "select current_user, count(*) from products group by 1"
docker run --rm -e PGPASSWORD=wrong-password postgres:18.7-alpine3.24 psql -h "$IP" -U reader -d shop -tA -c "select 1"
```
```text
psql: error: connection to server at "172.17.0.2", port 5432 failed: fe_sendauth: no password supplied
reader|2
psql: error: connection to server at "172.17.0.2", port 5432 failed: FATAL:  password authentication failed for user "reader"
```
Three tries from a **different** container (so rule 7 applies): no password (refused: `no password supplied`), the right one (accepted: `reader` sees the 2 rows it was granted), a wrong one (refused: `password authentication failed`). This is exactly what [Lab 04, check 4](../../labs/04-database.md#step-10--the-postgres-container) showed with the project database.

**6. The same tools on the lab's server**
```bash
docker compose exec -T postgres pg_isready -U lab -d lab
docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tA -c "select datname from pg_database order by 1;" -c "\du"'
```
```text
/var/run/postgresql:5432 - accepting connections
lab
postgres
template0
template1
lab|Superuser, Create role, Create DB, Replication, Bypass RLS
```
`pg_isready` is the healthcheck of the project's `postgres` service. The lab server has a database `lab` and one role, `lab`, which is a **superuser**: the account the container created from `POSTGRES_USER`. Clean up: `docker stop course-pg3` (started with `--rm`, so it disappears).

## What if…?
**…the role has `SELECT` only and tries to write?**
```bash
docker exec -i course-pg3 psql -U postgres -d shop -q <<'SQL'
SET ROLE reader;
INSERT INTO products (name) VALUES ('eraser');
SQL
```
```text
ERROR:  permission denied for table products
```
(Real output: in the run that followed the `GRANT SELECT`, this `INSERT` came right after the successful `SELECT`.) Reading was granted, writing was not: **least privilege** works. This is the safest shape for an application that only reads. The project takes a shortcut: its API connects as `lab`, the superuser, which can do anything.
It is simple for a lab, but in production you would create a role such as `app` with only `SELECT`, `INSERT`, `UPDATE`, `DELETE` on the `notes` table, so that a bug or an injection cannot drop tables.

## In short
1. A PostgreSQL **server** holds **databases**; a connection is made to one database **as a role**; databases hold **schemas** (`public`) that hold **tables**; roles belong to the whole server.
2. `pg_hba.conf` decides, top to bottom, who may connect from where: in the official image the container itself is trusted, everyone else needs a **password** (`scram-sha-256`).
3. A new role has **no** privileges: `GRANT` only what it needs (least privilege); `pg_isready` tests whether a server is up.

## Check your understanding
1. In which order are the objects nested: table, schema, database, server?
2. A new role `reader` tries `SELECT * FROM products;` right after `CREATE ROLE`. What happens, and what fixes it?
3. Why can you run `psql` inside the `postgres` container without a password, but not from another container?
4. What does `pg_isready -U lab -d lab` print when the server is up, and where does this project use it?
5. Why is it better for the API to connect as a role with limited privileges than as the superuser?

<details><summary>Answers</summary>

1. Server, then database, then schema, then table.
2. `ERROR: permission denied for table products`: a new role has no privileges. `GRANT SELECT ON products TO reader;` fixes it.
3. The first rules of `pg_hba.conf` (`local` and `127.0.0.1`) are `trust`, so connections from inside the container are accepted without proof; connections arriving over the network match the last rule, which requires `scram-sha-256` (a password).
4. `/var/run/postgresql:5432 - accepting connections` (the address and the verdict, exit code 0). It is the healthcheck of the `postgres` service in `docker-compose.yml`.
5. Least privilege: if the API is hacked, or a bug or SQL injection runs a destructive statement, a limited role cannot drop tables, change roles or read other databases, while a superuser can do anything.

</details>

## Official documentation
- [Managing databases](https://www.postgresql.org/docs/current/managing-databases.html)
- [Database roles](https://www.postgresql.org/docs/current/user-manag.html)
- [Privileges (`GRANT`)](https://www.postgresql.org/docs/current/ddl-priv.html)
- [`pg_hba.conf`: client authentication](https://www.postgresql.org/docs/current/auth-pg-hba-conf.html)
- [Connection strings](https://www.postgresql.org/docs/current/libpq-connect.html#LIBPQ-CONNSTRING)
- [`pg_isready`](https://www.postgresql.org/docs/current/app-pg-isready.html)

## Where you use this in the project
- [Lab 04, step 10](../../labs/04-database.md#step-10--the-postgres-container): the `postgres` service, `POSTGRES_USER` / `POSTGRES_DB` creating the first role and database, the healthcheck with `pg_isready`, and check 4, a client container refused without a password (rule 7).
- [Lab 04, step 11](../../labs/04-database.md#step-11--the-database-layer-the-first-migration-and-the-migrate-job): `DATABASE_URL` is a connection address: user `lab`, host `postgres`, port `5432`, database `lab`.
- [Lab 04, step 13](../../labs/04-database.md#step-13--the-admin-profile-a-door-to-the-database-closed-by-default): connecting from outside through the admin proxy still hits rule 7 and needs the password.
- [AWS 06 — RDS](../aws/06-rds.md): on RDS the master user is **not** a true superuser, and access is controlled by a security group in front of the same kind of password check.
