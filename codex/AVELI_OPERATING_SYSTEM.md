# AVELI Operating System

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

The default operating loop is:

1. Bootstrap environment
2. Establish truth
3. Run baseline verification
4. Apply minimal safe mutation
5. Re-verify the exact invariant
6. Cleanup
7. Report evidence, outcome, and residual risk

Manual exploration is not verification.
UI symptoms are not root truth.

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

## Bootstrap Order (HARD CONTRACT)

Codex MUST fully bootstrap before any work.

1. Load env
   `ops/env_load.sh`

2. Validate env
   `ops/env_validate.sh`

3. Start backend if needed
   `poetry run uvicorn app.main:app --host 127.0.0.1 --port 8080`

4. Verify backend
   - `/healthz = 200`
   - `/readyz = 200`

5. Start frontend (STATIC ONLY)

   Kill existing:
   - terminate process on port 3000

   Build:
flutter build web --relese-o /tmp/aveli-web
--dart-define=API_BASE_URL=http://127.0.0.1:8080/
--dart-define=FRONTEND_URL=http://127.0.0.1:3000/
--dart-define=SUPABASE_URL=https://aiftpfyrqjhstcnblyhb.supabase.co
--dart-define=SUPABASE_ANON_KEY=sb_publishable_BZydrmej9Wr20eKsAD6wpw_rzyvMWGl
--dart-define=STRIPE_PUBLISHABLE_KEY=pk_live_51ST1rjRZyaYOU0ia8oBtklEM0BNbNUAMSN0KgX8s8sDtTbWnob0c6yG97XRgTkPw5RRYpANrGnL8ff8dYGCMCsCo00aOCDoAWp
--dart-define=OAUTH_REDIRECT_WEB=http://localhost:3000/auth/callback



Serve (SPA):
- Python server with index.html fallback

6. Verify frontend
- returns HTML
- calls correct backend

7. Verify MCP endpoints

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

Timing:

- before → expected
- during → action
- after → result

No logging → no mutation.

---

## Ledger Consistency Rule

Codex MUST maintain session ledger:

- session_id
- environment
- created entities
- mutations
- timestamps
- cleanup status

Ledger MUST update after EVERY mutation.

If entity cannot be reconstructed:
- STOP

---

## Cleanup Rules (STRICT)

Codex MUST:

- delete all created entities
- verify deletion
- log results

If anything remains:
- STOP and report IDs

Codex MUST assume production safety always.

---

## Python Execution

Always use:

- `poetry run <command>`

Never:

- raw python
- raw pytest

If poetry missing:
- STOP

---

## Frontend Runtime (MANDATORY)

Frontend MUST:

- run on `127.0.0.1:3000`
- be STATIC BUILD
- use correct backend

Flutter dev server is FORBIDDEN.

---

## Static Frontend Execution

Build + serve via SPA fallback (index.html).

Validation:

- HTML loads
- correct API target

If not:
- STOP

---

## Playwright Rules

Allowed:

- render verification
- network verification
- E2E flow

Forbidden:

- auth hacks
- guessed selectors
- fake flows

---

## Playwright Auth Injection

Must:

1. login via API
2. inject token
3. reload
4. verify authenticated state

If fails:
- STOP

---

## Process Control (MANDATORY)

Codex MUST track all processes:

- frontend
- backend
- python
- playwright

Rules:

- capture PID/port
- store in ledger
- kill on cleanup
- verify termination

If process remains:
- STOP

---

## Domain-Level Observability Usage

Always:

1. expected state
2. actual state
3. failure boundary

Logs are secondary.

---

## When To Use MCP vs API vs SQL vs UI

- MCP → first
- API → contract
- SQL → storage truth
- UI → last

---

## Fallback Order

1. MCP
2. Repo
3. API
4. SQL read
5. SQL write
6. Playwright

Must log fallback reason.

---

## Forward Progression Rule

Codex MUST NOT stall.

If blocked:

1. fallback to next layer
2. log uncertainty
3. continue safely

STOP only if:

- unsafe mutation
- unknown identity
- cleanup impossible

---

## Final Rule

If any layer:

- diverges from DB
- breaks identity
- fails cleanup

→ system is NOT verified