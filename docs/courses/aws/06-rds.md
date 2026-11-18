# AWS 06 — RDS: managed databases

> **Course:** [AWS](./README.md)  ·  **Time:** ~45 min  ·  **Needs:** [AWS 04 — VPC](./04-vpc.md) (subnets); [Networking 07 — Firewalls and security groups](../networking/07-firewalls-and-security-groups.md)
> **Used in the labs:** [Lab 04](../../labs/04-database.md) (the `postgres` container stands in for an RDS instance)
> **No real AWS here:** this module never touches an AWS account. Its hands-on queries the lab's local Postgres and says, line by line, what RDS does differently.

## What you will learn
- Say what **Amazon RDS** is and what AWS looks after for you, and what stays your job.
- Name the parts of an RDS setup (instance, class, storage, subnet group, security group, parameter group, endpoint) and find each one in this project.
- Explain **Multi-AZ**, **read replicas**, **backups** and **snapshots**, and why they are different things.
- Predict what your application sees when its database restarts or fails over.

## Words you need
| Word | Plain-words meaning |
|---|---|
| **Managed service** | A service where AWS runs the machines and the software for you (installs, patches, replaces broken hardware) and you only use it. |
| **RDS** (Relational Database Service) | AWS's managed service for relational databases (PostgreSQL, MySQL, MariaDB, Oracle, SQL Server, Db2, and Aurora). |
| **DB instance** | One database server run by RDS: an engine, a size, and storage. |
| **Engine** | The database software itself (here PostgreSQL) and its version. |
| **Instance class** | The size of the server: CPU and memory (names like `db.t4g.micro`, `db.m`, `db.r`). A bigger class costs more. |
| **Storage** | The disk (EBS volume) where the data lives; you choose its type and size, and it can survive the server being replaced. |
| **Endpoint** | The DNS name applications use to reach the database (`name.xxxx.region.rds.amazonaws.com`). AWS can point it at another server without the app changing anything. |
| **DB subnet group** | The list of private subnets, in at least two Availability Zones, where an instance is allowed to live. See [AWS 04](./04-vpc.md). |
| **Security group** | The firewall of the instance: for example "allow port 5432 only from the API's security group". |
| **Parameter group** | The set of engine settings (connection limit, memory use...) applied to an instance; you change settings there, not by editing files. |
| **Multi-AZ** | A **standby** copy of the database in another Availability Zone, kept in step with the main one; AWS switches to it if the main one fails. |
| **Read replica** | An extra, read-only copy that serves queries to take load off the main database. It is a performance tool, not a safety net. |
| **Snapshot / automated backup** | A saved copy of the database's disk. Restoring one always creates a **new** instance. |
| **Secrets Manager** | The AWS service that stores passwords and hands them to applications, so they are not in files. |

## The idea
**Analogy.** Running your own database is **owning a house**: you fix the plumbing, repaint, change the locks and replace the boiler yourself. RDS is **renting a managed apartment**: the landlord
handles the building (heating, repairs, security, a spare flat if yours floods), and you only decide what goes inside (your tables and data) and how big an apartment you need.

**Precisely.** RDS runs the database engine on a server you cannot log into (no SSH, no operating system access). AWS takes care of installing and patching the engine, taking backups, replacing failed hardware and, if you
ask for it, failing over to a standby. **You** still own the data model, the queries, the indexes, the sizing, the settings and who may connect. That split is the *shared responsibility* idea.

```mermaid
flowchart LR
  subgraph vpc["VPC"]
    subgraph a["private subnet, zone a"]
      p[("RDS primary")]
    end
    subgraph b["private subnet, zone b"]
      s[("standby (Multi-AZ)")]
    end
    app["application<br/>(security group: app-sg)"]
  end
  app -->|"endpoint DNS name, port 5432<br/>(db-sg allows only app-sg)"| p
  p -. "synchronous copy of every write" .-> s
```

**What your application sees when the main database fails (Multi-AZ):**
```mermaid
sequenceDiagram
  participant App
  participant E as Endpoint (DNS name)
  participant P as Primary (zone a)
  participant S as Standby (zone b)
  App->>E: connect to the endpoint
  E->>P: resolves to the primary
  P-xP: failure
  Note over App: connections break, queries fail for a short time
  S->>S: AWS promotes the standby
  E->>S: the endpoint now resolves to the new primary
  App->>E: reconnect: works again
```
The application keeps the **same** endpoint name; it only needs to reconnect.

## The code, line by line
There is no AWS command here. Instead, the project's real `postgres` service from `docker-compose.yml`, with the RDS setting each line stands for:

```yaml
  postgres:
    image: postgres:18.7-alpine3.24            # engine + version
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-lab}     # master user name
      POSTGRES_DB: ${POSTGRES_DB:-lab}         # initial database name
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?set POSTGRES_PASSWORD in .env (see .env.example)}
    volumes:
      - pgdata:/var/lib/postgresql             # storage
    networks:
      - private                                # subnet group + security group
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]   # status "Available"
```

| Line | What it does | The RDS counterpart, and the difference |
|---|---|---|
| `image: postgres:18.7-alpine3.24` | Engine and exact version. | **Engine** and **engine version** chosen at creation. RDS offers minor-version upgrades during a **maintenance window**; here you change the tag yourself. |
| `POSTGRES_USER` / `POSTGRES_DB` | First account and database. | The **master user** and initial database. In RDS the master user is **not** a true superuser (it gets the `rds_superuser` role), because AWS keeps control of the server. |
| `POSTGRES_PASSWORD: ${...}` | Password from `.env`. | The master password, ideally kept in **Secrets Manager** and handed to the application at start. |
| `volumes: pgdata:...` | The named volume that survives the container ([Docker 08](../docker/08-volumes-and-bind-mounts.md)). | **Storage**: an EBS volume with a type and size, optionally growing automatically. |
| `networks: - private` and no `ports:` | Only containers on `private` can connect. | The **DB subnet group** (private subnets) plus the **security group** rule "5432 from the API only" ([Lab 03](../../labs/03-networking.md)). |
| `healthcheck: pg_isready` | Docker marks the container `healthy` when it accepts connections. | The instance status **Available**, plus CloudWatch metrics and events. |
| *(absent)* | There is no size line: the container may use all the laptop's memory and CPU. | The **instance class** fixes CPU and memory. |
| *(absent)* | Nothing copies the data elsewhere. | **Multi-AZ**, **automated backups** and **snapshots**. |

## The commands
Local commands only. Each one is read-only.

| Command / flag | Meaning |
|---|---|
| `docker compose exec -T postgres sh -c '...'` | Run a command inside the `postgres` container; `-T` disables the terminal (needed in scripts); `sh -c '...'` lets the container's own `$POSTGRES_USER` variable be used. |
| `psql -U USER -d DB` | The PostgreSQL command-line client: connect as `USER` to database `DB`. |
| `-tA` | Print only the values: `t` hides headings, `A` removes the alignment padding. |
| `-c "SQL"` | Run one SQL statement (or a backslash command like `\l`) and exit; repeat to run several. |
| `show NAME;` | Print one engine setting (what an RDS **parameter group** controls). |
| `\l` / `\du` | List the databases / the roles (accounts). |
| `docker inspect CONTAINER --format '...'` | Print selected details of a container, here its resource limits (Go template, see [Docker 03](../docker/03-dockerfile.md)). |

## Hands-on
Against the lab's running stack (Lab 04). Real output, trimmed. No password is shown: the app's URL is printed with the password hidden.

**1. The engine and its settings (RDS: engine version and parameter group)**
```bash
docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tA -c "select version();" -c "show listen_addresses;" -c "show max_connections;" -c "show shared_buffers;" -c "select pg_size_pretty(pg_database_size(current_database()));"'
```
```text
PostgreSQL 18.7 on x86_64-pc-linux-musl, compiled by gcc (Alpine 15.2.0) 15.2.0, 64-bit
*
100
128MB
7862 kB
```
The exact engine version (18.7, on Alpine/musl). `listen_addresses = *` means "accept connections on every network the container is on": the **network and password** protect it, as the security group does in AWS. `max_connections = 100` and
`shared_buffers = 128MB` are settings that, in RDS, live in a **parameter group**; RDS derives such defaults from the instance's memory, so a bigger class gets higher values. The last line is the database's size on disk, which RDS would bill as storage.

**2. The accounts (RDS: master user)**
```bash
docker compose exec -T postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "\du"'
```
```text
                             List of roles
 Role name |                         Attributes                         
-----------+------------------------------------------------------------
 lab       | Superuser, Create role, Create DB, Replication, Bypass RLS
```
One account, `lab`, and it **is** a superuser: on your laptop you own the whole server. In RDS the master user cannot do everything (no access to the machine, some settings locked): that is the price of AWS taking care of the server.

**3. The endpoint, and the "instance size"**
```bash
docker compose exec -T api python -c "import db; print('endpoint seen by the app:', db.engine.url.render_as_string(hide_password=True))"
docker inspect $(docker compose ps -q postgres) --format 'memory limit (bytes, 0 = none): {{.HostConfig.Memory}}  cpu limit (nano-CPUs, 0 = none): {{.HostConfig.NanoCpus}}  restart policy: {{if .HostConfig.RestartPolicy.Name}}{{.HostConfig.RestartPolicy.Name}}{{else}}none{{end}}'
```
```text
endpoint seen by the app: postgresql+psycopg://lab:***@postgres:5432/lab
memory limit (bytes, 0 = none): 0  cpu limit (nano-CPUs, 0 = none): 0  restart policy: no
```
The app reaches the database through one name, `postgres`, resolved by Docker DNS: the stand-in for the RDS **endpoint**. If you ever change where the database runs, only that name must keep working. There is **no limit** on memory or CPU (0 means
none) and **no restart policy**: no instance class, and nothing restarts the database if it dies.

## What if…?
**…the database goes away for a few seconds?** One instance, no standby: the closest local picture of a failure without Multi-AZ. While polling `GET /notes` once a second, the database container was stopped for about 8 seconds and then started again
(`docker compose stop postgres`, wait, `docker compose start postgres`). Real result, one HTTP status per second:
```text
200 200 200 200 500 500 500 500 500 500 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200 200
```
Six `500` answers (the API could not reach the database), then `200` again **without restarting any API container**: the connection pool tests each connection before use (`pool_pre_ping`, [Lab 04, step 11](../../labs/04-database.md)) and
simply opens new ones. `GET /health` stayed `200` throughout, because it never touches the database (a liveness check, see [Lab 02](../../labs/02-load-balancing.md)). Afterwards `GET /notes` answered `[]` again (the table is empty because the test notes were deleted).
With **Multi-AZ** the outage is a failover of about a minute or two (see the AWS documentation) with the same endpoint; without it, you wait for the instance to be repaired or restored. In both cases the application **must reconnect**, which is why
a pool that checks its connections matters.

## In short
1. RDS is a managed database: AWS runs, patches, backs up and repairs the server; you own the schema, queries, sizing and access.
2. Safety comes from **Multi-AZ** (automatic failover to a standby), **backups and snapshots** (restore into a new instance) and a **private subnet group + security group**; **read replicas** are only for read performance.
3. Applications use the **endpoint** name and must be ready to **reconnect**; the lab's `postgres` service is a stand-in without size limits, failover or managed backups.

## Check your understanding
1. Name two things AWS does for you with RDS and two things that stay your responsibility.
2. What is the difference between a Multi-AZ standby and a read replica?
3. You restore a snapshot. Do you get your old instance back, or something else?
4. Why does the application keep working after a failover without changing its configuration?
5. In this project, which local line plays the role of the RDS subnet group and security group?

<details><summary>Answers</summary>

1. AWS: patching the engine, taking automated backups, replacing failed hardware, failing over to a standby. You: the schema and queries, indexes and sizing, settings (parameter group), and who may connect (security group, passwords).
2. A Multi-AZ standby exists for **availability**: it is a synchronous copy in another zone that takes over if the main one fails. A read replica exists for **read performance**: an asynchronous, read-only copy that serves queries; it is not an automatic safety net.
3. A **new** instance with its own endpoint, created from the snapshot; the old one is not changed.
4. The application uses the endpoint's DNS **name**, and AWS repoints that name to the promoted standby; the app only has to reconnect.
5. `networks: - private` (an internal network) together with having no `ports:` line.

</details>

## Official documentation
- [What is Amazon RDS?](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Welcome.html)
- [Multi-AZ DB instance deployments](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZSingleStandby.html)
- [Backing up and restoring an RDS instance](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_CommonTasks.BackupRestore.html)
- [Working with parameter groups](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_WorkingWithParamGroups.html)
- [PostgreSQL on Amazon RDS](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_PostgreSQL.html)

## Where you use this in the project
- [Lab 04, step 10](../../labs/04-database.md#step-10--the-postgres-container): the `postgres` service, private network, volume and password, and the table of RDS pieces in its section 2.2.
- [Lab 04, step 11](../../labs/04-database.md#step-11--the-database-layer-the-first-migration-and-the-migrate-job): `DATABASE_URL` is the endpoint handed to the app; the `migrate` job is the migration task you would run before a deployment.
- [Lab 03](../../labs/03-networking.md): the `private` network is the private subnet that keeps the database away from the internet.
