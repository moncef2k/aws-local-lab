#!/usr/bin/env bash
# PreToolUse hook for Bash: blocks commands that could destroy data,
# leak secrets, or touch a real AWS account.
# Exit 2 = block the command; the message on stderr is shown to Claude.
# No jq/python needed, so it works in Git Bash on Windows.

input=$(cat)

# Pull the "command" value out of the JSON (falls back to the whole input).
cmd=$(printf '%s' "$input" | tr -d '\n' \
  | sed -E 's/.*"command"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)".*/\1/')

block() {
  echo "BLOCKED by .claude/hooks/guard-bash.sh: $1" >&2
  echo "If this is really needed, explain why to the user and let them run it themselves." >&2
  exit 2
}

# --- Git: no history rewriting on the remote, no throwing away work ---
if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+push([^|;&]*)[[:space:]](--force|-f)([[:space:]]|$|=)'; then
  block "force push rewrites history on GitHub."
fi
if printf '%s' "$cmd" | grep -Eq 'git[[:space:]]+(reset[[:space:]]+--hard|clean[[:space:]]+-[a-zA-Z]*f)'; then
  block "git reset --hard / git clean -f throws away work. Ask the user first."
fi

# --- Docker: never wipe volumes or the whole Docker install ---
if printf '%s' "$cmd" | grep -Eq 'docker[[:space:]]+(system[[:space:]]+prune|volume[[:space:]]+(prune|rm))'; then
  block "this deletes Docker volumes or cached data (databases, images)."
fi
if printf '%s' "$cmd" | grep -Eq 'docker[[:space:]]+compose[^|;&]*[[:space:]]down[^|;&]*(-v|--volumes)([[:space:]]|$)'; then
  block "'docker compose down -v' deletes the database and storage volumes. Ask the user first."
fi

# --- rm -rf outside the project ---
if printf '%s' "$cmd" | grep -Eq 'rm[[:space:]]+-[a-zA-Z]*[rR][a-zA-Z]*[[:space:]]+("|'"'"')?(/|~|\.\.|\$HOME|[A-Za-z]:)'; then
  block "recursive delete outside the project folder."
fi

# --- Secrets: don't print .env files (.env.example is fine) ---
if printf '%s' "$cmd" | grep -Eq '(cat|less|more|head|tail|type|bat|grep|sed|awk|strings|xxd|base64)[[:space:]][^|;&]*\.env([[:space:]]|$|"|'"'"'|\.local|\.prod)'; then
  if ! printf '%s' "$cmd" | grep -Eq '\.env\.example'; then
    block "reading .env would put secrets into the conversation. Use .env.example instead."
  fi
fi

# --- AWS safety: everything must go to the local emulator ---
if printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])aws[[:space:]]'; then
  if ! printf '%s' "$cmd" | grep -Eq 'endpoint-url|AWS_ENDPOINT_URL|localhost|127\.0\.0\.1'; then
    block "aws CLI commands must target the local emulator (add --endpoint-url http://localhost:<port>). This lab must never touch a real AWS account."
  fi
fi
if printf '%s' "$cmd" | grep -Eq 'terraform[[:space:]]+(apply|destroy|import)'; then
  dir="${CLAUDE_PROJECT_DIR:-.}"
  if ! grep -rqsE '(localhost|127\.0\.0\.1|host\.docker\.internal)' --include='*.tf' "$dir"; then
    block "no local endpoint found in any .tf file. Terraform must point at the local emulator before apply/destroy."
  fi
fi

exit 0
