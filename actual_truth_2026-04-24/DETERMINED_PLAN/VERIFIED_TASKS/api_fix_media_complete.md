## TASK ID

api_fix_media_complete

---

## PROBLEM

- Frontend calls: POST /media/complete
- Backend route is missing or mismatched for this path
- Equivalent handler expected in: `backend/app/routes/api_media.py`, `backend/app/routes/upload.py`

---

## SYSTEM DECISION

- API truth = audit_over_spec
- Existing backend logic is canonical
- No new business logic is allowed

---

## REQUIRED ACTION

### STEP 1 — Locate candidates

- Open route source files:
  `backend/app/routes/api_media.py`, `backend/app/routes/upload.py`

- Identify all handlers related to this mismatch

---

### STEP 2 — Handler selection

#### STEP 2A — Selection criteria

Selected handler MUST:

- mark upload as complete
- update media state from uploaded to ready or processing according to existing logic
- NOT generate presign URLs
- NOT trigger playback
- NOT introduce new business logic

---

#### STEP 2B — Response contract (MANDATORY)

Expected response MUST be defined BEFORE implementation.

Response MUST:

- be JSON
- include confirmation of completion
- include media identifier
- include updated state when available
- not expose internal storage paths
- include all fields required by frontend usage context for this route

FOR read routes:
- MUST return structured data (list or object)

FOR write routes:
- MUST return confirmation or created resource

---

#### STEP 2C — Response validation rules

Selected handler MUST:

- return deterministic structure
- perform only valid completion state transition
- NOT duplicate state writes
- NOT require frontend transformation

IF response contract is unclear:
→ STOP

---

#### STEP 2D — Selection rule

IF multiple handlers exist:

- prefer:
  `backend/app/routes/api_media.py`

- fallback:
  `backend/app/routes/upload.py`

- IF still ambiguous:
  → STOP

---

### STEP 3 — Adapter implementation

#### STEP 3A — Route creation

- Create route:
  POST /media/complete

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
- handler does not perform allowed state transition
- handler triggers unrelated pipeline steps

→ STOP

---

## DO NOT

- modify media pipeline logic
- modify storage rules
- modify processing worker
- create or alter state transitions beyond existing logic
- trigger playback
- change request/response schemas
- modify frontend
- remove existing endpoints

---

## VERIFICATION

After change:

- Route resolves at runtime
- Response includes required fields:
  - completion confirmation
  - media identifier
  - updated state when available
- Response matches defined contract:
  - correct structure
  - required fields present
  - no raw internal storage paths
- no duplicate state writes occur
- no unrelated pipeline step is triggered
- no other routes changed

---

## STOP CONDITIONS

- handler does not perform state transition
- handler triggers unrelated pipeline steps
- multiple handlers produce different behavior
- response contract mismatch
- handler mutates state unpredictably
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
