#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

chmod +x codex/scripts/guard-task-branch.sh
chmod +x codex/scripts/start-task-branch.sh
chmod +x codex/scripts/install-task-guardrails.sh
chmod +x .githooks/pre-commit
chmod +x .githooks/pre-push

git config core.hooksPath .githooks

echo "Task guardrails installed."
echo "Git hooks path: $(git config --get core.hooksPath)"
echo "Start each task with:"
echo "  ./codex/scripts/start-task-branch.sh \"<task-name>\""
