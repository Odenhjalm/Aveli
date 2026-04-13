# ACE-002_ENTRY_STATE_CONTRACT_LOCK

## TASK_ID

ACE-002

## TYPE

CONTRACT_UPDATE

## OWNER

OWNER

## DEPENDS_ON

[
  "ACE-001"
]

## GOAL

Materialize the future contract update that locks `GET /entry-state` inside `actual_truth/contracts/onboarding_entry_authority_contract.md` as the single canonical post-auth routing authority surface.

## SCOPE

- `actual_truth/contracts/onboarding_entry_authority_contract.md`

## EXACT REQUIRED CONTRACT CHANGES

When `ACE-002` is executed later, update only `actual_truth/contracts/onboarding_entry_authority_contract.md` to lock all of the following:

- `GET /entry-state` is the single canonical post-auth routing authority surface.
- `GET /entry-state` owns post-auth routing decisions after identity validation.
- `GET /entry-state` is the only surface that composes auth-subject onboarding state, membership app-entry state, profile projection readiness, and teacher/admin metadata into post-auth entry decisions.
- The contract must define an exact allowed response field list for `GET /entry-state`.
- The contract must define an exact forbidden response field list for `GET /entry-state`.
- The contract must explicitly state that `/profiles/me` is projection-only and must not be required before post-auth routing decisions.
- The contract must explicitly separate entry truth from pre-entry UI selection, including intro-course selection, payment UI choices, checkout-return state, referral transport, invite transport, and profile form UI state.
- The contract must defer credential, token, email-verification, and onboarding-completion execution details to `auth_onboarding_contract.md`.
- The contract must defer profile projection shape and write boundaries to `profile_projection_contract.md`.
- The contract must defer membership state lifecycle and membership purchase/app-entry state ownership to `commerce_membership_contract.md` while retaining full entry composition inside `onboarding_entry_authority_contract.md`.
- The contract must defer teacher-rights field authority, mutation authority, and role/admin semantics to `onboarding_teacher_rights_contract.md` while retaining post-auth entry composition inside `onboarding_entry_authority_contract.md`.
- The contract must explicitly reject frontend route state, token claims alone, profile hydration alone, Stripe checkout success, membership state alone, teacher/admin role alone, course enrollment, invite token presence, or referral link presence as complete post-auth routing authority.

## FORBIDDEN ACTIONS

- Do not edit contract files during this materialization step.
- Do not create `ACE-004`, `ACE-005`, `ACE-006`, `ACE-007`, or any later task.
- Do not create backend, frontend, or test alignment tasks.
- Do not edit backend files.
- Do not edit frontend files.
- Do not edit tests.
- Do not assume entry authority is already consolidated before `ACE-002` executes.
- During later `ACE-002` execution, do not edit contracts outside the declared scope.
- Do not let `/profiles/me`, `onboarding_contract.md`, membership-only rules, teacher-rights rules, frontend route metadata, or checkout-return state redefine `/entry-state`.

## ACCEPTANCE CRITERIA

- `onboarding_entry_authority_contract.md` identifies `GET /entry-state` as the sole post-auth routing authority surface.
- `onboarding_entry_authority_contract.md` contains exact allowed and forbidden field lists for `GET /entry-state`.
- `onboarding_entry_authority_contract.md` states that `/profiles/me` is not a bootstrap prerequisite for post-auth routing decisions.
- `onboarding_entry_authority_contract.md` separates entry truth from pre-entry UI selection.
- `onboarding_entry_authority_contract.md` contains explicit deferrals to auth, profile, membership, and teacher-rights contracts without giving those contracts ownership of full entry composition.
- No backend, frontend, test, or adjacent contract files are edited by `ACE-002`.
- The task remains classified as `BLOCKER-RESOLUTION` for the later implementation tree.

## BLOCKERS

- `ACE-002` depends on `ACE-001` because detailed `/entry-state` law must sit under a system-law pointer that has already established the canonical owner.
- `ACE-003` is blocked until `ACE-002` defines the consolidated entry-authority truth that adjacent contracts must defer to.
- `ACE-004` and later implementation work remain blocked until this contract lock exists and adjacent contract overlap is cleaned by `ACE-003`.

## VERIFICATION STEPS

- Confirm `actual_truth/contracts/onboarding_entry_authority_contract.md` changed only within the entry-authority lock scope.
- Confirm `GET /entry-state` appears as the single canonical post-auth routing authority surface.
- Confirm exact allowed and forbidden response field lists are present for `GET /entry-state`.
- Confirm `/profiles/me` is explicitly projection-only and not required before post-auth routing decisions.
- Confirm the contract distinguishes entry truth from pre-entry UI selection.
- Confirm deferrals to `auth_onboarding_contract.md`, `profile_projection_contract.md`, `commerce_membership_contract.md`, and `onboarding_teacher_rights_contract.md`.
- Confirm no backend, frontend, test, or `ACE-004+` files were created.

## PROMPT

```text
Execute ACE-002 as a contract-only update after ACE-001 is complete. Update only actual_truth/contracts/onboarding_entry_authority_contract.md. Lock GET /entry-state as the single canonical post-auth routing authority surface, including exact allowed fields, exact forbidden fields, relation to /profiles/me, separation from pre-entry UI selection, and explicit deferrals to auth_onboarding_contract.md, profile_projection_contract.md, commerce_membership_contract.md, and onboarding_teacher_rights_contract.md. Do not edit backend, frontend, tests, or adjacent contracts. Confirm no ACE-004+ task is created.
```

USER_FACING_PRODUCT_TEXT_REQUIREMENT: Swedish only if product text is touched; this task is not expected to touch product text. Task prompt remains English.
