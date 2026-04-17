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
- mix generate, execute, and confirm modes
- use UI-first debugging

---

## Task Input Model

Every execution MUST start with a task.

Task defines:

- scope
- retrieval queries
- evaluation criteria

No system operation may run without an explicit task context.

Every run MUST begin with:

`input(task, mode)`

---

## Canonical Task-Driven Pipeline

Canonical pipeline:

`input(task, mode) -> ingestion -> index -> retrieval -> evidence -> contract -> verification`

Stage responsibilities:

- `input(task, mode)` binds explicit task context and explicit mode
- `ingestion` loads only the authoritative inputs required by the task
- `index` binds retrieval to the active canonical index under vector index policy
- `retrieval` executes task-scoped retrieval only
- `evidence` produces canonical, traceable evidence from retrieval output
- `contract` diffs canonical evidence against canonical truth
- `verification` is the mode-driven final stage

Rules:

- retrieval MUST be task-scoped
- evidence MUST remain canonical
- contract MUST always precede verification
- no phase may duplicate another phase's responsibility
- no legacy or alternative flow is allowed

---

## Canonical Mutation and Observability Boundary

OBSERVABILITY IS NOT A WRITE CONSTRAINT.

Codex MUST distinguish canonical system mutations from non-canonical
observability writes before deciding whether a task violates read-only,
no-code, audit, generate, or confirm constraints.

### Canonical system mutations

Canonical system mutations are authoritative writes that can change system
truth, runtime truth, accepted baseline, contracts, source code, index
authority, accepted task artifacts, or persisted domain state.

Canonical system mutations include writes to:

- source code
- accepted baseline slots or baseline manifests
- authoritative contracts
- SYSTEM_LAWS or manifest authority
- active index authority artifacts
- database, storage, or runtime domain truth
- task artifacts that become authoritative execution input

Canonical system mutations are forbidden in read-only, no-code audit, generate,
and confirm scopes unless an explicit later rule requires a specific
materialized artifact for that mode.

### Non-canonical observability writes

Non-canonical observability writes are logging, tracing, debug artifacts,
telemetry, and local cache writes that do not define authority.

Non-canonical observability writes:

- are non-authoritative
- MUST NOT create or redefine system truth
- MUST NOT define corpus membership, ranking, prompt content, contract truth,
  runtime truth, baseline truth, or domain state
- MUST NOT be used as the only proof of a canonical invariant
- MUST NOT block execution merely because they are filesystem writes
- MUST remain isolated from canonical authority paths

If a tool performs side-effect logging, tracing, telemetry, debug output, or
local cache writes, Codex MUST still execute the tool when the tool is otherwise
required by the task.

If an observability write fails, Codex MUST classify the observability surface
as `PARTIAL` or `BLOCKED` and continue when canonical retrieval output or other
required canonical evidence remains available. Observability write failure MUST
NOT be treated as a canonical mutation violation.

### Retrieval in no-code audit

Retrieval tools MUST always be executable in NO-CODE AUDIT or policy-only audit
scopes.

Retrieval MUST NOT be skipped because the retrieval tool writes logs, traces,
debug artifacts, telemetry, or local cache files as non-canonical side effects.

If retrieval is skipped due to observability side effects:

STOP: RETRIEVAL INCORRECTLY BLOCKED BY NON-CANONICAL OBSERVABILITY

### Read-only interpretation

When this OS says read-only, no-code, no mutation, or no system state mutation,
the prohibition applies to canonical system mutations only.

Non-canonical observability writes are not canonical system mutations and are
not a write constraint.

---

## Execution Modes

Codex MUST determine which mode applies before starting work.

### MODE: generate

Use for:

- contract diff review
- task derivation
- evidence-backed task generation
- building task-scoped retrieval inputs

Generate mode is READ-ONLY.

Purpose:

- produce tasks from contract diff

Output:

- deterministic task set

Generate mode MUST:

- not assume implementation
- not mutate system state
- classify ambiguity as `UNKNOWN`, `PARTIAL`, `BLOCKED`, or `DRIFT`
- continue unless core access is blocked

GENERATE MODE OUTPUT LAW:

- Generated tasks MUST be written to:
  actual_truth/DETERMINED_TASKS/

- Tasks MUST follow:
  - TYPE
  - DEPENDS_ON
  - deterministic structure

- Generated tasks become the next valid input(task) for execution

- If tasks are not materialized:
  → STOP

---

### MODE: execute

Use for:

- task-scoped implementation validation
- contract-bound runtime checks
- scoped mutation when task execution requires it
- running scoped tests
- cleanup

Execute mode is MUTATION-CAPABLE.

Purpose:

- validate implementation against contract

Output:

- pass/fail per task

Execute mode MUST:

- use canonical evidence
- not reinterpret contracts
- validate environment before execution
- STOP on ambiguity
- use local-only execution unless explicitly overridden
- log mutations
- verify before and after mutation
- cleanup created entities where applicable

---

### MODE: confirm

Use for:

- final truth assertion
- canonical state confirmation
- task-complete system confirmation

Confirm mode is READ-ONLY unless a later rule explicitly requires runtime startup for verification.

Purpose:

- assert system matches canonical truth

Output:

- PASS or FAIL

Confirm mode MUST:

- fail on any deviation
- not produce new tasks
- not mutate system state
- use canonical evidence
- not reinterpret contracts
- STOP on ambiguity

Confirm mode inherits execute-mode environment, authority, and verification constraints unless a later rule is explicitly mutation-only.

---

## Mode Enforcement

- Mode MUST be explicit for every run
- Mode MUST NOT change during execution
- Mixing modes in one run is forbidden

---

DEPENDENCY LAW:

Before a task is generated, modified, executed, or confirmed:

1. A DEPENDENCY AUDIT MUST be performed.

2. Each task MUST declare:

   TYPE:
   - OWNER (creates truth)
   - GATE (validates truth)
   - AGGREGATE (system-wide validation)

   DEPENDS_ON:
   - explicit list of task IDs

3. A task is VALID only if:
   - all DEPENDS_ON tasks produce the required truth
   - no dependency is implicit
   - no dependency points to a later undefined task

4. TASK CREATION IS FORBIDDEN WITHOUT:
   - TYPE classification
   - explicit DEPENDS_ON mapping

If missing:
→ TASK IS INVALID
→ STOP

---

EXECUTION LAW:

Execution order MUST be derived from dependency graph:

- perform dependency audit
- build DAG
- perform topological sort

FORBIDDEN:

- manual ordering
- domain-based ordering
- “logical grouping”

---

GATE TASK RULE:

If a task requires truth not yet produced:

IF:

- truth is owned by a later task
  → task MUST be marked DEFERRED

IF:

- current task is the owner of the missing truth
  → STOP

---

REPLAY LAW:

Deferred tasks MUST be re-executed only after their dependencies are satisfied.

---

VIOLATION:

If Codex creates or executes a task without dependency audit:
→ STOP
→ invalidate execution

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

`DO NOT touch it` means Codex MUST NOT mutate authoritative index artifacts or
use a query path that rebuilds, repairs, promotes, or redefines index authority.
Isolated non-canonical observability writes, such as retrieval traces or health
telemetry, do not touch index authority and MUST NOT block retrieval execution.

If index missing:

- STOP
- request rebuild or build once

---

### Temporary Rule 6A - Retrieval During RTX Outage

This temporary operating rule is active until:

- the RTX-capable machine is back in service
- semantic indexing is explicitly re-approved by the user

During this period:

- GitHub code search is the default retrieval surface for repository search
- absence of an approved local semantic index artifact MUST NOT trigger local index rebuild
- local index rebuild is forbidden
- remote GPU provisioning is forbidden
- background indexing services are forbidden
- semantic indexing is deferred
- semantic indexing may be reconsidered only after documented retrieval failures across multiple system layers and explicit user re-approval

---

### Rule 7 - INDEX ENVIRONMENT LAW

All index-related tasks MUST:

- use .repo_index/.search_venv/Scripts/python.exe
- execute retrieval/indexing only through the controller-approved Windows path

Codex MUST NOT:

- use system python
- use .venv
- use the legacy Linux search virtualenv interpreter path
- install dependencies ad hoc
- attempt environment discovery

If environment is missing or inconsistent:
→ STOP

PYTHON EXECUTION LOCK

For index pipeline:

- ONLY allowed interpreter:
  .repo_index/.search_venv/Scripts/python.exe

Violation:

- any use of "python" without explicit path
- any use of wrong venv
- any use of the legacy Linux search virtualenv interpreter path

---

### Enforcement

If Codex attempts to rebuild index without explicit permission:

STOP: INDEX REBUILD NOT APPROVED

---

VIEW CONTRACT ENFORCEMENT

If a task targets a specific view:

- retrieval MUST be constrained by that view contract
- forbidden sources MUST be excluded at retrieval stage
- evidence outside view scope MUST be discarded

Violation:

- evidence contains fields outside view contract

---

TASK MATERIALIZATION ENFORCEMENT

After generate mode:

- generated tasks MUST be:
  1. written to actual_truth/DETERMINED_TASKS/
  2. immediately eligible as next input(task)

Execution MUST NOT proceed without materialized tasks

Violation:

- tasks exist only in output, not in repo

---

## Mandatory Workflow Enforcement

Codex MUST follow `codex/AVELI_EXECUTION_WORKFLOW.md` for all non-trivial work.

If the task affects ingestion, index, retrieval, evidence, contract, or verification, Codex MUST:

1. require explicit `input(task, mode)`
2. follow the canonical pipeline in exact order
3. refuse contract-bypassing verification
4. refuse legacy or alternative flow

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

- repo/tooling, OpenAI pipeline, and canonical backend startup via `backend.bootstrap.run_server`
  - Windows: `.\.venv\Scripts\python.exe`
  - Linux: `./.venv/bin/python`
- backend-specific scripts under `backend/scripts/`
  - Windows: `.\backend\.venv\Scripts\python.exe`
  - Linux: `./backend/.venv/bin/python`
- semantic-search runtime / MCP search server
  - Windows: `.\.repo_index\.search_venv\Scripts\python.exe`
  - No Linux interpreter path is canonical for retrieval/indexing.

Codex MUST:

- invoke Python through the canonical interpreter for the relevant tool surface
- use explicit interpreter path for backend startup
- prefer explicit interpreter paths over PATH discovery
- treat environment readiness as a precondition for execution
- rebuild the vector index only after search-index hygiene rules are in place

Codex MUST NOT:

- rely on shell activation
- use bare `python`
- use `poetry run`
- call `uvicorn` directly for backend startup
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

## MCP Bootstrap Law

`ops/mcp_bootstrap_gate.ps1` is the mandatory local bootstrap gate for
MCP/backend-dependent work.

Codex MUST run `ops/mcp_bootstrap_gate.ps1` and confirm PASS in the current
session before:

- MCP usage
- backend verification
- backend testing that depends on MCP or local backend runtime
- local audit flows that rely on MCP tools
- Codex tasks that assume backend or MCP availability
- tasks that rely on local MCP endpoints
- tasks that rely on stdio MCP tools being callable from the active environment

Trust boundary:

- MCP availability is NOT assumed from `.vscode/mcp.json` presence alone
- backend availability is NOT assumed from prior session state
- local testing that depends on MCP/backend MUST first pass the bootstrap gate
- MCP and backend runtime are UNTRUSTED until the bootstrap gate passes in the
  current session

Fail-closed rule:

- if `ops/mcp_bootstrap_gate.ps1` fails, STOP
- do not proceed into MCP-backed audits, backend verification, local integration
  testing, implementation, or verification steps that depend on MCP/backend
  runtime
- report the failing checks clearly

Evidence requirement:

- Codex MUST report that `ops/mcp_bootstrap_gate.ps1` was run
- Codex MUST report PASS or FAIL before proceeding into MCP/backend-dependent
  work
- Codex MUST NOT imply MCP/backend readiness without current-session evidence
  from the bootstrap gate

Prompt-generation enforcement:

- any generated Codex prompt or task scaffold that involves MCP usage, backend
  verification, local backend testing involving backend runtime, or MCP-based
  audits MUST insert the standard `MCP BOOTSTRAP BLOCK` before audit,
  verification, implementation, or testing instructions
- the reusable prompt block is `codex/prompts/MCP_BOOTSTRAP_BLOCK.md`
- the block is subordinate to this OS law and MUST NOT redefine bootstrap
  authority
- generated prompts MUST NOT mark the block optional for MCP/backend-dependent
  work

This rule is fail-closed operating policy. It does not change truth order,
workflow order, MCP authority order, or the requirement that contract precedes
verification.

---

## Runtime Defaults

Default local runtime:

- Backend: `http://127.0.0.1:8080`
- Frontend: `http://127.0.0.1:3000`
- MCP mode: `local`

Rules:

- no dynamic port guessing
- no mixed environments in execute or confirm mode
- if mismatch in execute or confirm mode → STOP
- if mismatch in generate mode → classify and continue if possible

---

## Task-Scoped Analysis Order (Generate Mode)

For each task, Codex MUST work in this order:

1. Read SYSTEM_LAWS and the active contract relevant to the task
2. Fetch CURRENT_TRUTH required by the task
3. Map EMERGENT_TRUTH only within task scope
4. Use semantic search to connect task-specific flows and hidden dependencies
5. Use MCP only to validate contradictions or inspect targeted runtime boundaries
6. Write task-scoped artifacts
7. Move to next task

Codex MUST NOT:

- interleave unfinished task scopes
- repeatedly re-analyze completed task scopes without cause
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

Each task artifact SHOULD classify findings as:

- `aligned`
- `mismatch`
- `drift`
- `violation`
- `unknown`
- `blocked`

---

## Ambiguity Rule

### Generate Mode

If ambiguity exists:

- mark `UNKNOWN`, `PARTIAL`, or `BLOCKED`
- continue

STOP only if:

- SYSTEM_LAWS unavailable
- CURRENT_TRUTH unavailable
- repo structure unavailable

### Execute Mode / Confirm Mode

If ambiguity exists:

- STOP

Examples:

- ambiguous DB target
- ambiguous cloud/local env
- missing required schema
- missing required MCP continuity

---

## Canonical Backend Execution Protocol (Execute / Confirm Modes Only)

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
- NEVER use remote DB in execute or confirm mode unless explicitly instructed
- use the deterministic replay of `backend/supabase/baseline_slots` as the authoritative local DB source for MCP audit, testing, and verification
- treat `supabase/migrations/` as production migration source only, not local verification DB authority

If `DATABASE_URL` is missing or ambiguous:

- STOP

### Startup Command

```bash
# Windows
.\.venv\Scripts\python.exe -m backend.bootstrap.run_server

# Linux
./.venv/bin/python -m backend.bootstrap.run_server
```

This is the ONLY valid backend startup command set.

Codex MUST use explicit interpreter path for backend startup.

Codex MUST use `backend.bootstrap.run_server` as the only backend startup entrypoint.

Codex MUST NOT:

- use `python`
- use `poetry run`
- use shell activation (`activate`, `source`)
- call `uvicorn` directly
- modify this command unless explicitly instructed

### Pre-Flight Check

Before starting backend:

- `DATABASE_URL` exists
- `DATABASE_URL` is local
- `MCP_MODE=local`
- no cloud env active

If any fail:

- STOP

### Post-Start Verification

Codex MUST verify:

- `GET /healthz` → `200`
- `GET /readyz` → `200`

MCP endpoints:

- `/mcp/verification`
- `/mcp/logs`
- `/mcp/media-control-plane`
- `/mcp/domain-observability`

Worker health:

- `get_worker_health` → all `ok`

If any fail:

- STOP

---

## Bootstrap Order (Execute / Confirm Modes Only)

Codex MUST fully bootstrap before execution work.

1. Load env
   - `ops/env_load.sh`

2. Validate env
   - `ops/env_validate.sh`

3. Run pre-flight validation

4. Start backend

5. Run `ops/mcp_bootstrap_gate.ps1` and require PASS before trusting backend or
   MCP readiness

6. Verify backend

7. Start frontend if task requires frontend

8. Verify frontend if task requires frontend

9. Verify MCP continuity

If any required step fails:

- STOP
- no mutation allowed

---

## Auth Model (Execute / Confirm / E2E Only)

Codex MUST use E2E credentials from `backend/.env` when auth is required for execution.

Flow:

1. Read `E2E_EMAIL` / `E2E_PASSWORD`
2. POST `/auth/login`
3. Extract token
4. Inject token if browser flow is required
5. Verify `/auth/me`

Forbidden:

- guessing credentials
- UI login if API login is enough
- alternative auth flows

If auth fails in required execution path:

- STOP

---

## Verification Order

The canonical order is:

1. `input(task, mode)`
2. `ingestion`
3. `index`
4. `retrieval`
5. `evidence`
6. `contract`
7. `verification`

verification = mode-driven final stage

- generate -> task generation
- execute -> task validation
- confirm -> system truth assertion

Rules:

- contract MUST complete before verification
- verification MUST match task scope
- no phase may duplicate another phase's responsibility
- verify exact invariant
- UI observation is never sufficient verification

---

## Mutation Rules (Execute Mode Only)

- always pre-read
- one mutation plane at a time
- MCP → API → SQL
- SQL last resort
- no blind mutation
- capture before/after evidence

---

## Logging (Execute Mode Only)

Every mutation MUST be logged.

This section governs logging for canonical execute-mode mutations. It does not
classify non-canonical logging, tracing, debug artifacts, telemetry, or local
cache writes as canonical mutations, and it does not prohibit observability in
read-only, no-code audit, generate, or confirm scopes.

Each log MUST include:

- action
- entity_id
- timestamp
- expected_state
- actual_state
- result

---

## Ledger Consistency Rule

In Execute Mode, Codex MUST maintain a session ledger.

If entity lineage cannot be reconstructed:

- STOP

---

## Cleanup Rules (Execute Mode Only)

Codex MUST:

- delete all created entities unless task explicitly preserves them
- verify deletion

---

## Python Execution

Use the explicit interpreter paths defined in `Python Execution Rules`.

Use the task-declared environment otherwise.

Do not improvise Python executors.

---

## Frontend Runtime

Frontend is NEVER a primary truth source.

### Generate Mode

- do not start frontend unless task explicitly requires frontend evidence

### Execute Mode / Confirm Mode

- static build only unless task explicitly overrides
- port 3000
- correct backend target required

---

## Playwright Rules

Use Playwright only when:

- UI verification is explicitly required
- no higher-authority layer can verify the invariant

No hacks.
No UI-first diagnosis.

---

## Process Control (Execute / Confirm Modes Only)

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

### Generate Mode

1. SYSTEM_LAWS
2. Supabase
3. Repo
4. Semantic search
5. MCP validation
6. Backend API
7. Logs
8. UI

### Execute Mode / Confirm Mode

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

- classify blockage
- continue with remaining valid layers if mode allows

---

## Local Execution Context (Execute Mode Only)

Purpose:
Ensure Codex runs against a safe, local, reproducible candidate database.

### Database Selection Rule

Codex MUST prefer local database:

`postgresql://postgres:postgres@127.0.0.1:5432/aveli_local`

Codex MUST verify required schemas:

- `app.*`
- `auth.*`
- `runtime_media`
- `media_assets`
- `home_player_uploads`
- `livekit_webhook_jobs`

If missing:

- bootstrap baseline

### Local DB Bootstrap

1. Create DB
2. Apply baseline (`0001` → latest accepted slot)
3. Verify schema completeness

### Backend Startup Rule

Codex MUST start backend using local DB.

Worker errors:

- allowed only if non-blocking
- blocking = missing runtime-required tables

If blocking:

- extend baseline, not runtime code

---

## Baseline Completeness Gate

Before any downstream implementation, schema-dependent repair, or verification
may proceed, Codex MUST perform a Baseline Completeness Audit.

Definitions:

- `runtime authority`
  - any canonical runtime-owned domain surface that the running system treats as
    authoritative for reads, writes, state transitions, worker behavior, API
    behavior, or verification boundaries
- `baseline substrate`
  - the minimal canonical baseline-replayed substrate required for that runtime
    authority to exist safely from scratch, including required schemas, tables,
    storage substrate, and other materialized runtime prerequisites
- `baseline-owner task`
  - the explicit `OWNER` task that is responsible for creating the baseline
    substrate if clean baseline replay does not already materialize it

Mandatory mapping:

For every runtime authority, Codex MUST materialize this chain before
implementation begins:

`runtime authority -> canonical baseline substrate -> baseline-owner task`

Mandatory audit:

Before downstream implementation begins, Codex MUST:

1. enumerate every runtime authority in scope
2. identify the canonical baseline substrate required by each authority
3. cross-check runtime dependencies against clean baseline replay schema
4. identify missing tables, schemas, storage substrate, and other required
   materialized objects before implementation begins
5. verify that each required substrate either:
   - exists in clean baseline replay
   - or has a clearly defined baseline-owner task that will create it

Blocking rules:

Downstream implementation is FORBIDDEN if:

- any runtime authority lacks an identified canonical baseline substrate
- any runtime authority lacks a baseline-owner task
- any required substrate is missing from clean baseline replay and no
  baseline-owner task exists
- runtime dependencies and baseline schema do not match exactly

STOP condition:

If any mismatch is found between runtime authority and baseline substrate, or if
any authority lacks explicit ownership, Codex MUST fail closed and stop.

`STOP: BASELINE COMPLETENESS GATE FAILED`

No downstream implementation, worker repair, API repair, schema-dependent
verification, or domain expansion may proceed until the authority to substrate
to owner-task chain is complete and the required substrate is materialized in
clean replay or explicitly planned by a baseline-owner task.

Example failure:

If commerce runtime depends on `orders` and `payments`, but clean baseline
replay does not materialize those tables and no baseline-owner task exists,
commerce implementation MUST NOT proceed.

Domain coverage:

This gate is mandatory for:

- commerce
- auth
- media
- all future domains

---

## Baseline Replay Contract

A baseline replay is the only valid proof of baseline correctness.

A valid replay MUST include:

1. minimal auth substrate
   - schema `auth`
   - table `auth.users` with required identity surface

2. baseline slots
   - `0001` through latest accepted slot
   - strict order

3. minimal storage substrate if runtime depends on it
   - schema `storage`
   - `storage.objects`
   - `storage.buckets`

---

## Replay Validation Requirements

A replay is NOT valid unless all are true:

- schema applies cleanly
- backend boots successfully
- `/healthz` returns `200`
- `/readyz` returns `200`
- MCP endpoints return `200`
  - `/mcp/logs`
  - `/mcp/verification`
  - `/mcp/media-control-plane`
  - `/mcp/domain-observability`

- worker health reports all `ok`

If any fail:

- baseline is INVALID
- STOP

Baseline must be:

- deterministic
- reproducible from scratch
- aligned with runtime behavior

---

## Constraints

- replay must not rely on pre-existing DB state
- replay must not depend on production services
- replay must not modify accepted baseline slots
- all fixes must be append-only

---

## MCP Continuity Rule

### Generate Mode

If generic registry is broken but canonical MCP access path works:

- classify registry as `misconfigured`
- continue

### Execute Mode / Confirm Mode

Required MCP endpoints must verify cleanly.
If unavailable:

- STOP

---

## Test Execution Rule

Only local scoped tests allowed unless task explicitly overrides.

---

## Verification Scope Rule

Verification MUST match task scope only.

Do not escalate into full-system verification unless explicitly required.

---

## Pre-Supabase Push Preparation (Execute Mode Only)

Before any push candidate is considered valid, Codex MUST ensure:

- baseline == runtime
- tests pass
- no schema gaps
- no unresolved blocking drift in target scope

---

## Forbidden Actions

Codex MUST NOT:

- use production DB in execute or confirm mode
- guess schema
- bypass DB errors
- disable workers to fake green startup
- redefine authorities through convenience code
- silently accept legacy fallbacks as canonical

---

## Local Storage Substrate Rule

If system depends on external storage (`storage.objects`, `storage.buckets`):

- baseline MUST NOT define them as business truth
- local verification MUST provision minimal compatible substrate if runtime depends on them

Codex MUST:

1. detect storage dependency
2. check storage schema presence
3. provision minimal local substrate if required
4. verify workers start cleanly

If storage is missing and required:

- STOP in execute or confirm mode
- mark `BLOCKED` in generate mode

---

## Final Guarantee

### Generate Mode

Codex guarantees evidence-based reporting, not mutation safety.

### Execute Mode

All execution MUST occur in:

- local app
- local DB
- local MCP

If any required execution layer diverges:

- STOP

### Confirm Mode

All confirmation MUST:

- use canonical evidence
- remain read-only
- return PASS or FAIL

If any required confirmation layer diverges or any deviation is detected:

- FAIL

---

CONTRACT AUTHORITY RULE

The ONLY authoritative contract set is:

actual_truth/contracts/

All other contract-like files in:

- docs/
- legacy docs
- implementation plans

are classified as:

- reference
- historical
- non-authoritative

Codex MUST:

- extract rules ONLY from actual_truth/contracts/
- ignore all other contract sources unless explicitly required by task

Violation:

- mixing contract sources
- extracting rules from non-authoritative contract files

---

DECISIONS AUTHORITY RULE

- Aveli_System_Decisions.md is the canonical semantic truth layer.
- It MUST be treated as a separate rule category: DECISIONS.

Codex MUST:

- extract rules from Aveli_System_Decisions.md as DECISIONS
- NOT merge these rules into:
  - OS
  - WORKFLOW
  - CONTRACTS
  - MANIFEST

Violation:

- merging DECISIONS into other rule layers
- omitting DECISIONS from rule extraction

---

RULE INVENTORY CATEGORY MODEL

Rule categories:

- OS
- WORKFLOW
- CONTRACT
- MANIFEST
- DECISIONS

Classification rule:

- All rules from Aveli_System_Decisions.md MUST be classified as DECISIONS
- They MUST NOT be reclassified
