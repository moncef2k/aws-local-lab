# Course: Nginx

How the web server, reverse proxy and load balancer of the project works, from zero, for a complete beginner: what Nginx is, how its configuration is organised, how it passes requests on, balances load and reacts when a server fails. Every module has an everyday
analogy, diagrams, line-by-line explanations, a hands-on exercise with **real captured output**, a quiz and links to the official documentation.

**Prerequisite:** [Networking 03](../networking/03-http.md) (HTTP) and [Networking 04](../networking/04-proxies.md) (proxies) help. The exercises use Docker, so [Docker 01](../docker/01-images-and-containers.md) is a good first read.
Back to the [course index](../README.md). Read each module next to the lab that uses it ([Lab 02](../../labs/02-load-balancing.md)).

## Modules
| # | Module | Status | First used in the labs |
|---|---|---|---|
| 01 | [What a web server and a reverse proxy are](./01-web-server-and-reverse-proxy.md) | ✅ written | Lab 02, step 4 |
| 02 | [Config structure, `server` and `location` matching](./02-config-server-location.md) | ✅ written | Lab 02, step 4 |
| 03 | [`proxy_pass` and proxy headers](./03-proxy-pass-and-headers.md) | ✅ written | Lab 02, step 4 |
| 04 | Upstreams and load-balancing methods | ⬜ planned | Lab 02, step 5 |
| 05 | Timeouts, retries and passive health checks | ⬜ planned | Lab 02, step 6 |
| 06 | Static files and caching headers | ⬜ planned | Lab 08, step 26 |
| 07 | HTTPS in Nginx | ⬜ planned | Lab 08, step 28 |
| 08 | Logs and debugging | ⬜ planned | Lab 02, step 4 |

The order of the numbers is the suggested reading order. The order in which modules are written follows
[`COURSES-PLAN.md`](../../COURSES-PLAN.md) (modules 06 and 07 wait for Lab 08).
