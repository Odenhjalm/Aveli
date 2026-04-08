# AOI-001 AUTH RUNTIME SUBSTRATE SLOT

TYPE: `OWNER`  
TASK_TYPE: `BASELINE_SLOT`  
DEPENDS_ON: `[]`

## Goal

Create append-only baseline slot `0023_auth_runtime_substrate.sql` to add the canonical auth runtime substrate required by `auth_onboarding_baseline_contract.md`.

## Required Outputs

- table `app.refresh_tokens`
- table `app.auth_events`
- only the minimum fields required by contract

## Forbidden

- modifying accepted baseline slots
- adding teacher-request or certificate tables
- adding avatar/media tables
- relying on runtime introspection or pre-existing remote state

## Exit Criteria

- `0023_auth_runtime_substrate.sql` exists
- baseline objects match contract names exactly
- no non-canonical auth tables are introduced
