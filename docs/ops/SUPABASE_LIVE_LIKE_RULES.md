# Supabase Live-like Rules

These rules apply to any remote (non-local) Supabase project.

## Guardrails
- Treat every remote project as live-like unless explicitly verified as non-prod.
- Remote destructive operations are forbidden (no `db reset`, no drop/wipe).
- Only forward, additive, idempotent repair migrations may be applied remotely.

## Required environment gates for remote mutation
All must be true before any remote mutation:
- `ENVIRONMENT` is one of: `staging`, `devlive`
- `CONFIRM_NON_PROD=1`
- `SUPABASE_PROJECT_REF` is present in `docs/ops/SUPABASE_ALLOWLIST.txt`

## Allowed remote actions
- Read-only verification (schema/functions/policies).
- Additive migrations that are forward-compatible and idempotent.

## Forbidden remote actions
- `supabase db reset`, `drop schema`, `drop table`, `truncate` on live-like projects.
- Any change without the explicit gates above.

## Review expectations
- Every remote migration must include `IF NOT EXISTS` or equivalent guards.
- Prefer adding new objects over altering existing behavior.
- If a destructive change is required, implement locally only and document a manual plan.
