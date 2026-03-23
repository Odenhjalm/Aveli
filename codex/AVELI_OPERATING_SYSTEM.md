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

These repo files define the local operating baseline:

- `.vscode/mcp.json` → registered MCP servers and endpoints
- `ops/env_load.sh` → canonical environment bootstrap
- `ops/env_validate.sh` → environment validation
- `ops/verify_all.sh` → full verification flow
- `ops/verify_all_minimal.sh` → minimal verification flow
- `supabase/migrations/` → canonical schema history
- `README.md` → repo-wide operational conventions

If local anchors and prompt instructions disagree, prefer the repo anchor unless the prompt explicitly overrides it.

---

## Truth Hierarchy

When sources disagree, resolve truth in this order:

1. Repo contracts
   - code
   - schema
   - config
   - migration history
   - MCP configuration

2. Aveli authoritative MCPs
   - `aveli-domain-observability`
   - `aveli-verification`
   - `aveli-media-control-plane`

3. Backend API responses

4. SQL reads of canonical storage state

5. `aveli-logs`

6. Playwright / UI observation

Rules:

- Prefer the highest authoritative layer that can answer the question
- Do not skip directly to UI when MCP or API can answer first
- Do not use logs to overrule domain truth
- Do not use SQL to infer derived behavior if MCP already exposes it
- Do not use UI to discover truth; use UI to verify already-established truth

---

## MCP Stack

### Primary Aveli Operator Stack

- `aveli-domain-observability`
  - domain state
  - lifecycle
  - invariant state
  - runtime truth

- `aveli-verification`
  - structured invariant checks
  - before/after mutation probes

- `aveli-media-control-plane`
  - canonical media truth
  - readiness
  - resolution
  - media lifecycle

- `aveli-logs`
  - execution explanation
  - failures
  - timing
  - worker health

- `playwright`
  - user-path verification
  - render verification
  - browser/network confirmation

### Supporting MCPs

- `supabase`
  - schema inspection
  - SQL read/write when explicitly needed
  - branch/functions/docs as configured

- `context7`
  - third-party package/framework documentation

- `figma`
  - design context and asset extraction

Rules:

- If Aveli exposes a capability through an Aveli MCP, prefer that MCP
- Supporting MCPs do not overrule Aveli runtime truth
- Playwright is a verification layer, not a primary truth source

---

## Runtime Defaults (MANDATORY)

Unless explicitly overridden:

- Backend base URL:
  `http://127.0.0.1:8080`

- Frontend base URL:
  `http://127.0.0.1:3000`

- MCP mode:
  `local`

- Worker expectation:
  enabled when the task requires worker-backed flows

Rules:

- Do NOT resolve runtime dynamically between multiple ports or hosts
- Do NOT trust stale `.env` values over observed local runtime
- Do NOT mix local frontend with production backend unless the task explicitly allows it
- If actual runtime differs from these defaults, verify and report the mismatch before proceeding

---

## Bootstrap Order

For any runtime-affecting task, use this order:

1. Load env
   - `ops/env_load.sh`

2. Validate env
   - `ops/env_validate.sh`

3. Confirm backend:
   - `/healthz = 200`
   - `/readyz = 200`

4. Confirm MCP endpoints:
   - `/mcp/logs`
   - `/mcp/media-control-plane`
   - `/mcp/domain-observability`
   - `/mcp/verification`

5. Confirm frontend:
   - `http://127.0.0.1:3000` returns HTML

6. Confirm auth preconditions if authenticated work is needed

If any required bootstrap step fails:
- STOP
- report blocker
- do not mutate anything

---

## Auth Model (E2E ONLY)

Normal rule:

- Do NOT use `/auth/login` for normal operator work
- Do NOT create users unless the task explicitly requires user provisioning
- Do NOT guess credentials
- Do NOT use reset or recovery flows

E2E exception:

- `/auth/login` is allowed ONLY with:
  - `E2E_EMAIL`
  - `E2E_PASSWORD`

Purpose:

- establish a controlled test session
- support authenticated API verification
- support Playwright verification

Rules:

- E2E credentials are treated as controlled test identity credentials
- Codex MUST NOT modify the E2E user unless the task explicitly allows mutation of the E2E user state
- Codex MUST NOT create replacement users during verification runs
- Auth bootstrap MUST come from API login, not custom browser-only tricks

After login:

- use access token for API
- use access/refresh token for Playwright storage injection
- verify with `/auth/me`

If E2E auth fails:
- STOP
- report auth blocker

---

## Verification Order

Every runtime-affecting task follows this order:

1. Contract verification
2. Domain state verification
3. Verification MCP baseline
4. Mutation
5. Post-mutation verification
6. API boundary verification
7. UI / Playwright verification
8. Cleanup verification

Rules:

- Verification must test the exact invariant changed
- “Clicked around and it looked okay” does NOT count
- If a deterministic verification step does not exist, state the gap explicitly and use the next safest layer

---

## Mutation Rules

Codex MUST mutate conservatively.

Rules:

- No mutation without pre-read
- One authoritative mutation plane per step
- Prefer MCP → API → SQL write
- SQL write is last resort unless task is schema work or tightly scoped repair
- No mutation of production entities for exploratory purposes
- Only test entities are allowed during verification runs unless explicitly stated otherwise
- Capture before/after evidence for every non-trivial mutation
- Do not batch unrelated changes
- Do not mix diagnosis, repair, and cleanup in one unverified jump
- Playwright is NOT the default write plane unless the task is explicitly UI-only

---

## Ledger Consistency Rule

For tasks that create or mutate test entities, Codex MUST maintain a session ledger.

Ledger MUST track:

- session_id
- environment
- backend_url
- frontend_url
- created entity ids
- mutation timestamps
- API calls made
- cleanup outcomes
- protocol notes

Definition of “immediate ledger update”:

After each mutation, ledger MUST be updated:
- before the next API call
- before the next UI interaction
- before polling/waiting
- before navigation/reload

This applies to:
- course creation
- media upload completion
- cover attachment
- save operations
- deletions

Recoverable violation:

- if a mutation happened and the created entity can still be deterministically reconstructed,
  Codex MUST:
  - record it immediately
  - add a `late_ledger_write` note
  - continue only if no ambiguity exists

Hard stop violation:

- if a mutation happened and the created entity cannot be reconstructed deterministically,
  Codex MUST:
  - STOP
  - report protocol violation
  - perform cleanup if safe

Rules:

- Ledger integrity is required
- Ledger recovery is allowed only when reconstruction is deterministic
- Do not sacrifice system verification for an unrecoverable bookkeeping gap

---

## Cleanup Rules

Cleanup is mandatory for verification work.

Codex MUST:

- delete all created courses
- delete all created media
- clear all created cover attachments
- verify deletion via MCP/API/SQL as appropriate

Rules:

- Cleanup must use supported contracts first
- Do not delete outside the tracked artifact set
- Do not mutate unrelated existing data
- If cleanup is incomplete:
  - STOP
  - report leftovers precisely
- If cleanup is partially successful:
  - record what was removed
  - record what remains
  - do not guess-delete

---

## Python Execution

Codex MUST use the repository Python toolchain.

Rules:

- NEVER call `pytest` directly
- NEVER assume global Python
- NEVER assume global test tooling

Always use:

- `poetry run <command>`

Examples:

- tests:
  `poetry run pytest path/to/test_file.py`

- scripts:
  `poetry run python script.py`

- backend:
  `poetry run uvicorn app.main:app`

If `poetry` is unavailable:
- STOP
- report blocker

Do NOT silently fall back to raw `python` or raw `pytest`.

---

## Frontend Runtime (Verification)

For any task requiring UI or Playwright verification:

Frontend MUST:

- run at `http://127.0.0.1:3000`
- use `API_BASE_URL=http://127.0.0.1:8080`
- be a STATIC BUILD

Flutter dev server is NOT allowed for verification.

Rules:

- Do NOT use production frontend
- Do NOT mix frontend/backend environments
- Do NOT proceed to Playwright without valid local frontend

---

## Static Frontend Execution

Build:

`flutter build web --release -o /tmp/aveli-web \
  --dart-define=API_BASE_URL=http://127.0.0.1:8080 \
  --dart-define=FRONTEND_URL=http://127.0.0.1:3000`

Serve with SPA fallback:

`python3 - <<'PY'
import http.server
from pathlib import Path

root = Path('/tmp/aveli-web').resolve()
index = root / 'index.html'

class SPAHandler(http.server.SimpleHTTPRequestHandler):
    def translate_path(self, path):
        path = path.split('?',1)[0].split('#',1)[0]
        resolved = (root / path.lstrip('/')).resolve()
        if not resolved.exists():
            return str(index)
        return str(resolved)

    def log_message(self, format, *args):
        return

http.server.ThreadingHTTPServer(('127.0.0.1', 3000), SPAHandler).serve_forever()
PY`

Validation:

- `http://127.0.0.1:3000` returns HTML
- frontend network calls target `http://127.0.0.1:8080`

If not:
- STOP
- report `frontend bootstrap blocker`

---

## Playwright Rules

Playwright is a verification layer.

Allowed:

- render validation
- network verification
- end-to-end flow verification
- user-visible contract verification

Forbidden:

- auth workarounds
- token bridges
- local HTTP auth servers
- guessed routes
- guessed selectors when deterministic alternatives exist

If UI requires hacks or unsupported workarounds:
- STOP
- report blocker

---

## Playwright Auth Injection

Playwright MUST use the same auth source as API:

1. login via `/auth/login` using E2E credentials
2. inject tokens into browser storage
3. reload app
4. proceed only after authenticated read surface is confirmed

Rules:

- Do not invent alternate auth flows
- Do not print secrets to chat
- Do not rely on UI login when API login already exists

If auth cannot be injected deterministically:
- STOP
- report `playwright auth blocker`

---

## Routing Requirement

Frontend MUST support SPA routing.

Server MUST fallback unknown routes to `index.html`.

If routing is broken:
- STOP
- report `frontend routing blocker`

---

## Domain-Level Observability Usage

`aveli-domain-observability` is the primary runtime diagnosis surface.

Default usage:

- translate bug into domain terms
- identify involved entities
- identify expected invariant
- identify actual invariant
- identify state transition or failure boundary

Rules:

- Prefer domain state over transport noise
- Use logs only after state is known
- If domain state and UI disagree, resolve that discrepancy before mutating

---

## When To Use MCP vs API vs SQL vs UI

Use the smallest layer that is both authoritative and appropriate.

- MCP
  - use for structured state, reasons, verification, controlled domain operations

- API
  - use for backend contract behavior, auth boundaries, route semantics

- SQL read
  - use for canonical row-level proof and schema truth

- SQL write
  - use only for schema work, controlled repair, or explicit setup tasks

- UI / Playwright
  - use only after lower layers are verified

Decision rule:

- If Aveli MCP can answer it, start there
- If the question is about backend contract, use API
- If the question is about stored row state, use SQL read
- If the question is about user-visible behavior after truth is established, use UI

---

## Fallback Order

When the preferred layer cannot answer the question, fall back in this order:

1. Aveli MCP
2. Repo scripts / local contracts
3. Backend API
4. SQL read
5. SQL write / migration
6. Playwright
7. Human escalation

Rules:

- Move downward only when higher layer is unavailable or insufficient
- Record the fallback reason
- Never jump straight to UI when stronger layers exist

---

## Final Rule

If any layer:

- diverges from DB truth without explanation
- overrides canonical identity
- fails cleanup
- leaves unrecoverable ledger ambiguity

→ system is NOT verified

No exceptions.