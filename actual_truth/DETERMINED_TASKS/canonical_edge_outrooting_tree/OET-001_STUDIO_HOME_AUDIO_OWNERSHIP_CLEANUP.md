# OET-001 STUDIO HOME AUDIO OWNERSHIP CLEANUP

- TYPE: `OWNER`
- GROUP: `ACTIVE AUTHORITY DRIFT`
- REQUIRED BEFORE FUTURE CORE FEATURE WORK: `YES`
- EXECUTION CLASS: `BLOCKER`
- CURRENT STATUS: `HISTORICAL / VERIFIED COMPLETE`

## Historical Note

The problem statement below records the pre-execution audit state and is retained only as historical task context.

## Problem Statement

Mounted studio home-audio course-link behavior still resolves course ownership through `c.created_by AS teacher_id` inside `backend/app/repositories/home_audio_sources.py`, and mounted `backend/app/routes/studio.py` consumes that result for `/studio/home-player/course-links`.

This leaves a live legacy ownership path beside the already-ratified canonical course ownership substrate in `app.courses.teacher_id`.
Active home-audio inclusion still belongs to `app.home_player_course_links`, so this task may only clean legacy ownership consumption around that substrate after the substrate itself is explicitly baseline-owned.

## Contract References

- [course_monetization_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/course_monetization_contract.md)
- [home_audio_aggregation_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/home_audio_aggregation_contract.md)
- [supabase_integration_boundary_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/supabase_integration_boundary_contract.md)

## Audit Inputs

- `OEA-01`
- `OEA-02`

## Implementation Surfaces Affected

- `backend/app/repositories/home_audio_sources.py`
- `backend/app/routes/studio.py`
- `backend/app/repositories/courses.py`

## Depends On

- `BCP-042AA_append_home_player_course_link_inclusion_substrate`
- `CMTZ-001_BASELINE_OWNERSHIP_AND_MONETIZATION_FOUNDATION`
- `AOI-003_baseline_bound_auth_persistence`

## Acceptance Criteria

- mounted `/studio/home-player/course-links` no longer resolves course owner through `c.created_by`
- studio home-audio ownership consumes only canonical course ownership already owned by `app.courses.teacher_id`
- `app.home_player_course_links` remains the active home-audio inclusion substrate and this task only removes legacy ownership drift around that substrate
- the mounted studio route remains a consumer of canonical ownership truth rather than a second authority surface
- no mutation or reinterpretation of `auth.users`, `app.auth_subjects`, `app.memberships`, `app.orders`, `app.payments`, or `app.course_enrollments` occurs
- no new ownership field, alias, or fallback ownership helper is introduced

## Stop Conditions

- stop if the task proposes a new course-ownership model instead of consuming `app.courses.teacher_id`
- stop if the task would redefine or replace `app.home_player_course_links` instead of consuming the baseline-owned substrate
- stop if any scoped change touches checkout, webhook, membership, order, payment, or course-enrollment core
- stop if `created_by` remains in the mounted home-audio ownership path after the task is complete

## Out Of Scope

- studio quiz authority
- events authority
- JWT claim cleanup
- any contract rewrite
