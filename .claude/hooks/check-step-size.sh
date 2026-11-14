#!/usr/bin/env bash
# Stop hook: when Claude is about to stop, check that the latest commit
# respects the "small step" rule in CLAUDE.md (about 150 lines, a few files).
# Checks each commit only once. Exit 2 makes Claude continue and tell the user.

input=$(cat)

# Avoid loops: if Claude is already continuing because of a Stop hook, let it stop.
if printf '%s' "$input" | grep -Eq '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
head=$(git rev-parse HEAD 2>/dev/null) || exit 0

marker=".claude/.last-size-check"
[ "$(cat "$marker" 2>/dev/null)" = "$head" ] && exit 0
echo "$head" > "$marker"

MAX_LINES=150
MAX_FILES=5

# Ignore PLAN.md ticks, lock files and lab docs, which are not "real" changes.
stat=$(git show --shortstat --format= HEAD -- . \
  ':(exclude)PLAN.md' ':(exclude)*lock*' ':(exclude)*.lock' ':(exclude)docs/**' 2>/dev/null)

files=$(printf '%s' "$stat" | grep -Eo '[0-9]+ files? changed' | grep -Eo '[0-9]+')
ins=$(printf '%s' "$stat" | grep -Eo '[0-9]+ insertions?' | grep -Eo '[0-9]+')
del=$(printf '%s' "$stat" | grep -Eo '[0-9]+ deletions?' | grep -Eo '[0-9]+')
files=${files:-0}; lines=$(( ${ins:-0} + ${del:-0} ))

if [ "$lines" -gt "$MAX_LINES" ] || [ "$files" -gt "$MAX_FILES" ]; then
  short=$(git rev-parse --short HEAD)
  echo "Step-size check: the last commit ($short) changed $lines lines in $files files," >&2
  echo "which is above the small-step limit in CLAUDE.md (~$MAX_LINES lines, a few files)." >&2
  echo "Tell the user this in one or two sentences, and suggest how it could have been split." >&2
  echo "Do not undo or rewrite the commit yourself; the user decides." >&2
  exit 2
fi

exit 0
