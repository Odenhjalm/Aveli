# T07 Replace Tests That Canonize require_app_entry

## STATUS

PLANNED
NO-CODE TASK DEFINITION

## PURPOSE

This task defines the test-suite rewrite needed after T06 so tests stop
canonizing `require_app_entry` as application-entry authority.

## AUTHORITY LOAD

This task is governed by:

- rewritten active contracts after T04
- T06 backend authority cleanup
- `actual_truth/contracts/application_domain_map_contract.md`

## VERIFIED CURRENT DRIFT

- Existing tests still encode `require_app_entry` as canonical app-entry
  authority
- That test doctrine conflicts with the locked rule that `GET /entry-state` is
  the sole post-auth routing authority
- The drift is contradiction `C02`

## DEPENDENCIES

- `T06`

## REQUIRED MUTATION

- Replace tests that treat `require_app_entry` as canonical authority
- Rewrite those tests so they assert:
  - `GET /entry-state` is the sole routing authority
  - backend guards are enforcement-only reuse
  - no second app-entry model exists in tests

## MUTATION SCOPE

- backend tests that currently canonize `require_app_entry`
- any frontend tests that still assume obsolete guard authority

## VERIFICATION REQUIREMENT

- test expectations align to `GET /entry-state` as sole routing authority
- no remaining test canonizes `require_app_entry`
- no rewritten test reintroduces profile or token fallback authority

## STOP CONDITIONS

- Stop if any replacement test requires a second app-entry authority model
- Stop if T06 is not complete enough to define enforcement-only guard behavior

## NEXT STEP

Apply the test rewrite after T06 and use the updated tests as the verification
layer for downstream invite-removal work.
