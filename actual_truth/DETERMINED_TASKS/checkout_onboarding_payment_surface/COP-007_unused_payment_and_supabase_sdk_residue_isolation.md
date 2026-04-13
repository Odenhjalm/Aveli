# COP-007_unused_payment_and_supabase_sdk_residue_isolation

- ID: COP-007
- TYPE: LEGACY_REMOVAL
- DAG_ROLE: OWNER
- LAUNCH_CLASSIFICATION: PRE_LAUNCH_REQUIRED
- DEPENDS_ON: [COP-002]
- GOAL: Remove or isolate unused payment/Supabase SDK residue from the checkout/onboarding payment surface without crossing unrelated domains.
- SCOPE: Limit work to residue verified by the audit: unused payment SDK files/dependencies in the frontend payment surface and Supabase SDK/config residue that could imply frontend authority. First re-verify actual usage. Remove only residue proven unused or isolate it from checkout/onboarding payment flows. If required Supabase usage is discovered outside checkout/onboarding scope, do not refactor that unrelated domain in this task; record it as a separate non-blocking follow-up.
- VERIFICATION: Confirm no checkout/onboarding payment path imports or uses Supabase SDKs, direct Stripe authority, raw PaymentIntents, Card Element, Tokens, Sources, or frontend membership mutation. Confirm removals do not break non-payment domains. Confirm no new dependency is introduced.
- PROMPT:
```text
Re-verify unused payment and Supabase SDK residue in the frontend checkout/onboarding payment surface. Remove or isolate only residue proven unused in that scope. Do not refactor unrelated media or non-payment domains. Confirm no checkout/onboarding payment path imports Supabase SDKs, uses direct Stripe authority, or mutates membership. Do not change backend, schema, environment, or deploys.
```
- MUTATION POLICY: FRONTEND_LEGACY_REMOVAL_ONLY
- IMPLEMENTATION LOGIC: NONE
- USER_FACING_PRODUCT_TEXT_REQUIREMENT: Swedish only if product copy is touched; task prompt remains English.

