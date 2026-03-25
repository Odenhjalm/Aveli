## TASK ID

api_resolve_profiles_duplicates

---

## PROBLEM

- Frontend profile calls target `backend/app/routes/api_profiles.py` behavior
- Legacy duplicate exists in `backend/app/routes/profiles.py`
- Overlapping profile routes include:
  - GET /profiles/me
  - GET /profiles/avatar/{media_id}
  - GET /profiles/{user_id}/certificates
  - PATCH /profiles/me
  - POST /profiles/me/avatar
- Backend runtime routing is mismatched for canonicality
- Equivalent handler expected in: `backend/app/routes/api_profiles.py`, `backend/app/routes/profiles.py`

---

## SYSTEM DECISION

- API truth = audit_over_spec
- Existing backend logic is canonical
- No new business logic is allowed

---

## REQUIRED ACTION

### STEP 1 — Locate candidates

- Open route source files:
  `backend/app/main.py`, `backend/app/routes/api_profiles.py`, `backend/app/routes/profiles.py`

- Identify all handlers related to this mismatch

### STEP 2 — Handler selection

#### STEP 2A — Selection criteria

Selected handler MUST:

- match intent of routes:
  - read
  - update
- include all duplicate endpoints from legacy source
- NOT introduce new business logic

#### STEP 2B — Response contract (MANDATORY)

Expected response MUST be defined BEFORE implementation.

Response MUST:

- be JSON
- preserve fields required by frontend profile views
- include required fields for that route type

FOR read routes:
- MUST return structured data (list or object)

FOR write routes:
- MUST return confirmation or updated resource

#### STEP 2C — Response validation rules

Selected handler MUST:

- return deterministic structure
- NOT expose raw external objects
- NOT require frontend transformation

IF response contract is unclear:
→ STOP

#### STEP 2D — Selection rule

IF multiple mounted sources are found:

- prefer:
  `backend/app/routes/api_profiles.py`

- fallback:
  `backend/app/routes/profiles.py`

- IF overlap diverges in response/behavior:
  → STOP

### STEP 3 — Adapter implementation

#### STEP 3A — Route creation

- Keep router mount:
  `app.include_router(api_profiles.router)` in `backend/app/main.py`

- Remove this router mount:
  `app.include_router(profiles.router)`

#### STEP 3B — Adapter rules

Canonicalization MUST:

- keep handler logic in canonical source unchanged
- not duplicate handlers
- not call through HTTP

#### STEP 3C — Request/response passthrough

- Request for profile routes MUST remain unchanged
- Response for profile routes MUST be returned unchanged
- No transformation allowed

### STEP 4 — Failure handling

IF:

- canonical source cannot be mounted deterministically
- overlap requires behavioral merge
- response contract differs between sources

→ STOP

---

## DO NOT

- delete `backend/app/routes/profiles.py`
- modify route handlers
- change endpoint paths or methods
- modify frontend files
- refactor imports in `backend/app/main.py`

---

## VERIFICATION

After change:

- `backend/app/main.py` does not include `app.include_router(profiles.router)`
- `backend/app/main.py` includes `app.include_router(api_profiles.router)`
- Profile routes remain resolvable at runtime
- No other router include statements are changed

---

## STOP CONDITIONS

- `backend/app/main.py` does not include `app.include_router(api_profiles.router)`
- `backend/app/routes/profiles.py` contains unique endpoints not in canonical source
- any media route includes are modified

---

## RISK LEVEL

LOW

---

## CATEGORY

api_layer / duplicate_resolution / non-breaking

---

## EXECUTION ORDER

- Can be executed independently: true
- Depends on: none

---

## NOTES

- Adapter only
- Backend logic remains canonical
- Legacy router file is retained as reference
- Removal of `backend/app/routes/profiles.py` deferred
