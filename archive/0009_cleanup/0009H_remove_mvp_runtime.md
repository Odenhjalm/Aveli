# 0009H_remove_mvp_runtime

TASK_ID: T008
STATUS: COMPLETE
TYPE: OWNER
PURPOSE: Avlägsna den separata legacy/MVP-runtimeytan som fortfarande monterar `api_me`, `api_payments` och subscription-era endpoints.
FILES AFFECTED:
- backend/app/mvp/main.py
- backend/app/routes/api_me.py
- backend/app/routes/api_payments.py
- backend/docs/mvp_api.md
- backend/tests/test_mvp_endpoints.py
- backend/tests/test_membership_read.py
- backend/tests/test_referral_memberships.py
- frontend/landing/pages/checkout/return.tsx
- frontend/RENAMING_NOTES.md
DEPENDS_ON:
- T007
DONE_WHEN:
- `app.mvp.main` finns inte längre som körbar runtimeyta.
- `api_me` och `api_payments` kan inte längre fungera som aktiv learner/runtime- eller payments-surface.
- Repo:t dokumenterar inte längre en separat MVP API-runtime för subscription-era flöden.
VALIDATION:
- `rg "app\\.mvp\\.main|api_me|api_payments" backend frontend` visar inga aktiva runtime-mounts eller körinstruktioner kvar.
- Riktad backendverifiering visar att endast `app.main` är aktiv runtime-ingång.
