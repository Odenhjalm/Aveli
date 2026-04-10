# OET-011 REQUIRED OUTROOTING GATE

- TYPE: `AGGREGATE`
- GROUP: `AGGREGATE`
- REQUIRED BEFORE FUTURE CORE FEATURE WORK: `YES`
- EXECUTION CLASS: `COMPLETION GATE`

## Problem Statement

The required outrooting lane is complete only if mounted runtime authority drift is removed, JWT shadow claims are neutralized, tests assert current truth, and contradicted planning artifacts are corrected without touching the canonical core.

## Contract References

- [auth_onboarding_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/auth_onboarding_contract.md)
- [commerce_membership_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/commerce_membership_contract.md)
- [course_access_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/course_access_contract.md)
- [course_monetization_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/course_monetization_contract.md)

## Audit Inputs

- `OEA-01`
- `OEA-02`
- `OEA-03`
- `OEA-04`
- `OEA-05`
- `OEA-07`
- `OEA-08`

## Implementation Surfaces Affected

- `backend/app/repositories/home_audio_sources.py`
- `backend/app/models.py`
- `backend/app/routes/studio.py`
- `backend/app/routes/api_events.py`
- `backend/app/routes/auth.py`
- `backend/tests`
- `actual_truth/contracts`
- `actual_truth/DETERMINED_TASKS`

## Depends On

- `OET-001`
- `OET-002`
- `OET-003`
- `OET-004`
- `OET-006`
- `OET-007`

## Acceptance Criteria

- no mounted studio home-audio authority path in scope uses `created_by`
- no mounted studio quiz authority path in scope uses `created_by`
- no mounted events owner-only path in scope uses `created_by` as a legacy shortcut
- JWT payloads in scope no longer function as a second authority surface beside canonical auth-subject reads
- scoped tests align to mounted runtime truth
- scoped contracts and task artifacts no longer contain proven contradicted implementation-drift claims
- the canonical core remains untouched
- any remaining work is confined to `OET-005`, `OET-008`, `OET-009`, and `OET-010`

## Stop Conditions

- stop if any required task still needs a core authority decision to be reopened
- stop if required cleanup would touch `auth.users`, `app.auth_subjects`, `app.memberships`, `app.orders`, `app.payments`, or `app.course_enrollments`
- stop if mounted runtime still exposes evidence-backed active authority drift after supposed completion

## Out Of Scope

- optional later hardening
- dormant sessions and alias cleanup
- support-surface introspection cleanup
