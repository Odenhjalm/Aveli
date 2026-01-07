# Aveli Dev Workflow Contract

Goal: Keep development deterministic and safe. No surprises, no secret leaks, no “it probably works” pushes.

Rules

1. Never work directly in `/home/oden/Aveli` when making changes.
   - Use a clean ephemeral git worktree under `/home/oden/worktrees/<task>-<timestamp>`.
2. No secrets printed. No env files committed. Never modify `/home/oden/Aveli/backend/.env`.
3. `docs/verify/LAUNCH_READINESS_REPORT.md` is opt-in only.
   - It may only be written if `VERIFY_WRITE_REPORT=1` is set.
4. Codex creates a new branch for each task, runs the full verification gate(s), and pushes only if gates pass.
5. Oden merges only after reviewing:
   - A diff and a clear explanation of changes.
   - PASS outputs from Codex.

Standard Gate

1. Baseline Verification:
   - `VERIFY_WRITE_REPORT=0 APP_ENV=development ./verify_all.sh`
2. Overlay Verification (if test overlay exists):
   - `VERIFY_WRITE_REPORT=0 APP_ENV=development BACKEND_ENV_OVERLAY_FILE=/home/oden/Aveli/backend/test.env ./verify_all.sh`

Deliverables from Codex

- Branch pushed after successful verification.
- Exact commands run + PASS output.
- Short explanation of files changed and why.
- Any risks/assumptions noted during implementation.

Oden’s Role After Codex Deliverables

1. Review the diff and commit messages.
2. Verify PASS outputs.
3. Merge into `fix/mvp-stabilization` (or `main` when ready).
4. Rerun verify tests after merge.
5. Push final changes.
