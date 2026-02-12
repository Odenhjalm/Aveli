#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./codex/scripts/start-task-branch.sh "<task-name>" [--base <branch>] [--prefix <prefix>] [--allow-dirty]

Examples:
  ./codex/scripts/start-task-branch.sh "lesson reorder"
  ./codex/scripts/start-task-branch.sh "fix media crash" --prefix fix --base main
EOF
}

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

task_name="$1"
shift

base_branch=""
branch_prefix="feature"
allow_dirty="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)
      base_branch="${2:-}"
      shift 2
      ;;
    --prefix)
      branch_prefix="${2:-}"
      shift 2
      ;;
    --allow-dirty)
      allow_dirty="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$base_branch" ]]; then
  remote_head="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [[ -n "$remote_head" ]]; then
    base_branch="${remote_head#origin/}"
  elif git show-ref --verify --quiet refs/heads/main; then
    base_branch="main"
  elif git show-ref --verify --quiet refs/heads/master; then
    base_branch="master"
  else
    base_branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  fi
fi

if [[ -z "$base_branch" ]]; then
  echo "Could not detect a base branch. Use --base <branch>." >&2
  exit 1
fi

if [[ "$allow_dirty" != "true" ]]; then
  if ! git diff --quiet || ! git diff --cached --quiet; then
    cat >&2 <<'EOF'
Working tree has unstaged/staged changes.
Commit or stash them before starting a new task branch.
If intentional, rerun with --allow-dirty.
EOF
    exit 1
  fi

  if [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
    cat >&2 <<'EOF'
Working tree has untracked files.
Commit/stash/clean them before starting a new task branch.
If intentional, rerun with --allow-dirty.
EOF
    exit 1
  fi
fi

if ! git show-ref --verify --quiet "refs/heads/$base_branch"; then
  if git show-ref --verify --quiet "refs/remotes/origin/$base_branch"; then
    git checkout -b "$base_branch" "origin/$base_branch" >/dev/null 2>&1
  else
    echo "Base branch '$base_branch' not found locally or on origin." >&2
    exit 1
  fi
fi

current_branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
if [[ "$current_branch" != "$base_branch" ]]; then
  git checkout "$base_branch" >/dev/null 2>&1
fi

slug="$(printf '%s' "$task_name" \
  | tr '[:upper:]' '[:lower:]' \
  | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g')"
if [[ -z "$slug" ]]; then
  slug="task"
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
candidate="${branch_prefix}/${slug}-${timestamp}"
counter=1
while git show-ref --verify --quiet "refs/heads/$candidate"; do
  candidate="${branch_prefix}/${slug}-${timestamp}-${counter}"
  counter=$((counter + 1))
done

git checkout -b "$candidate" >/dev/null 2>&1
echo "Created and switched to task branch: $candidate"
