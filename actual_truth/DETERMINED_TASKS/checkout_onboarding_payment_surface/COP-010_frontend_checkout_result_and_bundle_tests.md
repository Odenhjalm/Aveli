# COP-010_frontend_checkout_result_and_bundle_tests

- ID: COP-010
- TYPE: TEST_ALIGNMENT
- DAG_ROLE: OWNER
- LAUNCH_CLASSIFICATION: BLOCKER
- DEPENDS_ON: [COP-008]
- GOAL: Add or align frontend tests for checkout-result refresh behavior, bundle checkout backend usage, and frontend non-authority.
- SCOPE: Limit tests to frontend checkout/onboarding payment paths verified in the audit. Cover membership checkout launch, course checkout launch, bundle checkout launch through backend, checkout result/return/cancel behavior, backend session refresh, and absence of local access grants. Include stale test alignment for checkout API constructor/method drift when directly in this scope.
- VERIFICATION: Tests must fail if frontend checkout grants access locally, treats Stripe redirect success as authority, expects bundle payment_link as checkout authority, bypasses backend APIs, or reintroduces direct Supabase/Stripe authority in checkout/onboarding payment flows. Tests must confirm checkout-critical copy remains Swedish where tested.
- PROMPT:
```text
Add or align frontend tests for the verified checkout/onboarding payment surface only. Cover membership checkout launch, course checkout launch, bundle checkout through the backend endpoint, checkout return/cancel/result handling, backend session refresh, and frontend non-authority. Update stale checkout tests only within this scope. Do not add speculative product behavior, backend changes, schema changes, environment changes, or deploys.
```
- MUTATION POLICY: TEST_FILES_ONLY
- IMPLEMENTATION LOGIC: NONE
- USER_FACING_PRODUCT_TEXT_REQUIREMENT: Swedish only for user-facing test expectations; task prompt remains English.

