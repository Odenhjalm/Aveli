# COP-003_webhook_support_table_baseline_slot

- ID: COP-003
- TYPE: BASELINE_SLOT
- DAG_ROLE: OWNER
- LAUNCH_CLASSIFICATION: BLOCKER
- DEPENDS_ON: [COP-002]
- GOAL: Materialize append-only baseline ownership for webhook support tables that are runtime-referenced and contract-authorized.
- SCOPE: Add an append-only baseline slot for app.payment_events and app.billing_logs only if COP-002 explicitly classifies them as baseline-owned support tables. Do not create app.transactions or app.subscriptions unless COP-002 explicitly reclassifies them as baseline-owned runtime authority. Do not alter accepted baseline slots.
- VERIFICATION: Clean baseline replay must materialize the exact contract-authorized support tables. Replay must not create unauthorized commerce authority tables. The support tables must be sufficient for webhook idempotency/logging paths that were runtime-referenced in the audit. Stop if COP-002 does not authorize this exact baseline scope.
- PROMPT:
```text
Create the append-only baseline slot required by COP-002 for webhook support tables. Materialize app.payment_events and app.billing_logs only when the contract classifies them as baseline-owned support tables. Do not create unauthorized app.transactions or app.subscriptions tables. Do not modify accepted baseline slots, runtime code, frontend code, environment, or deploys. Verify clean baseline replay.
```
- MUTATION POLICY: BASELINE_APPEND_ONLY
- IMPLEMENTATION LOGIC: NONE
- USER_FACING_PRODUCT_TEXT_REQUIREMENT: Swedish only; no product copy is added by this task.

