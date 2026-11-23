# Course: FastAPI

How the project's Python API works, from zero, for a complete beginner: routes, parameters, validation, automatic documentation, async code, dependencies and tests. Every module has an everyday
analogy, diagrams, line-by-line explanations, a hands-on exercise with **real captured output**, a quiz and links to the official documentation.

**Prerequisite:** basic Python (functions, classes). The exercises run in throw-away containers, so [Docker 01](../docker/01-images-and-containers.md) is a good first read.
Back to the [course index](../README.md). Read each module next to the lab that uses it ([Lab 01](../../labs/01-containers.md) and [Lab 04](../../labs/04-database.md)).

## Modules
| # | Module | Status | First used in the labs |
|---|---|---|---|
| 01 | [How a Python web API works, and routes](./01-how-a-web-api-works.md) | ✅ written | Lab 01, step 2 |
| 02 | [Uvicorn and ASGI](./02-uvicorn-and-asgi.md) | ✅ written | Lab 01, step 2 |
| 03 | [Path, query and body parameters](./03-parameters.md) | ✅ written | Lab 04, step 12 |
| 04 | [Pydantic models and validation](./04-pydantic.md) | ✅ written | Lab 04, step 12 |
| 05 | [Automatic OpenAPI docs](./05-openapi-docs.md) | ✅ written | Lab 01, step 2 |
| 06 | `async def` vs `def` | ⬜ planned | Lab 01, step 2 |
| 07 | [Dependencies and dependency injection](./07-dependencies.md) | ✅ written | Lab 04, step 11 |
| 08 | Testing with `TestClient` | on request | Lab 04, step 12 |

Module 08 is written only when asked for (`course fastapi testing`). The order of the numbers is the suggested reading order; the order in which modules are written follows
[`COURSES-PLAN.md`](../../COURSES-PLAN.md) (module 07 was written early because step 16 needs it).
