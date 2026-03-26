## TASK ID

auth_refresh_canonical_contract_docs

---

## PROBLEM

- Auth audit docs still describe forgot/reset flows as unmounted legacy behavior
- Current frontend and mounted backend use: `/auth/request-password-reset`, `/auth/reset-password`, `/auth/send-verification`, `/auth/verify-email`
- Equivalent evidence expected in: `actual_truth_2026-04-26/auth/auth_system_rules.md`, `docs/audit/20260109_aveli_visdom_audit/E2E_FLOWS.md`, `docs/audit/20260109_aveli_visdom_audit/README.md`, `backend/app/routes/api_auth.py`, `backend/app/routes/email_verification.py`, `frontend/lib/api/auth_repository.dart`

---

## SYSTEM DECISION

- Auth behavior must stay inside the existing trust boundary
- Mounted backend logic is canonical
- No auth redesign is allowed

---

## REQUIRED ACTION

### STEP 1 — Locate candidates

- Open contract source files:
  `actual_truth_2026-04-26/auth/auth_system_rules.md`, `docs/audit/20260109_aveli_visdom_audit/E2E_FLOWS.md`, `docs/audit/20260109_aveli_visdom_audit/README.md`, `backend/app/routes/api_auth.py`, `backend/app/routes/email_verification.py`, `frontend/lib/api/auth_repository.dart`

- Identify every auth-doc statement that no longer matches mounted runtime behavior

### STEP 2 — Handler selection

#### STEP 2A — Selection criteria

Selected canonical contract MUST:

- follow mounted runtime auth routes
- preserve the existing trust boundary
- include verification-email flows actually used by the frontend

#### STEP 2B — Response contract (MANDATORY)

Expected response MUST be defined BEFORE implementation.

Response MUST:

- be markdown contract output
- list canonical mounted auth endpoints
- classify compatibility aliases explicitly
- include verification-email flow coverage

FOR read routes:
- MUST return structured data (list or object)

FOR write routes:
- MUST return confirmation or created resource

#### STEP 2C — Response validation rules

Selected contract MUST:

- match current mounted code
- NOT preserve stale unmounted-route claims as current truth
- NOT redesign auth behavior

IF response contract is unclear:
→ STOP

#### STEP 2D — Selection rule

IF audit docs and runtime code disagree:

- prefer mounted runtime code
- keep stale audit statements only as historical notes

- IF still ambiguous:
  → STOP

### STEP 3 — Adapter implementation

#### STEP 3A — Route creation

- Create updated canonical auth contract artifacts:
  `actual_truth_2026-04-26/auth/auth_system_rules.md`
  `docs/audit/20260109_aveli_visdom_audit/E2E_FLOWS.md`
  `docs/audit/20260109_aveli_visdom_audit/README.md`

#### STEP 3B — Adapter rules

Contract refresh MUST:

- preserve current auth endpoint behavior
- mark `/auth/forgot-password` as compatibility-only when relevant
- include `/auth/send-verification` and `/auth/verify-email`

#### STEP 3C — Request/response passthrough

- Mounted auth routes MUST be described unchanged
- Compatibility aliases MUST be described unchanged
- No speculative transformations allowed

### STEP 4 — Failure handling

IF:

- mounted auth routes cannot be proven
- verification-email flow ownership is unclear
- auth redesign is required

→ STOP

---

## DO NOT

- redesign auth
- change token logic
- remove compatibility paths without proof
- modify frontend behavior

---

## VERIFICATION

After change:

- auth docs reflect current mounted routes
- verification-email flow is included in canonical contract docs
- stale unmounted-flow statements are removed or marked historical

---

## STOP CONDITIONS

- canonical runtime auth surface cannot be proven
- doc update requires auth redesign
- verification flow ownership is ambiguous

---

## RISK LEVEL

LOW

---

## CATEGORY

auth / contract_refresh

---

## EXECUTION ORDER

- Can be executed independently: true
- Depends on: `api_refresh_usage_diff_current_frontend`

---

## NOTES

- Documentation refresh only
- Mounted auth runtime remains canonical
