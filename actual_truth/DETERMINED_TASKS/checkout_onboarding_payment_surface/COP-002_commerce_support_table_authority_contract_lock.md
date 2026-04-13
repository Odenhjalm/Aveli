# COP-002_commerce_support_table_authority_contract_lock

- ID: COP-002
- TYPE: CONTRACT_UPDATE
- DAG_ROLE: OWNER
- LAUNCH_CLASSIFICATION: BLOCKER
- DEPENDS_ON: [COP-001]
- GOAL: Lock the contract-level authority status of checkout support tables and unresolved schema names before implementation changes.
- SCOPE: Update only authoritative contracts under actual_truth/contracts. Explicitly classify app.payment_events and app.billing_logs as webhook/idempotency/logging support tables if COP-001 confirms they are required by runtime behavior. Explicitly classify app.transactions and app.subscriptions as non-authority, legacy, absent, or blocked according to COP-001 truth. Preserve canonical authority: app.orders and app.payments own purchases, app.memberships owns membership state, Stripe is infrastructure, and frontend never grants access.
- VERIFICATION: Confirm the contract states whether each of app.payment_events, app.billing_logs, app.transactions, and app.subscriptions is baseline-owned, support-only, non-authority, legacy, absent, or blocked. Confirm no new product behavior or speculative payment flow is introduced. Confirm contract copy is deterministic and does not make Stripe or frontend authoritative.
- PROMPT:
```text
Update the authoritative commerce/payment contracts only after COP-001 has established current database truth. Explicitly classify app.payment_events, app.billing_logs, app.transactions, and app.subscriptions by authority and baseline ownership. Preserve backend-owned payment authority, app.memberships membership authority, and frontend non-authority. Do not implement runtime code, schema, environment changes, deploys, or product redesign.
```
- MUTATION POLICY: CONTRACT_FILES_ONLY
- IMPLEMENTATION LOGIC: NONE
- USER_FACING_PRODUCT_TEXT_REQUIREMENT: Swedish only for any product-facing examples; the task prompt remains English.

