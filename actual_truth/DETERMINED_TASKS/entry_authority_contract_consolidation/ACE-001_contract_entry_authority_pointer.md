# ACE-001_CONTRACT_ENTRY_AUTHORITY_POINTER

## TASK_ID

ACE-001

## TYPE

CONTRACT_UPDATE

## OWNER

OWNER

## DEPENDS_ON

[]

## GOAL

Materialize the future contract update that adds or clarifies the single system-law pointer for post-auth entry authority.

The intended locked truth is:

- post-auth entry authority has exactly one canonical owner
- that owner is `actual_truth/contracts/onboarding_entry_authority_contract.md`
- all other contracts may reference but must not redefine entry composition or routing truth

## SCOPE

- `actual_truth/contracts/SYSTEM_LAWS.md`

## EXACT REQUIRED CONTRACT CHANGES

When `ACE-001` is executed later, update only `actual_truth/contracts/SYSTEM_LAWS.md` to add or clarify a single cross-domain entry-authority pointer with these requirements:

- Define that post-auth entry composition and routing truth have exactly one canonical contract owner.
- Name `actual_truth/contracts/onboarding_entry_authority_contract.md` as that owner.
- State that all other contracts may reference the entry-authority owner but must not redefine entry composition, post-auth routing truth, app-entry composition, or `/entry-state` ownership.
- Keep the law at the system-law pointer level; do not duplicate the `/entry-state` response shape or domain-specific field rules in `SYSTEM_LAWS.md`.

## FORBIDDEN ACTIONS

- Do not edit contract files during this materialization step.
- Do not create `ACE-004`, `ACE-005`, `ACE-006`, `ACE-007`, or any later task.
- Do not create backend, frontend, or test alignment tasks.
- Do not edit backend files.
- Do not edit frontend files.
- Do not edit tests.
- Do not assume entry authority is already consolidated before `ACE-001`, `ACE-002`, and `ACE-003` execute.
- During later `ACE-001` execution, do not edit contracts outside the declared scope.

## ACCEPTANCE CRITERIA

- `SYSTEM_LAWS.md` contains one clear pointer identifying `onboarding_entry_authority_contract.md` as the only canonical owner for post-auth entry composition and routing truth.
- `SYSTEM_LAWS.md` does not duplicate the detailed `/entry-state` response contract.
- No other contract is edited by `ACE-001`.
- The contract update preserves `ACE-002` as the owner of detailed `/entry-state` law.
- The task remains classified as `BLOCKER-RESOLUTION` for the later implementation tree.

## BLOCKERS

- `ACE-002` cannot safely lock `/entry-state` as the detailed authority surface until the system-law owner pointer exists.
- `ACE-004` and later implementation work remain blocked until `ACE-001`, `ACE-002`, and `ACE-003` execute in dependency order.

## VERIFICATION STEPS

- Confirm `actual_truth/contracts/SYSTEM_LAWS.md` changed only within the entry-authority pointer scope.
- Confirm the pointer names `actual_truth/contracts/onboarding_entry_authority_contract.md`.
- Confirm no detailed field list or response shape for `/entry-state` was added to `SYSTEM_LAWS.md`.
- Confirm no backend, frontend, test, or `ACE-004+` files were created.

## PROMPT

```text
Execute ACE-001 as a contract-only update. Update only actual_truth/contracts/SYSTEM_LAWS.md to add or clarify the single system-law pointer that post-auth entry composition and routing truth are owned only by actual_truth/contracts/onboarding_entry_authority_contract.md. Do not edit backend, frontend, tests, or any other contract file. Do not define the /entry-state response shape here; leave detailed /entry-state law for ACE-002. Confirm no ACE-004+ task is created.
```

USER_FACING_PRODUCT_TEXT_REQUIREMENT: Swedish only if product text is touched; this task is not expected to touch product text. Task prompt remains English.
