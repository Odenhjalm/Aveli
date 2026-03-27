# AVELI Operating System

Use aveli_system_manifest.json as primary system truth.

---

## Purpose

This document defines the deterministic operating contract for Codex inside Aveli.

Unless explicitly overridden by a later task instruction, Codex MUST follow this document.

Codex operates as a system operator, not a guessing assistant.

Principles:

- No guessing
- No hidden fallbacks
- No unsafe shortcuts
- No mixing diagnosis and repair without evidence
- No UI-first debugging
- No environment ambiguity

---

## Core Execution Model (ADDED)

Codex MUST behave as a deterministic operator.

Codex MUST NOT:

- infer environment
- guess database targets
- improvise execution commands

Codex MUST:

- follow canonical execution protocols
- validate environment before execution
- STOP on ambiguity

---

## Local Anchors

These files MAY define parts of the local operating baseline, but MUST NOT be trusted without verification.

Candidate anchors:

- `.vscode/mcp.json`
- `ops/env_load.sh`
- `ops/env_validate.sh`
- `ops/verify_all.sh`
- `ops/verify_all_minimal.sh`
- `supabase/migrations/`
- `README.md`

Rules:

- Codex MUST verify existence before use
- Codex MUST verify relevance before relying on them
- Codex MUST NOT assume scripts are correct or up-to-date
- Repo files are NOT automatically truth — only verified behavior is truth

If anchor verification fails:
- fallback to MCP or runtime inspection

---

## Truth Hierarchy

When sources disagree, resolve truth in this order:

1. Repo contracts
2. Aveli MCPs
3. Backend API
4. SQL read
5. Logs
6. UI / Playwright

Rules:

- Always prefer the highest authoritative layer
- Never start from UI
- Logs never override domain truth
- SQL is not used if MCP already exposes truth

---

## MCP Stack (MANDATORY)

Codex MUST actively use MCP as primary inspection layer.

### Aveli MCPs (PRIMARY)

- `aveli-domain-observability`
- `aveli-verification`
- `aveli-media-control-plane`
- `aveli-logs`

### Supporting MCPs

- `supabase`
- `context7`
- `playwright`
- `figma`

Rules:

- If MCP can answer → MUST use MCP
- Never skip MCP for repo/API
- UI is ALWAYS last

---

## Runtime Defaults (MANDATORY)

- Backend: `http://127.0.0.1:8080`
- Frontend: `http://127.0.0.1:3000`
- MCP mode: `local`

Rules:

- No dynamic port guessing
- No mixed environments
- If mismatch → STOP and report

---

## 🔥 CANONICAL BACKEND EXECUTION PROTOCOL (NEW — CRITICAL)

Codex MUST follow this exact protocol when starting backend.

### Environment Rules

Codex MUST ensure:

- DATABASE_URL is set
- DATABASE_URL uses 127.0.0.1 (local DB)
- MCP_MODE=local
- APP_ENV=dev

Codex MUST check:

- FLY_APP_NAME is NOT set
- K_SERVICE is NOT set

If any cloud env detected:
→ MUST override or STOP

---

### Database Rule

Codex MUST:

- Use LOCAL database ONLY
- NEVER use remote DB unless explicitly instructed

If DATABASE_URL is missing or ambiguous:
→ STOP

---

### Startup Command (CANONICAL)

cd backend
poetry run uvicorn app.main:app --host 127.0.0.1 --port 8080


Codex MUST NOT modify this command.

---

### Pre-Flight Check (MANDATORY)

Before starting backend:

- DATABASE_URL exists
- DATABASE_URL is local
- MCP_MODE=local
- No cloud env active

If any fail:
→ STOP

---

### Post-Start Verification (MANDATORY)

Codex MUST verify:

- GET /healthz → 200
- GET /readyz → 200

MCP endpoints:

- /mcp/verification
- /mcp/logs
- /mcp/media-control-plane
- /mcp/domain-observability

Worker health:

- get_worker_health → all "ok"

If any fail:
→ STOP

---

## Bootstrap Order (HARD CONTRACT)

Codex MUST fully bootstrap before any work.

1. Load env
   `ops/env_load.sh`

2. Validate env
   `ops/env_validate.sh`

3. Run pre-flight validation (NEW)

4. Start backend

5. Verify backend

6. Start frontend (STATIC ONLY)

7. Verify frontend

8. Verify MCP endpoints

If ANY step fails:
- STOP
- no mutation allowed

---

## Auth Model (E2E ONLY)

Codex MUST use E2E credentials from `backend/.env`.

Flow:

1. Read E2E_EMAIL / E2E_PASSWORD
2. POST `/auth/login`
3. Extract token
4. Inject into browser
5. Verify `/auth/me`

Forbidden:

- guessing credentials
- UI login
- alternative auth flows

If auth fails:
- STOP

---

## Verification Order

1. Contract
2. Domain state
3. MCP baseline
4. Mutation
5. Re-verify
6. API verify
7. Playwright verify
8. Cleanup verify

Rules:

- Must verify exact invariant
- UI observation ≠ verification

---

## Mutation Rules

- Always pre-read
- One mutation plane at a time
- MCP → API → SQL
- SQL last resort
- No blind production mutation
- Capture before/after evidence

---

## Logging (MANDATORY)

Every mutation MUST be logged.

Each log MUST include:

- action
- entity_id
- timestamp
- expected_state
- actual_state
- result

---

## Ledger Consistency Rule

Codex MUST maintain session ledger.

If entity cannot be reconstructed:
→ STOP

---

## Cleanup Rules (STRICT)

Codex MUST:

- delete all created entities
- verify deletion

---

## Python Execution

Always use:

- `poetry run <command>`

---

## Frontend Runtime (MANDATORY)

- static build only
- port 3000
- correct backend

---

## Playwright Rules

- real flows only
- no hacks

---

## Process Control (MANDATORY)

Codex MUST track all processes.

---

## Domain-Level Observability Usage

Always:

1. expected state
2. actual state
3. failure boundary

---

## Fallback Order

1. MCP
2. Repo
3. API
4. SQL read
5. SQL write
6. Playwright

---

## Forward Progression Rule

Codex MUST NOT stall.

---

## Final Rule

If any layer:

- diverges from DB
- breaks identity
- fails cleanup

→ system is NOT verified

---

## Local Execution Mode (MANDATORY FOR TASK EXECUTION)

Purpose:
Ensure Codex always runs against a safe, local, fully aligned database.

---

### Database Selection Rule

Codex MUST:

1. Prefer local database:
   postgresql://postgres:postgres@127.0.0.1:54322/aveli_local

2. Verify required schemas:

- app.*
- auth.*
- runtime_media
- media_assets
- home_player_uploads
- livekit_webhook_jobs

If missing:
→ bootstrap baseline

---

### Local DB Bootstrap

1. Create DB
2. Apply baseline (0001 → latest slot)
3. Verify schema completeness

---

### Backend Startup Rule

Codex MUST start backend using local DB.

Worker errors:

- Allowed only if non-blocking
- Blocking = missing tables used in runtime

If blocking:
→ extend baseline (NOT runtime code)

---

---

## BASELINE REPLAY CONTRACT

A baseline replay is the only valid method of proving baseline correctness.

A valid replay MUST include:

1. minimal auth substrate
   - schema auth
   - table auth.users (id required)

2. baseline slots
   - 0001 through latest accepted slot
   - applied in strict order

3. minimal storage substrate IF required by runtime
   - schema storage
   - storage.objects
   - storage.buckets
   - only if runtime queries depend on them

---

## REPLAY VALIDATION REQUIREMENTS

A replay is NOT valid unless ALL conditions are met:

- schema applies cleanly (no errors)
- backend boots successfully
- /healthz returns 200
- /readyz returns 200
- MCP endpoints respond (200):
  - /mcp/logs
  - /mcp/verification
  - /mcp/media-control-plane
  - /mcp/domain-observability
- worker health surface reports all "ok"

---

## FAILURE RULE

If any validation step fails:

  baseline is INVALID
  execution MUST STOP
  baseline must be fixed before proceeding

Ensure baseline is:

- deterministic
- reproducible from scratch
- aligned with runtime behavior

---

## CONSTRAINTS

- replay must not rely on pre-existing DB state
- replay must not depend on production services
- replay must not modify accepted baseline slots
- all fixes must be append-only (new slots)

---
### MCP Continuity Rule

Codex MUST verify MCP endpoints.

If unavailable:
→ STOP

---

### Test Execution Rule

Only local scoped tests allowed.

---

### Verification Scope Rule

Must match task scope only.

---

### Pre-Supabase Push Preparation

Codex MUST ensure:

- baseline == runtime
- tests pass
- no schema gaps

---

### Forbidden Actions

Codex MUST NOT:

- use production DB
- guess schema
- bypass DB errors
- disable workers

---

LOCAL STORAGE SUBSTRATE RULE

If system depends on external storage (storage.objects, storage.buckets):

- Baseline MUST NOT define these tables
- Local verification MUST provision minimal compatible schema

Codex MUST:

1. Detect storage dependency
2. Check presence of storage schema
3. If missing:
   → provision minimal local substrate
4. Verify workers start cleanly

If storage is missing and not provisioned:
→ STOP

---

### Final Guarantee

All execution MUST occur in:

local app + local DB + local MCP

If any layer diverges:
→ STOP