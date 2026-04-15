# T11 Rewire Referral Transport And Membership Handoff

## STATUS

PLANNED
NO-CODE TASK DEFINITION

## PURPOSE

This task defines the cross-domain work needed to rewire referral transport and
membership handoff to the canonical post-invite model.

## AUTHORITY LOAD

This task is governed by:

- T01 ratified referral source vocabulary decision
- T02 ratified create-profile decision
- T05 append-only baseline alignment requirement
- rewritten active contracts after T04

## VERIFIED CURRENT DRIFT

- Current referral email transport still lands at `/login` instead of the
  canonical create-profile onboarding step
- Current referral-derived membership handoff still uses source `invite`
- These drifts are contradictions `C06` and `C07` at runtime/backend level

## DEPENDENCIES

- `T01`
- `T02`
- `T05`
- `T09`
- `T10`

## REQUIRED MUTATION

- Rewire referral email transport so the recipient enters onboarding at the
  create-profile step
- Rewire referral-derived membership handoff so the canonical non-purchase
  source label is `referral`
- Preserve referral as non-purchase membership grant only
- Preserve the rule that referral does not create purchase or payment truth

## MUTATION SCOPE

- backend referral services
- backend membership-grant services
- frontend referral entry flow
- tests that assert referral transport and referral membership handoff

## VERIFICATION REQUIREMENT

- referral email transport lands at create-profile
- referral-derived membership handoff uses source `referral`
- no runtime path keeps `invite` as referral-derived membership vocabulary

## STOP CONDITIONS

- Stop if baseline alignment from T05 is still undefined or contradicted
- Stop if any proposal reopens the locked referral vocabulary or create-profile
  decisions

## NEXT STEP

Implement the referral transport and membership-handoff rewrite and then use
that output as a dependency for T12.
