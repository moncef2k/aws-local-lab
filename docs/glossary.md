# Glossary

Every AWS / infrastructure term used in the course, in plain words. Each lab adds the terms it
introduces. "Local" is what we use in this project instead of the AWS service.

| Term | What it means | AWS service / local stand-in | Lab |
|---|---|---|---|
| **Active vs passive health check** | Active: the load balancer calls a health URL on a timer and removes failing servers before users notice (AWS ALB). Passive: it only notices a server is dead when a real request fails (open-source Nginx). | AWS: target group health check · Local: Nginx `max_fails` / `fail_timeout` | 02 |
| **ALB** (Application Load Balancer) | Receives web traffic and spreads it over several copies of an app; stops sending traffic to broken ones. | AWS: ALB · Local: Nginx | 02 |
| **Alembic** | The migration tool of the SQLAlchemy family: applies numbered migration scripts to a database and remembers which ones were applied (in the `alembic_version` table). | Local tool (AWS has no equivalent: you run it as a task or CI step) | 04 |
| **Asynchronous job** | Work the API accepts now and does later: it answers `202 Accepted` with a job id, a worker does the work, and the client polls `GET /jobs/{id}` for the status. | AWS: SQS + a worker (ECS/Lambda) + DynamoDB for the status · Local: Redis list + hash, `worker` (step 23) | 07 |
| **At-least-once delivery** | The queue promises every message is processed at least once, possibly twice (if a worker crashes before it confirms). So the work must be idempotent. | AWS: SQS standard queue · Local: reliable-queue pattern (step 23) | 07 |
| **Auto Scaling** | Adding or removing copies of an app automatically, based on load. | AWS: Auto Scaling groups · Local: Kubernetes HPA | 12 |
| **Availability Zone (AZ)** | A separate data centre inside an AWS region. Spreading over several AZs survives the loss of one. | AWS only — cannot be simulated on one laptop | 03 |
| **Bastion host** | A small, hardened server you go through to reach machines that are not exposed to the internet (such as a database in a private subnet). AWS offers Systems Manager Session Manager as a bastion without open ports. | AWS: bastion EC2 / SSM Session Manager · Local: the `db-proxy` service | 04 |
| **Bridge network** | A virtual network created by Docker; containers on it can reach each other by name. | Local: Docker network | 03 |
| **Bucket** | A named container for files (objects) in object storage. | AWS: S3 bucket · Local: SeaweedFS bucket | 06 |
| **Cache hit / miss** | A **hit** means the answer was found in the cache; a **miss** means it was not, so the program asks the original source (the database) and usually stores the answer. | Local: Redis cache (Lab 05) | 05 |
| **Cache invalidation** | Removing or refreshing a cached copy because the original changed. In cache-aside the application deletes the cached copy right after it writes to the database. | Local: `forget()` in `api/main.py` | 05 |
| **Cache-aside** | Read pattern: look in the cache first; on a miss, read the database and store the result in the cache. | AWS: ElastiCache · Local: Redis | 05 |
| **CDN** (Content Delivery Network) | Servers around the world that keep copies of your static files close to users. | AWS: CloudFront · Local: Nginx with caching headers (only the headers, no real CDN) | 08 |
| **CIDR** | A way to write an address range: `172.23.0.0/16` means "addresses starting with `172.23`"; the number after `/` says how many of the 32 bits are fixed (bigger number = smaller range). | AWS: VPC and subnet ranges · Local: Docker network subnets | 03 |
| **CloudWatch** | AWS monitoring: metrics, logs, dashboards, alarms. | Local: Prometheus + Grafana + Loki | 09 |
| **Compose profile** | A label on a Compose service (`profiles: ["admin"]`) that keeps it switched off unless you ask for it with `--profile admin`. | Local: used for the optional `db-proxy` | 04 |
| **Connection pool** | A set of already-open database connections that the app reuses, because opening a connection is slow. SQLAlchemy's engine owns one. | Local: SQLAlchemy engine (AWS: RDS Proxy pools connections for many apps) | 04 |
| **Container** | A running, isolated process with its own filesystem, started from an image. Lighter than a virtual machine. | AWS: ECS / EKS tasks · Local: Docker | 01 |
| **CRUD** | Create, Read, Update, Delete: the four basic things you can do with stored records. In an HTTP API they map to `POST`, `GET`, `PUT`, `DELETE`. | Local: the `/notes` routes of the API | 04 |
| **Dead-letter queue (DLQ)** | A second queue that receives the messages that failed too many times, so one bad message does not loop forever and can be inspected. | AWS: SQS DLQ + `maxReceiveCount` · Local: not simulated | 07 |
| **Defence in depth** | Several layers of protection, so that getting through one (say, a bug in the API) does not give access to everything (say, the database). | AWS: public/private subnets + security groups · Local: `public` and `private` networks | 03 |
| **Docker Compose** | A tool that starts several containers from one YAML file. | Local only (like a mini CloudFormation for containers) | 00 |
| **Dockerfile** | The recipe to build an image. | AWS: same, then pushed to ECR | 01 |
| **Environment variable** | A named setting handed to a program from outside (`UVICORN_LOG_LEVEL=warning`), so the same image can behave differently per environment. | AWS: task definition `environment`, Parameter Store | 01 |
| **`.env` file** | A local file of settings and secrets, read by Docker Compose. Never committed to Git; `.env.example` is the committed template. | Local only (AWS: Secrets Manager / Parameter Store) | 00 |
| **ECR** (Elastic Container Registry) | AWS's private store for container images. | Local: the Docker image store | 01 |
| **EC2** | Virtual machines in AWS. | Local: a container is a lighter equivalent | 01 |
| **EKS** | Managed Kubernetes in AWS. | Local: k3d | 11 |
| **ElastiCache** | Managed Redis/Memcached in AWS. | Local: Redis | 05 |
| **Eviction (LRU)** | What a full cache does to make room: it deletes entries. **LRU** (least recently used) deletes the ones unused the longest. | AWS: ElastiCache parameter `maxmemory-policy` · Local: `--maxmemory-policy allkeys-lru` | 05 |
| **Failover** | Continuing to serve requests, on the remaining copies, when one copy fails. | AWS: ALB + several targets · Local: Nginx `proxy_next_upstream` | 02 |
| **FastAPI / Uvicorn** | A Python web framework / the server that runs it. | AWS: your app code running on ECS/EKS/EC2 | 01 |
| **Graceful degradation** | Designing a system so that when an optional part fails it gets slower or simpler instead of failing completely. Here: with Redis down the API answers from the database and marks the reply `X-Cache: BYPASS`. | Local: `read_note` in `api/main.py` | 05 |
| **Health check** | A regular request ("are you OK?") that tells a load balancer or orchestrator whether a copy of an app is healthy. | AWS: target group health check · Local: Nginx + Docker `healthcheck` | 02 |
| **HPA** (Horizontal Pod Autoscaler) | Kubernetes object that changes the number of pod copies based on CPU or other metrics. | AWS: Auto Scaling | 12 |
| **Host header** | The HTTP header that carries the name the client typed in the URL (`Host: s3.localhost:8088`). A server or proxy with several sites uses it to choose one, and a presigned URL's signature covers it. | Local: Nginx `server_name`, `proxy_set_header Host $http_host` | 06 |
| **`.gitkeep`** | An empty file whose only purpose is to make Git keep an otherwise empty folder. | Git convention | 00 |
| **IAM** | AWS users, roles and permissions. | Not simulated in this lab (fake credentials only) | 13 |
| **IaC** (Infrastructure as Code) | Describing infrastructure in files that a tool applies, instead of clicking in a console. | AWS: CloudFormation · Local: Terraform | 13 |
| **Idempotent** | An operation you can run several times with the same result as running it once. Migrations are idempotent: the second `alembic upgrade head` finds the database already up to date and does nothing. | Local: Alembic, `docker compose up -d` | 04 |
| **Image** | A read-only package (app + dependencies) from which containers start. | AWS: ECR stores them · Local: built by Docker | 01 |
| **Internal network** | A Docker network with no gateway: containers on it can talk to each other and to nothing outside. | AWS: private subnet without a NAT Gateway · Local: `internal: true` | 03 |
| **Internet Gateway / NAT Gateway** | Internet Gateway: the door between a VPC and the internet, in both directions (public subnets). NAT Gateway: lets machines in private subnets start connections *out*, without letting the internet start connections *in*. | AWS only (the closest local thing is a network with a gateway) | 03 |
| **Layer (image)** | One Dockerfile instruction, stored as a cached piece of the image. Put rarely-changing steps first so rebuilds are fast. | Docker concept | 01 |
| **k3d** | Runs a small Kubernetes cluster (k3s) inside Docker containers. | Local stand-in for EKS | 11 |
| **k6** | A load-testing tool: simulates many users and reports latency and errors. | Local tool | 10 |
| **Listener** | The part of a load balancer that accepts connections on a port (for example HTTP on 80) and applies rules to them. | AWS: ALB listener · Local: `listen 80;` in Nginx | 02 |
| **Load balancer** | See ALB. | | 02 |
| **Make / Makefile** | A tool that runs named recipes (`make up`) defined in a `Makefile`. Used here as a shortcut for long Docker commands. | Local tool | 00 |
| **Mermaid** | Text syntax for diagrams, rendered by GitHub and many editors. Used for all diagrams here. | Documentation tool | 00 |
| **Migration** | A small numbered script that changes the structure of a database (create a table, add a column). Applied in order, once each, so every copy of the database ends up the same. | Local: Alembic · AWS: run as a task or pipeline step before deployment | 04 |
| **Name-based routing** | One address and port serving several sites: the proxy reads the `Host` header and picks the matching `server` block. The unmatched requests go to the `default_server`. | AWS: ALB listener rules on the host header · Local: Nginx `server_name` + `default_server` | 06 |
| **Nginx** | A web server and reverse proxy. Used as load balancer and as static file server. | Local stand-in for ALB / CloudFront origin | 02 |
| **Non-root user** | Running the app as an unprivileged user inside the container, so a compromised app has little power. | AWS: same advice for ECS/EKS tasks | 01 |
| **One-shot job** | A container that does one task and exits (code 0 = success) instead of running forever, like the `migrate` service. | AWS: ECS run-task, Kubernetes Job, CI step · Local: Compose service with `restart: "no"` | 04 |
| **ORM** (object-relational mapper) | A library that maps tables to classes and rows to objects, and writes the SQL for you. | Local: SQLAlchemy | 04 |
| **Pinning** | Fixing an exact version (`python:3.12.16-slim-trixie`, `fastapi==0.163.0`) instead of "latest", so a rebuild gives the same result. | Good practice everywhere | 01 |
| **Playwright** | A tool that drives a real browser from a script. Used here to take screenshots. | Documentation tool | 00 |
| **Port mapping** | Publishing a container port on the host: `127.0.0.1:8000:8000` = host address : host port : container port. | AWS: security group + load balancer listener | 01 |
| **Presigned URL** | A temporary link that gives access to one private object, without credentials. The link carries a signature computed from the secret key, the object, the expiry **and the host name**: change any of them and the signature no longer matches (`SignatureDoesNotMatch`). | AWS: S3 presigned URL · Local: SeaweedFS, signed for `s3.localhost` | 06 |
| **Private subnet** | A network area with no direct access from the internet; databases and app servers live here. | AWS: VPC private subnet · Local: Docker network marked `internal` | 03 |
| **Producer / consumer** | The producer puts messages on a queue (here the API); the consumer, also called a worker, takes them off and does the work. | AWS: an app calling `SendMessage` / a worker calling `ReceiveMessage` · Local: `api` / `worker` | 07 |
| **Prometheus / Grafana / Loki** | Metrics database / dashboards / log database. | Local stand-ins for CloudWatch | 09 |
| **Public subnet** | A network area reachable from the internet; only the load balancer lives here. | AWS: VPC public subnet · Local: Docker network `public` | 03 |
| **Pydantic** | A Python library that checks the shape of data (types, lengths) and converts it; FastAPI uses it to validate requests (`422` when wrong) and shape answers. | Local library (no AWS equivalent) | 04 |
| **RDS** | Managed relational databases (here: PostgreSQL) in AWS. | Local: Postgres container | 04 |
| **Redis** | An in-memory key-value store, used for caching and simple queues. | AWS: ElastiCache | 05 |
| **Replica** | One of several identical copies of the same app. | AWS: several tasks/instances · Local: `docker compose` replicas | 02 |
| **Queue (message queue)** | An ordered line of messages: first in, first out. It separates asking for work from doing it, absorbs spikes and lets producer and consumer fail and scale independently. | AWS: SQS · Local: a Redis list (`queue:jobs`) | 07 |
| **Reverse proxy** | A server that receives requests on behalf of other servers and forwards them. A load balancer is a reverse proxy that picks one of several servers. | AWS: ALB · Local: Nginx | 02 |
| **Round-robin** | Handing requests to the servers one after the other, in turn. The default way Nginx and an ALB spread load. | AWS: ALB default · Local: Nginx default | 02 |
| **S3** | AWS object storage (files in buckets). | Local: SeaweedFS | 06 |
| **S3 endpoint** | The address of the S3 API. SDKs and the AWS CLI use `amazonaws.com` by default; `--endpoint-url` points them at another server. | Local: `http://s3:8333` inside Docker, `http://s3.localhost` from your machine | 06 |
| **SeaweedFS** | An open-source storage system with an S3-compatible API; the lab uses it as the local S3 because MinIO no longer publishes container images. | Local stand-in for S3 | 06 |
| **Security group** | A firewall around a resource: who may connect to which port. | Local: Docker network membership | 03 |
| **Service discovery (DNS)** | Finding the servers behind a name. On a Docker network, the name of a service resolves to the addresses of its containers, and Docker's DNS (`127.0.0.11`) answers. | AWS: ECS/EKS registering targets · Local: Docker DNS + nginx `resolve` | 02 |
| **Session (database)** | A short conversation with the database inside which changes are staged and then saved with `commit` (or dropped). The API opens one per request and closes it at the end. | Local: SQLAlchemy `Session` | 04 |
| **SQLAlchemy** | The Python library used for the database layer: engine (connection pool), ORM models, sessions. | Local library (works the same against RDS) | 04 |
| **SQS** | AWS message queue: a producer puts jobs in, workers take them out. | Local: a Redis list (Phase 1), then SQS on an emulator (Phase 3) | 07 |
| **Stale** | Out of date: a cached copy that no longer matches the original. A TTL limits how long data can stay stale. | Local: Redis cache with a 60 s TTL | 05 |
| **Subnet** | A slice of a bigger network range. Machines in the same subnet reach each other directly; what leaves it goes through a gateway. | AWS: VPC subnet (lives in one AZ) · Local: Docker network | 03 |
| **Target group** | The list of servers a load balancer can send traffic to, with their health checks. | AWS: ALB target group · Local: Nginx `upstream` block | 02 |
| **Terraform** | A tool that creates infrastructure from `.tf` files. | Local tool, pointed at an emulator | 13 |
| **Test (shell test)** | A script that checks one behaviour of the running lab and exits 0 (pass) or non-zero (fail). `make test` runs them all. | AWS: (none) · Local: `tests/NN_*.sh` | 02 |
| **tmpfs** | A folder kept in memory instead of on disk; its content disappears when the container stops. Used on Redis's `/data` so Docker does not create a hidden volume. | Local: Compose `tmpfs:` | 05 |
| **TTL** (time to live) | How long a cached value stays valid before it expires by itself. | AWS/Redis: key expiry (`EX`, `TTL`) · Local: Redis | 05 |
| **VPC** (Virtual Private Cloud) | Your own isolated network in AWS, divided into subnets. | Local: Docker networks | 03 |
| **Visibility timeout** | After a consumer receives an SQS message, the message is only hidden for a while; if it is not deleted in time (the consumer crashed) it becomes visible again for another consumer. | AWS: SQS · Local: the `BLMOVE` to a "processing" list (step 23) | 07 |
| **Volume** | Storage that outlives a container, so data survives a restart. | AWS: EBS · Local: Docker named volume | 04 |
