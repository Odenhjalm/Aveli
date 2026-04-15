# T12 Remove Active Invite Surfaces

## STATUS

PLANNED
NO-CODE TASK DEFINITION

## PURPOSE

This task defines the removal work needed to eliminate invite as an active
runtime doctrine after referral and baseline alignment are in place.

## AUTHORITY LOAD

This task is governed by:

- rewritten active contracts after T04
- T05 append-only baseline alignment path
- T07 test rewrite
- T11 referral transport and handoff rewrite

## VERIFIED CURRENT DRIFT

- Active invite surfaces still survive in runtime, frontend, fixtures, and
  tests even though invite is no longer active canonical doctrine
- Current repo still carries dual non-purchase grant topology through invite
  plus referral
- These drifts are contradictions `C08` and `C09`

## DEPENDENCIES

- `T04`
- `T05`
- `T07`
- `T11`

## REQUIRED MUTATION

- Remove active invite runtime surfaces
- Remove active invite frontend surfaces
- Remove invite-shaped fixtures and tests
- Remove dual non-purchase grant topology so referral is the only canonical
  non-purchase grant doctrine relevant to this onboarding path

## MUTATION SCOPE

- backend runtime auth/invite surfaces
- frontend invite routes and flows
- tests and fixtures
- derived docs that still present invite as active runtime doctrine

## VERIFICATION REQUIREMENT

- no active invite surface survives in runtime or frontend
- no fixture or test still requires invite as active doctrine
- referral remains the only canonical non-purchase grant doctrine for this
  onboarding path

## STOP CONDITIONS

- Stop if any proposed removal breaks the locked referral grant path
- Stop if any proposal attempts to preserve invite as fallback doctrine

## NEXT STEP

Execute invite-surface removal only after T11 and the T05 baseline mutation are
landed and verified.
