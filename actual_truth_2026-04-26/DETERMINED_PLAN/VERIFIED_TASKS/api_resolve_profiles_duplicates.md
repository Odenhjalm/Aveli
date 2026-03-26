## TASK ID

api_resolve_profiles_duplicates

---

## PROBLEM

- Mounted canonical profile behavior lives in: `backend/app/routes/api_profiles.py`
- Unmounted duplicate profile behavior still exists in: `backend/app/routes/profiles.py`
- Equivalent evidence expected in: `backend/app/main.py`, `backend/app/routes/api_profiles.py`, `backend/app/routes/profiles.py`

---

## SYSTEM DECISION

- API truth = audit_over_spec
- Mounted backend logic is canonical
- No new business logic is allowed

---

## TASK VALIDITY

- is_real_problem: true
- already_satisfied: false
- requires_code_change: false

---

## PROBLEM TYPE

problem_type: legacy_vs_canonical

classification_reason: Runtime is already canonical because only `api_profiles.router` is mounted. The remaining task is to isolate `profiles.py` as legacy-only and remove it from active route accounting, not to merge duplicate runtime behavior.

---

## REQUIRED ACTION

### STEP 1 — Verify canonical mount

- Confirm `app.include_router(api_profiles.router)` exists in `backend/app/main.py`
- Confirm `profiles.router` is not mounted in runtime

### STEP 2 — Canonical classification

- Treat `backend/app/routes/api_profiles.py` as the only runtime-authoritative profile surface
- Treat `backend/app/routes/profiles.py` as legacy-only source code
- Do NOT merge handlers
- Do NOT mount the legacy router

### STEP 3 — Route-accounting cleanup

- Remove `profiles.py` from active route accounting in plans and audits
- Keep the file only as a legacy reference until separately retired

---

## DO NOT

- mount `profiles.router`
- merge handler logic
- change endpoint paths or methods
- modify frontend behavior
- treat the legacy file as active runtime

---

## VERIFICATION

- `backend/app/main.py` includes `app.include_router(api_profiles.router)`
- `backend/app/main.py` does not include `app.include_router(profiles.router)`
- active route inventories classify `api_profiles.py` as canonical
- no task or audit treats `profiles.py` as active runtime

---

## STOP CONDITIONS

- `profiles.router` is found to be mounted
- `backend/app/routes/profiles.py` contains unique active runtime-only behavior
- classification remains ambiguous

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

- Legacy-vs-canonical cleanup only
- Mounted runtime remains canonical
- No runtime merge work is required
