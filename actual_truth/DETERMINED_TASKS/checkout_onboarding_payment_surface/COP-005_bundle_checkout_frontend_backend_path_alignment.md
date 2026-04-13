# COP-005_bundle_checkout_frontend_backend_path_alignment

- ID: COP-005
- TYPE: FRONTEND_ALIGNMENT
- DAG_ROLE: OWNER
- LAUNCH_CLASSIFICATION: BLOCKER
- DEPENDS_ON: [COP-002]
- GOAL: Align bundle checkout frontend behavior to the mounted backend bundle checkout path found in the audit.
- SCOPE: Limit work to frontend bundle checkout surfaces that currently expect a payment_link or otherwise do not call the mounted backend route POST /api/course-bundles/{bundle_id}/checkout-session. The frontend must request a backend-created Stripe Checkout Session and must not call Stripe or Supabase directly for authority. Do not redesign bundle purchase behavior beyond the mounted backend contract.
- VERIFICATION: Confirm bundle checkout UI/API code calls the backend bundle checkout endpoint, uses the returned checkout URL/session data, and grants no access locally. Confirm no payment_link assumption remains on the production-critical bundle checkout path. Confirm no direct Stripe SDK or Supabase SDK authority is introduced.
- PROMPT:
```text
Align the frontend bundle checkout path to the mounted backend endpoint POST /api/course-bundles/{bundle_id}/checkout-session. Remove the verified frontend assumption that bundle purchase depends on a payment_link field. The frontend must only launch a backend-created Stripe Checkout Session and must not grant access or call Stripe/Supabase for authority. Do not redesign product behavior, backend routes, environment, or deploys.
```
- MUTATION POLICY: FRONTEND_CODE_ONLY
- IMPLEMENTATION LOGIC: NONE
- USER_FACING_PRODUCT_TEXT_REQUIREMENT: Swedish only for all product-facing checkout copy; task prompt remains English.

