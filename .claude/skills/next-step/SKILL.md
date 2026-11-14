---
name: next-step
description: Do the next unchecked step of PLAN.md - implement, verify, commit, review, report, then stop and wait.
disable-model-invocation: true
---

Do exactly ONE step of the plan, following the rules in CLAUDE.md.

1. Read `PLAN.md`. Find the first unchecked step. If there is no PLAN.md, stop and say so.
   If every step is checked, say the phase is complete and stop.
2. Say in one line which step you are doing.
3. Make only the changes for that step. If it turns out bigger than ~150 lines or more than
   3 files, stop, propose how to split it in PLAN.md, and wait for my answer.
4. Verify it works with a real command (curl, test, `docker compose ps`, …) and keep the output.
5. Tick the step in `PLAN.md`, then make one commit: `step N: <short description>`.
6. Ask the `step-reviewer` subagent to review the commit. If its verdict is FAIL, fix the problem
   in a follow-up commit (`step N: fix <what>`), then review again (at most twice).
7. Report to me, briefly:
   - **What changed:** files and the reason for each
   - **AWS concept:** which AWS service or idea this step stands in for (one or two sentences)
   - **Verified with:** the command and the key line of its output
   - **Reviewer:** the verdict
   - **Check it yourself:** 1–3 commands I can run
8. STOP and wait. Do not start the next step.

Extra instructions from me for this step (may be empty): $ARGUMENTS
