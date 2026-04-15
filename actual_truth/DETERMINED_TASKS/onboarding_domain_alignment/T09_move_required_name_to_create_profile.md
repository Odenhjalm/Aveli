# T09 Move Required Name To Create-Profile

## STATUS

PLANNED
NO-CODE TASK DEFINITION

## PURPOSE

This task defines the cross-surface change needed to move required name from
registration to canonical create-profile.

## AUTHORITY LOAD

This task is governed by:

- `actual_truth/contracts/onboarding_target_truth_decision.md`
- rewritten active contracts after T04
- T02 ratified create-profile decision

## VERIFIED CURRENT DRIFT

- Current runtime, frontend, and tests still require `display_name` during
  registration
- Locked target truth requires required name at create-profile instead
- The drift is contradiction `C04`

## DEPENDENCIES

- `T02`

## REQUIRED MUTATION

- Remove required-name enforcement from registration surfaces
- Enforce required name only at canonical create-profile
- Preserve optional bio as create-profile-collected and profile-persisted

## MUTATION SCOPE

- backend auth register schemas and routes
- frontend signup flow
- tests and fixtures that assume required name at registration

## VERIFICATION REQUIREMENT

- registration no longer requires name
- create-profile requires name
- no fallback keeps required-name doctrine split across registration and
  create-profile

## STOP CONDITIONS

- Stop if any proposal keeps name required at both registration and
  create-profile
- Stop if any proposal moves required name away from canonical create-profile

## NEXT STEP

Implement the registration-to-create-profile shift and then feed that result
into T10 and T11.
