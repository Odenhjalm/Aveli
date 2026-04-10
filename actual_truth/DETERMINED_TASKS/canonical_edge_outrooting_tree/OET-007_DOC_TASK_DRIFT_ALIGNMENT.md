# OET-007 DOC TASK DRIFT ALIGNMENT

- TYPE: `OWNER`
- GROUP: `DOC / TASK ALIGNMENT`
- REQUIRED BEFORE FUTURE CORE FEATURE WORK: `YES`
- EXECUTION CLASS: `AUXILIARY`
- CURRENT STATUS: `HISTORICAL / VERIFIED COMPLETE`

## Historical Note

The problem statement below records the pre-execution audit state and is retained only as historical task context.

## Problem Statement

Current contracts and historical determined-task artifacts still contain implementation-drift claims that mounted runtime truth and existing guard tests already contradict.

Leaving those contradictions in place risks generating the wrong next tasks.

## Contract References

- [commerce_membership_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/commerce_membership_contract.md)
- [referral_membership_grant_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/referral_membership_grant_contract.md)
- [auth_onboarding_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/auth_onboarding_contract.md)

## Audit Inputs

- `OEA-07`
- `OEA-08`

## Implementation Surfaces Affected

- `actual_truth/contracts/commerce_membership_contract.md`
- `actual_truth/contracts/referral_membership_grant_contract.md`
- `actual_truth/DETERMINED_TASKS/auth_onboarding_contract_alignment/README.md`
- `actual_truth/DETERMINED_TASKS/auth_onboarding_contract_alignment/AOC-001_canonical_entrypoint_replacement.md`
- `actual_truth/DETERMINED_TASKS/auth_onboarding_contract_alignment/AOC-004_subject_profile_authority_replacement.md`
- `actual_truth/DETERMINED_TASKS/media_conflict_resolution`

## Depends On

- `OET-006`

## Acceptance Criteria

- only proven contradicted implementation-drift notes are updated
- no contract law section is reinterpreted or expanded without evidence
- commerce documentation no longer claims the mounted checkout, billing, or webhook core is absent when current runtime and guard tests disprove that claim
- referral documentation no longer claims auth register still owns referral redemption when current runtime evidence disproves that claim
- stale determined-task artifacts no longer instruct already-satisfied repairs such as mounting `admin.router` or removing auth-side referral coupling that current runtime no longer contains
- stale media task artifacts no longer treat removed playback or api-media surfaces as active runtime truth when current route inventory disproves that claim

## Stop Conditions

- stop if the task would change contract law rather than correcting contradicted implementation-drift notes
- stop if a claimed contradiction is not backed by mounted runtime truth and existing guard tests
- stop if doc repair attempts to reopen canonical core authority decisions

## Out Of Scope

- new contract creation
- runtime implementation
- optional later hardening in dead-code support domains
