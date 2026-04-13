# COP-009_backend_webhook_settlement_and_idempotency_tests

- ID: COP-009
- TYPE: TEST_ALIGNMENT
- DAG_ROLE: OWNER
- LAUNCH_CLASSIFICATION: BLOCKER
- DEPENDS_ON: [COP-004]
- GOAL: Add or align backend tests for checkout creation, webhook settlement, membership creation, bundle entitlement, and idempotency.
- SCOPE: Limit tests to verified backend checkout/payment surfaces: POST /api/checkout/create, POST /api/billing/create-subscription, POST /api/course-bundles/{bundle_id}/checkout-session, POST /api/stripe/webhook, order/payment settlement, app.memberships mutation through backend webhook logic, and support-table idempotency/logging behavior. Do not add tests for speculative checkout flows.
- VERIFICATION: Tests must prove backend-created Stripe Checkout Sessions remain the payment initiation mechanism, webhook settlement updates app.orders/app.payments before app.memberships where applicable, bundle purchases grant course entitlements without mutating membership, and duplicate webhook events are idempotent. Tests must fail if support-table baseline ownership is missing.
- PROMPT:
```text
Add or align backend tests for the verified checkout/payment backend surface only. Cover course checkout, membership subscription checkout, bundle checkout, Stripe webhook settlement, app.orders/app.payments settlement, app.memberships mutation only through backend membership purchase paths, bundle entitlement without membership mutation, and webhook idempotency/logging support tables. Do not add speculative flows, deploy, or mutate environment.
```
- MUTATION POLICY: TEST_FILES_ONLY
- IMPLEMENTATION LOGIC: NONE
- USER_FACING_PRODUCT_TEXT_REQUIREMENT: Swedish only if user-facing fixtures are added; task prompt remains English.

