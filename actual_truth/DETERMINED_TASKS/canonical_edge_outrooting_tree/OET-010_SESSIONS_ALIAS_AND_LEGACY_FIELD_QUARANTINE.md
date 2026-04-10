# OET-010 SESSIONS ALIAS AND LEGACY FIELD QUARANTINE

- TYPE: `OWNER`
- GROUP: `INACTIVE / DEAD-CODE QUARANTINE`
- REQUIRED BEFORE FUTURE CORE FEATURE WORK: `NO`
- EXECUTION CLASS: `OPTIONAL LATER HARDENING`

## Problem Statement

Dormant sessions edges still retain `stripe_price_id`, inactive session routes still survive, and alias-normalization plus legacy upload or media helper residue remains in inactive or support-only code.

These are not current core blockers, but they still enlarge the outrooting perimeter.

## Contract References

- [course_monetization_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/course_monetization_contract.md)
- [course_access_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/course_access_contract.md)

## Audit Inputs

- `OEA-11`
- `OEA-12`

## Implementation Surfaces Affected

- `backend/app/services/booking_service.py`
- `backend/app/repositories/sessions.py`
- `backend/app/routes/studio_sessions.py`
- `backend/app/routes/session_slots.py`
- `backend/app/schemas/__init__.py`
- `backend/app/utils/lesson_content.py`
- `backend/app/routes/upload.py`
- `backend/app/routes/media.py`

## Depends On

- `OET-011`

## Acceptance Criteria

- dormant sessions surfaces no longer retain `stripe_price_id` as live-looking commerce residue
- alias-normalization helpers remain only if a scoped mounted consumer still requires them; otherwise they are removed or explicitly quarantined
- legacy upload and media helpers are either clearly support-only or removed from ambiguous runtime-looking paths
- no scoped change touches canonical course or bundle monetization, purchase substrate, or media core authority

## Stop Conditions

- stop if the task would mutate canonical purchase or monetization core to satisfy dormant cleanup
- stop if a mounted studio path still requires a scoped helper and no safe replacement exists
- stop if dormant legacy fields remain capable of being mistaken for canonical truth after completion

## Out Of Scope

- active mounted authority drift
- events domain cleanup
- contract changes
