# AWS Local Lab — the course

A hands-on course on **AWS web-hosting architecture**. You build a local copy of it on your own
laptop — load balancer, private network, database, cache, object storage, queue and worker, monitoring,
then Kubernetes and Terraform — and prove each piece works with a sample app and a test.

Everything runs locally with fake credentials. **Nothing here ever touches a real AWS account.**

The goal: when you finish, you can **rebuild the whole project alone, from these docs only**, and you can
explain which AWS service each local piece stands for.

## How each lab is built
Every lab follows [`_TEMPLATE.md`](./_TEMPLATE.md):

1. **What you will learn** — the outcomes.
2. **Theory** — the concept, how AWS does it, how we reproduce it locally, a diagram.
3. **Prerequisites.**
4. **Steps** — each with *why*, the exact commands, the full content of new files, the expected
   (real, captured) output and what it means. Each step links to the reference commit.
5. **Verify**, **Troubleshooting** (every real error we met), **Going to real AWS**, **Clean up**,
   a **quiz**, optional **exercises** and **further reading**.

Terms are explained in the [glossary](../glossary.md).

## Learning path

| Lab | Topic | AWS service(s) it stands for | Status |
|---|---|---|---|
| [00](./00-setup.md) | Setup: tools, Docker basics, how the course is organised | — | ✅ done |
| [01](./01-containers.md) | Containers and the first API | EC2 / ECS, ECR | ✅ done |
| [02](./02-load-balancing.md) | Load balancing and health checks | ALB, target groups | ✅ done |
| [03](./03-networking.md) | Networking: public and private networks | VPC, subnets, security groups | ✅ done |
| [04](./04-database.md) | Database, migrations, persistence | RDS | ✅ done |
| [05](./05-caching.md) | Caching (cache-aside) | ElastiCache | ✅ done |
| [06](./06-object-storage.md) | Object storage and presigned URLs | S3 | ✅ done |
| [07](./07-queues-workers.md) | Queues and workers | SQS, Lambda / ECS workers | 🚧 in progress |
| 08 | Static frontend and caching headers | S3 static hosting, CloudFront | ⬜ planned |
| 09 | Monitoring and logs | CloudWatch | ⬜ planned |
| 10 | Testing an architecture, failure tests, load tests | — (k6) | ⬜ planned |
| 11 | Kubernetes | EKS | ⬜ planned |
| 12 | Autoscaling | Auto Scaling (HPA) | ⬜ planned |
| 13 | Infrastructure as Code against a local emulator | CloudFormation / Terraform | ⬜ planned |

Do the labs **in order**: each one builds on the previous one. Lab names above follow `SPEC.md`; the
exact step list is in [`PLAN.md`](../../PLAN.md).

## Prerequisites
- A computer able to run Docker Desktop (this project was built on Windows 11 with 31 GB RAM and ~96 GB free disk;
  with less than 16 GB RAM, keep the Phase 2 Kubernetes cluster small: 1 server + 1 agent node).
- Basic comfort with a terminal. No AWS knowledge is assumed — the theory sections start from zero.
- Tools are listed, with pinned versions and install lines, in [Lab 00](./00-setup.md).

## Screenshots
- **Terminal results** are pasted as text blocks (searchable, copyable).
- **Web UIs** (frontend, Grafana, Prometheus, MinIO console…) are captured by
  `scripts/screenshot.sh <url> <out.png>` and saved under `docs/labs/images/lab-NN/`.
  See [Lab 00, step 0](./00-setup.md#step-0--the-screenshot-tool).
- Things a script cannot capture (Docker Desktop, Windows dialogs) are marked
  `> 📸 TODO(you): …` in the lab, to be added by hand.

## Progress
Updated at the end of every lab. Last update: Lab 03 done (step 9, isolation test).

- [x] Course scaffolding: lab index, glossary, screenshot script
- [x] Lab 00 — Setup: tools, repo skeleton, Makefile
- [x] Lab 01 — Containers and the first API
- [x] Lab 02 — Load balancing and health checks
- [x] Lab 03 — Networking: public and private networks
- [ ] Phase 1 — Docker Compose (labs 00–10)
- [ ] Phase 2 — Kubernetes (labs 11–12)
- [ ] Phase 3 — Terraform and a local AWS emulator (lab 13)
