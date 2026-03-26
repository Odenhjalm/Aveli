## TASK ID

api_resolve_auth_duplicates

---

## PROBLEM

- Frontend auth calls target `backend/app/routes/api_auth.py` handlers
- Legacy duplicate exists in `backend/app/routes/auth.py`
- Overlapping routes include:
  - POST /auth/login
  - POST /auth/register
  - POST /auth/forgot-password
  - POST /auth/reset-password
  - POST /auth/refresh
- Backend runtime routing is mismatched for canonicality
- Equivalent handler expected in: `backend/app/routes/api_auth.py`, `backend/app/routes/auth.py`

---

## SYSTEM DECISION

- API truth = audit_over_spec
- Existing backend logic is canonical
- No new business logic is allowed

---

## REQUIRED ACTION

### STEP 1 — Locate candidates

- Open route source files:
  `backend/app/main.py`, `backend/app/routes/api_auth.py`, `backend/app/routes/auth.py`

- Identify all handlers related to this mismatch

### STEP 2 — Handler selection

#### STEP 2A — Selection criteria

Selected handler MUST:

- match intent of routes:
  - login, register, forgot-password, reset-password, refresh
- preserve auth token/session behavior
- NOT introduce new business logic

#### STEP 2B — Response contract (MANDATORY)

Expected response MUST be defined BEFORE implementation.

Response MUST:

- be JSON
- preserve response fields currently consumed by frontend auth flow
- keep auth token shape consistent with existing behavior

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

IF both files define duplicate endpoints:

- prefer:
  `backend/app/routes/api_auth.py`

- fallback:
  `backend/app/routes/auth.py`

- IF overlap differs in response/behavior:
  → STOP

### STEP 3 — Adapter implementation

#### STEP 3A — Route creation

- Keep router mount:
  `app.include_router(api_auth.router)` in `backend/app/main.py`

- Ensure this route is not mounted:
  `app.include_router(auth.router)`

#### STEP 3B — Adapter rules

Canonical resolution MUST:

- call existing logic directly through canonical router inclusion
- NOT call via HTTP
- NOT duplicate logic
- NOT introduce new service layer

#### STEP 3C — Request/response passthrough

- Request for auth routes MUST remain unchanged
- Response for auth routes MUST be returned unchanged
- No transformation allowed

### STEP 4 — Failure handling

IF:

- `backend/app/auth.py` contains unique routes not in canonical source and not documented as legacy
- handler behavior diverges between duplicate sources
- canonical file is missing any duplicated route

→ STOP

---

## DO NOT

- delete `backend/app/routes/auth.py`
- modify handler logic
- modify token flow logic
- change endpoint behavior
- modify frontend

---

## VERIFICATION

After change:

- `backend/app/main.py` includes `app.include_router(api_auth.router)`
- `backend/app/main.py` does not include `app.include_router(auth.router)`
- Auth routes resolve to canonical source
- Login, refresh, reset routes remain callable with unchanged behavior
- No other routes are changed

---

## STOP CONDITIONS

- unique routes in `backend/app/routes/auth.py` not mirrored in canonical source
- `backend/app/routes/api_auth.router` is not mounted
- any route requiring token behavior change is needed
- execution would modify token logic

---

## RISK LEVEL

MEDIUM (auth system)

---

## CATEGORY

api_layer / auth / duplicate_resolution

---

## EXECUTION ORDER

- Can be executed independently: true
- Depends on: none

---

## NOTES

- Adapter only
- Backend logic remains canonical
- This is a structural cleanup only
- Full removal of `backend/app/routes/auth.py` occurs in later phase
