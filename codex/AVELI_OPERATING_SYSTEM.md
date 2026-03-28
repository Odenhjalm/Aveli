
# AVELI Operating System v2

Use `aveli_system_manifest.json` together with this file as the operating contract.

SYSTEM_LAWS are defined by:

- Aveli_System_Decisions.md
- aveli_system_manifest.json

These define constraints, not runtime truth.

Unless explicitly overridden by a later task instruction, Codex MUST follow this document.

Codex operates as a system operator, not a guessing assistant.

---

## Purpose

Codex MUST:

- inspect reality without guessing
- separate diagnosis from repair
- avoid hidden fallbacks
- avoid unsafe shortcuts
- avoid environment ambiguity
- avoid mixing runtime truth with implementation intent

Codex MUST NOT:

- infer environment without evidence
- improvise execution commands
- treat repo code as runtime truth
- mix audit mode with mutation mode
- use UI-first debugging

---

## Operating Modes

Codex MUST determine which mode applies before starting work.

### 1. Inspection Mode
Use for:

- audits
- snapshots
- `actual_truth/`
- comparison against laws
- drift mapping
- domain analysis
- mismatch / violation / unknown reporting
- building evidence for future tasks

Inspection Mode is READ-ONLY.

Inspection Mode MUST NOT:

- bootstrap databases unless explicitly required
- mutate data
- apply migrations
- start frontend unless explicitly required
- require E2E auth unless explicitly required
- STOP on ambiguity unless core access is blocked

If ambiguity exists in Inspection Mode:
- classify as `UNKNOWN`, `PARTIAL`, `BLOCKED`, or `DRIFT`
- continue

---

### 2. Execution Mode
Use for:

- implementing code
- replaying baselines
- bootstrapping local DB
- running local backend for task execution
- performing mutations
- running scoped tests
- re-verification after mutation
- cleanup

Execution Mode is MUTATION-CAPABLE.

Execution Mode MUST:
- validate environment before execution
- STOP on ambiguity
- use local-only execution unless explicitly overridden
- log mutations
- verify before and after mutation
- cleanup created entities where applicable

---

## Vector Index Policy (MANDATORY)

Codex MUST treat the vector index as a persistent artifact.

---

### Rule 1 — Existence is authority

If a vector index exists:

- Codex MUST use it
- Codex MUST NOT rebuild it
- Codex MUST NOT question its quality

---

### Rule 2 — Rebuild is explicit only

Codex MAY rebuild the vector index ONLY if:

1. user explicitly requests rebuild
2. index files are missing
3. index is proven corrupted (cannot be read or queried)

---

### Rule 3 — Time-based rebuild is forbidden

Codex MUST NOT:

- rebuild because "it might be outdated"
- rebuild because "repo changed"
- rebuild based on commit count
- rebuild based on assumption

---

### Rule 4 — Quality is NOT a rebuild trigger

Bad search results DO NOT justify rebuild.

Codex MUST instead:

- improve filtering
- improve scoring
- improve extraction

---

### Rule 5 — Rebuild is expensive

Codex MUST treat index rebuild as:

- expensive operation
- last resort
- explicit decision

---

### Rule 6 — Required behavior

If index exists:

- USE it
- DO NOT touch it

If index missing:

- STOP
- request rebuild or build once

---

### Enforcement

If Codex attempts to rebuild index without explicit permission:

STOP: INDEX REBUILD NOT APPROVED

---
## Mandatory Workflow Enforcement

Codex MUST follow `codex/AVELI_EXECUTION_WORKFLOW.md` for all non-trivial work.

If the task affects audit, tasks, implementation, launch readiness, or verification, Codex MUST:

1. follow the workflow phases in order
2. refuse to skip phases
3. refuse implementation before `verified_tasks/` exists
4. refuse launch-readiness claims before Phase 6 passes

If the current prompt conflicts with the workflow:
- STOP
- report the conflict

---
## System Truth Model

Codex MUST interpret truth using the following model:

### SYSTEM_LAWS
Non-negotiable constraints:
- `Aveli_System_Decisions.md`
- `aveli_system_manifest.json`
- explicit later user decisions

### CURRENT_TRUTH
Authoritative runtime reality:
- Supabase project schema
- Supabase project data
- verified production-like runtime facts
- verified active storage/runtime relationships

### EMERGENT_TRUTH
Local implementation candidate:
- local backend
- local database
- repo code
- local MCP-backed runtime
- local baseline replay result

EMERGENT_TRUTH may be cleaner than CURRENT_TRUTH, but is NOT automatically truth.

---

## Truth Interpretation Rules

If sources disagree, resolve them like this:

1. SYSTEM_LAWS
2. CURRENT_TRUTH
3. EMERGENT_TRUTH
4. Logs
5. UI / Playwright

Rules:

- Repo code is NEVER runtime truth by itself
- Local DB is NEVER truth by itself
- Logs never override domain truth
- UI never overrides domain truth
- SQL read does not override MCP if MCP already exposes the same truth reliably

Classify disagreements as:

- `SYSTEM_VIOLATION`
  - CURRENT_TRUTH violates SYSTEM_LAWS

- `DRIFT`
  - EMERGENT_TRUTH differs from CURRENT_TRUTH

- `PREFERRED_DIRECTION`
  - EMERGENT_TRUTH aligns better with SYSTEM_LAWS than CURRENT_TRUTH, but is not yet verified truth

- `UNKNOWN`
  - evidence insufficient

- `BLOCKED`
  - required inspection path unavailable

---

## Core Execution Model

Codex MUST behave as a deterministic operator.

Codex MUST NOT:

- guess database targets
- guess active ports
- guess MCP topology
- guess environment role
- improvise canonical startup commands

Codex MUST:

- follow canonical execution protocols
- use declared authoritative paths first
- classify uncertainty explicitly
- avoid repeated discovery loops

---

## Python Execution Rules

Codex MUST use explicit interpreter paths for repo tooling.

Canonical interpreter split:

- repo/tooling and OpenAI pipeline: `.venv/bin/python`
- backend-specific scripts: `backend/.venv/bin/python`
- semantic-search runtime / MCP search server: `.repo_index/.search_venv/bin/python`

Codex MUST:

- invoke Python through the canonical interpreter for the relevant tool surface
- prefer explicit interpreter paths over PATH discovery
- treat environment readiness as a precondition for execution
- rebuild the vector index only after search-index hygiene rules are in place

Codex MUST NOT:

- rely on shell activation
- use bare `python`
- use dynamic interpreter discovery when the canonical path is known
- continue if the required interpreter, dependency set, or vector index is not ready

If environment readiness fails:

- STOP
- report the exact interpreter, dependency, or index blocker

---

## Local Anchors

These files MAY define parts of local operating baseline, but MUST NOT be trusted without verification.

Candidate anchors:

- `.vscode/mcp.json`
- `ops/env_load.sh`
- `ops/env_validate.sh`
- `ops/verify_all.sh`
- `ops/verify_all_minimal.sh`
- `supabase/migrations/`
- `README.md`

Rules:

- verify existence before use
- verify relevance before relying on them
- do not assume they are correct or current
- repo files are not automatically truth

If anchor verification fails:
- use canonical MCP / runtime / script path if available
- otherwise mark `BLOCKED`

---

## MCP Role Model

Codex MUST use MCP intentionally, not theatrically.

### Primary roles

#### CURRENT_TRUTH / DATA
- `supabase`
  - authoritative data and schema source

#### STRUCTURE
- `repo_index`
  - system structure
  - file inventory
  - path map

#### SEMANTIC
- `semantic_search`
 - PRIMARY tool for:
  - relationship discovery
  - cross-domain connections
  - hidden dependency discovery
SEMANTIC SEARCH RULE:

  Codex MUST use semantic_search before attempting manual repo traversal

#### VALIDATION / RUNTIME
- `aveli-verification`
  - targeted truth checks
- `aveli-media-control-plane`
  - media integrity and media state
- `aveli-logs`
  - worker state and runtime failures
- `aveli-domain-observability`
  - fallback domain inspection

#### OPTIONAL
- `context7`
  - external documentation only
- `playwright`
  - UI only if required
- `figma`
  - design-only context

---

## MCP Authority Order

When multiple MCPs could answer, prefer:

1. `supabase`
2. `aveli-verification`
3. `aveli-media-control-plane`
4. `aveli-logs`
5. `aveli-domain-observability`
6. `context7`
7. `playwright`
8. `figma`

Rules:

- If MCP can answer directly, use MCP
- Do not use logs when verification or Supabase can answer
- Do not use UI when MCP or backend can answer
- MCP is validation layer, not discovery theater

---

## MCP Usage Rules

Codex MUST NOT waste time rediscovering MCP topology when canonical access paths are already defined.

Codex MUST NOT:

- repeatedly list MCP resources without purpose
- probe already verified endpoints repeatedly
- use generic MCP registry discovery as a required precursor to work

If generic MCP registry is incomplete or misconfigured:
- mark registry as `misconfigured`
- continue using canonical repo-defined access paths

If an MCP path fails:
- mark that MCP as `PARTIAL`, `BLOCKED`, or `UNAVAILABLE`
- continue if higher-priority truth sources remain available

---

## Runtime Defaults

Default local runtime:

- Backend: `http://127.0.0.1:8080`
- Frontend: `http://127.0.0.1:3000`
- MCP mode: `local`

Rules:

- no dynamic port guessing
- no mixed environments in Execution Mode
- if mismatch in Execution Mode → STOP
- if mismatch in Inspection Mode → classify and continue if possible

---

## Domain Analysis Order (Inspection Mode)

For each domain, Codex MUST work in this order:

1. Read SYSTEM_LAWS
2. Fetch CURRENT_TRUTH from Supabase
3. Map EMERGENT_TRUTH from repo/local implementation
4. Use semantic search to connect flows and hidden dependencies
5. Use MCP only to validate contradictions or inspect targeted runtime boundaries
6. Write artifacts
7. Move to next domain

Codex MUST NOT:

- interleave unfinished domains
- repeatedly re-analyze completed domains without cause
- start from UI
- start from logs

---

## Evidence Classification

Every important claim MUST be backed by one or more of:

- SYSTEM_LAWS reference
- Supabase result
- repo file evidence
- semantic search evidence
- MCP validation result
- backend API response

Each domain artifact SHOULD classify findings as:

- `aligned`
- `mismatch`
- `drift`
- `violation`
- `unknown`
- `blocked`

---

## Ambiguity Rule

### Inspection Mode
If ambiguity exists:
- mark `UNKNOWN`, `PARTIAL`, or `BLOCKED`
- continue

STOP only if:
- SYSTEM_LAWS unavailable
- CURRENT_TRUTH unavailable
- repo structure unavailable

### Execution Mode
If ambiguity exists:
- STOP

Examples:
- ambiguous DB target
- ambiguous cloud/local env
- missing required schema
- missing required MCP continuity

---

## Canonical Backend Execution Protocol (Execution Mode Only)

Codex MUST follow this exact protocol when starting backend.

### Environment Rules

Codex MUST ensure:

- `DATABASE_URL` is set
- `DATABASE_URL` uses `127.0.0.1`
- `MCP_MODE=local`
- `APP_ENV=dev`

Codex MUST check:

- `FLY_APP_NAME` is NOT set
- `K_SERVICE` is NOT set

If cloud env detected:
- override safely or STOP

### Database Rule

Codex MUST:

- use LOCAL database only
- NEVER use remote DB in Execution Mode unless explicitly instructed

If `DATABASE_URL` is missing or ambiguous:
- STOP

### Startup Command

```bash
cd backend
poetry run uvicorn app.main:app --host 127.0.0.1 --port 8080
````

Codex MUST NOT modify this command unless explicitly instructed.

### Pre-Flight Check

Before starting backend:

* `DATABASE_URL` exists
* `DATABASE_URL` is local
* `MCP_MODE=local`
* no cloud env active

If any fail:

* STOP

### Post-Start Verification

Codex MUST verify:

* `GET /healthz` → `200`
* `GET /readyz` → `200`

MCP endpoints:

* `/mcp/verification`
* `/mcp/logs`
* `/mcp/media-control-plane`
* `/mcp/domain-observability`

Worker health:

* `get_worker_health` → all `ok`

If any fail:

* STOP

---

## Bootstrap Order (Execution Mode Only)

Codex MUST fully bootstrap before mutation work.

1. Load env

   * `ops/env_load.sh`

2. Validate env

   * `ops/env_validate.sh`

3. Run pre-flight validation

4. Start backend

5. Verify backend

6. Start frontend if task requires frontend

7. Verify frontend if task requires frontend

8. Verify MCP continuity

If any required step fails:

* STOP
* no mutation allowed

---

## Auth Model (Execution / E2E Only)

Codex MUST use E2E credentials from `backend/.env` when auth is required for execution.

Flow:

1. Read `E2E_EMAIL` / `E2E_PASSWORD`
2. POST `/auth/login`
3. Extract token
4. Inject token if browser flow is required
5. Verify `/auth/me`

Forbidden:

* guessing credentials
* UI login if API login is enough
* alternative auth flows

If auth fails in required execution path:

* STOP

---

## Verification Order

### Inspection Mode

1. Laws
2. Current truth
3. Emergent truth
4. Semantic connections
5. Targeted MCP validation
6. Artifact write

### Execution Mode

1. Contract
2. Domain state
3. MCP baseline
4. Mutation
5. Re-verify
6. API verify
7. Playwright verify if required
8. Cleanup verify

Rules:

* verify exact invariant
* UI observation is never sufficient verification

---

## Mutation Rules (Execution Mode Only)

* always pre-read
* one mutation plane at a time
* MCP → API → SQL
* SQL last resort
* no blind mutation
* capture before/after evidence

---

## Logging (Execution Mode Only)

Every mutation MUST be logged.

Each log MUST include:

* action
* entity_id
* timestamp
* expected_state
* actual_state
* result

---

## Ledger Consistency Rule

In Execution Mode, Codex MUST maintain a session ledger.

If entity lineage cannot be reconstructed:

* STOP

---

## Cleanup Rules (Execution Mode Only)

Codex MUST:

* delete all created entities unless task explicitly preserves them
* verify deletion

---

## Python Execution

Use:

```bash
poetry run <command>
```

for backend Python execution when operating inside backend environment.

Use the task-declared environment otherwise.

Do not improvise Python executors.

---

## Frontend Runtime

Frontend is NEVER a primary truth source.

### Inspection Mode

* do not start frontend unless task explicitly requires frontend evidence

### Execution Mode

* static build only unless task explicitly overrides
* port 3000
* correct backend target required

---

## Playwright Rules

Use Playwright only when:

* UI verification is explicitly required
* no higher-authority layer can verify the invariant

No hacks.
No UI-first diagnosis.

---

## Process Control (Execution Mode Only)

Codex MUST track all started processes and cleanly terminate them when task scope ends.

---

## Domain-Level Observability Usage

Always frame observations as:

1. expected state
2. actual state
3. failure boundary

Do not confuse absence of evidence with healthy state.

---

## Fallback Order

### Inspection Mode

1. SYSTEM_LAWS
2. Supabase
3. Repo
4. Semantic search
5. MCP validation
6. Backend API
7. Logs
8. UI

### Execution Mode

1. MCP
2. Repo
3. API
4. SQL read
5. SQL write
6. Playwright

---

## Forward Progression Rule

Codex MUST NOT stall.

If one layer is blocked:

* classify blockage
* continue with remaining valid layers if mode allows

---

## Local Execution Mode (Execution Mode Only)

Purpose:
Ensure Codex runs against a safe, local, reproducible candidate database.

### Database Selection Rule

Codex MUST prefer local database:

`postgresql://postgres:postgres@127.0.0.1:54322/aveli_local`

Codex MUST verify required schemas:

* `app.*`
* `auth.*`
* `runtime_media`
* `media_assets`
* `home_player_uploads`
* `livekit_webhook_jobs`

If missing:

* bootstrap baseline

### Local DB Bootstrap

1. Create DB
2. Apply baseline (`0001` → latest accepted slot)
3. Verify schema completeness

### Backend Startup Rule

Codex MUST start backend using local DB.

Worker errors:

* allowed only if non-blocking
* blocking = missing runtime-required tables

If blocking:

* extend baseline, not runtime code

---

## Baseline Replay Contract

A baseline replay is the only valid proof of baseline correctness.

A valid replay MUST include:

1. minimal auth substrate

   * schema `auth`
   * table `auth.users` with required identity surface

2. baseline slots

   * `0001` through latest accepted slot
   * strict order

3. minimal storage substrate if runtime depends on it

   * schema `storage`
   * `storage.objects`
   * `storage.buckets`

---

## Replay Validation Requirements

A replay is NOT valid unless all are true:

* schema applies cleanly
* backend boots successfully
* `/healthz` returns `200`
* `/readyz` returns `200`
* MCP endpoints return `200`

  * `/mcp/logs`
  * `/mcp/verification`
  * `/mcp/media-control-plane`
  * `/mcp/domain-observability`
* worker health reports all `ok`

If any fail:

* baseline is INVALID
* STOP

Baseline must be:

* deterministic
* reproducible from scratch
* aligned with runtime behavior

---

## Constraints

* replay must not rely on pre-existing DB state
* replay must not depend on production services
* replay must not modify accepted baseline slots
* all fixes must be append-only

---

## MCP Continuity Rule

### Inspection Mode

If generic registry is broken but canonical MCP access path works:

* classify registry as `misconfigured`
* continue

### Execution Mode

Required MCP endpoints must verify cleanly.
If unavailable:

* STOP

---

## Test Execution Rule

Only local scoped tests allowed unless task explicitly overrides.

---

## Verification Scope Rule

Verification MUST match task scope only.

Do not escalate into full-system verification unless explicitly required.

---

## Pre-Supabase Push Preparation (Execution Mode Only)

Before any push candidate is considered valid, Codex MUST ensure:

* baseline == runtime
* tests pass
* no schema gaps
* no unresolved blocking drift in target scope

---

## Forbidden Actions

Codex MUST NOT:

* use production DB in Execution Mode
* guess schema
* bypass DB errors
* disable workers to fake green startup
* redefine authorities through convenience code
* silently accept legacy fallbacks as canonical

---

## Local Storage Substrate Rule

If system depends on external storage (`storage.objects`, `storage.buckets`):

* baseline MUST NOT define them as business truth
* local verification MUST provision minimal compatible substrate if runtime depends on them

Codex MUST:

1. detect storage dependency
2. check storage schema presence
3. provision minimal local substrate if required
4. verify workers start cleanly

If storage is missing and required:

* STOP in Execution Mode
* mark `BLOCKED` in Inspection Mode

---

## Final Guarantee

### Inspection Mode

Codex guarantees evidence-based reporting, not mutation safety.

### Execution Mode

All execution MUST occur in:

* local app
* local DB
* local MCP

If any required execution layer diverges:

* STOP

```
