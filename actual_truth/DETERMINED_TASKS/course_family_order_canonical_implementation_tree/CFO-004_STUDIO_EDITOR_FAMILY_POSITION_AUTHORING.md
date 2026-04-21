# CFO-004 STUDIO EDITOR FAMILY POSITION AUTHORING

- TYPE: `OWNER`
- GROUP: `FRONTEND STUDIO`
- DEPENDS_ON:
  - `CFO-003`

## Problem Statement

The current studio editor cannot author canonical family/order intent.

- create hardcodes a fresh `course_group_id`
- create hardcodes `group_position = 0`
- save/update does not send `course_group_id`
- save/update does not send `group_position`

That means the UI currently blocks every non-singleton-family use case defined
by the contract.

## Contract References

- [AVELI_COURSE_DOMAIN_SPEC.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/AVELI_COURSE_DOMAIN_SPEC.md)
  - `7. PROGRESSION MODEL`
  - `12. FAILURE MODEL`
- [course_lesson_editor_contract.md](/C:/Users/Odenh/app/Aveli/actual_truth/contracts/course_lesson_editor_contract.md)
  - `5. STRUCTURE WRITE CONTRACTS`
  - `7. STRUCTURE READ CONTRACT`
  - `11. FRONTEND ALIGNMENT TARGET`

## Audit Inputs

- `CFA-07`
- `CFA-08`

## Target Files

- `frontend/lib/features/studio/presentation/course_editor_page.dart`
- `frontend/lib/features/studio/presentation/teacher_home_page.dart`
- `frontend/lib/features/studio/data/studio_repository.dart`
- `frontend/lib/features/studio/data/studio_models.dart`
- `frontend/test/unit/studio_repository_course_create_test.dart`
- `frontend/test/widgets/studio_course_family_position_authoring_test.dart`

## Expected Outcome

- studio create flow stops forcing singleton-family creation
- studio edit flow can submit canonical family move and same-family reorder
  intent through backend-owned surfaces
- UI derives selectable family options from backend-authored course list data
- UI does not infer access, pricing, or intro meaning from `group_position`
  beyond displaying backend-owned structure

## Verification Requirement

- repository and widget tests prove create payloads no longer hardcode a fresh
  UUID and `0` without user/backend intent
- update payload tests prove family/order fields are sent when edited
- UI tests prove editor controls are unavailable until backend authoring support
  exists and active once `CFO-003` lands

## Go Condition

- `CFO-003` provides deterministic POST/PATCH behavior and errors
- current studio course list/read surfaces already expose
  `course_group_id` and `group_position`

## Blocked Condition

- blocked if UI would need to invent family truth not present in backend data
- blocked if backend move/reorder semantics are not yet deterministic
- blocked if UI attempts to encode access or monetization meaning in
  `group_position`

## Out Of Scope

- learner/public course rendering
- bundle composition UI

