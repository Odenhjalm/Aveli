# COP-008_frontend_checkout_non_authority_gate

- ID: COP-008
- TYPE: CURRENT_TRUTH_VERIFICATION
- DAG_ROLE: GATE
- LAUNCH_CLASSIFICATION: BLOCKER
- DEPENDS_ON: [COP-005, COP-006, COP-012]
- GOAL: Confirm the frontend checkout/onboarding surface remains a non-authoritative renderer after frontend, copy, and residue alignment.
- SCOPE: Read-only verification of frontend checkout/onboarding payment paths after dependent tasks. Verify membership checkout, course checkout, bundle checkout, checkout return/cancel/result handling, and local/session refresh behavior. The frontend must never grant access, mutate app.memberships, call Supabase for authority, or treat Stripe success redirects as authority.
- VERIFICATION: Confirm all checkout entrypoints call backend APIs only. Confirm checkout result pages refresh backend-owned state and do not grant local access. Confirm no direct Supabase/Stripe authority remains in payment flows. Confirm checkout-critical product text remains Swedish.
- PROMPT:
```text
Perform a read-only frontend checkout non-authority gate after COP-005, COP-006, and COP-007. Verify membership, course, and bundle checkout paths call backend APIs only. Verify return/cancel/result handling refreshes backend-owned state and never grants access locally. Confirm no direct Supabase or Stripe authority remains in checkout/onboarding payment flows. Do not mutate code, schema, environment, or deploys.
```
- MUTATION POLICY: READ_ONLY_ONLY
- IMPLEMENTATION LOGIC: NONE
- USER_FACING_PRODUCT_TEXT_REQUIREMENT: Swedish only; task prompt remains English.

