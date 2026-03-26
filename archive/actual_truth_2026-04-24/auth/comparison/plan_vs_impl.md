# auth — planned vs implemented

## planned sources
- `actual_truth_2026-04-24/Aveli_System_Decisions.md`
- `actual_truth_2026-04-24/auth/auth_system_rules.md`
- `docs/SECURITY.md`
- `docs/audit/20260109_aveli_visdom_audit/SECURITY_REVIEW.md`
- `docs/audit/20260109_aveli_visdom_audit/E2E_FLOWS.md`
- `docs/audit/20260109_aveli_visdom_audit/README.md`

## implemented sources
- `backend/app/auth.py`
- `backend/app/routes/api_auth.py`
- `backend/app/routes/auth.py`
- `backend/app/routes/email_verification.py`
- `backend/app/repositories/auth.py`
- `backend/app/repositories/sessions.py`
- `backend/app/services/email_tokens.py`
- `frontend/lib/api/api_paths.dart`
- `frontend/lib/api/auth_repository.dart`
- `frontend/lib/core/auth/auth_controller.dart`
- `frontend/lib/core/auth/token_storage.dart`
- `frontend/lib/features/auth/presentation/forgot_password_page.dart`
- `frontend/lib/features/auth/presentation/new_password_page.dart`
- `frontend/lib/features/auth/presentation/verify_email_page.dart`

## system should be
- Mounted auth behavior should be documented against one canonical runtime surface.
- Password-reset, refresh, and verification flows should be described against mounted handlers only.
- Legacy duplicate auth files should never be treated as live behavior unless they are mounted.

## system is
- Frontend auth code now uses `/auth/request-password-reset`, `/auth/reset-password`, `/auth/send-verification`, and `/auth/verify-email`.
- Mounted `backend/app/routes/api_auth.py` handles login, refresh, forgot/reset compatibility, and `/auth/me`.
- `backend/app/routes/email_verification.py` provides the verification-mail flows used by the current frontend.
- Unmounted `backend/app/routes/auth.py` still duplicates login/refresh/forgot/reset behavior and older audit docs still describe it as the active implementation.

## mismatches
- `[important] auth_refresh_canonical_contract_docs` — auth audit docs still describe forgot/reset as unmounted legacy behavior and still omit the mounted verification-email surface used by the current frontend.
- `[important] api_resolve_legacy_auth_router_drift` — `backend/app/routes/auth.py` duplicates the active auth surface while staying unmounted.
