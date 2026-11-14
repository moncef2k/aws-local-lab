---
name: next-step
description: Do the next unchecked step of PLAN.md - implement, verify, commit, review, report, then stop and wait. Keeps the Jira ticket in sync (In Progress -> In Review; the previous one -> Done).
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
8. Ask the `step-reviewer` subagent to review the step commit and its docs commit. If its verdict
   is FAIL, fix the problem in a follow-up commit (`AWSLAB-NN step N: fix <what>`, or
   `AWSLAB-NN docs: lab NN step N - fix <what>` for the lab), then review again (at most twice).
9. Jira, after the review: move the ticket to **In Review** and add a comment with the report below
   (what changed, verified with, reviewer verdict, check-it-yourself commands, commit hashes).
   If the step is blocked: flag the ticket, comment why, and tell me.
10. Report to me, briefly:
    - **What changed:** files and the reason for each (code commit and docs commit)
    - **AWS concept:** which AWS service or idea this step stands in for (one or two sentences)
    - **Verified with:** the command and the key line of its output
    - **Reviewer:** the verdict
    - **Jira:** ticket key and its new column
    - **Check it yourself:** 1–3 commands I can run
    - **Screenshots for you:** every `📸 TODO(you)` left in the lab doc that I need to take
      (what to capture and the file name), or "none"
11. STOP and wait. Do not start the next step.

Extra instructions from me for this step (may be empty): $ARGUMENTS
