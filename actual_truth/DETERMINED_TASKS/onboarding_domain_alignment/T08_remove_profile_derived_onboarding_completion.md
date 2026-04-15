# T08 Remove Profile-Derived Onboarding Completion

## STATUS

PLANNED
NO-CODE TASK DEFINITION

## PURPOSE

This task defines the runtime change needed to remove profile-derived
onboarding completion semantics.

## AUTHORITY LOAD

This task is governed by:

- `actual_truth/contracts/onboarding_target_truth_decision.md`
- rewritten active contracts after T04
- T02 ratified create-profile decision

## VERIFIED CURRENT DRIFT

- Current runtime blocks `POST /auth/onboarding/complete` when
  `display_name` is absent
- That makes profile-name presence act like onboarding-completion authority
- The drift is contradiction `C03`

## DEPENDENCIES

- `T02`

## REQUIRED MUTATION

- Remove runtime coupling between onboarding completion and profile-name
  presence
- Preserve onboarding completion as explicit completion action only
- Keep persisted onboarding state authority on `app.auth_subjects`

## MUTATION SCOPE

- backend auth/onboarding runtime
- verification tests that currently expect profile-derived completion behavior

## VERIFICATION REQUIREMENT

- completion no longer depends on `display_name`
- `POST /auth/onboarding/complete` remains completion-only
- onboarding completion remains owned by `app.auth_subjects.onboarding_state`

## STOP CONDITIONS

- Stop if any proposed change turns `/profiles/me` into onboarding authority
- Stop if any proposed change removes explicit completion semantics instead of
  removing profile-derived drift

## NEXT STEP

Implement the runtime change and then use that result as one upstream input to
T10.
