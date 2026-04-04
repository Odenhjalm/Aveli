# 0009G_access_authority_cleanup

TASK_ID: T007
STATUS: COMPLETE
TYPE: OWNER
PURPOSE: Ta bort all aktiv backend-användning av `course_entitlements` som runtime authority så att `course_enrollments` blir ensam access-sanning.
FILES AFFECTED:
- backend/app/routes/stripe_webhooks.py
- backend/app/services/course_bundles_service.py
- backend/app/services/domain_observability/user_inspection.py
- backend/app/routes/domain_observability_mcp.py
- backend/app/repositories/course_entitlements.py
- backend/tests/test_course_checkout.py
- backend/tests/test_course_bundles.py
- backend/tests/test_webhook_upsert.py
DEPENDS_ON:
- none
DONE_WHEN:
- Ingen aktiv backend-runtimeyta läser eller skriver `course_entitlements` för access- eller learner-truth.
- Stripe- och bundle-flöden skapar endast kanonisk `course_enrollments`-truth.
- Aktiv observability exponerar inte entitlement-state som aktiv authority-signal.
VALIDATION:
- `rg "course_entitlements" backend/app` visar inga aktiva runtime-importer eller runtime-anrop kvar.
- Riktad checkout/webhook-verifiering visar endast `course_enrollments`-mutationer.
- Active local MCP/user-inspection-surface nämner inte entitlements som runtime-truth.
