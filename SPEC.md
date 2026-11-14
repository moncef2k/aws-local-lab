# SPEC.md — AWS hosting architecture, locally

Goal: learn AWS web hosting architecture by building a local copy of it on my laptop,
with sample apps that prove each piece works.

Work rules (small steps, one commit, stop and wait) are in `CLAUDE.md`.

If I have less than 16 GB of RAM, keep Phase 2 small (1 server + 1 agent node) and say so.

---

## Phase 1 — Core architecture with Docker Compose

Set up local stand-ins for these AWS services, on separate Docker networks that mimic a VPC:

- **`public` network:** only the load balancer (Nginx or Traefik), standing in for **ALB**.
  It is the only thing exposed to my machine, on port 80. Add a local HTTPS cert with
  mkcert if available.
- **`private` network:** the app containers, **PostgreSQL** (RDS), **Redis** (ElastiCache)
  and **MinIO** (S3). The database must NOT be reachable from my host, except through an
  optional admin profile.
- **Monitoring** (CloudWatch): Prometheus + Grafana + Loki, with a pre-built Grafana
  dashboard showing request rate, latency, errors, and CPU/RAM per container.

### Sample apps to deploy

1. **Static frontend** — plain HTML/JS, served by Nginx with caching headers
   (like S3 + CloudFront). It shows which app instance answered each request, so I can
   see load balancing happen.

2. **REST API** — Python FastAPI or Node Express (your choice; explain why).
   Run 3 replicas behind the load balancer. Endpoints:
   - `GET /health` — used by load balancer health checks
   - `GET /whoami` — returns the container hostname
   - CRUD on `/notes`, stored in Postgres, with migrations
   - `GET /notes/{id}` cached in Redis (cache-aside pattern)
   - `POST /upload` — stores a file in MinIO via the S3 SDK (boto3 / AWS SDK) and returns
     a presigned URL
   - `POST /jobs` — puts a job on a Redis queue
   - `/metrics` — for Prometheus

3. **Background worker** (like SQS + Lambda/ECS worker) — processes jobs from the queue,
   e.g. makes a thumbnail of an uploaded image, and saves the result to MinIO.

Apps must be stateless: no local files, all config from env vars.

### Tests that prove the architecture works

A `tests/` folder and a `make test` target that checks:

- **Load balancing:** 30 calls to `/whoami` reach all 3 replicas
- **Health checks:** when one API replica is killed (`docker kill`), traffic keeps flowing
  without errors, and it comes back when restarted
- **Persistence:** data survives `docker compose down && up` (named volumes)
- **Caching:** the second read of a note is served from Redis (prove it via a log or header)
- **Storage:** an uploaded file can be downloaded with its presigned URL
- **Async:** a submitted job is processed by the worker
- **Network isolation:** Postgres is NOT reachable from the host on port 5432
- **Load test (k6):** 50 virtual users for 1 minute; report p95 latency and error rate,
  and show it in Grafana

---

## Phase 2 — Kubernetes (like EKS + Auto Scaling)

Deploy the same apps on a local k3d cluster with:
- Deployments, Services, an Ingress, ConfigMaps/Secrets
- liveness and readiness probes
- a HorizontalPodAutoscaler on the API

Show the HPA scaling up during a k6 load test and back down afterwards.

---

## Phase 3 — Real AWS tooling against a local emulator

Use Terraform with the AWS provider pointed at a local AWS API emulator
(look up AWS's official "AWS Emulator" released Nov 2026, or Floci as a fallback;
check their current docs before writing config).

- Create an S3 bucket, a DynamoDB table and an SQS queue.
- Change the worker so it can use SQS instead of Redis, via an env var flag.
- Use fake credentials only, and add a guard so Terraform cannot accidentally point at a
  real AWS account.

---

## Deliverables

- `Makefile` with `up`, `down`, `test`, `load-test`, `logs`, `clean`
- `README.md` with:
  - an architecture diagram (Mermaid)
  - a table mapping each local component to its AWS equivalent
  - what this setup can't simulate (multi-AZ, a real CDN, IAM, etc.)
- `docs/LEARNING.md` — for each phase, what concept it teaches and what I'd change to
  deploy it on real AWS
