# auth — planned vs implemented

## planned sources
- docs/audit/20260109_aveli_visdom_audit/SECURITY_REVIEW.md
- docs/audit/20260109_aveli_visdom_audit/API_CATALOG.json
- docs/audit/20260109_aveli_visdom_audit/E2E_FLOWS.md
- docs/audit/20260109_aveli_visdom_audit/OPS_OBSERVABILITY.md
- archive/experiments/codex_output/login_system_report.md

## implemented sources
- backend/app/auth.py
- backend/app/routes/api_auth.py
- backend/app/routes/auth.py
- backend/app/repositories/auth.py
- backend/app/services/email_tokens.py
- frontend/lib/core/auth/auth_controller.dart
- frontend/lib/api/auth_repository.dart
- frontend/lib/features/auth/presentation/login_page.dart
- frontend/lib/features/auth/presentation/signup_page.dart
- backend/app/main.py

## gaps
- Catalog evidence indicates unmounted/legacy auth route behavior that does not align with current mounting strategy.
- OAuth and reset-password flows are documented as disabled, gated, or legacy in different artifacts, requiring explicit runtime confirmation.
- Frontend still references token/session flows that must match backend mount and behavior.

## contradictions
- Runtime shows active auth code and endpoints, while audit artifacts flag drift between mounted auth routers and endpoint expectations.
