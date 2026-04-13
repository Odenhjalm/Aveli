# ENTRY AUTHORITY CONTRACT CONSOLIDATION DAG

TREE_CLASSIFICATION: `BLOCKER-RESOLUTION`
PHASE: `CONTRACT_ONLY_PRE_IMPLEMENTATION`
MUTATION_SCOPE: `TASK_DEFINITION_FILES_ONLY`

## DAG

`ACE-001` → `ACE-002` → `ACE-003`

## What Each Task Locks

- `ACE-001` locks the system-law pointer that post-auth entry authority has exactly one canonical owner: `actual_truth/contracts/onboarding_entry_authority_contract.md`.
- `ACE-002` locks `GET /entry-state` inside `actual_truth/contracts/onboarding_entry_authority_contract.md` as the single canonical post-auth routing authority surface, including allowed fields, forbidden fields, `/profiles/me` separation, pre-entry UI selection separation, and explicit deferrals to auth, profile, membership, and teacher-rights contracts.
- `ACE-003` cleans overlap across adjacent contracts so auth, profile projection, UX onboarding, commerce membership, and teacher-rights contracts reference or defer to the entry authority instead of redefining entry composition.

## Why ACE-004+ Is Blocked

`ACE-004` and later implementation-alignment trees are blocked until this DAG executes because the authoritative contracts do not yet fully lock the consolidated entry truth. Current blockers include:

- `onboarding_entry_authority_contract.md` does not yet define `GET /entry-state` as the sole post-auth routing authority.
- `onboarding_contract.md` still claims "single source of truth" while also pointing frontend to `/entry-state`.
- `auth_onboarding_contract.md` still lists `/profiles/me` inside canonical entrypoints without the required post-auth entry deferral wording.
- `profile_projection_contract.md` still needs explicit wording that `/profiles/me` must never be required before post-auth routing decisions.
- `commerce_membership_contract.md` still expresses membership-only app access as an IF AND ONLY IF rule instead of explicitly deferring full entry composition.

Until those contract overlaps are resolved, backend, frontend, and test alignment tasks would risk implementing hidden assumptions about consolidated truth.

## Scope Boundary

This tree is contract-only and pre-implementation. It creates no backend tasks, no frontend tasks, no test-alignment tasks, and no `ACE-004` or later tasks. Contract files must not be edited during this materialization pass; they may be edited only when `ACE-001`, `ACE-002`, and `ACE-003` are executed as their own contract-update tasks.

## Language And Prompt Check

This tree introduces no user-facing product text. Any future user-facing product text touched by execution of this DAG must remain Swedish. Task prompts are copy-pasteable and written in English.
