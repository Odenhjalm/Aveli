## TASK ID

<to be filled>

---

## PROBLEM

- Frontend calls: <frontend route>
- Backend route is missing or mismatched for this path
- Equivalent handler expected in: <candidate backend files>

---

## SYSTEM DECISION

- API truth = audit_over_spec
- Existing backend logic is canonical
- No new business logic is allowed

---

## TASK VALIDITY

- is_real_problem: <true/false>
- already_satisfied: <true/false>
- requires_code_change: <true/false>

Rules:

- IF the mismatch is historical only:
  - set `is_real_problem: false`
  - set `already_satisfied: true`
  - set `requires_code_change: false`
  - STOP TASK GENERATION

- IF the mismatch is already resolved in current code:
  - set `is_real_problem: true`
  - set `already_satisfied: true`
  - set `requires_code_change: false`
  - STOP TASK GENERATION

- IF classification is ambiguous:
  - STOP TASK GENERATION

---

## TASK CLASSIFICATION (MANDATORY)

### STEP A — PROBLEM TYPE DETECTION

Codex MUST determine the exact problem type.

Choose ONE:

- `observability_issue`
  - audit mismatch
  - stale documentation
  - false-positive system signal

- `legacy_vs_canonical`
  - duplicate modules
  - unmounted routes
  - deprecated aliases

- `contract_mismatch`
  - frontend vs backend mismatch
  - request/response shape inconsistency

- `runtime_mismatch`
  - runtime vs DB mismatch
  - missing schema dependency

- `architecture_change`
  - requires new structure
  - requires structural or breaking change

### STEP B — VALIDATION

Codex MUST verify:

- Is this problem STILL present in current code?
- Is this based on a historical snapshot?

IF problem is already resolved:
- set `problem_type: already_satisfied`
- STOP TASK GENERATION

### STEP C — CLASSIFICATION RULES

Apply:

- `observability_issue` -> NO code change
- `legacy_vs_canonical` -> deprecate / isolate, NOT merge
- `contract_mismatch` -> adapter or contract update
- `runtime_mismatch` -> align to DB or runtime
- `architecture_change` -> requires Phase 3

### STEP D — STOP CONDITIONS

Codex MUST STOP if:

- problem is historical only
- problem is already resolved
- classification is ambiguous

### STEP E — OUTPUT

Task MUST include:

- `problem_type: <type>`
- `classification_reason: <why>`

If classification is wrong:
- TASK IS INVALID

---

## REQUIRED ACTION

Proceed ONLY if:

- `is_real_problem: true`
- `already_satisfied: false`
- `requires_code_change: true`
- `problem_type` is unambiguous
- classification rules allow code change for this task

### STEP 1 — Locate candidates

- Open route source files:
  <candidate backend files>

- Identify all handlers related to this mismatch

---

### STEP 2 — Handler selection

#### STEP 2A — Selection criteria

Selected handler MUST:

- match intent of route:
  - create / read / update
- NOT introduce new business logic
- NOT perform unintended state mutation

---

#### STEP 2B — Response contract (MANDATORY)

Expected response MUST be defined BEFORE implementation.

Response MUST:

- be JSON
- match frontend usage context
- include required fields for that route type

FOR read routes:
- MUST return structured data (list or object)

FOR write routes:
- MUST return confirmation or created resource

---

#### STEP 2C — Response validation rules

Selected handler MUST:

- return deterministic structure
- NOT expose raw external objects (e.g. Stripe SDK objects)
- NOT require frontend transformation

IF response contract is unclear:
→ STOP

---

#### STEP 2D — Selection rule

IF multiple handlers exist:

- prefer handler located in canonical API layer (e.g. api_* modules)

- fallback to non-canonical or legacy modules

- IF still ambiguous:
  → STOP

---

Selected handler MUST be explicitly identified before proceeding.

Implementation MUST NOT begin until:

- handler path is known
- handler satisfies selection criteria

IF handler cannot be explicitly identified:
→ STOP

### STEP 3 — Adapter implementation

#### STEP 3A — Route creation

- Create route:
  <frontend route>

---

#### STEP 3B — Adapter rules

New route MUST:

- call existing logic directly
- NOT call via HTTP
- NOT duplicate logic
- NOT introduce new service layer

---

#### STEP 3C — Request/response passthrough

- Request MUST be passed unchanged
- Response MUST be returned unchanged
- No transformation allowed

---

### STEP 4 — Failure handling

IF:

- handler not found
- multiple conflicting handlers exist

→ STOP

---

## DO NOT

- modify auth
- modify media_control_plane
- refactor business logic
- change request/response schemas
- modify frontend
- remove existing endpoints

---

## VERIFICATION

After change:

- Route resolves at runtime
- Response matches defined contract:
  - correct structure
  - required fields present
  - no raw external objects
- No unintended state mutation
- No other routes changed

---

## STOP CONDITIONS

- handler not found
- multiple handlers produce different behavior
- response contract mismatch
- handler mutates state unexpectedly
- change requires business logic modification

---

## RISK LEVEL

LOW

---

## PROBLEM TYPE

problem_type: <observability_issue | legacy_vs_canonical | contract_mismatch | runtime_mismatch | architecture_change>

classification_reason: <to be filled>

---

## CATEGORY

api_layer / adapter_fix

---

## EXECUTION ORDER

- Can be executed independently: true
- Depends on: none

---

## NOTES

- Adapter only
- Backend logic remains canonical
- Task must not introduce new system behavior
