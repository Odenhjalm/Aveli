# COP-001_live_db_checkout_schema_truth_gate

- ID: COP-001
- TYPE: CURRENT_TRUTH_VERIFICATION
- DAG_ROLE: GATE
- LAUNCH_CLASSIFICATION: BLOCKER
- DEPENDS_ON: []
- GOAL: Establish current live database truth for checkout-critical schema before any contract, baseline, backend, frontend, copy, or test remediation.
- SCOPE: Read-only verification of the authoritative database schema for app.memberships, app.orders, app.payments, app.stripe_customers, app.course_bundles, app.course_bundle_courses, app.payment_events, app.billing_logs, app.transactions, and app.subscriptions. This task exists because the prior audit could not confirm live DB schema access.
- VERIFICATION: Confirm the authoritative DB target before inspection. Confirm table presence, absence, shape, and ownership classification without writes. Classify unreachable DB access as BLOCKED. Confirm app.payment_events and app.billing_logs current truth. Confirm whether app.transactions and app.subscriptions exist and whether any mounted checkout/payment route treats them as authority. Stop downstream tasks on ambiguous DB target or inaccessible current truth.
- PROMPT:
```text
Execute a read-only current-truth verification of the checkout-critical database schema. Confirm the authoritative database target, then inspect table presence and ownership for app.memberships, app.orders, app.payments, app.stripe_customers, app.course_bundles, app.course_bundle_courses, app.payment_events, app.billing_logs, app.transactions, and app.subscriptions. Do not mutate schema, data, environment, code, or deploys. Fail closed if the database target is ambiguous or inaccessible.
```
- MUTATION POLICY: READ_ONLY_ONLY
- IMPLEMENTATION LOGIC: NONE
- USER_FACING_PRODUCT_TEXT_REQUIREMENT: Swedish only; no product copy is added by this task.

