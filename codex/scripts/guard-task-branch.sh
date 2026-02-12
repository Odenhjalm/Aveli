#!/usr/bin/env bash
set -euo pipefail

protected_branches="${CODEX_PROTECTED_BRANCHES:-main master develop dev production release}"

branch="${1:-}"
if [[ -z "$branch" ]]; then
  branch="${TASK_GUARD_BRANCH_OVERRIDE:-}"
fi
if [[ -z "$branch" ]]; then
  branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
fi

if [[ -z "$branch" ]]; then
  cat >&2 <<'EOF'
Task guardrail: detached HEAD is not allowed for task work.
Create a task branch first:
  ./codex/scripts/start-task-branch.sh "<task-name>"
EOF
  exit 1
fi

for protected in $protected_branches; do
  if [[ "$branch" == "$protected" ]]; then
    cat >&2 <<EOF
Task guardrail: branch '$branch' is protected for direct task work.
Create and switch to a task branch first:
  ./codex/scripts/start-task-branch.sh "<task-name>"
EOF
    exit 1
  fi
done

exit 0
