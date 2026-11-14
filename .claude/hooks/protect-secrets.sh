#!/usr/bin/env bash
# PreToolUse hook for Read/Edit/Write: keeps real secret files out of the conversation.
# .env.example is allowed (it only holds placeholder values).

input=$(cat)

path=$(printf '%s' "$input" | tr -d '\n' \
  | sed -nE 's/.*"(file_path|path)"[[:space:]]*:[[:space:]]*"((\\.|[^"\\])*)".*/\2/p')

[ -z "$path" ] && exit 0

name=$(printf '%s' "$path" | sed -E 's#.*[/\\]##')

case "$name" in
  .env.example|.env.sample|.env.template) exit 0 ;;
  .env|.env.*|*.pem|*.key|id_rsa|id_ed25519|credentials)
    echo "BLOCKED by .claude/hooks/protect-secrets.sh: '$name' may contain real secrets." >&2
    echo "Put placeholder values in .env.example instead, and ask the user to edit .env themselves." >&2
    exit 2
    ;;
esac

exit 0
