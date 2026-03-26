## TASK ID

api_resolve_legacy_auth_router_drift

---

## PROBLEM

- Mounted canonical auth behavior lives in: `backend/app/routes/api_auth.py`
- Unmounted duplicate auth behavior still exists in: `backend/app/routes/auth.py`
- Equivalent evidence expected in: `backend/app/main.py`, `docs/audit/20260109_aveli_visdom_audit/E2E_FLOWS.md`, `docs/audit/20260109_aveli_visdom_audit/README.md`

---

## SYSTEM DECISION

- API truth = audit_over_spec
- Mounted backend logic is canonical
- No new business logic is allowed

---

## REQUIRED ACTION

### STEP 1 — Locate candidates

- Open route source files:
  `backend/app/routes/api_auth.py`, `backend/app/routes/auth.py`, `backend/app/main.py`, `docs/audit/20260109_aveli_visdom_audit/E2E_FLOWS.md`, `docs/audit/20260109_aveli_visdom_audit/README.md`

- Identify every duplicated auth path and which file is actually mounted

### STEP 2 — Handler selection

#### STEP 2A — Selection criteria

Selected canonical source MUST:

- be mounted in `backend/app/main.py`
- preserve current auth behavior
- NOT require auth-flow redesign

#### STEP 2B — Response contract (MANDATORY)

Expected response MUST be defined BEFORE implementation.

Response MUST:

- be a deterministic canonical auth inventory
- identify mounted canonical handlers
- identify legacy duplicate handlers as non-authoritative

FOR read routes:
- MUST return structured data (list or object)

FOR write routes:
- MUST return confirmation or created resource

#### STEP 2C — Response validation rules

Selected canonical source MUST:

- match current runtime mounting
- NOT merge different auth behaviors implicitly
- NOT require guessing historical intent

IF response contract is unclear:
→ STOP

#### STEP 2D — Selection rule

IF multiple auth files exist:

- prefer mounted `backend/app/routes/api_auth.py`
- mark unmounted `backend/app/routes/auth.py` as legacy-only

- IF still ambiguous:
  → STOP

### STEP 3 — Adapter implementation

#### STEP 3A — Route creation

- Create explicit canonical auth inventory for:
  login, refresh, forgot-password compatibility, reset-password, `/auth/me`

#### STEP 3B — Adapter rules

Legacy-router cleanup MUST:

- preserve mounted `api_auth.py` behavior
- NOT mount `auth.py`
- NOT duplicate auth logic
- NOT redesign auth boundaries

#### STEP 3C — Request/response passthrough

- Mounted auth handlers MUST remain unchanged
- Legacy duplicate classification MUST be explicit
- No speculative transformations allowed

### STEP 4 — Failure handling

IF:

- canonical handler cannot be proven
- legacy file contains unique runtime-only behavior
- auth redesign is required

→ STOP

---

## DO NOT

- redesign auth
- modify token logic
- silently delete unique behavior
- change frontend auth flows

---

## VERIFICATION

After change:

- mounted auth routes are identified unambiguously
- `backend/app/routes/auth.py` is treated as legacy-only in audits/plans
- auth docs no longer describe unmounted handlers as current truth

---

## STOP CONDITIONS

- canonical mount cannot be proven
- legacy file contains unmatched active behavior
- change requires auth redesign

---

## RISK LEVEL

LOW

---

## CATEGORY

api_layer / legacy_drift

---

## EXECUTION ORDER

- Can be executed independently: true
- Depends on: `api_refresh_usage_diff_current_frontend`

---

## NOTES

- Classification and cleanup only
- Mounted auth router remains canonical
