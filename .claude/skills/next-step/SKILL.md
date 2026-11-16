---
name: next-step
description: Do the next unchecked step of PLAN.md - implement, verify, commit, write the due course modules, review, report, then stop and wait. Keeps the Jira ticket in sync (In Progress -> In Review; the previous one -> Done).
disable-model-invocation: true
---

Do exactly ONE step of the plan, following the rules in CLAUDE.md (including the "Jira" section).

1. Read `PLAN.md`. Find the first unchecked step. If there is no PLAN.md, stop and say so.
   If every step is checked, say the phase is complete and stop.
2. Jira, before starting:
   - Running `/next-step` means I approved the previous step: if its ticket is in **In Review**, move it
     to **Done** first.
   - Find this step's ticket (key next to the step in `PLAN.md`) and move it to **In Progress**.
   - If Jira is unreachable or not authenticated, say so in one line and continue without it.
3. Say in one line which step (and ticket) you are doing.
4. Make only the changes for that step. If it turns out bigger than ~150 lines or more than
   3 files, stop, propose how to split it in `PLAN.md` (and create/update the tickets), and wait for my answer.
5. Verify it works with a real command (curl, test, `docker compose ps`, …) and keep the output.
6. Tick the step in `PLAN.md`, then make one commit: `AWSLAB-NN step N: <short description>`.
7. Update the matching lab in `docs/labs/` (following `docs/labs/_TEMPLATE.md`) and commit it
   separately as `AWSLAB-NN docs: lab NN step N - <title>`. Use only outputs you actually captured in step 5.
8. Course modules (see "Tool courses" in CLAUDE.md). Unless I said "no course modules today": read the
   "Schedule by lab step" table of `COURSES-PLAN.md` and take the modules scheduled for this step, plus any
   carried over from earlier steps, at most 2 (slot 1 = current/next lab, slot 2 = labs 00-02 backlog).
   Add any module I asked for in the arguments as `course <tool> <module>` on top of that limit.
   For each module:
   - create its Jira ticket (Tâche under epic `AWSLAB-79`, `Course <tool> NN – <title>`, labels `courses` and
     `course-<tool>`) and move it to **In Progress**; record the key in `COURSES-PLAN.md`;
   - run its exercises and keep the real output (throw-away `docker run --rm` with pinned images);
   - write `docs/courses/<tool>/NN-<slug>.md` following `docs/courses/_TEMPLATE.md` and the writing standard;
   - update `docs/courses/README.md`, the progress log in `COURSES-PLAN.md`, and add the module to the
     `## Go deeper` list at the end of the matching lab (when that lab file exists);
   - commit: `AWSLAB-NNN docs: course <tool> module NN - <title>`.
   If the module needs a tool that is not installed yet (k3d, Terraform), leave it for a later step and say so.
9. Ask the `step-reviewer` subagent to review the step commit, its docs commit and any course commit. If its
   verdict is FAIL, fix the problem in a follow-up commit (`AWSLAB-NN step N: fix <what>`,
   `AWSLAB-NN docs: lab NN step N - fix <what>` for the lab, or `AWSLAB-NNN docs: course <tool> module NN - fix <what>`
   for a module), then review again (at most twice).
10. Jira, after the review: move the ticket to **In Review** and add a comment with the report below
   (what changed, verified with, reviewer verdict, check-it-yourself commands, commit hashes, new course modules).
   Move each course module ticket to **Done** once the reviewer passed its commit.
   If the step is blocked: flag the ticket, comment why, and tell me.
11. Report to me, briefly:
    - **What changed:** files and the reason for each (code commit and docs commit)
    - **AWS concept:** which AWS service or idea this step stands in for (one or two sentences)
    - **Verified with:** the command and the key line of its output
    - **Reviewer:** the verdict
    - **Jira:** ticket key and its new column
    - **Check it yourself:** 1–3 commands I can run
    - **Screenshots for you:** every `📸 TODO(you)` left in the lab doc that I need to take
      (what to capture and the file name), or "none"
    - **New course module:** one line per module, `New course module: <title> (<file>)` with its ticket key,
      or "none due"
12. STOP and wait. Do not start the next step.

Extra instructions from me for this step (may be empty): $ARGUMENTS
