# Course: Caching

Why and how to cache, for a complete beginner: what a cache is, how Redis works, how a full cache decides what to throw away, the cache-aside pattern, expiry and invalidation, and the classic pitfalls. Every module has an everyday
analogy, diagrams, line-by-line explanations, a hands-on exercise with **real captured output**, a quiz and links to the official documentation.

**Prerequisite:** [Databases 05](../databases/05-sqlalchemy.md) helps (reading a table from Python). The exercises use Docker, so [Docker 01](../docker/01-images-and-containers.md) is a good first read.
Back to the [course index](../README.md). Read each module next to the lab that uses it ([Lab 05](../../labs/05-caching.md)).

## Modules
| # | Module | Status | First used in the labs |
|---|---|---|---|
| 01 | [Why cache](./01-why-cache.md) | ✅ written | Lab 05, step 15 |
| 02 | [Redis basics and data types](./02-redis-data-types.md) | ✅ written | Lab 05, step 15 |
| 03 | [Eviction and `maxmemory`](./03-eviction-and-maxmemory.md) | ✅ written | Lab 05, step 15 |
| 04 | [Cache-aside and other patterns](./04-cache-aside-and-patterns.md) | ✅ written | Lab 05, step 16 |
| 05 | [TTL, expiry and invalidation](./05-ttl-and-invalidation.md) | ✅ written | Lab 05, step 16 |
| 06 | [Common pitfalls (stampede, stale data, penetration)](./06-pitfalls.md) | ✅ written | Lab 05, step 17 |

The order of the numbers is the suggested reading order. The order in which modules are written follows
[`COURSES-PLAN.md`](../../COURSES-PLAN.md).
