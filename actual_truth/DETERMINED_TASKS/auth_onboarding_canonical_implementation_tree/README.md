# AUTH_ONBOARDING_CANONICAL_IMPLEMENTATION_TREE

`input(task="Generate deterministic Auth + Onboarding implementation task tree from approved canonical decision package", mode="generate")`

## Scope

- Canonical truth is limited to:
  - `actual_truth/contracts/auth_onboarding_contract.md`
  - `actual_truth/contracts/auth_onboarding_failure_contract.md`
  - `actual_truth/contracts/auth_onboarding_baseline_contract.md`
  - `actual_truth/contracts/onboarding_teacher_rights_contract.md`
  - `actual_truth/contracts/profile_projection_contract.md`
  - `actual_truth/contracts/referral_membership_grant_contract.md`
- Repository code is legacy reference only.
- Deferred binary avatar/media work is explicitly out of scope.
- This artifact is implementation planning only.

## Contract Materialization Note

- Canonical contract decisions were materialized during this generate run.
- Because that truth now exists under `actual_truth/contracts/`, no further `CONTRACT_UPDATE` task is required in the downstream implementation tree.

## Materialized Task Order

1. `AOI-001` baseline auth runtime substrate slot
2. `AOI-002` admin bootstrap operator surface slot
3. `AOI-003` baseline-bound auth persistence and fallback removal
4. `AOI-004` onboarding completion route alignment
5. `AOI-005` teacher role admin grant/revoke alignment
6. `AOI-006` profile projection boundary alignment
7. `AOI-007` referral separation alignment inside auth surfaces
8. `AOI-008` failure envelope and Swedish message alignment
9. `AOI-009` frontend canonical flow alignment
10. `AOI-010` legacy auth/onboarding surface removal
11. `AOI-011` canonical test and verification alignment
12. `AOI-012` aggregate contract-surface verification

## Coverage Map

- Onboarding completion: `AOI-004`, `AOI-009`, `AOI-011`
- Admin bootstrap: `AOI-002`, `AOI-003`, `AOI-011`
- Teacher role authority: `AOI-005`, `AOI-009`, `AOI-010`, `AOI-011`
- Profile projection: `AOI-006`, `AOI-009`, `AOI-010`, `AOI-011`
- Referral separation: `AOI-007`, `AOI-009`, `AOI-010`, `AOI-011`
- Failure contract: `AOI-008`, `AOI-009`, `AOI-011`
- Baseline auth substrate: `AOI-001`, `AOI-002`, `AOI-003`, `AOI-011`
