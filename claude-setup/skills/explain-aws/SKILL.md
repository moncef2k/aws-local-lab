---
name: explain-aws
description: Explain what the latest step (or a named component) corresponds to in real AWS - service, console location, rough cost, and what changes in production. Use when the user asks how something in this lab maps to AWS.
---

Explain the AWS side of this lab, as a teacher, for someone learning AWS.

Topic: $ARGUMENTS
If the topic is empty, explain the latest commit (`git show --stat HEAD`, and PLAN.md for context).

Cover, in this order and briefly (aim for under 250 words):

1. **What we built locally** — one or two sentences, naming the files involved.
2. **The real AWS equivalent** — the exact service(s), e.g. "Application Load Balancer (ELB)",
   "Amazon RDS for PostgreSQL", and where it lives in the AWS console.
3. **How it would look on AWS** — the key resources you would create (e.g. target group,
   listener, security group, subnet group), and a tiny Terraform resource name list if useful.
4. **Differences** — what the local version does not simulate (multi-AZ, IAM, real scaling,
   managed backups, etc.).
5. **Cost idea** — rough monthly cost range on AWS and whether it is in the free tier.
   Prices change: say they are approximate and point to the AWS pricing page; do not invent
   exact numbers you are unsure of.
6. **Check your understanding** — one short question for me to answer.

Do not change any files.
