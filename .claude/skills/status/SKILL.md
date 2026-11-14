---
name: status
description: Show a quick health table of the local AWS lab - containers, endpoints, plan progress. Use when the user asks if things are running or what state the lab is in.
---

Give me a quick health report of the lab. Read-only: do not start, stop, or change anything.

1. **Plan progress** — from `PLAN.md`: steps done / total, and the next unchecked step.
2. **Git** — current branch, last commit (`git log --oneline -1`), uncommitted changes (yes/no),
   and commits not pushed to GitHub (`git status -sb`).
3. **Containers** — if a compose file exists, run `docker compose ps` and list each service with
   its state and health. If Docker is not running, say so and stop here.
4. **Endpoints** — only for services that exist in the compose file, check with curl
   (short timeout), for example:
   - load balancer: `http://localhost/` and `/health`
   - API: `/whoami` (call it 3 times to show load balancing)
   - Grafana: `http://localhost:3000/api/health`
   - Prometheus: `http://localhost:9090/-/healthy`
   - MinIO: `http://localhost:9000/minio/health/live` (or the port in the compose file)
   Use the real ports from the compose file, not these guesses.
5. **Kubernetes** — only if a k3d cluster exists: `kubectl get pods,hpa` summary.

Output one compact table: Component | AWS equivalent | Status (OK / DOWN / not built yet) | Note.
Then at most 2 lines on anything that needs attention.
