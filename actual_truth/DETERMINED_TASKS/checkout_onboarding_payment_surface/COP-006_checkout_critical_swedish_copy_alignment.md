# COP-006_checkout_critical_swedish_copy_alignment

- ID: COP-006
- TYPE: COPY_ALIGNMENT
- DAG_ROLE: OWNER
- LAUNCH_CLASSIFICATION: PRE_LAUNCH_REQUIRED
- DEPENDS_ON: [COP-002]
- GOAL: Make checkout-critical user-facing text fully Swedish without changing payment authority or behavior.
- SCOPE: Limit copy work to checkout/onboarding payment paths identified in the audit: membership checkout, course paywall checkout, checkout WebView fallback, checkout result/return/cancel states, launch-critical landing checkout return/cancel pages, and backend error text that can surface to users on checkout paths. Do not change non-checkout product copy in this task.
- VERIFICATION: Confirm checkout-critical user-facing text is Swedish, including diacritics where the existing UI style supports them. Confirm task prompts and developer-facing task text remain English and copy-paste ready. Confirm no authority, routing, schema, or Stripe behavior is changed.
- PROMPT:
```text
Update only checkout-critical user-facing copy to Swedish. Cover membership checkout, course paywall checkout, checkout WebView fallback, checkout result/return/cancel states, launch-critical landing checkout return/cancel pages, and backend checkout errors that can surface to users. Do not alter payment authority, routing, schema, Stripe behavior, environment, or deploys. Keep developer/task prompts in English.
```
- MUTATION POLICY: COPY_ONLY
- IMPLEMENTATION LOGIC: NONE
- USER_FACING_PRODUCT_TEXT_REQUIREMENT: Swedish only for all checkout-critical product-facing text; task prompt remains English.

