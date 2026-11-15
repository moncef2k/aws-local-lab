# Glossary

Every AWS / infrastructure term used in the course, in plain words. Each lab adds the terms it
introduces. "Local" is what we use in this project instead of the AWS service.

| Term | What it means | AWS service / local stand-in | Lab |
|---|---|---|---|
| **Active vs passive health check** | Active: the load balancer calls a health URL on a timer and removes failing servers before users notice (AWS ALB). Passive: it only notices a server is dead when a real request fails (open-source Nginx). | AWS: target group health check · Local: Nginx `max_fails` / `fail_timeout` | 02 |
| **ALB** (Application Load Balancer) | Receives web traffic and spreads it over several copies of an app; stops sending traffic to broken ones. | AWS: ALB · Local: Nginx | 02 |
| **Auto Scaling** | Adding or removing copies of an app automatically, based on load. | AWS: Auto Scaling groups · Local: Kubernetes HPA | 12 |
| **Availability Zone (AZ)** | A separate data centre inside an AWS region. Spreading over several AZs survives the loss of one. | AWS only — cannot be simulated on one laptop | 03 |
| **Bridge network** | A virtual network created by Docker; containers on it can reach each other by name. | Local: Docker network | 03 |
| **Bucket** | A named container for files (objects) in object storage. | AWS: S3 bucket · Local: MinIO bucket | 06 |
| **Cache-aside** | Read pattern: look in the cache first; on a miss, read the database and store the result in the cache. | AWS: ElastiCache · Local: Redis | 05 |
| **CDN** (Content Delivery Network) | Servers around the world that keep copies of your static files close to users. | AWS: CloudFront · Local: Nginx with caching headers (only the headers, no real CDN) | 08 |
| **CloudWatch** | AWS monitoring: metrics, logs, dashboards, alarms. | Local: Prometheus + Grafana + Loki | 09 |
| **Container** | A running, isolated process with its own filesystem, started from an image. Lighter than a virtual machine. | AWS: ECS / EKS tasks · Local: Docker | 01 |
| **Docker Compose** | A tool that starts several containers from one YAML file. | Local only (like a mini CloudFormation for containers) | 00 |
| **Dockerfile** | The recipe to build an image. | AWS: same, then pushed to ECR | 01 |
| **Environment variable** | A named setting handed to a program from outside (`UVICORN_LOG_LEVEL=warning`), so the same image can behave differently per environment. | AWS: task definition `environment`, Parameter Store | 01 |
| **`.env` file** | A local file of settings and secrets, read by Docker Compose. Never committed to Git; `.env.example` is the committed template. | Local only (AWS: Secrets Manager / Parameter Store) | 00 |
| **ECR** (Elastic Container Registry) | AWS's private store for container images. | Local: the Docker image store | 01 |
| **EC2** | Virtual machines in AWS. | Local: a container is a lighter equivalent | 01 |
| **EKS** | Managed Kubernetes in AWS. | Local: k3d | 11 |
| **ElastiCache** | Managed Redis/Memcached in AWS. | Local: Redis | 05 |
| **Failover** | Continuing to serve requests, on the remaining copies, when one copy fails. | AWS: ALB + several targets · Local: Nginx `proxy_next_upstream` | 02 |
| **FastAPI / Uvicorn** | A Python web framework / the server that runs it. | AWS: your app code running on ECS/EKS/EC2 | 01 |
| **Health check** | A regular request ("are you OK?") that tells a load balancer or orchestrator whether a copy of an app is healthy. | AWS: target group health check · Local: Nginx + Docker `healthcheck` | 02 |
| **HPA** (Horizontal Pod Autoscaler) | Kubernetes object that changes the number of pod copies based on CPU or other metrics. | AWS: Auto Scaling | 12 |
| **`.gitkeep`** | An empty file whose only purpose is to make Git keep an otherwise empty folder. | Git convention | 00 |
| **IAM** | AWS users, roles and permissions. | Not simulated in this lab (fake credentials only) | 13 |
| **IaC** (Infrastructure as Code) | Describing infrastructure in files that a tool applies, instead of clicking in a console. | AWS: CloudFormation · Local: Terraform | 13 |
| **Image** | A read-only package (app + dependencies) from which containers start. | AWS: ECR stores them · Local: built by Docker | 01 |
| **Layer (image)** | One Dockerfile instruction, stored as a cached piece of the image. Put rarely-changing steps first so rebuilds are fast. | Docker concept | 01 |
| **k3d** | Runs a small Kubernetes cluster (k3s) inside Docker containers. | Local stand-in for EKS | 11 |
| **k6** | A load-testing tool: simulates many users and reports latency and errors. | Local tool | 10 |
| **Listener** | The part of a load balancer that accepts connections on a port (for example HTTP on 80) and applies rules to them. | AWS: ALB listener · Local: `listen 80;` in Nginx | 02 |
| **Load balancer** | See ALB. | | 02 |
| **Make / Makefile** | A tool that runs named recipes (`make up`) defined in a `Makefile`. Used here as a shortcut for long Docker commands. | Local tool | 00 |
| **Mermaid** | Text syntax for diagrams, rendered by GitHub and many editors. Used for all diagrams here. | Documentation tool | 00 |
| **MinIO** | An S3-compatible object store you can run locally. | Local stand-in for S3 | 06 |
| **Nginx** | A web server and reverse proxy. Used as load balancer and as static file server. | Local stand-in for ALB / CloudFront origin | 02 |
| **Non-root user** | Running the app as an unprivileged user inside the container, so a compromised app has little power. | AWS: same advice for ECS/EKS tasks | 01 |
| **Pinning** | Fixing an exact version (`python:3.12.16-slim-trixie`, `fastapi==0.163.0`) instead of "latest", so a rebuild gives the same result. | Good practice everywhere | 01 |
| **Playwright** | A tool that drives a real browser from a script. Used here to take screenshots. | Documentation tool | 00 |
| **Port mapping** | Publishing a container port on the host: `127.0.0.1:8000:8000` = host address : host port : container port. | AWS: security group + load balancer listener | 01 |
| **Presigned URL** | A temporary link that gives access to one private object, without credentials. | AWS: S3 presigned URL · Local: MinIO | 06 |
| **Private subnet** | A network area with no direct access from the internet; databases and app servers live here. | AWS: VPC private subnet · Local: Docker network marked `internal` | 03 |
| **Prometheus / Grafana / Loki** | Metrics database / dashboards / log database. | Local stand-ins for CloudWatch | 09 |
| **Public subnet** | A network area reachable from the internet; only the load balancer lives here. | AWS: VPC public subnet · Local: Docker network `public` | 03 |
| **RDS** | Managed relational databases (here: PostgreSQL) in AWS. | Local: Postgres container | 04 |
| **Redis** | An in-memory key-value store, used for caching and simple queues. | AWS: ElastiCache | 05 |
| **Replica** | One of several identical copies of the same app. | AWS: several tasks/instances · Local: `docker compose` replicas | 02 |
| **Reverse proxy** | A server that receives requests on behalf of other servers and forwards them. A load balancer is a reverse proxy that picks one of several servers. | AWS: ALB · Local: Nginx | 02 |
| **Round-robin** | Handing requests to the servers one after the other, in turn. The default way Nginx and an ALB spread load. | AWS: ALB default · Local: Nginx default | 02 |
| **S3** | AWS object storage (files in buckets). | Local: MinIO | 06 |
| **Security group** | A firewall around a resource: who may connect to which port. | Local: Docker network membership | 03 |
| **Service discovery (DNS)** | Finding the servers behind a name. On a Docker network, the name of a service resolves to the addresses of its containers, and Docker's DNS (`127.0.0.11`) answers. | AWS: ECS/EKS registering targets · Local: Docker DNS + nginx `resolve` | 02 |
| **SQS** | AWS message queue: a producer puts jobs in, workers take them out. | Local: a Redis list (Phase 1), then SQS on an emulator (Phase 3) | 07 |
| **Target group** | The list of servers a load balancer can send traffic to, with their health checks. | AWS: ALB target group · Local: Nginx `upstream` block | 02 |
| **Terraform** | A tool that creates infrastructure from `.tf` files. | Local tool, pointed at an emulator | 13 |
| **Test (shell test)** | A script that checks one behaviour of the running lab and exits 0 (pass) or non-zero (fail). `make test` runs them all. | AWS: (none) · Local: `tests/NN_*.sh` | 02 |
| **VPC** (Virtual Private Cloud) | Your own isolated network in AWS, divided into subnets. | Local: Docker networks | 03 |
| **Volume** | Storage that outlives a container, so data survives a restart. | AWS: EBS · Local: Docker named volume | 04 |
