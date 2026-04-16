# T14 Membership Trial Duration Decision

## STATUS

NO-CODE RATIFICATION.

This document resolves the ordinary membership checkout trial-duration conflict
only. It does not implement code, rewrite active contracts, mutate baseline,
change tests, or change frontend/backend behavior.

## 1. AUTHORITY LOAD

Authority inspected:

- `actual_truth/contracts/onboarding_target_truth_decision.md`
- `actual_truth/contracts/commerce_membership_contract.md`
- `actual_truth/contracts/onboarding_contract.md`
- `actual_truth/contracts/aveli_embedded_checkout_spec.md`
- `actual_truth/contracts/referral_membership_grant_contract.md`
- `actual_truth/contracts/referral_redeem_edge_contract.md`
- `actual_truth/analysis/AUDIT_EXISTING_CHECKOUT_AND_STRIPE_SURFACES.md`
- `actual_truth/DETERMINED_TASKS/onboarding_domain_alignment/T13_lock_and_implement_ordinary_checkout_welcome_flow.md`
- `actual_truth/DETERMINED_TASKS/onboarding_domain_alignment/task_manifest.json`
- `backend/app/services/subscription_service.py`
- checkout, membership, referral, and landing-page trial-duration references
  found by repo search

Repo-visible current 30-day ordinary checkout trial encodings:

- `actual_truth/contracts/onboarding_target_truth_decision.md` states that
  ordinary self-signup checkout creates purchase-backed membership state with a
  30-day free trial and required card details.
- `actual_truth/contracts/commerce_membership_contract.md` states that ordinary
  self-signup membership checkout MUST configure a 30-day free trial, and that
  ordinary self-signup purchase MUST include a 30-day free trial with card
  details required.
- `actual_truth/contracts/onboarding_contract.md` states that payment provides
  30 days free trial for ordinary self-signup membership checkout and requires
  card details during that trial.
- `actual_truth/DETERMINED_TASKS/onboarding_domain_alignment/T13_lock_and_implement_ordinary_checkout_welcome_flow.md`
  states that checkout creates purchase-backed membership semantics with a
  30-day free trial and card details required.
- `actual_truth/DETERMINED_TASKS/onboarding_domain_alignment/task_manifest.json`
  requires the new ordinary checkout flow to have a 30-day trial with required
  card collection and stops if checkout omits that 30-day trial.
- `backend/app/services/subscription_service.py` defines
  `ORDINARY_MEMBERSHIP_TRIAL_DAYS = 30`.
- `backend/app/services/subscription_service.py` passes that value to Stripe as
  `subscription_data.trial_period_days`.
- `actual_truth/analysis/AUDIT_EXISTING_CHECKOUT_AND_STRIPE_SURFACES.md`
  records the active 30-day contract/code truth and identifies the 14-day
  product intent as a ratification conflict.
- `actual_truth/contracts/aveli_embedded_checkout_spec.md` records that the
  active contract stack still encodes a 30-day ordinary self-signup trial while
  the product intent says 14 days to test the app.

Repo-visible 14-day evidence:

- `actual_truth/analysis/AUDIT_EXISTING_CHECKOUT_AND_STRIPE_SURFACES.md`
  records the newly declared product intent as 14 days to test the app with
  card details required.
- `actual_truth/contracts/aveli_embedded_checkout_spec.md` captures the Aveli
  embedded checkout product intent as 14 days to test the app, pending
  ratification.
- `frontend/lib/features/landing/presentation/landing_page.dart` already
  contains 14-day Swedish landing-page trial copy. This is product-copy drift
  toward 14 days, not checkout authority by itself.

Non-trial 30-day or variable-duration evidence:

- `backend/tests/test_course_checkout.py`,
  `backend/tests/test_course_bundles.py`, and
  `backend/tests/test_webhook_upsert.py` use `now() + interval '30 days'` in
  membership fixture setup. Those are test fixture durations and are not
  ordinary Stripe checkout trial doctrine by themselves.
- Referral `free_days` and `free_months` references in contracts, backend, and
  tests are referral grant duration rules. They are not purchase-backed Stripe
  trial semantics.

## 2. EXECUTIVE VERDICT

PASS.

The conflict is ratified in favor of the newly declared product intent:
ordinary Aveli membership checkout now canonically uses a 14-day trial/test
period with card details required.

The previous 30-day ordinary checkout trial rule is superseded for ordinary
purchase-backed membership checkout. It must not remain active ordinary
checkout target truth after the later contract and implementation alignment
pass.

## 3. CURRENT TRIAL-DURATION STATE

Before this ratification:

- active ordinary checkout target truth encoded a 30-day free trial with card
  details required
- backend Stripe subscription checkout creation encoded 30 days through
  `ORDINARY_MEMBERSHIP_TRIAL_DAYS = 30`
- Stripe checkout session creation used that value as
  `subscription_data.trial_period_days`
- the embedded checkout audit/spec identified a 14-day product intent but
  correctly marked it as pending ratification
- frontend landing copy already contained 14-day trial language, creating drift
  against the active 30-day checkout truth

## 4. LOCKED DECISION

The canonical ordinary purchase-backed membership checkout trial duration is
14 days.

Card details remain required before the trial begins.

The embedded checkout specification may proceed on 14-day assumptions after the
downstream active contracts and implementation are updated to this ratified
rule.

This decision applies to ordinary purchase-backed membership checkout only. It
does not change referral, coupon, teacher-issued, or other non-purchase
membership grant doctrine.

This is a pure ordinary-checkout trial-duration rule change, not a broader
membership duration doctrine change.

## 5. SUPERSEDED RULE

Superseded rule:

```text
Ordinary self-signup membership checkout has a 30-day free trial with card
details required.
```

Replacement rule:

```text
Ordinary self-signup membership checkout has a 14-day trial/test period with
card details required.
```

30-day ordinary checkout trial semantics are no longer canonical after this
ratification.

## 6. AFFECTED LAYERS

Later alignment is required in:

- contracts: replace ordinary checkout 30-day references with the ratified
  14-day rule while preserving checkout/payment authority, membership
  authority, onboarding authority, and `/profiles/me` projection-only status
- task tree: revise T13 and the onboarding domain-alignment task manifest where
  they require a 30-day ordinary checkout trial
- backend: update the ordinary membership checkout trial constant and Stripe
  session creation so `trial_period_days` uses 14
- frontend copy: ensure checkout and related product copy consistently say 14
  days and do not leave conflicting 30-day text
- tests: update or add focused tests for 14-day ordinary checkout trial
  semantics, required card details, and Stripe session configuration
- Stripe checkout/session creation: use the ratified 14-day trial duration and
  keep card collection required
- audit/spec artifacts: clear pending-conflict language once active contracts
  are updated

Unaffected layers:

- referral `free_days` and `free_months` grant duration doctrine
- referral source vocabulary
- referral redeem request/response boundary
- non-purchase referral membership handoff
- onboarding completion authority
- profile projection boundary

## 7. STOP CONDITIONS

Stop future alignment or implementation if:

- any active ordinary checkout contract still preserves 30 days as canonical
  after the contract update pass
- backend Stripe session creation uses 14 days while frontend checkout copy
  says 30 days, or frontend checkout copy says 14 days while backend still uses
  30 days
- any implementation changes referral `free_days` or `free_months` doctrine
  under this decision
- referral grants are treated as Stripe trials
- checkout/payment authority is moved into onboarding
- onboarding completion is moved into checkout
- `/profiles/me` is used as onboarding, routing, checkout, payment, or
  membership authority
- frontend success state is treated as membership authority instead of backend
  webhook-confirmed membership state

## 8. FINAL NEXT STEP

Update active contracts and implementation to the ratified 14-day embedded
checkout flow.

The next pass must align contract truth first, then backend Stripe checkout
session creation, frontend checkout copy, routing tests, and focused trial/card
tests. No implementation should proceed on mixed 30-day and 14-day ordinary
checkout assumptions.
