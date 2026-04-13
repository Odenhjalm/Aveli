# COP-004_webhook_support_table_fail_closed_alignment

- ID: COP-004
- TYPE: BACKEND_ALIGNMENT
- DAG_ROLE: OWNER
- LAUNCH_CLASSIFICATION: BLOCKER
- DEPENDS_ON: [COP-003]
- GOAL: Align backend webhook support-table behavior with the baseline-owned contract so idempotency/logging truth is not silently bypassed.
- SCOPE: Limit work to backend webhook support paths that reference app.payment_events and app.billing_logs. Remove or replace silent missing-table tolerance only where the baseline now owns the required substrate. Preserve existing backend-owned checkout authority and Stripe webhook settlement behavior. Do not change frontend behavior or invent new payment flows.
- VERIFICATION: Confirm webhook idempotency/logging paths no longer silently treat missing baseline-owned support tables as acceptable. Confirm checkout.session and invoice webhook settlement still route through backend order/payment/membership logic. Confirm no frontend authority, direct Stripe authority, or product behavior change is introduced.
- PROMPT:
```text
Align backend webhook support-table behavior with the contract and baseline produced by COP-002 and COP-003. Limit the change to runtime-referenced app.payment_events and app.billing_logs handling. Preserve existing backend-owned checkout, order, payment, and membership authority. Do not change frontend behavior, environment, deploys, or product design. Fail closed if required support tables are missing.
```
- MUTATION POLICY: BACKEND_CODE_ONLY
- IMPLEMENTATION LOGIC: NONE
- USER_FACING_PRODUCT_TEXT_REQUIREMENT: Swedish only for any surfaced error text; task prompt remains English.

