## TASK ID

courses_refresh_quiz_route_audit

---

## PROBLEM

- Older audit artifacts still record a PATCH quiz-question mismatch
- Current frontend and backend both use PUT for question updates
- Equivalent evidence expected in: `docs/audit/20260109_aveli_visdom_audit/API_USAGE_DIFF.md`, `frontend/lib/features/studio/data/studio_repository.dart`, `backend/app/routes/studio.py`

---

## SYSTEM DECISION

- Audit truth must reflect current repo state
- Existing runtime logic is canonical
- No new business logic is allowed

---

## REQUIRED ACTION

### STEP 1 — Locate candidates

- Open source files:
  `docs/audit/20260109_aveli_visdom_audit/API_USAGE_DIFF.md`, `frontend/lib/features/studio/data/studio_repository.dart`, `backend/app/routes/studio.py`

- Identify the stale quiz-route claim and the current PUT-based implementation

### STEP 2 — Handler selection

#### STEP 2A — Selection criteria

Selected audit record MUST:

- prefer current frontend code
- prefer current mounted backend code
- NOT preserve stale PATCH claims as current truth

#### STEP 2B — Response contract (MANDATORY)

Expected response MUST be defined BEFORE implementation.

Response MUST:

- be markdown audit output
- record the current PUT method accurately
- mark the old PATCH claim as stale or historical

FOR read routes:
- MUST return structured data (list or object)

FOR write routes:
- MUST return confirmation or created resource

#### STEP 2C — Response validation rules

Selected audit record MUST:

- be deterministic
- match current code exactly
- NOT guess at intermediate history

IF response contract is unclear:
→ STOP

#### STEP 2D — Selection rule

IF audit doc and code disagree:

- prefer current code
- keep old PATCH claim only as historical context

- IF still ambiguous:
  → STOP

### STEP 3 — Adapter implementation

#### STEP 3A — Route creation

- Create refreshed quiz-route audit output in:
  `docs/audit/20260109_aveli_visdom_audit/API_USAGE_DIFF.md`

#### STEP 3B — Adapter rules

Audit refresh MUST:

- preserve current PUT route
- NOT create new quiz endpoints
- NOT alter quiz behavior

#### STEP 3C — Request/response passthrough

- Current PUT route MUST be recorded unchanged
- No speculative transformations allowed

### STEP 4 — Failure handling

IF:

- current quiz method cannot be proven
- audit history cannot be separated from current truth

→ STOP

---

## DO NOT

- modify quiz behavior
- add PATCH compatibility routes
- change frontend runtime behavior

---

## VERIFICATION

After change:

- quiz-route audit reflects current PUT behavior
- stale PATCH mismatch is removed or marked historical

---

## STOP CONDITIONS

- current method cannot be proven
- task requires route changes instead of audit refresh

---

## RISK LEVEL

LOW

---

## CATEGORY

courses / audit_refresh

---

## EXECUTION ORDER

- Can be executed independently: true
- Depends on: `api_refresh_usage_diff_current_frontend`

---

## NOTES

- Audit refresh only
