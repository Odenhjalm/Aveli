# Checkout Onboarding Payment Surface Remediation Task Tree

This directory materializes the deterministic remediation task tree generated from the established no-code checkout/payment audit.

The tree covers only verified audit findings:

- live DB schema access was not confirmed
- app.payment_events and app.billing_logs are runtime-referenced support tables without repo-baseline ownership in the audit
- app.transactions and app.subscriptions have unresolved schema authority/truth
- bundle checkout frontend behavior is incomplete relative to the mounted backend bundle checkout route
- unused payment/Supabase SDK residue remains in or near the frontend payment surface
- checkout-critical user-facing text is not fully Swedish
- frontend checkout must remain non-authoritative
- tests are required for webhook settlement, idempotency, and checkout-result refresh behavior

It does not introduce new product behavior or redesign checkout.

