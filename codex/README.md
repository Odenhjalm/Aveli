# Codex - Struktur och Arbetsflode

## Struktur
```text
codex/
  prompts/
    task.feature.md
    task.fix.md
  tasks/
    EXAMPLES.md
  scripts/
    start-task-branch.sh
    guard-task-branch.sh
    install-task-guardrails.sh
.githooks/
  pre-commit
  pre-push
```

## Task Guardrail (Obligatorisk)
1. Installera guardrails en gang per klon:
```bash
./codex/scripts/install-task-guardrails.sh
```
2. Starta varje ny uppgift med en ny branch:
```bash
./codex/scripts/start-task-branch.sh "<task-name>"
```
3. Commits och push blockeras pa skyddade brancher (`main`, `master`, `develop`, `dev`, `production`, `release`).

## Manuell Patch-Applicering
```bash
git apply --whitespace=fix patch.diff
git add -A
git commit -m "AI: apply patch"
git push
```
