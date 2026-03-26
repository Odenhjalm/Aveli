## TASK ID

auth_deprecate_forgot_password_alias

---

## PROBLEM

- Frontend calls: POST /auth/request-password-reset
- Backend exposes alias path: POST /auth/forgot-password
- Route canonicality is mismatched (alias is compatibility path)
- Equivalent handler expected in: `backend/app/routes/api_auth.py`

---

## SYSTEM DECISION

- API truth = audit_over_spec
- Existing backend logic is canonical
- No new business logic is allowed

---

## REQUIRED ACTION

### STEP 1 — Locate candidates

- Open route source files:
  `backend/app/routes/api_auth.py`

- Identify all handlers related to this mismatch

### STEP 2 — Handler selection

#### STEP 2A — Selection criteria

Selected handler MUST:

- match intent of routes:
  - password reset request
- preserve request and response schema
- NOT alter token or auth state logic

#### STEP 2B — Response contract (MANDATORY)

Expected response MUST be defined BEFORE implementation.

Response MUST:

- be JSON
- preserve request/response fields for password reset
- remain compatible with frontend usage context

FOR read routes:
- MUST return structured data (list or object)

FOR write routes:
- MUST return confirmation or created resource

#### STEP 2C — Response validation rules

Selected handler MUST:

- return deterministic structure
- NOT expose raw external objects
- NOT require frontend transformation

IF response contract is unclear:
→ STOP

#### STEP 2D — Selection rule

IF multiple alias handlers exist:

- prefer:
  `backend/app/routes/api_auth.py`

- IF contract differs from canonical route:
  → STOP

### STEP 3 — Adapter implementation

#### STEP 3A — Route creation

- Add to alias route (`POST /auth/forgot-password`) one of:
  - `deprecated=True` or `include_in_schema=False`

- Keep canonical route:
  POST /auth/request-password-reset

#### STEP 3B — Adapter rules

Alias behavior MUST:

- remain callable for compatibility
- call existing logic directly through existing handler
- NOT call via HTTP
- NOT duplicate logic

#### STEP 3C — Request/response passthrough

- Request for alias route MUST remain unchanged
- Response for alias route MUST remain unchanged
- No transformation allowed

### STEP 4 — Failure handling

IF:

- contract cannot be proven identical
- frontend uses alias as primary flow
- token logic would change

→ STOP

---

## DO NOT

- modify auth flow structure.
- modify token logic.
- create new auth behavior.
- change request/response schemas
- modify frontend
- remove existing endpoints

---

## VERIFICATION

After change:

- `POST /auth/request-password-reset` remains canonical and unchanged
- `POST /auth/forgot-password` remains callable for compatibility
- schema/docs do not list alias when `include_in_schema=False`
- no other auth routes are modified

---

## STOP CONDITIONS

- handler code differs between canonical and alias routes
- frontend requires alias as primary
- token logic changes are required
- change would alter auth behavior

---

## RISK LEVEL

LOW

---

## CATEGORY

auth / api cleanup / non-breaking

---

## EXECUTION ORDER

- Can be executed independently: true
- Depends on: none

---

## NOTES

- Adapter only
- Backend logic remains canonical
- Full removal of alias route is a later phase
