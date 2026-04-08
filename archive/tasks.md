# AVELI Cleanroom Rebuild – Task Tracker

This document mirrors the mandated rebuild scope so we can track progress end-to-end. Each phase rolls up into the single objective: Supabase-first, secure, unified stack.

## Phase 0 — Groundwork
- [x] Enumerate repository structure (`tree -a`).
- [x] Enumerate Supabase schema + current RLS status via MCP.
- [x] Produce initial rebuild plan and get confirmation to proceed.

## Phase 1 — Secrets & Repo Hygiene
- [ ] Remove `.env` and other secret-bearing files from git history; expand `.gitignore`.
- [ ] Mint new secrets (JWT, Stripe, LiveKit, Supabase) and expose **only** placeholders in `.env.example` / `.env.docker.example`.
- [ ] Audit repo for hard-coded keys (docs, logs, scripts) and scrub them.
- [ ] Ensure Docker / tooling never implicitly load `.env` (require explicit env-files/vars).

## Phase 2 — Single Source of Truth for Schema
- [x] Delete `database/` and `backend/migrations/sql/` folders (already staged for removal, finalize).
- [x] Confirm via MCP that no legacy schemas/tables remain; drop any stragglers.
- [ ] Document canonical workflow: MCP SQL → `supabase/migrations/**` → snapshot.

## Phase 3 — Supabase Schema Alignment & RLS
- [x] Diff live schema vs repo migrations; capture drift report.
- [x] Enable RLS on every `app.*` table; define policies for student/teacher/admin flows.
- [x] Write new migrations reflecting the fixes (incl. comments removal, triggers, helpers).
- [ ] Export fresh `supabase/security_definer_export.sql` + `supabase/schema.sql` snapshot.
- [ ] Record executed MCP SQL in final report.

## Phase 4 — Backend & QA Hardening
- [ ] Point backend config exclusively to Supabase (remove local Postgres defaults) and wire secrets.
- [ ] Ensure `/api/billing` & related routes match QA expectations; refactor services if needed.
- [ ] Update `scripts/qa_teacher_smoke.py` to new endpoints and edge cases.
- [ ] Add/extend pytest coverage for `/healthz`, `/readyz`, billing, membership, storage flows.
- [ ] Align backend dependency management (Poetry, linting) with new reality.

## Phase 5 — Tooling, Docker, CI
- [ ] Rewrite `.github/workflows/flutter.yml` to: apply Supabase migrations, run backend tests, start backend, run QA smoke, run Flutter tests.
- [ ] Simplify `Makefile` to working targets only (backend dev/test, supabase migrate, QA, docker up/down).
- [ ] Update `docker-compose.yml` to be Supabase-aware, no local Postgres, env-driven secrets, working stack on `docker compose up`.

## Phase 6 — Documentation Refresh
- [ ] Rewrite `README.md`, `backend/README.md`, `docs/local_backend_setup.md`, `Inför lansering.md` (Supabase-first instructions, OS coverage, release checklist with DONE/NOT DONE).
- [ ] Remove or archive conflicting docs (`starta_backend.md`, legacy Postgres guides, dead checklists) or rewrite them to match the new flow.

## Phase 7 — Dead Code & Cleanup
- [ ] Delete unused scripts, assets, archived DB dumps, and redundant directories.
- [ ] Regenerate Flutter/web env integration files to reference new config.
- [ ] Confirm repo is free of caches/binaries before final handoff.

## Reporting & Deliverables
- [ ] For every modified file: include the **full file** content in the final response.
- [ ] For deletions: list under `FILES REMOVED`.
- [ ] For Supabase changes: capture exact SQL executed via MCP.
- [ ] Provide verification steps (tests run, docker compose up) in final summary.
