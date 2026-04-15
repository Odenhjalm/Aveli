# Onboarding Domain Alignment DAG Summary

## Authority Load

This DAG is grounded in:

- `actual_truth/contracts/onboarding_target_truth_decision.md`
- `actual_truth/contracts/application_domain_map_contract.md`
- `actual_truth/contracts/ratifications/T01_referral_source_vocabulary_decision.md`
- `actual_truth/contracts/ratifications/T02_create_profile_surface_decision.md`
- `actual_truth/contracts/ratifications/T03_application_subject_naming_decision.md`
- rewritten active contracts after T04
- resolved T05 baseline audit and task definition

## Resolved Contradictions

- `C11` resolved by T03 ratification and adopted by T04 contract rewrite
- `C12` resolved by T01 ratification
- `C13` resolved by T02 ratification and adopted by T04 contract rewrite
- `C10` resolved at active-contract-corpus level by T04
- T05 resolved the baseline audit question and locked that baseline alignment
  requires an append-only mutation path rather than in-place editing

## Dependency Graph

Deterministic dependency spine:

- `T01, T02, T03 -> T04 -> T05`
- `T04 -> T06 -> T07`
- `T02 -> T08, T09 -> T10`
- `T01, T02, T05, T09, T10 -> T11`
- `T04, T05, T07, T11 -> T12`

Deterministic topological order:

1. `T01`
2. `T02`
3. `T03`
4. `T04`
5. `T05`
6. `T06`
7. `T07`
8. `T08`
9. `T09`
10. `T10`
11. `T11`
12. `T12`

## Task Status

- `T01` resolved and ratified
- `T02` resolved and ratified
- `T03` resolved and ratified
- `T04` completed as active-contract rewrite
- `T05` defined as append-only baseline mutation task; baseline mutation not yet
  executed
- `T06` planned
- `T07` planned
- `T08` planned
- `T09` planned
- `T10` planned
- `T11` planned
- `T12` planned

## Blockers Resolved

- Canonical non-purchase membership source label is locked as `referral`
- Canonical create-profile execution surface is locked as
  `POST /auth/onboarding/create-profile`
- Canonical application-subject naming is locked on `app.auth_subjects`
- Active contract corpus no longer treats invite as active canonical doctrine
- Baseline audit is resolved and identifies one append-only mutation path

## Blockers Remaining

- Append-only baseline mutation for membership-source vocabulary is not yet
  created
- Backend still contains duplicate app-entry model logic outside
  `GET /entry-state`
- Tests still canonize `require_app_entry`
- Runtime still derives onboarding completion from profile-name presence
- Registration still requires name before canonical create-profile execution
- Runtime/frontend still use `/profiles/me` instead of a dedicated
  create-profile mutation
- Referral transport and membership handoff still reflect pre-canonical drift
- Active invite surfaces still exist outside the rewritten contract corpus

## Final Assertion

This task tree is deterministic because:

- the decision gates T01-T03 are locked and ratified
- T04 is completed
- T05 is resolved as an append-only baseline task requirement
- every remaining task T06-T12 has explicit upstream dependencies
- no remaining task reopens target truth already locked upstream
