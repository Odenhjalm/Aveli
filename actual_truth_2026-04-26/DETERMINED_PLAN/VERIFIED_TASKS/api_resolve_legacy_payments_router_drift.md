## TASK ID

api_resolve_legacy_payments_router_drift

---

## PROBLEM

- Mounted checkout/billing behavior lives in: `backend/app/routes/api_checkout.py`, `backend/app/routes/billing.py`, `backend/app/routes/api_orders.py`
- Unmounted duplicate payments behavior still exists in: `backend/app/routes/api_payments.py`
- Equivalent evidence expected in: `backend/app/main.py`, `docs/audit/20260109_aveli_visdom_audit/API_USAGE_DIFF.md`, `docs/audit/20260109_aveli_visdom_audit/FRONTEND_REVIEW.md`

---

## SYSTEM DECISION

- API truth = audit_over_spec
- Mounted backend logic is canonical
- No new business logic is allowed

---

## REQUIRED ACTION

### STEP 1 — Locate candidates

- Open route source files:
  `backend/app/routes/api_checkout.py`, `backend/app/routes/billing.py`, `backend/app/routes/api_orders.py`, `backend/app/routes/api_payments.py`, `backend/app/main.py`, `docs/audit/20260109_aveli_visdom_audit/API_USAGE_DIFF.md`

- Identify every payments/checkout path that is mounted vs unmounted

### STEP 2 — Handler selection

#### STEP 2A — Selection criteria

Selected canonical source MUST:

- be mounted in `backend/app/main.py`
- preserve current checkout, billing, and order behavior
- NOT resurrect `/payments/*` as active truth unless explicitly mounted

#### STEP 2B — Response contract (MANDATORY)

Expected response MUST be defined BEFORE implementation.

Response MUST:

- be a deterministic canonical inventory
- identify mounted checkout/billing/order handlers
- identify `api_payments.py` as legacy-only or removable

FOR read routes:
- MUST return structured data (list or object)

FOR write routes:
- MUST return confirmation or created resource

#### STEP 2C — Response validation rules

Selected canonical source MUST:

- match runtime mounting
- NOT preserve stale `/payments/*` assumptions as current truth
- NOT require guessing deprecated intent

IF response contract is unclear:
→ STOP

#### STEP 2D — Selection rule

IF multiple payments files exist:

- prefer mounted `api_checkout.py`, `billing.py`, and `api_orders.py`
- mark unmounted `api_payments.py` as legacy-only

- IF still ambiguous:
  → STOP

### STEP 3 — Adapter implementation

#### STEP 3A — Route creation

- Create explicit canonical route inventory for:
  checkout, billing subscription, billing portal, order creation, order lookup

#### STEP 3B — Adapter rules

Legacy-router cleanup MUST:

- preserve mounted handlers
- NOT mount `api_payments.py`
- NOT duplicate checkout or billing logic
- NOT invent new `/payments/*` APIs

#### STEP 3C — Request/response passthrough

- Mounted route behavior MUST remain unchanged
- Legacy duplicate classification MUST be explicit
- No speculative transformations allowed

### STEP 4 — Failure handling

IF:

- canonical mounted handlers cannot be proven
- unmounted router contains unique active behavior
- new business logic is required

→ STOP

---

## DO NOT

- create new payment routes
- modify Stripe behavior
- duplicate checkout logic
- change frontend behavior without evidence

---

## VERIFICATION

After change:

- mounted billing/checkout/order routes are the only canonical API truth
- `api_payments.py` is removed from active route accounting
- audit artifacts stop treating legacy `/payments/*` paths as current runtime

---

## STOP CONDITIONS

- canonical mount cannot be proven
- legacy file contains unmatched active behavior
- change requires business-logic redesign

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
- Mounted checkout/billing/order routes remain canonical
