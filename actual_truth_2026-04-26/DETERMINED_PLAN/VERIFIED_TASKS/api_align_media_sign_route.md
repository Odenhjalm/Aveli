## TASK ID

api_align_media_sign_route

---

## PROBLEM

- Frontend calls: POST `/api/media/sign`
- Mounted backend route is: POST `/media/sign`
- Equivalent handler expected in: `backend/app/routes/media.py`, `frontend/lib/api/api_paths.dart`, `frontend/lib/features/media/data/media_repository.dart`, `frontend/lib/services/media_service.dart`

---

## SYSTEM DECISION

- API truth = audit_over_spec
- Existing backend logic is canonical
- No new business logic is allowed

---

## REQUIRED ACTION

### STEP 1 — Locate candidates

- Open route source files:
  `backend/app/routes/media.py`, `frontend/lib/api/api_paths.dart`, `frontend/lib/features/media/data/media_repository.dart`, `frontend/lib/services/media_service.dart`

- Identify the mounted signer handler and every active frontend caller

### STEP 2 — Handler selection

#### STEP 2A — Selection criteria

Selected handler MUST:

- keep existing signing logic unchanged
- preserve current response schema
- NOT introduce new storage or auth behavior

#### STEP 2B — Response contract (MANDATORY)

Expected response MUST be defined BEFORE implementation.

Response MUST:

- be JSON
- preserve `media_id`, signed URL, and expiration fields
- remain compatible with current frontend callers

FOR read routes:
- MUST return structured data (list or object)

FOR write routes:
- MUST return confirmation or created resource

#### STEP 2C — Response validation rules

Selected handler MUST:

- return deterministic structure
- NOT expose new internal storage details
- NOT require frontend transformation beyond current callers

IF response contract is unclear:
→ STOP

#### STEP 2D — Selection rule

IF multiple options exist:

- prefer existing signer logic in `backend/app/routes/media.py`
- fallback to frontend path correction only if no non-breaking backend adapter is acceptable

- IF still ambiguous:
  → STOP

### STEP 3 — Adapter implementation

#### STEP 3A — Route creation

- Create or align route:
  POST `/api/media/sign`

#### STEP 3B — Adapter rules

New route or path alignment MUST:

- call existing logic directly
- NOT call via HTTP
- NOT duplicate signer logic
- NOT introduce new service layers

#### STEP 3C — Request/response passthrough

- Request MUST be passed unchanged
- Response MUST be returned unchanged
- No transformation allowed

### STEP 4 — Failure handling

IF:

- mounted signer handler cannot be reused
- compatibility requires new business logic
- response schema changes are required

→ STOP

---

## DO NOT

- modify signing rules
- modify auth rules
- modify media-control-plane logic
- change request/response schemas

---

## VERIFICATION

After change:

- active frontend sign calls resolve at runtime
- response matches current signer schema
- no signing behavior changes

---

## STOP CONDITIONS

- handler not found
- compatibility requires schema drift
- signer behavior would change

---

## RISK LEVEL

LOW

---

## CATEGORY

api_layer / adapter_fix

---

## EXECUTION ORDER

- Can be executed independently: true
- Depends on: `api_refresh_usage_diff_current_frontend`

---

## NOTES

- Adapter only
- Backend signer remains canonical
