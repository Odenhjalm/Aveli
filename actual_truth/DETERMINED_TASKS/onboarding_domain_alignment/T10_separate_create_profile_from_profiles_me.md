# T10 Separate Create-Profile From /profiles/me

## STATUS

PLANNED
NO-CODE TASK DEFINITION

## PURPOSE

This task defines the implementation work needed to separate create-profile
from `/profiles/me` and establish the dedicated onboarding-owned surface.

## AUTHORITY LOAD

This task is governed by:

- `actual_truth/contracts/onboarding_target_truth_decision.md`
- rewritten active contracts after T04
- T02 ratified create-profile decision

## VERIFIED CURRENT DRIFT

- Current create-profile behavior still routes through `/profiles/me`
- `/profiles/me` is projection-only and must not own create-profile authority
- The drift is contradiction `C05`

## DEPENDENCIES

- `T08`
- `T09`

## REQUIRED MUTATION

- Implement `POST /auth/onboarding/create-profile` as the canonical
  onboarding-owned mutation surface
- Remove create-profile execution responsibility from `/profiles/me`
- Keep `/profiles/me` projection-only
- Preserve optional image as media-mediated only

## MUTATION SCOPE

- backend auth/onboarding route surfaces
- frontend onboarding flow
- onboarding and profile tests

## VERIFICATION REQUIREMENT

- create-profile executes through `POST /auth/onboarding/create-profile`
- `/profiles/me` remains projection-only
- media authority does not move into onboarding or profile projection

## STOP CONDITIONS

- Stop if any implementation continues to route create-profile through
  `/profiles/me`
- Stop if any implementation makes create-profile binary media authority

## NEXT STEP

Implement the dedicated create-profile surface and use the result as an
upstream dependency for T11.
