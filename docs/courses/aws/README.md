# Course: AWS

The real AWS services behind each local component of this project, for a complete beginner. Every module has an everyday analogy, diagrams, line-by-line explanations, a hands-on exercise with **real captured output**, a quiz
and links to the official documentation.

**This course never touches a real AWS account.** Its exercises either use the lab's local stand-ins (Docker networks, MinIO, later the local emulator of Lab 13) or are design exercises, and every module says where the local version differs from AWS.

**Prerequisite:** none, but the Networking course helps for the VPC modules. Back to the [course index](../README.md). Read each module next to the lab whose component it explains.

## Modules
| # | Module | Status | Stand-in in the labs |
|---|---|---|---|
| 01 | Regions and Availability Zones | ⬜ planned | (not simulated) |
| 02 | IAM: users, roles, policies, access keys | ⬜ planned | fake credentials (Lab 06) |
| 03 | Compute: EC2, ECS, Fargate and EKS | ⬜ planned | Docker, then k3d |
| 04 | [VPC: subnets, route tables, gateways](./04-vpc.md) | ✅ written | `public` / `private` Docker networks (Lab 03) |
| 05 | ELB: ALB, target groups, health checks | ⬜ planned | Nginx (Lab 02) |
| 06 | [RDS: managed databases](./06-rds.md) | ✅ written | Postgres container (Lab 04) |
| 07 | ElastiCache | ⬜ planned | Redis container (Lab 05) |
| 08 | S3: buckets, objects, presigned URLs | ⬜ planned | MinIO (Lab 06) |
| 09 | CloudFront and CDNs | on request | Nginx caching headers (Lab 08) |
| 10 | SQS: standard and FIFO queues | ⬜ planned | Redis list, then an emulator (Labs 07, 13) |
| 11 | DynamoDB | on request | emulator (Lab 13) |
| 12 | CloudWatch: metrics, logs, alarms | ⬜ planned | Prometheus, Grafana, Loki (Lab 09) |
| 13 | Pricing and cost control | ⬜ planned | the "Rough cost" line of every lab |
| 14 | Well-Architected Framework basics | ⬜ planned | the tests of the labs |

Modules marked "on request" are written only when asked for (`course aws cloudfront`, `course aws dynamodb`). The order of the numbers is the suggested reading order; the order in which modules are written follows
[`COURSES-PLAN.md`](../../COURSES-PLAN.md).
