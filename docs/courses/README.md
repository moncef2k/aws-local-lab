# Tool courses

A second learning track next to the [labs](../labs/README.md). The **labs** show *how to build* the project, step by step.
The **courses** explain *each tool in depth*, for a complete beginner, so you understand what you typed.

Every module: an everyday analogy first, diagrams (Mermaid), every sample explained line by line, every command explained,
a hands-on exercise with **real captured output**, a "What if...?" experiment, a 3-line recap, a 5-question quiz and links to
the official documentation. Modules are written alongside the lab steps, following [`COURSES-PLAN.md`](../../COURSES-PLAN.md).
Modules marked ⬜ are planned, ✅ are written.

## Suggested reading order
1. **Docker**, because every lab runs in containers.
2. **Networking**, because every later idea (load balancer, private network, DNS) builds on it.
3. **Nginx**, the load balancer and the frontend server.
4. **FastAPI**, the API you are load-balancing.
5. **Databases**, then **Caching**, then **Workers and queues**, in the order the labs add them.
6. **Kubernetes**, then **Terraform**, for Phases 2 and 3.
7. **AWS**: not a block to read in one go. Read each module next to the lab that stands in for that service;
   *Regions and Availability Zones* and *Pricing* are good first reads.

## The courses
| Course | Modules | Written |
|---|---|---|
| [Docker](./docker/README.md) | 10 | 10 |
| [Networking](./networking/README.md) | 8 | 7 |
| [Nginx](./nginx/README.md) | 8 | 1 |
| [FastAPI](./fastapi/README.md) | 7 (+1 on request) | 3 |
| [Databases](./databases/README.md) | 9 | 7 |
| Caching | 6 | 0 |
| Workers and queues | 7 | 0 |
| Kubernetes | 10 | 0 |
| Terraform | 6 (+1 on request) | 0 |
| [AWS](./aws/README.md) | 12 (+2 on request) | 2 |

## Which lab uses which course
Modules whose topic first appears in each lab. Read them before, during or after the lab.

| Lab | Course modules |
|---|---|
| [00 - Setup](../labs/00-setup.md) | [Docker 02](./docker/02-docker-desktop-wsl2.md), AWS 01 |
| [01 - Containers](../labs/01-containers.md) | [Docker 01](./docker/01-images-and-containers.md), [Docker 03](./docker/03-dockerfile.md), [Docker 04](./docker/04-layers-and-build-cache.md), [Docker 05](./docker/05-tags-and-registries.md), [Docker 06](./docker/06-config-and-secrets.md), [Docker 07](./docker/07-networks.md), [Docker 09](./docker/09-compose.md), [Docker 10](./docker/10-debugging.md), [Networking 01](./networking/01-ip-ports-tcp.md), [Networking 03](./networking/03-http.md), [Networking 05](./networking/05-nat-and-port-forwarding.md), FastAPI 01, FastAPI 02, FastAPI 05, FastAPI 06, AWS 03, AWS 13 |
| [02 - Load balancing](../labs/02-load-balancing.md) | [Networking 02](./networking/02-dns.md), [Networking 04](./networking/04-proxies.md), [Nginx 01](./nginx/01-web-server-and-reverse-proxy.md), Nginx 02, Nginx 03, Nginx 04, Nginx 05, Nginx 08, AWS 05, AWS 14 |
| [03 - Networking](../labs/03-networking.md) | [Networking 06](./networking/06-subnets-and-cidr.md), [Networking 07](./networking/07-firewalls-and-security-groups.md), [AWS 04](./aws/04-vpc.md) |
| [04 - Database](../labs/04-database.md) | [Docker 08](./docker/08-volumes-and-bind-mounts.md), [FastAPI 03](./fastapi/03-parameters.md), [FastAPI 04](./fastapi/04-pydantic.md), [FastAPI 07](./fastapi/07-dependencies.md), FastAPI 08 *(on request)*, [Databases 01](./databases/01-relational-basics.md), [Databases 02](./databases/02-sql.md), [Databases 03](./databases/03-postgresql.md), [Databases 04](./databases/04-schemas-and-migrations.md), [Databases 05](./databases/05-sqlalchemy.md), [Databases 06](./databases/06-indexes.md), [Databases 07](./databases/07-transactions.md), Databases 08, Databases 09, [AWS 06](./aws/06-rds.md) |
| [05 - Caching](../labs/README.md) | Caching 01, Caching 02, Caching 03, Caching 04, Caching 05, Caching 06, AWS 07 |
| [06 - Object storage](../labs/README.md) | AWS 02, AWS 08 |
| [07 - Queues and workers](../labs/README.md) | Workers and queues 01, Workers and queues 02, Workers and queues 03, Workers and queues 04, Workers and queues 05, Workers and queues 06, AWS 10 |
| [08 - Frontend and CDN](../labs/README.md) | Networking 08, Nginx 06, Nginx 07, AWS 09 *(on request)* |
| [09 - Monitoring](../labs/README.md) | AWS 12 |
| [10 - Testing and load](../labs/README.md) | - |
| [11 - Kubernetes](../labs/README.md) | Kubernetes 01, Kubernetes 02, Kubernetes 03, Kubernetes 04, Kubernetes 05, Kubernetes 06, Kubernetes 07, Kubernetes 08 |
| [12 - Autoscaling](../labs/README.md) | Kubernetes 09, Kubernetes 10 |
| [13 - Terraform and emulator](../labs/README.md) | Workers and queues 07, Terraform 01, Terraform 02, Terraform 03, Terraform 04, Terraform 05, Terraform 06, Terraform 07 *(on request)*, AWS 11 *(on request)* |

## How a module is organised
See [`_TEMPLATE.md`](./_TEMPLATE.md). New modules are added with the commit message `AWSLAB-NNN docs: course <tool> module NN - <title>`.

