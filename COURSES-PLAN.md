# COURSES-PLAN.md - tool courses (second learning track)

Status: **APPROVED 2026-11-16** (your answers to the 5 decisions are applied below). Jira epic: **`AWSLAB-79` "Tool courses"**.
Nothing under `docs/courses/` exists yet; the first module is written at the stop of the next lab step.

The labs (`docs/labs/`) show **how to build** the project. The courses (`docs/courses/`) explain **each tool in depth**
for a complete beginner, so you understand what you typed. The labs workflow in `CLAUDE.md` stays as it is; course modules
are an extra deliverable written at the end of a lab step's stop (see "How modules get written").

## Summary

| | |
|---|---|
| Courses | 10 |
| Modules scheduled | **83** (trimmed from 98 by merging 11 pairs and moving 4 to *on request*) |
| On request only | 4 (marked "on request" in the course tables and listed in "On-request modules") |
| Backlog from labs 00-02 (topic already appeared) | 29 |
| Steps left in PLAN.md | 52 (steps 8-59), capacity 2 modules per step = 104 slots, **21 slots free** |
| Wait between "topic appears in a lab" and "module written" | about 9 steps on average, longest 28 (the backlog tail) |

Why some waits are long: Lab 04 (Database) introduces 14 modules in only 5 steps (slot 1 gives it 1 per step), and the backlog from
labs 00-02 uses one slot per step until step 36. Nothing is skipped, it is just a queue. The free slots at the end
(steps 46, 47, 48, 50, 51, 56, 57, 58, 59) are where on-request modules and any slip land.

## Conventions

- **Location:** `docs/courses/<tool>/NN-<slug>.md`, one file per module, 150-300 lines. `NN` is the *reading order*
  inside the course, not the writing order (so numbers of on-request modules stay reserved).
- **Extra files** (created in the first module commit, nothing else): `docs/courses/README.md` (index, reading order,
  lab-to-course map), `docs/courses/_TEMPLATE.md` (the module skeleton below), and a short `docs/courses/<tool>/README.md`
  per course (module list and prerequisites), created with that course's first module.
- **Module skeleton** (your writing standard): *What you will learn* -> *Words you need* (every term defined in plain
  words, none left unexplained in a table) -> concept (everyday analogy first, then the precise explanation) -> Mermaid diagram
  (sequence diagram for "who talks to whom", flowchart for structure) -> annotated config/code (comment per line + table
  `line / what it does / what happens if you change or remove it`) -> commands (what it does, each flag, how to read the
  output) -> *Hands-on* (runs on your laptop with Docker, **real captured output only**) -> *What if...?* experiment ->
  *In short* (3 lines) -> quiz (5 questions, answers in `<details>`) -> official docs -> *Where you use this in the project*
  (links to lab sections).
- **Exercises** use throw-away `docker run --rm <pinned image>` containers, so they do not depend on the state of the lab
  and never touch your data. Every image is pinned (no `:latest`).
- **Commit message:** `AWSLAB-NNN docs: course <tool> module NN - <title>`, where `AWSLAB-NNN` is the module's own ticket.
- **"Go deeper" in the labs:** when a module is written, I add its link to a short `## Go deeper` list at the very end of the
  lab where its topic first appears (column "First appears"), in the same commit. If that lab file does not exist yet, the
  link is added when the lab is written. No other edit to existing labs.

## How modules get written

1. At the end of each lab step, **after its docs commit and before the reviewer runs**, I write **at most 2 modules**:
   - **Slot 1: the current/next lab.** The oldest not-yet-written module whose topic first appears in the current lab or the
     next one (earliest first step, then Docker -> Networking -> Nginx -> FastAPI -> the rest).
   - **Slot 2: the backlog from labs 00-02**, most basic first: Docker, Networking, Nginx, FastAPI, then AWS.
   - If one queue is empty the other takes both slots. Never more than 2.
2. **Jira:** each module gets its ticket **only when it is scheduled**: a *Tache* under epic `AWSLAB-79`, titled
   `Course <tool> NN - <title>`, labels `courses` and `course-<tool>`, created straight into **In Progress** (transition `21`).
   It moves to **Done** (`41`) once the module is committed and the reviewer passed it. The key is then recorded in the
   "Ticket" column below.
3. For each module: run its exercises to capture real output, write the file, update `docs/courses/README.md` and the lab's
   "Go deeper" list, commit.
4. The `step-reviewer` checks the course commit(s) together with the step's code and docs commits (real outputs, beginner
   writing standard, size, links, no secrets). FAIL -> fix in a small follow-up commit, review again (at most twice).
5. The report gets one line per module: `New course module: <title> (<file>)`.
6. "no course modules today" skips them for that session; the queue just waits.
7. The "Target step" column is a forecast, not a promise: if a step needs a module sooner I move it up and say so.
8. Constraints that delay a module on purpose: Kubernetes modules wait until k3d is installed (step 40, with your OK);
   Terraform modules wait until Terraform is installed (step 53, with your OK), except the concept module (step 52).
   The AWS course has no exercises against a real account; its exercises are "map this lab component to the service" tasks or
   run against local stand-ins (SeaweedFS as the local S3, later the emulator). I say so inside the module rather than invent output.

## On-request modules

Not scheduled. Written only when you type **`course <tool> <module>`** (for example `course fastapi testing`), at the next stop,
on top of the 2-per-step cap (and with its own ticket created then).

| Command | Module | Why it is on request |
|---|---|---|
| `course fastapi testing` | FastAPI 08 - Testing with TestClient (`fastapi/08-testing.md`) | The labs test with shell scripts; pytest-style testing is a bonus. |
| `course aws cloudfront` | AWS 09 - CloudFront and CDNs (`aws/09-cloudfront.md`) | Lab 08 explains CloudFront in its own theory; a deeper course module is a bonus. |
| `course aws dynamodb` | AWS 11 - DynamoDB (`aws/11-dynamodb.md`) | Only one table is created (step 55); the lab explains what is needed. |
| `course terraform modules` | Terraform 07 - Modules (`terraform/07-modules.md`) | Not used in the labs; concept only. |

## The courses

`First appears` = the first PLAN.md step whose work uses the topic. `Target step` = when the module is written (forecast). `Ticket` is filled in when the module is scheduled.

### Docker - How containers and Compose work, from zero. (10 modules)

| # | Module | File | First appears | Target step | Ticket | Used by |
|---|---|---|---|---|---|---|
| 01 | Images, containers and their lifecycle | `01-images-and-containers.md` | step 2 (Lab 01) | step 8 | AWSLAB-81 | `docker build`, `docker run`, stop/rm (2); `docker kill` and restart (6) |
| 02 | Docker Desktop on Windows (WSL2) | `02-docker-desktop-wsl2.md` | step 0 (Lab 00) | step 9 | AWSLAB-83 | Environment check; what actually runs on this laptop (cAdvisor tweaks again in step 31) |
| 03 | Dockerfile instructions | `03-dockerfile.md` | step 2 (Lab 01) | step 10 | AWSLAB-85 | `api/Dockerfile` (FROM, COPY, RUN, USER, CMD) |
| 04 | Layers and the build cache | `04-layers-and-build-cache.md` | step 2 (Lab 01) | step 11 | AWSLAB-87 | Dependencies copied before code to reuse the cache |
| 05 | Tags, digests and registries | `05-tags-and-registries.md` | step 2 (Lab 01) | step 12 | AWSLAB-89 | Pinned `python:3.12-slim-...`, the no-`:latest` rule |
| 06 | Environment variables, config and secrets | `06-config-and-secrets.md` | step 3 (Lab 01) | step 13 | AWSLAB-91 | Compose `environment:` and `.env` / `.env.example` |
| 07 | Docker networks and service-name DNS | `07-networks.md` | step 3 (Lab 01) | step 14 | AWSLAB-93 | Compose default network (3), `api` resolving to every replica (4-5), `public`/`private` (8) |
| 08 | Volumes and bind mounts | `08-volumes-and-bind-mounts.md` | step 10 (Lab 04) | step 11 | AWSLAB-86 | Postgres named volume; persistence test (14) |
| 09 | Docker Compose | `09-compose.md` | step 3 (Lab 01) | step 15 | AWSLAB-95 | `docker-compose.yml`, `up`, `ps`, `deploy.replicas` |
| 10 | Debugging: logs, exec, inspect | `10-debugging.md` | step 3 (Lab 01) | step 16 | AWSLAB-97 | `docker compose ps/logs` now; `exec` and `network inspect` later |

### Networking - IPs, ports, DNS, HTTP, NAT, subnets, firewalls, TLS. (8 modules)

| # | Module | File | First appears | Target step | Ticket | Used by |
|---|---|---|---|---|---|---|
| 01 | IP addresses, ports, localhost and TCP | `01-ip-ports-tcp.md` | step 2 (Lab 01) | step 17 | AWSLAB-99 | `curl localhost:<port>`, published ports; refused vs timeout during failover (6) |
| 02 | DNS | `02-dns.md` | step 4 (Lab 02) | step 18 | AWSLAB-101 | Docker DNS `127.0.0.11`, `resolve` + `valid=5s` |
| 03 | HTTP requests, responses and status codes | `03-http.md` | step 2 (Lab 01) | step 19 | AWSLAB-103 | `curl` on `/health` and `/whoami`; 502/503 during failover |
| 04 | Proxies: forward vs reverse | `04-proxies.md` | step 4 (Lab 02) | step 20 | AWSLAB-105 | Nginx as a reverse proxy in front of the API |
| 05 | NAT and port forwarding | `05-nat-and-port-forwarding.md` | step 3 (Lab 01) | step 21 | AWSLAB-107 | `127.0.0.1:<port>:8000` mapping; private network without NAT (8) |
| 06 | Subnets and CIDR | `06-subnets-and-cidr.md` | step 8 (Lab 03) | step 8 | AWSLAB-80 | Network subnets in `docker network inspect` |
| 07 | Firewalls and security groups | `07-firewalls-and-security-groups.md` | step 8 (Lab 03) | step 9 | AWSLAB-82 | Public/private split and the isolation test (9) |
| 08 | HTTPS and TLS | `08-https-and-tls.md` | step 28 (Lab 08) | step 39 | - | mkcert certificate, port 443, redirect |

### Nginx - Web server, reverse proxy and load balancer. (8 modules)

| # | Module | File | First appears | Target step | Ticket | Used by |
|---|---|---|---|---|---|---|
| 01 | What a web server and a reverse proxy are | `01-web-server-and-reverse-proxy.md` | step 4 (Lab 02) | step 22 | - | `lb/nginx.conf` in front of the API |
| 02 | Config structure, `server` and `location` matching | `02-config-server-location.md` | step 4 (Lab 02) | step 23 | - | `events`, `http`, `server`, `upstream` blocks; routing `/health`, `/whoami`; host-based routing later (D4) |
| 03 | `proxy_pass` and proxy headers | `03-proxy-pass-and-headers.md` | step 4 (Lab 02) | step 24 | - | `proxy_pass http://api`, `Host`, `X-Forwarded-*` |
| 04 | Upstreams and load-balancing methods | `04-upstream-and-load-balancing.md` | step 5 (Lab 02) | step 25 | - | `upstream`, `zone`, `server ... resolve`, 3 replicas |
| 05 | Timeouts, retries and passive health checks | `05-timeouts-retries-failover.md` | step 6 (Lab 02) | step 26 | - | `max_fails`, `fail_timeout`, `proxy_next_upstream` |
| 06 | Static files and caching headers | `06-static-files-and-caching-headers.md` | step 26 (Lab 08) | step 39 | - | Frontend Nginx; `Cache-Control`, `ETag` (27) |
| 07 | HTTPS in Nginx | `07-https.md` | step 28 (Lab 08) | step 40 | - | `listen 443 ssl`, certificate, 80 to 443 redirect |
| 08 | Logs and debugging | `08-logs-and-debugging.md` | step 4 (Lab 02) | step 27 | - | `nginx -t`, `docker logs lb`, access/error log formats |

### FastAPI - How the Python API in this project works. (7 modules + 1 on request)

| # | Module | File | First appears | Target step | Ticket | Used by |
|---|---|---|---|---|---|---|
| 01 | How a Python web API works, and routes | `01-how-a-web-api-works.md` | step 2 (Lab 01) | step 28 | - | `api/` app, `GET /health`, `GET /whoami` |
| 02 | Uvicorn and ASGI | `02-uvicorn-and-asgi.md` | step 2 (Lab 01) | step 29 | - | Dockerfile `CMD uvicorn ...` |
| 03 | Path, query and body parameters | `03-parameters.md` | step 12 (Lab 04) | step 19 | AWSLAB-102 | `/notes/{id}`, `POST /notes` body |
| 04 | Pydantic models and validation | `04-pydantic.md` | step 12 (Lab 04) | step 20 | AWSLAB-104 | Note request/response schemas |
| 05 | Automatic OpenAPI docs | `05-openapi-docs.md` | step 2 (Lab 01) | step 30 | - | `/docs` and `/openapi.json` come for free |
| 06 | `async def` vs `def` | `06-async.md` | step 2 (Lab 01) | step 31 | - | Handlers in step 2; matters for DB, Redis, boto3 later |
| 07 | Dependencies and dependency injection | `07-dependencies.md` | step 11 (Lab 04) | step 16 | AWSLAB-96 | DB session per request |
| 08 | Testing with TestClient | `08-testing.md` | step 12 (Lab 04) | on request | - | The labs test with shell scripts; this adds pytest-style tests |

### Databases - Relational basics, SQL, PostgreSQL, migrations, ORMs. (9 modules)

| # | Module | File | First appears | Target step | Ticket | Used by |
|---|---|---|---|---|---|---|
| 01 | Relational databases: tables, rows, keys | `01-relational-basics.md` | step 10 (Lab 04) | step 13 | AWSLAB-90 | Postgres container, `\dt` |
| 02 | SQL basics | `02-sql.md` | step 10 (Lab 04) | step 14 | AWSLAB-92 | `psql` queries; CRUD in step 12 |
| 03 | PostgreSQL: server, roles, databases | `03-postgresql.md` | step 10 (Lab 04) | step 15 | AWSLAB-94 | `postgres` service, `pg_isready`, password from `.env` |
| 04 | Schemas, migrations and Alembic | `04-schemas-and-migrations.md` | step 11 (Lab 04) | step 17 | AWSLAB-98 | First migration creating `notes`; `migrate` one-shot service, `alembic_version` |
| 05 | ORMs and SQLAlchemy | `05-sqlalchemy.md` | step 11 (Lab 04) | step 18 | AWSLAB-100 | DB layer in the API |
| 06 | Indexes | `06-indexes.md` | step 12 (Lab 04) | step 21 | AWSLAB-106 | Primary-key lookups in `GET /notes/{id}` |
| 07 | Transactions | `07-transactions.md` | step 12 (Lab 04) | step 22 | AWSLAB-108 | Commit/rollback in create/update/delete |
| 08 | Connection pooling | `08-connection-pooling.md` | step 12 (Lab 04) | step 23 | - | 3 replicas x pool size vs Postgres `max_connections` |
| 09 | Backups: pg_dump and restore | `09-backups.md` | step 14 (Lab 04) | step 24 | - | Persistence test; RDS snapshots comparison |

### Caching - Why and how to cache, with Redis. (6 modules)

| # | Module | File | First appears | Target step | Ticket | Used by |
|---|---|---|---|---|---|---|
| 01 | Why cache | `01-why-cache.md` | step 15 (Lab 05) | step 26 | - | Redis container; the latency motivation |
| 02 | Redis basics and data types | `02-redis-data-types.md` | step 15 (Lab 05) | step 27 | - | `redis-cli ping`; strings now, lists/hashes in step 22 |
| 03 | Eviction and `maxmemory` | `03-eviction-and-maxmemory.md` | step 15 (Lab 05) | step 28 | - | `maxmemory` + `allkeys-lru` in the Redis config |
| 04 | Cache-aside and other patterns | `04-cache-aside-and-patterns.md` | step 16 (Lab 05) | step 29 | - | `GET /notes/{id}` read path |
| 05 | TTL, expiry and invalidation | `05-ttl-and-invalidation.md` | step 16 (Lab 05) | step 30 | - | TTL on cached notes; delete the key on PUT/DELETE |
| 06 | Common pitfalls (stampede, stale data, penetration) | `06-pitfalls.md` | step 17 (Lab 05) | step 31 | - | Cache test; what the simple pattern does not cover |

### Workers and queues - Async work, queues, delivery guarantees, retries. (7 modules)

| # | Module | File | First appears | Target step | Ticket | Used by |
|---|---|---|---|---|---|---|
| 01 | Synchronous vs asynchronous work, and queues | `01-sync-async-and-queues.md` | step 22 (Lab 07) | step 35 | - | `POST /jobs` returns an id immediately; API enqueues, worker consumes |
| 02 | Redis lists as a queue (`BLMOVE`) | `02-redis-lists-as-a-queue.md` | step 22 (Lab 07) | step 36 | - | Reliable-queue pattern, job hash |
| 03 | Delivery guarantees | `03-delivery-guarantees.md` | step 22 (Lab 07) | step 37 | - | At-most-once vs at-least-once; why `BLMOVE` |
| 04 | The worker loop and graceful shutdown | `04-worker-loop-and-graceful-shutdown.md` | step 23 (Lab 07) | step 37 | - | `worker/` main loop, SIGTERM handling |
| 05 | Idempotency | `05-idempotency.md` | step 23 (Lab 07) | step 38 | - | Safe re-processing of a job |
| 06 | Retries, backoff and dead-letter queues | `06-retries-backoff-and-dlq.md` | step 24 (Lab 07) | step 38 | - | Thumbnail job failing and being retried; SQS redrive policy (56) |
| 07 | Redis lists vs SQS | `07-redis-lists-vs-sqs.md` | step 57 (Lab 13) | step 49 | - | Queue abstraction with two backends (57-58) |

### Kubernetes - Pods to autoscaling, with kubectl. (10 modules)

| # | Module | File | First appears | Target step | Ticket | Used by |
|---|---|---|---|---|---|---|
| 01 | Why Kubernetes exists; cluster, node, pod, namespace | `01-why-kubernetes-cluster-node-pod.md` | step 40 (Lab 11) | step 41 | - | k3d cluster creation, `kubectl get nodes`, namespace `lab` (42) |
| 02 | `kubectl` and YAML manifests | `02-kubectl.md` | step 40 (Lab 11) | step 41 | - | Every later check uses it |
| 03 | Deployments, ReplicaSets and Jobs | `03-deployments-replicasets-jobs.md` | step 44 (Lab 11) | step 43 | - | Bootstrap Job (44), API Deployment (45) |
| 04 | Services | `04-services.md` | step 43 (Lab 11) | step 42 | - | Headless Service for Postgres (43), API Service (45) |
| 05 | ConfigMaps and Secrets | `05-configmaps-and-secrets.md` | step 42 (Lab 11) | step 42 | - | `kubectl get cm,secret -n lab` |
| 06 | Volumes, PVCs and StatefulSets | `06-storage-and-statefulsets.md` | step 43 (Lab 11) | step 43 | - | Postgres StatefulSet + PVC |
| 07 | Liveness and readiness probes | `07-probes.md` | step 45 (Lab 11) | step 44 | - | API Deployment probes |
| 08 | Ingress | `08-ingress.md` | step 47 (Lab 11) | step 44 | - | Traefik Ingress on `localhost:8080` |
| 09 | Resource requests and limits | `09-resources-requests-limits.md` | step 49 (Lab 12) | step 45 | - | Requests/limits + `kubectl top` |
| 10 | Autoscaling with the HPA | `10-hpa.md` | step 50 (Lab 12) | step 45 | - | HorizontalPodAutoscaler on the API |

### AWS - The real services behind each local component. (12 modules + 2 on request)

| # | Module | File | First appears | Target step | Ticket | Used by |
|---|---|---|---|---|---|---|
| 01 | Regions and Availability Zones | `01-regions-and-azs.md` | step 1 (Lab 00) | step 32 | - | Lab 00 theory: what AWS is, what a laptop cannot simulate |
| 02 | IAM: users, roles, policies, access keys | `02-iam.md` | step 18 (Lab 06) | step 32 | - | Fake access keys for the local S3 (SeaweedFS); presigned URLs (19-20) |
| 03 | Compute: EC2, ECS, Fargate and EKS | `03-compute.md` | step 2 (Lab 01) | step 33 | - | Lab 01: container vs VM, 'Going to real AWS'; EKS from step 40 |
| 04 | VPC: subnets, route tables, gateways | `04-vpc.md` | step 8 (Lab 03) | step 10 | AWSLAB-84 | Public/private Docker networks |
| 05 | ELB: ALB, target groups, health checks | `05-elb.md` | step 4 (Lab 02) | step 34 | - | Nginx stands in for the ALB |
| 06 | RDS: managed databases | `06-rds.md` | step 10 (Lab 04) | step 12 | AWSLAB-88 | Postgres container stands in for RDS |
| 07 | ElastiCache | `07-elasticache.md` | step 15 (Lab 05) | step 25 | - | Redis container stands in for ElastiCache |
| 08 | S3: buckets, objects, presigned URLs | `08-s3.md` | step 18 (Lab 06) | step 33 | - | SeaweedFS (local S3), `POST /upload` |
| 09 | CloudFront and CDNs | `09-cloudfront.md` | step 26 (Lab 08) | on request | - | Static frontend + caching headers (Lab 08) |
| 10 | SQS: standard and FIFO queues | `10-sqs.md` | step 22 (Lab 07) | step 34 | - | Redis queue now, SQS in steps 56-58 |
| 11 | DynamoDB | `11-dynamodb.md` | step 55 (Lab 13) | on request | - | Table created with Terraform |
| 12 | CloudWatch: metrics, logs, alarms | `12-cloudwatch.md` | step 29 (Lab 09) | step 40 | - | Prometheus / Grafana / Loki stand in for it |
| 13 | Pricing and cost control | `13-pricing.md` | step 2 (Lab 01) | step 35 | - | The 'Rough cost' line of every lab |
| 14 | Well-Architected Framework basics | `14-well-architected.md` | step 6 (Lab 02) | step 36 | - | Failover test = reliability pillar; Phase 1 wrap-up |

### Terraform - Infrastructure as Code with HCL. (6 modules + 1 on request)

| # | Module | File | First appears | Target step | Ticket | Used by |
|---|---|---|---|---|---|---|
| 01 | Infrastructure as Code | `01-iac-concepts.md` | step 52 (Lab 13) | step 52 | - | Emulator decision note |
| 02 | HCL, resources and data sources | `02-hcl-and-resources.md` | step 54 (Lab 13) | step 53 | - | `provider` and resource blocks; S3 bucket, DynamoDB table, SQS queue |
| 03 | Providers | `03-providers.md` | step 54 (Lab 13) | step 53 | - | AWS provider with local endpoints and fake keys |
| 04 | Variables, validation and outputs | `04-variables-and-outputs.md` | step 54 (Lab 13) | step 54 | - | Endpoint variable with a local-only validation |
| 05 | `init`, `plan`, `apply`, `destroy` | `05-plan-and-apply.md` | step 54 (Lab 13) | step 54 | - | `scripts/tf.sh`, plan/apply checks |
| 06 | State | `06-state.md` | step 55 (Lab 13) | step 55 | - | `terraform.tfstate` after the first apply |
| 07 | Modules | `07-modules.md` | step 59 (Lab 13) | on request | - | Not used in the labs, concept only |

## Schedule by lab step

What each stop adds. `lab` = slot 1 (current/next lab), `backlog` = slot 2 (labs 00-02, most basic first).

| After step | Slot 1 (lab) | Slot 2 (backlog) |
|---|---|---|
| 8 | Networking 06 - Subnets and CIDR | Docker 01 - Images, containers and their lifecycle |
| 9 | Networking 07 - Firewalls and security groups | Docker 02 - Docker Desktop on Windows (WSL2) |
| 10 | AWS 04 - VPC: subnets, route tables, gateways | Docker 03 - Dockerfile instructions |
| 11 | Docker 08 - Volumes and bind mounts | Docker 04 - Layers and the build cache |
| 12 | AWS 06 - RDS: managed databases | Docker 05 - Tags, digests and registries |
| 13 | Databases 01 - Relational databases: tables, rows, keys | Docker 06 - Environment variables, config and secrets |
| 14 | Databases 02 - SQL basics | Docker 07 - Docker networks and service-name DNS |
| 15 | Databases 03 - PostgreSQL: server, roles, databases | Docker 09 - Docker Compose |
| 16 | FastAPI 07 - Dependencies and dependency injection | Docker 10 - Debugging: logs, exec, inspect |
| 17 | Databases 04 - Schemas, migrations and Alembic | Networking 01 - IP addresses, ports, localhost and TCP |
| 18 | Databases 05 - ORMs and SQLAlchemy | Networking 02 - DNS |
| 19 | FastAPI 03 - Path, query and body parameters | Networking 03 - HTTP requests, responses and status codes |
| 20 | FastAPI 04 - Pydantic models and validation | Networking 04 - Proxies: forward vs reverse |
| 21 | Databases 06 - Indexes | Networking 05 - NAT and port forwarding |
| 22 | Databases 07 - Transactions | Nginx 01 - What a web server and a reverse proxy are |
| 23 | Databases 08 - Connection pooling | Nginx 02 - Config structure, `server` and `location` matching |
| 24 | Databases 09 - Backups: pg_dump and restore | Nginx 03 - `proxy_pass` and proxy headers |
| 25 | AWS 07 - ElastiCache | Nginx 04 - Upstreams and load-balancing methods |
| 26 | Caching 01 - Why cache | Nginx 05 - Timeouts, retries and passive health checks |
| 27 | Caching 02 - Redis basics and data types | Nginx 08 - Logs and debugging |
| 28 | Caching 03 - Eviction and `maxmemory` | FastAPI 01 - How a Python web API works, and routes |
| 29 | Caching 04 - Cache-aside and other patterns | FastAPI 02 - Uvicorn and ASGI |
| 30 | Caching 05 - TTL, expiry and invalidation | FastAPI 05 - Automatic OpenAPI docs |
| 31 | Caching 06 - Common pitfalls (stampede, stale data, penetration) | FastAPI 06 - `async def` vs `def` |
| 32 | AWS 02 - IAM: users, roles, policies, access keys | AWS 01 - Regions and Availability Zones |
| 33 | AWS 08 - S3: buckets, objects, presigned URLs | AWS 03 - Compute: EC2, ECS, Fargate and EKS |
| 34 | AWS 10 - SQS: standard and FIFO queues | AWS 05 - ELB: ALB, target groups, health checks |
| 35 | Workers and queues 01 - Synchronous vs asynchronous work, and queues | AWS 13 - Pricing and cost control |
| 36 | Workers and queues 02 - Redis lists as a queue (`BLMOVE`) | AWS 14 - Well-Architected Framework basics |
| 37 | Workers and queues 03 - Delivery guarantees; Workers and queues 04 - The worker loop and graceful shutdown | - |
| 38 | Workers and queues 05 - Idempotency; Workers and queues 06 - Retries, backoff and dead-letter queues | - |
| 39 | Networking 08 - HTTPS and TLS; Nginx 06 - Static files and caching headers | - |
| 40 | Nginx 07 - HTTPS in Nginx; AWS 12 - CloudWatch: metrics, logs, alarms | - |
| 41 | Kubernetes 01 - Why Kubernetes exists; cluster, node, pod, namespace; Kubernetes 02 - `kubectl` and YAML manifests | - |
| 42 | Kubernetes 04 - Services; Kubernetes 05 - ConfigMaps and Secrets | - |
| 43 | Kubernetes 03 - Deployments, ReplicaSets and Jobs; Kubernetes 06 - Volumes, PVCs and StatefulSets | - |
| 44 | Kubernetes 07 - Liveness and readiness probes; Kubernetes 08 - Ingress | - |
| 45 | Kubernetes 09 - Resource requests and limits; Kubernetes 10 - Autoscaling with the HPA | - |
| 46 | - | - |
| 47 | - | - |
| 48 | - | - |
| 49 | Workers and queues 07 - Redis lists vs SQS | - |
| 50 | - | - |
| 51 | - | - |
| 52 | Terraform 01 - Infrastructure as Code | - |
| 53 | Terraform 02 - HCL, resources and data sources; Terraform 03 - Providers | - |
| 54 | Terraform 04 - Variables, validation and outputs; Terraform 05 - `init`, `plan`, `apply`, `destroy` | - |
| 55 | Terraform 06 - State | - |
| 56 | - | - |
| 57 | - | - |
| 58 | - | - |
| 59 | - | - |

If a queue is empty, the other slot takes its place, so a few rows show two modules in the same column.

## Lab to course map (will go into `docs/courses/README.md` and the labs' "Go deeper" lists)

| Lab | Modules whose topic first appears there |
|---|---|
| 00 - Setup | AWS 01, Docker 02 |
| 01 - Containers | AWS 03, AWS 13, Docker 01, Docker 03, Docker 04, Docker 05, Docker 06, Docker 07, Docker 09, Docker 10, FastAPI 01, FastAPI 02, FastAPI 05, FastAPI 06, Networking 01, Networking 03, Networking 05 |
| 02 - Load balancing | AWS 05, AWS 14, Networking 02, Networking 04, Nginx 01, Nginx 02, Nginx 03, Nginx 04, Nginx 05, Nginx 08 |
| 03 - Networking | AWS 04, Networking 06, Networking 07 |
| 04 - Database | AWS 06, Databases 01, Databases 02, Databases 03, Databases 04, Databases 05, Databases 06, Databases 07, Databases 08, Databases 09, Docker 08, FastAPI 03, FastAPI 04, FastAPI 07, FastAPI 08 *(on request)* |
| 05 - Caching | AWS 07, Caching 01, Caching 02, Caching 03, Caching 04, Caching 05, Caching 06 |
| 06 - Object storage | AWS 02, AWS 08 |
| 07 - Queues and workers | AWS 10, Workers and queues 01, Workers and queues 02, Workers and queues 03, Workers and queues 04, Workers and queues 05, Workers and queues 06 |
| 08 - Frontend and CDN | AWS 09 *(on request)*, Networking 08, Nginx 06, Nginx 07 |
| 09 - Monitoring | AWS 12 |
| 10 - Testing and load | - |
| 11 - Kubernetes | Kubernetes 01, Kubernetes 02, Kubernetes 03, Kubernetes 04, Kubernetes 05, Kubernetes 06, Kubernetes 07, Kubernetes 08 |
| 12 - Autoscaling | Kubernetes 09, Kubernetes 10 |
| 13 - Terraform and emulator | AWS 11 *(on request)*, Terraform 01, Terraform 02, Terraform 03, Terraform 04, Terraform 05, Terraform 06, Terraform 07 *(on request)*, Workers and queues 07 |

## Suggested reading order (will go into `docs/courses/README.md`)

1. **Docker**, because every lab runs in containers.
2. **Networking**, because every later idea (load balancer, private network, DNS) builds on it.
3. **Nginx**, the load balancer and the frontend server.
4. **FastAPI**, the API you are load-balancing.
5. **Databases**, then **Caching**, then **Workers and queues**, in the order the labs add them.
6. **Kubernetes**, then **Terraform**, for Phases 2 and 3.
7. **AWS**: not a block to read in one go. Read each module next to the lab that stands in for that service (the AWS
   course README will list which); `Regions and AZs` and `Pricing` are good first reads.

## What was merged to get from 98 to 83

Docker: *Container lifecycle* into *Images and containers*. Networking: *TCP* into *IP and ports*. Nginx: *Config structure*
and *server/location* into one. FastAPI: *Routes* into *How a Python web API works*. Databases: *Alembic* into *Schemas and
migrations*. Caching: *TTL* and *Invalidation* into one. Workers: *Sync vs async* and *Queues* into one; *Retries* and
*Dead-letter queues* into one. Kubernetes: *Why*, *Cluster/node/pod* and *Namespace* into one. AWS: *EC2* and *ECS/EKS* into
*Compute*. Terraform: *HCL* and *Resources* into one. Each merged module may be up to 300 lines; if one needs more, it is split
back and the plan updated.

## What I am NOT touching

`PLAN.md`, `SPEC.md`, `docs/glossary.md`, hooks. Existing labs get nothing except the short `## Go deeper` list described above.
`CLAUDE.md`, `.claude/skills/next-step/SKILL.md` and `.claude/agents/step-reviewer.md` change only after you say yes to the diffs.

## Your decisions (all applied)

1. **Size and ordering:** option B (trim to ~80 -> 83), optional modules on request, slot 1 = current/next lab, slot 2 = backlog.
2. **Jira:** epic `AWSLAB-79` created; each module ticket created only when scheduled.
3. **Commit prefix:** `AWSLAB-NNN docs: course <tool> module NN - <title>`.
4. **Labs:** only a short "Go deeper" list at the end of each lab, added when a matching module is written.
5. **Reviewer:** `step-reviewer` also checks the course commit.

## Still to do (in order)

1. [x] Plan approved and committed (`AWSLAB-79 docs: courses plan`).
2. [x] Jira epic `AWSLAB-79` created.
3. [x] Workflow changes applied (`AWSLAB-79 docs: tool courses workflow`, commit `8d2e3da`).
4. [x] First two modules written at the stop of step 8 (see the progress log).
5. [x] Step 9 modules written (Networking 07 and Docker 02).
6. [x] Step 10 modules written (AWS 04 and Docker 03).
7. [x] Step 11 modules written (Docker 08 and Docker 04).
8. [x] Step 12 modules written (AWS 06 and Docker 05).
9. [x] Step 13 modules written (Databases 01 and Docker 06).
10. [x] Step 14 modules written (Databases 02 and Docker 07).
11. [x] Step 15 modules written (Databases 03 and Docker 09).
12. [x] Step 16 modules written (FastAPI 07 and Docker 10). The Docker course is now complete (10 of 10).
13. [x] Step 17 modules written (Databases 04 and Networking 01).
14. [x] Step 18 modules written (Databases 05 and Networking 02).
15. [x] Step 19 modules written (FastAPI 03 and Networking 03).
16. [x] Step 20 modules written (FastAPI 04 and Networking 04).
17. [x] Step 21 modules written (Databases 06 and Networking 05).
18. [ ] Next modules: see "Schedule by lab step" (step 22: Databases 07 and Nginx 01).

## Progress log
_(one line per module: module, ticket, commit hash, reviewer verdict)_

| Stop | Module | Ticket | Commit | Reviewer |
|---|---|---|---|---|
| step 8 | Docker 01 - Images, containers and their lifecycle | AWSLAB-81 | `a7e05cb` (+ fixes `fd0f70d`, `c5c8f2e`) | PASS WITH NOTES, notes fixed |
| step 8 | Networking 06 - Subnets and CIDR | AWSLAB-80 | `66ff45a` (+ fixes `0abb548`, `8cb0f1a`) | PASS WITH NOTES, notes fixed |
| step 9 | Networking 07 - Firewalls and security groups | AWSLAB-82 | `45a8506` (+ fix `1a47189`) | PASS WITH NOTES, notes fixed |
| step 9 | Docker 02 - Docker Desktop on Windows (WSL2) | AWSLAB-83 | `2a313d0` (+ fix `6118283`) | PASS WITH NOTES, notes fixed |
| step 10 | Docker 03 - Dockerfile instructions | AWSLAB-85 | `5042d55` | PASS WITH NOTES (index/plan updates landed in `df8fde2`) |
| step 10 | AWS 04 - VPC: subnets, route tables, gateways | AWSLAB-84 | `df8fde2` (message lacks ticket key) | PASS WITH NOTES |
| step 11 | Docker 08 - Volumes and bind mounts | AWSLAB-86 | `7e5e393` | PASS WITH NOTES, notes fixed |
| step 11 | Docker 04 - Layers and the build cache | AWSLAB-87 | `fbae44a` | PASS WITH NOTES, notes fixed |
| step 12 | Docker 05 - Tags, digests and registries | AWSLAB-89 | `bf8046c` | PASS WITH NOTES, notes fixed |
| step 12 | AWS 06 - RDS: managed databases | AWSLAB-88 | `79d1f80` (the module file itself landed in `bf8046c` by mistake: `git add docs/courses` picked it up) | PASS WITH NOTES, notes fixed |
| step 13 | Databases 01 - Relational databases: tables, rows, keys | AWSLAB-90 | `dfcd792` | PASS |
| step 13 | Docker 06 - Environment variables, config and secrets | AWSLAB-91 | `cbc61b1` | PASS WITH NOTES, notes fixed |
| step 14 | Databases 02 - SQL basics | AWSLAB-92 | `ee7873f` | PASS |
| step 14 | Docker 07 - Docker networks and service-name DNS | AWSLAB-93 | `fbe97a1` | PASS WITH NOTES, notes fixed |
| step 15 | Databases 03 - PostgreSQL: server, roles, databases | AWSLAB-94 | `4d6abfc` | PASS WITH NOTES, notes fixed |
| step 15 | Docker 09 - Docker Compose | AWSLAB-95 | `94328bb` | PASS WITH NOTES |
| step 16 | FastAPI 07 - Dependencies and dependency injection | AWSLAB-96 | `638f721` | PASS WITH NOTES |
| step 16 | Docker 10 - Debugging: logs, exec, inspect | AWSLAB-97 | `05437a4` | PASS WITH NOTES, notes fixed |
| step 17 | Databases 04 - Schemas, migrations and Alembic | AWSLAB-98 | `c597ab8` (its README and plan edits landed in `5b18a58`) | PASS WITH NOTES, notes fixed |
| step 17 | Networking 01 - IP addresses, ports, localhost and TCP | AWSLAB-99 | `5b18a58` | PASS WITH NOTES, notes fixed |
| step 18 | Databases 05 - ORMs and SQLAlchemy | AWSLAB-100 | `933c52b` (its README and plan edits landed in `f370dfc`) | PASS WITH NOTES, notes fixed |
| step 18 | Networking 02 - DNS | AWSLAB-101 | `f370dfc` | PASS |
| step 19 | FastAPI 03 - Path, query and body parameters | AWSLAB-102 | `806f732` (its README and plan edits landed in `2a861c8`) | PASS WITH NOTES, notes fixed |
| step 19 | Networking 03 - HTTP requests, responses and status codes | AWSLAB-103 | `2a861c8` | PASS WITH NOTES, notes fixed |
| step 20 | FastAPI 04 - Pydantic models and validation | AWSLAB-104 | `bd8715c` (+ fix `2b27971`) | PASS WITH NOTES, notes fixed (broken link; 321 lines, accepted) |
| step 20 | Networking 04 - Proxies: forward vs reverse | AWSLAB-105 | `9b315e1` | PASS |
| step 21 | Databases 06 - Indexes | AWSLAB-106 | `9823660` (+ fix `737cb5f`) | PASS WITH NOTES, notes fixed |
| step 21 | Networking 05 - NAT and port forwarding | AWSLAB-107 | `beb84dd` (+ fix `a520736`) | PASS WITH NOTES, notes fixed |
