# Repo Hygiene Policy

## Purpose
Keep the repository clean and deterministic by preventing local caches, generated artifacts, and secrets from entering version control.

## Non-negotiables
- Work only in a clean worktree (never in /home/oden/Aveli).
- Never commit secrets or live credentials. Keep .env files local and ignored.
- Do not track generated artifacts or tool caches.

## Must never be tracked
- Supabase CLI temp/cache: `supabase/.temp/`
- VS Code workspace extensions list: `.vscode/extensions.json`
- Local environment files: `.env`, `.env.*`, `.envrc`
- Build outputs and caches: `node_modules/`, `.next/`, `.dart_tool/`, `build/`, `dist/`, `__pycache__/`, `.pytest_cache/`

## Local-only files
- Use `.env.local` or `.env.*.local` for private overrides.
- Keep tooling caches in their default locations; they should be ignored by `.gitignore`.

## If a tool writes to tracked files
1. Revert the change immediately.
2. Decide whether the file should be ignored; if so, update `.gitignore`.
3. Re-run `./ops/hygiene_check.sh` before committing.

## Enforcement
- Run `./ops/hygiene_check.sh` before every commit.
- Enable the pre-commit hook once per clone:
  ```bash
  git config core.hooksPath .githooks
  ```

## Clean worktree rule for automation
Automation (Codex, scripts, CI) must run only in a clean worktree. If the working tree is dirty, create a new worktree and proceed there.
