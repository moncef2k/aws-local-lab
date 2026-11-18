# PLAN.md — AWS local lab

Status: **APPROVED 2026-11-14** (decisions D1–D4 confirmed, see below).

Source of truth for *what* to build: `SPEC.md`. Rules for *how* to work: `CLAUDE.md`.

## How to read this plan
- Every step = **one code commit** (1–3 files, < ~150 lines) **+ one docs commit** (`docs: lab NN step N - <title>`),
  then a `step-reviewer` pass, then I stop and wait for "next".
- Each step lists the **check** that proves it works (run before ticking the box).
- Lab numbers match `docs/labs/` in `SPEC.md`. A lab's theory (sections 1–3 of the template) is written
  in the docs commit of its first step; its closing sections (verify, real-AWS mapping, clean-up, quiz,
  glossary, index) in the docs commit of its last step.
- Each lab ends with a step that adds its own `tests/NN_*.sh`; `make test` just runs them all.
- Steps may be split further if they turn out bigger than expected (rule from CLAUDE.md).
- **Jira** (project `AWSLAB`, kanban): each lab heading shows its epic key, each step shows its ticket key
  (step N = `AWSLAB-(18+N)` for the original 60 steps). Jira shows *status*; this file stays the source of truth
  for *content*. Workflow and rules: `CLAUDE.md` → "Jira".
- **One PR per lab (🔀).** At the last step of each lab (marked 🔀), after the review, I push `dev` and give you the
  compare link `https://github.com/moncef2k/aws-local-lab/compare/main...dev`. You merge it; tell me when
  done and I check that `dev` is in sync with `main` before starting the next lab (I'll ask before any
  merge/pull that touches your branch).

## Environment check (done 2026-11-14, read-only)
| Item | Result |
|---|---|
| OS / CPU | Windows 11 Pro 10.0.26200 · Ryzen 9 8945HS (8 cores / 16 threads) |
| RAM / free disk | 31.3 GB / 95.8 GB on C: → **enough for the full Phase 2** (1 server + 2 agents) |
| Docker / Compose | 29.2.1 / v5.0.2 ✅ |
| kubectl, git, python, node | installed ✅ (kubectl comes with Docker Desktop) |
| **make** | ✅ installed by you afterwards (`winget install --id ezwinports.make -e`) — to re-check at step 1 |
| **k3d** | ❌ missing — needed in Phase 2 (installed at step 40, with your OK) |
| **terraform** | ❌ missing — needed in Phase 3 (installed at step 53, with your OK) |
| **mkcert** | ❌ missing — optional, for local HTTPS (step 28, with your OK) |

Nothing will be installed system-wide without asking you first.

## Decisions (all confirmed by you on 2026-11-14)
- **D1 – `make` on Windows:** GNU Make, installed by you with `winget install --id ezwinports.make -e`.
  The Makefile sets `SHELL` to Git Bash explicitly (step 1).
- **D2 – API language:** **Python FastAPI** — same language as the worker (boto3, Pillow for
  thumbnails), `prometheus-client` and Alembic are mature, and OpenAPI docs come free.
- **D3 – Load balancer:** **Nginx** (same tool as the frontend, fewer moving parts). Caveat explained in
  Lab 02: open-source Nginx only does *passive* health checks, while ALB does *active* ones. We use an Nginx
  version whose `upstream` supports `server ... resolve` plus `resolver 127.0.0.11 valid=5s`, so replicas that
  restart (new IP) rejoin automatically.
- **D4 – Reaching Grafana / MinIO console / Prometheus:** host-based routing through the load balancer
  (`grafana.localhost`, `s3.localhost`, `console.localhost`) instead of extra published ports. Presigned URLs
  also need `s3.localhost` to be valid from your browser.

## Known constraints from the hooks
- `docker compose down -v` and `docker volume rm/prune` are blocked, so **`make clean` is something you run
  yourself**; I will test the persistence step with plain `down && up`.
- `aws`/`terraform apply` are only allowed against a local endpoint (Phase 3 guard works with that).

---

## Phase 1 — Core architecture with Docker Compose

### Lab 00 — Setup (tools, Docker basics, how the course works) · epic `AWSLAB-4`
- [x] **0. Course scaffolding.** `AWSLAB-18` Code commit: `scripts/screenshot.sh <url> <out.png>` (Playwright in a pinned
  Docker image, ~1280px PNG, output under `docs/labs/images/lab-NN/`). For any `*.localhost` host in the URL it
  passes `--add-host <name>:host-gateway` to `docker run`, so the container can capture pages served by the
  load balancer on the host. Docs commit: `docs/labs/README.md`
  (index, learning path, prerequisites, progress table) and `docs/glossary.md` (initial terms).
  *Check:* run the script against a throw-away local page (also one reached via a `*.localhost` name) → PNG
  exists, is ~1280px wide, no secrets visible.
- [x] **1. Repo skeleton.** `AWSLAB-19` 🔀 `Makefile` with `SHELL` set to Git Bash (explicit Windows path, so recipes behave
  the same under cmd/PowerShell/Git Bash; `up down logs clean` real; `test load-test` stubs), `.env.example`,
  folder layout (`api/ worker/ frontend/ lb/ monitoring/ tests/ k8s/ terraform/`) with `.gitkeep`s.
  *Check:* `make --version`, `make help` / `make up` on an empty compose file run without error.
  Docs: write `00-setup.md` (tools, versions, Docker basics, repo layout, **how to run make** from PowerShell
  and Git Bash, the winget install line). Then push `dev` + PR link (end of Lab 00).

### Lab 01 — Containers & the first API · epic `AWSLAB-5`
- [x] **2. Minimal API.** `AWSLAB-20` FastAPI app with `GET /health` and `GET /whoami` (hostname), pinned deps,
  `Dockerfile` (pinned `python:3.12-slim-…`, non-root user). *Check:* `docker build` + `docker run` + curl both routes.
- [x] **3. Compose service for the API.** `AWSLAB-21` 🔀 `docker-compose.yml` with `api` (config from env vars, temporary
  `127.0.0.1` port mapping). *Check:* `docker compose ps` healthy, curl `/whoami`. Push `dev` + PR link.

### Lab 02 — Load balancing (ALB) · epic `AWSLAB-6`
- [x] **4. Nginx load balancer.** `AWSLAB-22` `lb/nginx.conf` + `lb` service on port 80; API port mapping removed.
  Pin an Nginx version whose `upstream` supports `server <name> resolve` (open-source Nginx ≥ 1.27.3 — I'll
  confirm in the release notes before pinning), with `resolver 127.0.0.11 valid=5s;` and an upstream `zone`.
  *Check:* `nginx -t`; `curl localhost/health` works, `localhost:<api port>` no longer does.
- [x] **5. Three API replicas.** `AWSLAB-23` `deploy.replicas: 3`; the upstream `resolve` re-reads Docker DNS so all 3 IPs
  are used. *Check:* 30 curls to `/whoami` show 3 distinct hostnames.
- [x] **6. Health checks & failover.** `AWSLAB-24` Container `healthcheck`, Nginx `max_fails` / `fail_timeout` /
  `proxy_next_upstream`. Lab 02 explains why `resolve` + `valid=5s` matters: a restarted replica gets a new IP
  and rejoins within ~5 s without reloading Nginx (plain `proxy_pass` would keep the stale IP forever).
  *Check:* `docker kill` one replica while curling in a loop → 0 failed requests; restart → it rejoins.
- [x] **7. Tests for Lab 02.** `AWSLAB-25` 🔀 `tests/02_load_balancing.sh` and `tests/02_failover.sh` (includes the rejoin
  after restart); wire `make test`. *Check:* `make test` green. Push `dev` + PR link.

### Lab 03 — Networking (VPC, subnets, security groups) · epic `AWSLAB-7`
- [x] **8. Public / private networks.** `AWSLAB-26` `public` network (LB only, publishes 80) and `private`
  (`internal: true`, apps only); LB attached to both. *Check:* `docker network inspect`, app still reachable via LB,
  containers on `private` cannot reach the internet (like a private subnet without NAT).
- [x] **9. Isolation test.** `AWSLAB-27` 🔀 `tests/03_network_isolation.sh`: API containers not reachable from the host;
  only port 80 published. *Check:* `make test` green.

### Lab 04 — Database (RDS) · epic `AWSLAB-8`
- [x] **10. Postgres container.** `AWSLAB-28` `postgres:<pinned>` on `private`, named volume, password from `.env`,
  healthcheck, no host port. *Check:* `pg_isready` via `docker compose exec`.
- [x] **11. DB layer + migrations.** `AWSLAB-29` SQLAlchemy + Alembic, first migration (`notes` table), one-shot `migrate`
  service the API waits for. *Check:* table exists (`\dt`), `alembic_version` set.
- [x] **12. Notes CRUD.** `AWSLAB-30` `POST/GET/PUT/DELETE /notes`. *Check:* curl the full create→read→update→delete cycle through the LB.
- [ ] **13. Admin profile.** `AWSLAB-31` `--profile admin` publishes Postgres on `127.0.0.1:5432` (via a small proxy), off by default.
  *Check:* without the profile `5432` is closed; with it `psql` connects.
- [ ] **14. DB tests.** `AWSLAB-32` 🔀 `tests/04_persistence.sh` (`down && up` keeps data) and Postgres-not-reachable check
  added to the isolation test. *Check:* `make test` green.

### Lab 05 — Caching (ElastiCache) · epic `AWSLAB-9`
- [ ] **15. Redis container.** `AWSLAB-33` Pinned image, `private`, password, `maxmemory` + `allkeys-lru`. *Check:* `redis-cli ping` from inside.
- [ ] **16. Cache-aside on `GET /notes/{id}`.** `AWSLAB-34` TTL, invalidation on PUT/DELETE, `X-Cache: HIT|MISS` header + log line.
  *Check:* first read MISS, second HIT, after update MISS again.
- [ ] **17. Cache test.** `AWSLAB-35` 🔀 `tests/05_cache.sh`. *Check:* `make test` green.

### Lab 06 — Object storage (S3) · epic `AWSLAB-10`
- [ ] **18. MinIO + bucket bootstrap.** `AWSLAB-36` `private` network, volume, one-shot `mc` job creating the bucket, fake creds in `.env`. *Check:* bucket listed via `mc`.
- [ ] **19. `POST /upload` + presigned URL.** `AWSLAB-37` boto3 against MinIO, endpoint and bucket from env vars. *Check:* upload returns key + URL.
- [ ] **20. Public S3 endpoint via the LB.** `AWSLAB-38` `s3.localhost` route → MinIO so presigned URLs work from the host (signed with the public endpoint). *Check:* `curl` the presigned URL from the host, bytes match.
- [ ] **21. Storage test.** `AWSLAB-39` 🔀 `tests/06_storage.sh` upload → download → compare checksum. *Check:* `make test` green.

### Lab 07 — Queues & workers (SQS) · epic `AWSLAB-11`
- [ ] **22. `POST /jobs` + `GET /jobs/{id}`.** `AWSLAB-40` Enqueue to a Redis list (reliable `BLMOVE` pattern), job status in a Redis hash. *Check:* job id returned, status `queued`.
- [ ] **23. Worker container.** `AWSLAB-41` `worker/` consumes jobs, config from env, no local state, graceful shutdown. *Check:* logs show job picked up, status → `done` (stub work).
- [ ] **24. Thumbnail job.** `AWSLAB-42` Worker reads the uploaded image from MinIO (Pillow), writes the thumbnail back. *Check:* thumbnail object exists in the bucket.
- [ ] **25. Async test.** `AWSLAB-43` 🔀 `tests/07_async.sh` submit job → poll until done → thumbnail downloadable. *Check:* `make test` green.

### Lab 08 — Frontend & CDN (S3 static hosting + CloudFront) · epic `AWSLAB-12`
- [ ] **26. Static frontend.** `AWSLAB-44` `frontend/` (HTML/JS) served by its own Nginx container behind the LB at `/`; shows which API instance answered each call. *Check:* open in browser; reload shows different instances.
- [ ] **27. Caching headers.** `AWSLAB-45` `Cache-Control`, `ETag`, `immutable` for hashed assets, `no-cache` for `index.html`. *Check:* `curl -I` → 200 then 304 with `If-None-Match`; screenshot via `scripts/screenshot.sh`.
- [ ] **28. Local HTTPS (optional).** `AWSLAB-46` 🔀 mkcert cert, LB listens on 443, 80 redirects. Needs mkcert installed (will ask). *Check:* `curl https://localhost/health`. Skipped and documented if you decline.

### Lab 09 — Monitoring (CloudWatch) · epic `AWSLAB-13`
- [ ] **29. API `/metrics`.** `AWSLAB-47` `prometheus-client` middleware (request count, latency histogram, errors). *Check:* `curl /metrics` shows `http_requests_total`.
- [ ] **30. Prometheus.** `AWSLAB-48` Scrapes all 3 replicas through Docker DNS service discovery. *Check:* `/targets` shows 3 up (screenshot).
- [ ] **31. cAdvisor.** `AWSLAB-49` Per-container CPU/RAM metrics (may need Docker Desktop/WSL2 tweaks — will explain if not). *Check:* `container_cpu_usage_seconds_total` returns series.
- [ ] **32. Grafana + datasource provisioning.** `AWSLAB-50` Behind LB at `grafana.localhost`, admin password from `.env`. *Check:* login works, Prometheus datasource green.
- [ ] **33. Dashboard (1/2).** `AWSLAB-51` Provisioned JSON: request rate, p95 latency, error rate. *Check:* panels show data under curl traffic (screenshot).
- [ ] **34. Dashboard (2/2).** `AWSLAB-52` CPU and RAM per container panels. *Check:* panels populated (screenshot).
- [ ] **35. Loki + log shipper.** `AWSLAB-53` 🔀 Loki + Grafana Alloy (Promtail is EOL — will check current docs) shipping container logs. *Check:* LogQL query in Grafana returns API logs.

### Lab 10 — Testing & load (k6) · epic `AWSLAB-14`
- [ ] **36. Test runner polish.** `AWSLAB-54` `make test` prints a summary table and exits non-zero on any failure; add `tests/README` of what each test proves. *Check:* break something on purpose → red; revert → green.
- [ ] **37. k6 load test.** `AWSLAB-55` `tests/load/k6.js` (50 VUs, 1 min, thresholds on p95 and error rate) run via pinned `grafana/k6` image, `make load-test`. *Check:* summary printed with p95 and error rate.
- [ ] **38. k6 → Grafana.** `AWSLAB-56` Send k6 metrics to Prometheus (remote write) and add a panel. *Check:* panel shows the run (screenshot).
- [ ] **39. Root `README.md`.** `AWSLAB-57` 🔀 **Update the existing root `README.md`** (created outside the plan, ticket `AWSLAB-78`) — do not write a new one: bring its status line, architecture diagram (mark what is now built), local-vs-AWS table, lab table and roadmap up to date, and add "what this can't simulate" if missing. **End of Phase 1** — full `make down && make up && make test` run.

---

## Phase 2 — Kubernetes (EKS + Auto Scaling)
Full size is possible: **1 server + 2 agents** (31 GB RAM).

### Lab 11 — Kubernetes · epic `AWSLAB-15`
- [ ] **40. Install k3d + create the cluster.** `AWSLAB-58` Ask before installing; `k8s/k3d-config.yaml` (pinned k3s image, port 8080→80). *Check:* `kubectl get nodes` shows 3 Ready.
- [ ] **41. Images into the cluster.** `AWSLAB-59` Build/tag apps with explicit versions, `k3d image import`. *Check:* images listed on nodes.
- [ ] **42. Namespace, ConfigMap, Secret.** `AWSLAB-60` Secret generated from `.env` by a script, never committed. *Check:* `kubectl get cm,secret -n lab`.
- [ ] **43. Postgres in-cluster.** `AWSLAB-61` StatefulSet + PVC + headless Service. *Check:* pod Ready, `pg_isready`.
- [ ] **44. Redis + MinIO in-cluster.** `AWSLAB-62` *Check:* pods Ready, bucket bootstrap Job completes.
- [ ] **45. API Deployment.** `AWSLAB-63` 3 replicas, Service, liveness + readiness probes, migration Job. *Check:* `kubectl rollout status`; port-forward `/whoami`.
- [ ] **46. Worker Deployment.** `AWSLAB-64` *Check:* a posted job reaches `done`.
- [ ] **47. Frontend + Ingress.** `AWSLAB-65` Frontend Deployment, Traefik Ingress (bundled with k3s). *Check:* `curl localhost:8080/whoami` shows several pod names.
- [ ] **48. Kubernetes smoke test.** `AWSLAB-66` 🔀 `tests/k8s_smoke.sh` + `make k8s-test`. *Check:* green; kill a pod → still serves.

### Lab 12 — Autoscaling (HPA) · epic `AWSLAB-16`
- [ ] **49. Resource requests/limits + metrics-server check.** `AWSLAB-67` *Check:* `kubectl top pods` returns data.
- [ ] **50. HorizontalPodAutoscaler.** `AWSLAB-68` On the API (CPU target, min 2 / max 8). *Check:* `kubectl get hpa` shows a target.
- [ ] **51. Scale test.** `AWSLAB-69` 🔀 k6 against the Ingress; record scale-up and scale-down (`kubectl get hpa -w`). *Check:* replicas rise during load and fall back afterwards; real output pasted in the lab.

---

## Phase 3 — Terraform against a local AWS emulator

### Lab 13 — Infrastructure as Code · epic `AWSLAB-17`
- [ ] **52. Choose the emulator.** `AWSLAB-70` Look up current docs for AWS's official emulator (Nov 2026) vs Floci;
  write a short decision note (`docs/decisions/emulator.md`). No config written before reading the docs.
- [ ] **53. Emulator container.** `AWSLAB-71` Pinned image, `aws` compose profile, health check. Install Terraform first (ask). *Check:* AWS CLI container with fake creds and `--endpoint-url http://localhost:<port>` lists S3 buckets.
- [ ] **54. Terraform provider + safety guard.** `AWSLAB-72` Provider with local endpoints, fake keys, `skip_*` flags,
  `allowed_account_ids`, a validation that refuses any non-local endpoint, wrapper `scripts/tf.sh`. *Check:* `terraform init/validate/plan`; a deliberately wrong endpoint is rejected.
- [ ] **55. S3 bucket + DynamoDB table.** `AWSLAB-73` *Check:* `terraform apply`, then list both via the CLI.
- [ ] **56. SQS queue.** `AWSLAB-74` *Check:* apply, `aws sqs list-queues` shows it.
- [ ] **57. Queue abstraction in the worker.** `AWSLAB-75` Interface + Redis backend, `QUEUE_BACKEND=redis` default, behaviour unchanged. *Check:* `make test` still green.
- [ ] **58. SQS backend.** `AWSLAB-76` `QUEUE_BACKEND=sqs` in API enqueue + worker. *Check:* job processed through SQS.
- [ ] **59. SQS test + final docs pass.** `AWSLAB-77` 🔀 `tests/13_sqs.sh`; finish `docs/labs/README.md`, `docs/glossary.md`, cross-links, root `README.md` update. *Check:* `make test` green with both backends.

---

## Progress log
_(filled in as steps are completed: step, commit hash, reviewer verdict)_
