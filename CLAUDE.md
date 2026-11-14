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
5. Ask the `step-reviewer` subagent to review the commit. If it says FAIL, fix it in a
   small follow-up commit and review again (at most twice).
6. STOP. Tell me:
   - what changed and why (explain the AWS concept it represents),
   - how you verified it,
   - the reviewer's verdict,
   - the command(s) I can run to check it myself.
   Then WAIT.

- Only start the next step when I type "next" (or clearly approve).
- If I ask a question, answer it and wait again. Do not continue on your own.
- If I say a step is wrong, fix or redo that step only.

### Resuming after /clear or a new session
- Read `PLAN.md` and continue with the first unchecked step, following these same rules.

## Project tooling (in `.claude/`)
- **Skills:** `/next-step` runs one step of the loop above; `/explain-aws` explains the AWS
  equivalent of the latest step; `/status` shows a health table of the lab.
- **Subagent:** `step-reviewer` (read-only) reviews each step commit.
- **Hooks:** `guard-bash.sh` blocks destructive git/docker/rm commands, reading `.env`, and any
  AWS/Terraform command not aimed at the local emulator; `protect-secrets.sh` blocks reading or
  editing secret files; `check-step-size.sh` warns when a commit is too big; `notify.ps1` shows a
  Windows notification when you stop.
- If a hook blocks you, do not try to get around it with another command. Explain to me what
  you wanted to do and why, and let me decide.

## Safety and quality rules
- Before the first step, check my OS, CPU, RAM, free disk space, and whether Docker,
  Docker Compose, kubectl, k3d and Terraform are installed. Tell me what is missing and
  how to install it. Never install anything system-wide without asking me.
- Pin every image and tool to a specific version. Never use `:latest`.
- Secrets go in `.env` (gitignored). Commit only `.env.example`.
- Use fake/local credentials only. Never connect to a real AWS account.
- If something does not work on my machine, explain why instead of silently skipping it.
- Never commit generated data, volumes, or large binaries.

## Git branches
- `main` is protected on GitHub: it only changes through pull requests. Never commit to `main`
  and never push to it.
- Work and commit on the `dev` branch. Before the first step of a session, check with
  `git branch --show-current` that you are on `dev`; if not, tell me instead of switching
  on your own when there are uncommitted changes.
- Do not push unless I ask. When I ask to "open a PR", push `dev` and give me the
  GitHub compare link (`https://github.com/moncef2k/aws-local-lab/compare/main...dev`).
