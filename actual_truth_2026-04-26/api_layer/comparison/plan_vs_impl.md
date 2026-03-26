# api_layer — planned vs implemented

## planned sources
- `actual_truth_2026-04-26/Aveli_System_Decisions.md`
- `aveli_system_manifest.json`
- `docs/audit/20260109_aveli_visdom_audit/API_CATALOG.json`
- `docs/audit/20260109_aveli_visdom_audit/API_CATALOG.md`
- `docs/audit/20260109_aveli_visdom_audit/API_USAGE_DIFF.md`
- `docs/audit/20260109_aveli_visdom_audit/FRONTEND_REVIEW.md`

## implemented sources
- `backend/app/main.py`
- `backend/app/routes/api_auth.py`
- `backend/app/routes/api_checkout.py`
- `backend/app/routes/api_media.py`
- `backend/app/routes/api_orders.py`
- `backend/app/routes/billing.py`
- `backend/app/routes/media.py`
- `backend/app/routes/playback.py`
- `backend/app/routes/auth.py`
- `backend/app/routes/api_payments.py`
- `frontend/lib/api/api_paths.dart`
- `frontend/lib/api/auth_repository.dart`
- `frontend/lib/features/payments/data/payments_repository.dart`
- `frontend/lib/features/payments/data/billing_api.dart`
- `frontend/lib/features/payments/services/stripe_service.dart`
- `frontend/lib/data/repositories/orders_repository.dart`

## system should be
- Audit-driven API truth should describe the current mounted backend surface and the current frontend call sites without stale legacy aliases.
- Canonical frontend paths should resolve against mounted routers only.
- Legacy duplicate routers should be classified as non-authoritative and should not keep generating false route mismatches.

## system is
- Current frontend code now uses `/api/checkout/create`, `/orders`, `/api/billing/*`, and `/auth/request-password-reset` as the active payment/auth surface.
- The backend still contains unmounted legacy router files `backend/app/routes/auth.py` and `backend/app/routes/api_payments.py`.
- `frontend/lib/api/api_paths.dart` still points `mediaSign` at `/api/media/sign`, while the mounted backend route remains `/media/sign`.
- Existing audit docs and older verified tasks still center on `/payments/*`, `/checkout/session`, and `/auth/forgot-password` usage that current frontend code no longer makes.

## mismatches
- `[blocking] api_align_media_sign_route` — current frontend `ApiPaths.mediaSign` targets `/api/media/sign`, but mounted backend logic exposes `/media/sign`.
- `[important] api_refresh_usage_diff_current_frontend` — `API_USAGE_DIFF.md`, `FRONTEND_REVIEW.md`, and the old determined plan still describe endpoint gaps that current frontend code has already moved away from.
- `[important] api_resolve_legacy_auth_router_drift` — unmounted `backend/app/routes/auth.py` duplicates mounted auth paths and keeps stale auth-route conclusions alive.
- `[important] api_resolve_legacy_payments_router_drift` — unmounted `backend/app/routes/api_payments.py` duplicates mounted billing/checkout behavior and pollutes route accounting.
