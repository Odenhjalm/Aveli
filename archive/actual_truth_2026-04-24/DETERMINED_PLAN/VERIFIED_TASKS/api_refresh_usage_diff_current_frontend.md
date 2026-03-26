## TASK ID

api_refresh_usage_diff_current_frontend

---

## PROBLEM

- Audit artifacts still record frontend calls to legacy paths such as `/payments/*`, `/checkout/session`, and `/auth/forgot-password`
- Current frontend code now uses canonical paths in: `frontend/lib/api/api_paths.dart`, `frontend/lib/features/payments/data/payments_repository.dart`, `frontend/lib/features/payments/data/billing_api.dart`, `frontend/lib/features/payments/services/stripe_service.dart`, `frontend/lib/data/repositories/orders_repository.dart`, `frontend/lib/api/auth_repository.dart`
- Equivalent evidence expected in: `docs/audit/20260109_aveli_visdom_audit/API_USAGE_DIFF.md`, `docs/audit/20260109_aveli_visdom_audit/FRONTEND_REVIEW.md`, `actual_truth_2026-04-24/DETERMINED_PLAN/*`

---

## SYSTEM DECISION

- API truth = audit_over_spec
- Existing mounted backend logic is canonical
- No new business logic is allowed

---

## REQUIRED ACTION

### STEP 1 — Locate candidates

- Open evidence source files:
  `docs/audit/20260109_aveli_visdom_audit/API_USAGE_DIFF.md`, `docs/audit/20260109_aveli_visdom_audit/FRONTEND_REVIEW.md`, `frontend/lib/api/api_paths.dart`, `frontend/lib/features/payments/data/payments_repository.dart`, `frontend/lib/features/payments/data/billing_api.dart`, `frontend/lib/features/payments/services/stripe_service.dart`, `frontend/lib/data/repositories/orders_repository.dart`, `frontend/lib/api/auth_repository.dart`, `backend/app/main.py`

- Identify every stale route claim that no longer matches current frontend code

### STEP 2 — Handler selection

#### STEP 2A — Selection criteria

Selected evidence set MUST:

- prefer current frontend call sites over stale audit line-number snapshots
- use mounted routers from `backend/app/main.py` as runtime truth
- NOT invent new runtime routes

#### STEP 2B — Response contract (MANDATORY)

Expected response MUST be defined BEFORE implementation.

Response MUST:

- be markdown and/or json audit artifact output
- enumerate current frontend paths
- enumerate current mounted backend matches/mismatches
- identify stale legacy entries explicitly

FOR read routes:
- MUST return structured data (list or object)

FOR write routes:
- MUST return confirmation or created resource

#### STEP 2C — Response validation rules

Selected evidence set MUST:

- be deterministic
- preserve exact current route strings
- NOT treat historical audit entries as current truth when code disagrees

IF response contract is unclear:
→ STOP

#### STEP 2D — Selection rule

IF multiple evidence sources disagree:

- prefer current repo call sites + mounted routers
- fallback to January 2026 audit docs as historical evidence only

- IF still ambiguous:
  → STOP

### STEP 3 — Adapter implementation

#### STEP 3A — Route creation

- Create refreshed artifacts:
  `docs/audit/20260109_aveli_visdom_audit/API_USAGE_DIFF.md`
  `docs/audit/20260109_aveli_visdom_audit/FRONTEND_REVIEW.md`
  dependent `actual_truth_2026-04-24/DETERMINED_PLAN/*` outputs

#### STEP 3B — Adapter rules

New audit output MUST:

- be generated from current repo state
- NOT add new routes
- NOT preserve stale mismatches for compatibility convenience

#### STEP 3C — Request/response passthrough

- Current frontend paths MUST be recorded unchanged
- Current backend paths MUST be recorded unchanged
- No speculative transformations allowed

### STEP 4 — Failure handling

IF:

- current frontend call sites cannot be proven
- mounted route inventory cannot be proven
- historical and current evidence cannot be separated

→ STOP

---

## DO NOT

- modify auth behavior
- modify billing or checkout business logic
- add compatibility routes
- modify frontend runtime behavior

---

## VERIFICATION

After change:

- API usage artifacts match current frontend code
- stale `/payments/*`, `/checkout/session`, and `/auth/forgot-password` assumptions are removed or marked historical
- dependent determined-plan outputs reference refreshed evidence

---

## STOP CONDITIONS

- frontend call-site inventory is incomplete
- mounted router inventory is ambiguous
- task requires guessing historical intent

---

## RISK LEVEL

LOW

---

## CATEGORY

api_layer / audit_refresh

---

## EXECUTION ORDER

- Can be executed independently: true
- Depends on: none

---

## NOTES

- Audit refresh only
- Current repo state is canonical input
