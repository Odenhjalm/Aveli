## TASK ID

api_fix_payments_plans

---

## PROBLEM

- Frontend calls: GET /payments/plans
- Backend route is missing or mismatched for this path
- Equivalent handler expected in: `backend/app/routes/billing.py`, `backend/app/routes/api_checkout.py`

---

## SYSTEM DECISION

- API truth = audit_over_spec
- Existing backend logic is canonical
- No new business logic is allowed

---

## REQUIRED ACTION

### STEP 1 — Locate candidates

- Open route source files:
  `backend/app/routes/billing.py`, `backend/app/routes/api_checkout.py`

- Identify all handlers related to this mismatch

### STEP 2 — Handler selection

#### STEP 2A — Selection criteria

Selected handler MUST:

- match intent of route:
  - read
- NOT introduce new business logic
- NOT perform unintended state mutation

#### STEP 2B — Response contract (MANDATORY)

Expected response MUST be defined BEFORE implementation.

Response MUST:

- be JSON
- return list of plan objects or pricing metadata
- include required fields for that route type

FOR read routes:
- MUST return structured data (list or object)

FOR write routes:
- MUST return confirmation or created resource

#### STEP 2C — Response validation rules

Selected handler MUST:

- return deterministic structure
- NOT expose raw external objects (e.g. Stripe SDK objects)
- NOT require frontend transformation

IF response contract is unclear:
→ STOP

#### STEP 2D — Selection rule

IF multiple handlers exist:

- prefer:
  `backend/app/routes/billing.py`

- fallback:
  `backend/app/routes/api_checkout.py`

- IF still ambiguous:
  → STOP

### STEP 3 — Adapter implementation

#### STEP 3A — Route creation

- Create route:
  GET /payments/plans

#### STEP 3B — Adapter rules

New route MUST:

- call existing logic directly
- NOT call via HTTP
- NOT duplicate logic
- NOT introduce new service layer

#### STEP 3C — Request/response passthrough

- Request MUST be passed unchanged
- Response MUST be returned unchanged
- No transformation allowed

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
