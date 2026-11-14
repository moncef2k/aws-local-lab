# CLAUDE.md — rules for working in this project

This project is a learning lab: a local copy of an AWS web hosting architecture
running on my laptop, with sample apps that prove each piece works.
The full description of what to build is in `SPEC.md`. Progress is tracked in `PLAN.md`.

## How to work (very important — always follow these rules)

### Planning
- If `PLAN.md` does not exist yet: read `SPEC.md`, then create `PLAN.md` — a numbered
  checklist that breaks every phase into small steps. Show it to me and WAIT for my
  approval. Do not write any code before I approve the plan.
- Each step must be one small, testable change: roughly 1–3 files and under ~150 lines changed.
- If a step turns out bigger than expected, split it and update `PLAN.md` instead of
  making a big commit.

### One step at a time
For each step:
1. Make ONLY the changes for that step. Nothing extra, no "while I'm here" changes.
2. Run a check that proves the step works (a curl, a test, `docker compose ps`, etc.).
3. Tick the step in `PLAN.md`.
4. Make ONE git commit with a clear message, e.g.
   `step 4: add Postgres container on private network`.
5. STOP. Tell me:
   - what changed and why (explain the AWS concept it represents),
   - how you verified it,
   - the command(s) I can run to check it myself.
   Then WAIT.

- Only start the next step when I type "next" (or clearly approve).
- If I ask a question, answer it and wait again. Do not continue on your own.
- If I say a step is wrong, fix or redo that step only.

### Resuming after /clear or a new session
- Read `PLAN.md` and continue with the first unchecked step, following these same rules.

## Safety and quality rules
- Before the first step, check my OS, CPU, RAM, free disk space, and whether Docker,
  Docker Compose, kubectl, k3d and Terraform are installed. Tell me what is missing and
  how to install it. Never install anything system-wide without asking me.
- Pin every image and tool to a specific version. Never use `:latest`.
- Secrets go in `.env` (gitignored). Commit only `.env.example`.
- Use fake/local credentials only. Never connect to a real AWS account.
- If something does not work on my machine, explain why instead of silently skipping it.
- Never commit generated data, volumes, or large binaries.
