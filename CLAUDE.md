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
  Check the step's Jira ticket status too (see "Jira") and bring it in line with the real state.

## Lab documentation (part of every step)
The project is also a course. `docs/labs/` must let me rebuild everything on my own later, while
learning the theory. Follow `docs/labs/_TEMPLATE.md` for every lab.

- **Doc commit after each code commit.** After the step commit, update the matching lab file in a
  second commit: `docs: lab NN step N - <title>`. Then review and stop, as usual.
  The ~150-line limit applies to code commits, not to docs.
- **Theory first.** When a lab starts, write sections 1–3 (what you will learn, theory, how AWS
  does it, how we reproduce it, a Mermaid diagram) before the steps. Explain for a beginner.
- **Self-sufficient steps.** Each step shows: why, the exact commands, the full content of new
  files (or the changed part with its path), the expected output, and what it means. Someone
  with only the doc and an empty folder must be able to reproduce it. Link the reference commit.
- **Real outputs only.** Paste output you actually captured while building, trimmed. Never invent output.
- **Screenshots:**
  - Terminal results → text code blocks (searchable), not images.
  - Web UIs (frontend, Grafana, Prometheus, MinIO console, …) → capture PNGs with a Playwright
    script in a pinned Docker image (`scripts/screenshot.sh <url> <out.png>`), saved under
    `docs/labs/images/lab-NN/`. Keep images small (PNG, about 1280px wide).
  - Things a script cannot capture (Docker Desktop, Windows dialogs) → add
    `> 📸 TODO(you): <what to capture> → save as images/lab-NN/<name>.png` and list these
    TODOs in your report so I can take them.
  - Never capture secrets (passwords, tokens) in screenshots or outputs.
- **Troubleshooting is gold.** Every real error we hit goes in the lab's Troubleshooting table,
  with the cause and the fix.
- **End of each lab:** complete verify, real-AWS mapping, clean-up, 3–5 quiz questions with
  answers in `<details>`, an optional exercise, and links to official docs. Update
  `docs/labs/README.md` (index + progress) and `docs/glossary.md`.
- If a step changes something an earlier lab already explains, update that lab too.

## Jira (kanban board, project key `AWSLAB`)
Jira shows the **status** of the work; `PLAN.md` stays the **source of truth for content** (what each step is).
If the two disagree about what a step is, `PLAN.md` wins and the ticket is updated to match.
Columns: **To Do → In Progress → In Review → Done**.
The board uses French status names. Mapping, with the transition id to pass to `transitionJiraIssue`
(these are global transitions, valid from any status; site `moncefspace.atlassian.net`):

| Column | Jira status | Transition id |
|---|---|---|
| To Do | À faire | `11` |
| In Progress | En cours | `21` |
| In Review | Revue en cours | `31` |
| Done | Terminé(e) | `41` |

Issue types: **Epic** for labs, **Tâche** (Task) for steps, linked with `parent`. A blocked ticket gets the
**Flagged → Impediment** field (`customfield_10021`) set, plus a comment saying why.

- **Structure:** each lab = an Epic (`Lab NN – <title>`); each `PLAN.md` step = a ticket in that epic, titled
  `Step N – <title>`, description = the step text and its check from `PLAN.md`, label `lab-NN`.
- **Keys:** the ticket key is recorded next to its step in `PLAN.md` (e.g. ``- [x] **2. Minimal API.** `AWSLAB-20` ``; epics are on the lab headings).
  When a step is split or added in `PLAN.md`, create or update its ticket too.
- **Workflow per step:**
  1. When you start the step, move its ticket to **In Progress**.
  2. After the code commit, the docs commit and the `step-reviewer` pass, move it to **In Review** and add a
     comment with the same report you give me: what changed, verified with, reviewer verdict,
     check-it-yourself commands, and the commit hashes.
  3. When I say "next" (or clearly approve), move the ticket to **Done** *before* starting the next step.
- **If blocked:** flag the ticket (impediment), comment why, and tell me. Do not work around it silently.
- **Commit messages** start with the ticket key: `AWSLAB-22 step 4: add Nginx load balancer` and
  `AWSLAB-22 docs: lab 02 step 4 - Nginx load balancer`.
- Jira comments follow the same rules as lab docs: real outputs only, never secrets, tokens or `.env` content.
- If Jira is unreachable or not authenticated, say so and continue the step without it. Do not invent ticket
  keys; tell me so the board can be brought up to date afterwards.

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
