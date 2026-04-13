# ACE-003_CONTRACT_DEFERRAL_CLEANUP

## TASK_ID

ACE-003

## TYPE

CONTRACT_UPDATE

## OWNER

OWNER

## DEPENDS_ON

[
  "ACE-002"
]

## GOAL

Materialize the future contract update that cleans overlap and adds explicit deferrals across adjacent contracts after `GET /entry-state` is locked by `ACE-002`.

## SCOPE

- `actual_truth/contracts/auth_onboarding_contract.md`
- `actual_truth/contracts/profile_projection_contract.md`
- `actual_truth/contracts/onboarding_contract.md`
- `actual_truth/contracts/commerce_membership_contract.md`
- `actual_truth/contracts/onboarding_teacher_rights_contract.md`

## EXACT REQUIRED CONTRACT CHANGES

When `ACE-003` is executed later, update only the scoped contracts to add or clarify these deferrals:

- In `auth_onboarding_contract.md`, keep `/profiles/me` as current profile projection read/update only, remove or qualify any wording that makes it a canonical post-auth entrypoint, and add a delegated `GET /entry-state` reference for post-auth routing decisions.
- In `auth_onboarding_contract.md`, state that Auth + Onboarding owns credential, token, email-verification, and onboarding-completion execution only; it does not own full post-auth entry composition.
- In `profile_projection_contract.md`, add stronger wording that `/profiles/me` must never be required before post-auth routing decisions and must never bootstrap, repair, infer, or replace `GET /entry-state`.
- In `onboarding_contract.md`, reduce the contract to a UX companion for onboarding copy, pre-entry UI sequencing, and onboarding completion intent only; remove or qualify the "single source of truth" claim so it cannot compete with `onboarding_entry_authority_contract.md`.
- In `onboarding_contract.md`, preserve its `/entry-state` frontend usage direction only as a reference to `onboarding_entry_authority_contract.md`, not as local authority.
- In `commerce_membership_contract.md`, replace membership-only app-access IF AND ONLY IF wording with wording that membership lifecycle and current membership state are owned there, while full post-auth entry composition and routing are deferred to `onboarding_entry_authority_contract.md`.
- In `onboarding_teacher_rights_contract.md`, clarify that it owns field authority, role/admin semantics, and teacher-rights mutation execution only; it does not own full post-auth entry composition or routing.
- Across all scoped contracts, remove overlapping authority claims that redefine entry composition, duplicate `/entry-state`, or make `/profiles/me`, membership alone, role/admin fields alone, onboarding UX, checkout state, invite state, referral state, frontend route metadata, or token claims complete post-auth routing authority.

## FORBIDDEN ACTIONS

- Do not edit contract files during this materialization step.
- Do not create `ACE-004`, `ACE-005`, `ACE-006`, `ACE-007`, or any later task.
- Do not create backend, frontend, or test alignment tasks.
- Do not edit backend files.
- Do not edit frontend files.
- Do not edit tests.
- Do not assume entry authority is already consolidated before `ACE-003` executes.
- During later `ACE-003` execution, do not edit contracts outside the declared scope.
- Do not introduce hidden fallback authority through legacy wording, compatibility language, route metadata, or projection success.

## ACCEPTANCE CRITERIA

- `auth_onboarding_contract.md` contains delegated `GET /entry-state` wording and no longer treats `/profiles/me` as post-auth entry-routing authority.
- `profile_projection_contract.md` explicitly says `/profiles/me` must never be required before post-auth routing decisions.
- `onboarding_contract.md` is reduced to a UX companion and no longer claims to be the single source of truth for entry authority.
- `commerce_membership_contract.md` defers full post-auth entry composition while preserving membership lifecycle and current membership state ownership.
- `onboarding_teacher_rights_contract.md` distinguishes field authority, execution authority, and post-auth entry composition.
- No scoped contract duplicates the `GET /entry-state` response shape owned by `onboarding_entry_authority_contract.md`.
- No backend, frontend, test, or `ACE-004+` files are created.
- The task remains classified as `BLOCKER-RESOLUTION` for the later implementation tree.

## BLOCKERS

- `ACE-003` depends on `ACE-002` because adjacent contracts cannot defer to the entry-authority lock until `GET /entry-state` is defined there.
- `ACE-004` and later backend, frontend, and test alignment trees remain blocked until these adjacent contract overlaps are cleaned.

## VERIFICATION STEPS

- Confirm only the five scoped contracts changed.
- Confirm `auth_onboarding_contract.md` delegates post-auth routing decisions to `GET /entry-state`.
- Confirm `profile_projection_contract.md` explicitly forbids requiring `/profiles/me` before post-auth routing decisions.
- Confirm `onboarding_contract.md` is UX companion only and no longer claims single-source entry authority.
- Confirm `commerce_membership_contract.md` defers full entry composition to `onboarding_entry_authority_contract.md`.
- Confirm `onboarding_teacher_rights_contract.md` separates field authority, mutation execution, and entry composition.
- Confirm no backend, frontend, test, or `ACE-004+` files were created.

## PROMPT

```text
Execute ACE-003 as a contract-only update after ACE-002 is complete. Update only actual_truth/contracts/auth_onboarding_contract.md, actual_truth/contracts/profile_projection_contract.md, actual_truth/contracts/onboarding_contract.md, actual_truth/contracts/commerce_membership_contract.md, and actual_truth/contracts/onboarding_teacher_rights_contract.md. Add explicit deferrals so post-auth routing composition belongs only to onboarding_entry_authority_contract.md and GET /entry-state. Cover delegated /entry-state in auth_onboarding_contract.md, stronger /profiles/me non-bootstrap wording, onboarding_contract as UX companion only, commerce membership deferral for full entry composition, and teacher-rights separation between field authority, execution, and entry composition. Do not edit backend, frontend, tests, or any unscoped contract. Confirm no ACE-004+ task is created.
```

USER_FACING_PRODUCT_TEXT_REQUIREMENT: Swedish only if product text is touched; this task is not expected to touch product text. Task prompt remains English.
