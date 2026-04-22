# COURSE DRIP SCHEDULE CONTRACT

## STATUS

ACTIVE

This contract is the only canonical owner of course drip scheduling semantics.
It operates under `SYSTEM_LAWS.md`, `AVELI_COURSE_DOMAIN_SPEC.md`, and
`course_access_contract.md`.

This contract owns:

- legacy uniform drip semantics on `app.courses`
- custom lesson-offset drip semantics on
  `app.course_custom_drip_configs` and
  `app.course_custom_drip_lesson_offsets`
- mode resolution
- enrollment initialization rules
- worker advancement rules
- invalid-state fail-closed behavior
- post-enrollment schedule lock semantics

This contract does not own:

- learner/public response shapes
- editor request/response shapes
- protected lesson-access gating semantics

## 1. CONTRACT LAW

- Course drip scheduling has exactly one canonical semantic owner:
  `course_drip_schedule_contract.md`.
- Legacy uniform drip remains canonical only on
  `app.courses.drip_enabled` and `app.courses.drip_interval_days`.
- Custom lesson-offset drip remains canonical only on
  `app.course_custom_drip_configs` and
  `app.course_custom_drip_lesson_offsets`.
- Active scheduling authority on one course is mutually exclusive:
  `custom_lesson_offsets`, `legacy_uniform_drip`, or `no_drip_immediate_access`.
- Presence of a valid `app.course_custom_drip_configs` row selects custom mode.
  No additional persisted mode field is allowed.
- `app.course_enrollments.current_unlock_position` remains the only canonical
  stored unlock state.
- Unlock progression remains worker-owned. Frontend and learner runtime must not
  compute unlock state.
- `app.lessons` remains structure-only and `app.course_enrollments` remains
  access-state-only.

## 2. CANONICAL AUTHORITIES

Legacy uniform scheduling authority:

- `app.courses.drip_enabled`
- `app.courses.drip_interval_days`

Custom lesson-offset scheduling authority:

- `app.course_custom_drip_configs.course_id`
- `app.course_custom_drip_lesson_offsets.course_id`
- `app.course_custom_drip_lesson_offsets.lesson_id`
- `app.course_custom_drip_lesson_offsets.unlock_offset_days`

Access-state authority:

- `app.course_enrollments.granted_at`
- `app.course_enrollments.drip_started_at`
- `app.course_enrollments.current_unlock_position`

Lesson ordering authority:

- `app.lessons.position`

Forbidden as schedule authority:

- custom drip fields on `app.lessons`
- custom drip snapshot fields on `app.course_enrollments`
- frontend-derived unlock logic
- mixed legacy and custom active authority on one course
- fallback from invalid custom state to legacy or no-drip

## 3. LEGACY UNIFORM DRIP

Legacy uniform drip is active only when:

- no `app.course_custom_drip_configs` row exists for the course
- `app.courses.drip_enabled = true`
- `app.courses.drip_interval_days > 0`

Legacy uniform semantics:

- unlock anchor is `app.course_enrollments.drip_started_at`
- `drip_started_at` remains equal to `granted_at`
- enrollment initialization unlocks lesson position `1` when lessons exist
- worker advancement computes:
  `1 + floor((evaluated_at - drip_started_at) / drip_interval_days)`
- computed unlock position is clamped to the highest existing lesson position
- worker updates only when the computed unlock position is greater than the
  stored position

## 4. CUSTOM LESSON-OFFSET DRIP

Custom lesson-offset drip is active only when a
`app.course_custom_drip_configs` row exists for the course and the schedule is
valid.

Custom schedule meaning:

- one child row exists for each lesson on the course
- `unlock_offset_days` is the cumulative day offset from
  `app.course_enrollments.drip_started_at`
- offsets are interpreted in `app.lessons.position` order
- the first lesson offset is `0` when lessons exist
- offsets are nondecreasing by lesson position

Custom mode also requires:

- `app.courses.drip_enabled = false`
- `app.courses.drip_interval_days is null`

## 5. MODE RESOLUTION

Canonical mode resolution order:

1. if a custom config row exists, custom mode is selected and the custom
   schedule must validate
2. else if `app.courses.drip_enabled = true`, legacy uniform drip is active
3. else the course is `no_drip_immediate_access`

Fail-closed rules:

- invalid custom mode must raise and block runtime mutation
- invalid custom mode must not silently fall back to legacy uniform drip
- invalid custom mode must not silently fall back to no-drip
- legacy uniform drip must raise if `drip_enabled = true` and
  `drip_interval_days` is not positive

## 6. ENROLLMENT INITIALIZATION

`app.canonical_create_course_enrollment(...)` is the only canonical enrollment
creation path.

Initialization rules:

- no-drip courses unlock the highest existing lesson position immediately
- legacy uniform drip unlocks lesson position `1` when lessons exist
- custom lesson-offset drip unlocks the highest lesson position whose
  `unlock_offset_days = 0`
- all modes set `drip_started_at = granted_at`

## 7. WORKER ADVANCEMENT

`app.canonical_worker_advance_course_enrollment_drip(...)` is the only
canonical drip advancement path.

Worker rules:

- worker reads live course scheduling authority
- worker owns all mutations of `current_unlock_position`
- worker must never decrease `current_unlock_position`
- custom mode computes the highest lesson position whose `unlock_offset_days`
  is less than or equal to elapsed days from `drip_started_at`
- no-drip mode is a no-op because enrollment initialization already grants the
  full available lesson range

## 8. POST-ENROLLMENT SCHEDULE LOCK

Once any `app.course_enrollments` row exists for a course, all
schedule-affecting edits are forbidden.

Schedule-affecting edits include:

- inserting or deleting a custom config root
- inserting, updating, or deleting lesson-offset rows
- switching between legacy, custom, and no-drip modes
- editing `app.courses.drip_enabled` or `app.courses.drip_interval_days` on a
  custom-mode course
- lesson insert
- lesson delete
- lesson reorder
- any future lesson-visibility change that changes unlock-order participation

Allowed after enrollment:

- lesson content-only edits
- lesson title edits
- non-schedule course metadata edits that do not change scheduling authority or
  lesson unlock order

## 9. CROSS-CONTRACT BOUNDARY

- `AVELI_COURSE_DOMAIN_SPEC.md` retains field-location facts, entity map, and
  course-domain boundaries only.
- `course_lesson_editor_contract.md` owns only editor read/write shapes. It
  must not define scheduling semantics, mode resolution, worker behavior, or
  schedule locks.
- `course_access_contract.md` owns protected access gating only. It must not
  define how unlock position is computed.
- `course_public_surface_contract.md` and `learner_public_edge_contract.md`
  own learner/public serialization only. They must not define drip semantics.
