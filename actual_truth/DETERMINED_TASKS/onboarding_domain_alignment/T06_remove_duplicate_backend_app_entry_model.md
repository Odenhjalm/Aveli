# T06 Remove Duplicate Backend App Entry Model

## STATUS

PLANNED
NO-CODE TASK DEFINITION

## PURPOSE

This task defines the backend-runtime work needed to remove the duplicate
app-entry model that currently exists outside `GET /entry-state`.

## AUTHORITY LOAD

This task is governed by:

- `actual_truth/contracts/onboarding_target_truth_decision.md`
- `actual_truth/contracts/application_domain_map_contract.md`
- rewritten active contracts after T04

## VERIFIED CURRENT DRIFT

- Backend runtime currently defines app-entry evaluation and guard semantics in
  `backend/app/auth.py` and `backend/app/permissions.py`
- This duplicates the canonical post-auth decision model owned only by
  `GET /entry-state`
- The drift is contradiction `C01`

## DEPENDENCIES

- `T04`

## REQUIRED MUTATION

- Reduce backend guards to enforcement-only reuse of canonical entry truth
- Remove any backend-local app-entry model that defines, derives, or extends
  separate entry semantics outside `GET /entry-state`
- Preserve backend enforcement where needed, but only as lawful reuse of the
  canonical model

## MUTATION SCOPE

- `backend/app/auth.py`
- `backend/app/permissions.py`
- related backend guard call sites if they still encode duplicate app-entry
  semantics

## VERIFICATION REQUIREMENT

- `GET /entry-state` remains the sole authority for post-auth routing outputs
- backend guards enforce without inventing a second app-entry model
- no backend fallback derives entry from profile, token claims, or guard-local
  state

## STOP CONDITIONS

- Stop if any proposed change requires reopening the locked `GET /entry-state`
  authority model
- Stop if any proposed change makes `/profiles/me` or token claims entry
  authority

## NEXT STEP

Implement the backend-runtime change set that removes duplicate app-entry
semantics and then hand off to T07.
