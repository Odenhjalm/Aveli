# api_layer — planned vs implemented

## planned sources
- docs/audit/20260109_aveli_visdom_audit/API_CATALOG.md
- docs/audit/20260109_aveli_visdom_audit/API_CATALOG.json
- docs/audit/20260109_aveli_visdom_audit/API_USAGE_DIFF.md
- docs/audit/20260109_aveli_visdom_audit/SYSTEM_MAP.md

## implemented sources
- backend/app/main.py
- backend/app/routes/admin.py
- backend/app/routes/api_auth.py
- backend/app/routes/api_ai.py
- backend/app/routes/api_media.py
- backend/app/routes/api_me.py
- backend/app/routes/api_notifications.py
- backend/app/routes/api_checkout.py
- backend/app/routes/api_orders.py
- backend/app/routes/api_profiles.py
- backend/app/routes/courses.py
- backend/app/routes/studio.py
- backend/app/routes/landing.py
- backend/app/routes/community.py
- backend/app/routes/upload.py
- backend/app/routes/billing.py

## gaps
- Unmounted routes are documented (`backend/app/routes/auth.py`, `backend/app/routes/api_payments.py`) and require explicit operational intent.
- API usage diff evidence includes frontend/API contract checks that should be re-run as implementation evolves.
- MCP-oriented route modules are present and need to be included in the same runtime-contract accounting.

## contradictions
- Router mount set and generated catalog diverge on route visibility for some paths, indicating documentation/runtime drift.
