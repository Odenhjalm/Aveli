# Outrooting Execution Plan

## Source Restriction

This plan is derived from these files only:

- `DRIFT_MANIFEST.json`
- `DRIFT_REGISTER.md`
- `OUTROOTING_PRIORITY_MAP.md`
- `CANONICAL_VS_NONAUTHORITATIVE_BOUNDARY.md`

No other source is used to define scope, authority, ordering, or verification in this plan.

## Planning Boundary

This is a no-code execution plan.

It does not:

- implement outrooting
- expand the drift register
- reinterpret canonical authority
- authorize mutation by itself

Any later execution task must preserve the canonical boundary exactly as defined in `CANONICAL_VS_NONAUTHORITATIVE_BOUNDARY.md`.

## Global Pre-Checks Before Any Mutation

Every future outrooting task must pass all pre-checks below before code mutation is allowed:

1. Confirm the target drift item still exists in both `DRIFT_MANIFEST.json` and `DRIFT_REGISTER.md` without scope expansion.
2. Confirm the proposed mutation scope is limited to the files and surfaces already recorded for that drift item.
3. Confirm no locked baseline slot, lockfile entry, or mounted canonical authority path is in the proposed edit set.
4. Confirm the action class matches this plan for the target drift item.
5. Confirm verification criteria are defined before edits start.
6. Confirm the task is isolated if it touches a different drift item, a different doctrine, or a different verification surface.
7. Confirm any overlap with canonical authority is split out and preserved unchanged.
8. Confirm newly discovered drift is treated as a stop condition rather than silently absorbed into the active task.

If any pre-check fails, execution must stop before mutation.

## Execution Ordering

Execution order follows the priority map and is expressed as isolated waves:

1. Wave 1: profile and recording transition-layer collapse
   - `LOF-005`
   - `LOF-004`
2. Wave 2: alternate read and playback path isolation
   - `LOF-002`
   - `LOF-003`
3. Wave 3: membership compatibility transition collapse
   - `LOF-001`
4. Wave 4: stale broader test alignment
   - `LOF-006`

## Grouping Strategy

Logical grouping is allowed only for planning and sequencing.

Execution grouping rules:

- `LOF-005` and `LOF-004` belong to the same program wave because both remove the profile and recording legacy doctrine, but they should execute as separate isolated tasks.
- `LOF-002` and `LOF-003` belong to the same program wave because both fence alternate non-canonical access paths, but they should execute as separate isolated tasks.
- `LOF-001` must stay isolated because it touches app-entry semantics and Stripe-era compatibility residue.
- `LOF-006` must stay last and isolated because it should reflect already-completed runtime and payload cleanup rather than lead it.

No pair in `LOF-001` through `LOF-006` should be executed as one combined mutation task.

## Per-Item Execution Plan

## LOF-005

- Action: `collapse transition layer`
- Planned wave: `Wave 1`
- Regression risk: `HIGH`

### Post-Condition

The listed studio, seminar, ingest, schema, and frontend payload surfaces no longer preserve a legacy recording doctrine built around `asset_url`, source-list arrays, or source-specific recording variants.

The surviving path uses the canonical media and studio-session doctrine only.

### Affected Files And Surfaces

- `backend/app/routes/studio.py::recording placeholder upload path`
- `backend/app/repositories/seminars.py::get_recording_by_asset_url`
- `backend/app/repositories/seminars.py::upsert_recording`
- `backend/app/services/livekit_events.py::recording ingest path`
- `backend/app/schemas.py::SeminarRecordingResponse`
- `backend/app/schemas/__init__.py::SeminarRecordingResponse`
- `frontend/lib/data/models/seminar.g.dart`
- `frontend/lib/data/models/teacher_profile_media.dart::TeacherProfileMediaKind`
- `frontend/lib/data/models/teacher_profile_media.dart::TeacherProfileLessonSource`
- `frontend/lib/data/models/teacher_profile_media.dart::TeacherProfileRecordingSource`
- `frontend/lib/data/models/teacher_profile_media.dart::lessonMediaSources`
- `frontend/lib/data/models/teacher_profile_media.dart::seminarRecordingSources`

### Must Not Touch

- locked baseline slots `0001` through `0019`
- `backend/supabase/baseline_slots.lock.json`
- mounted canonical media authority already protected by the baseline gates
- canonical profile/community authority already accepted into the locked baseline path

### Required Pre-Checks

- confirm the task remains restricted to the listed backend and frontend payload surfaces
- confirm no proposed edit depends on rewriting mounted canonical authority instead of collapsing residual transition code
- confirm verification can prove removal of `asset_url` and source-list doctrine from the listed scope

### Verification Criteria

- no listed surface preserves `asset_url` as active runtime truth
- no listed surface preserves source-list payload doctrine as active runtime truth
- the remaining path in scope is consistent with the canonical single media-object and `recording_url` doctrine already named in the foundation set
- the canonical boundary remains unchanged

## LOF-004

- Action: `collapse transition layer`
- Planned wave: `Wave 1`
- Regression risk: `MEDIUM`

### Post-Condition

The listed cleanup, model, script, and migration-adjacent surfaces no longer treat `teacher_profile_media` as an active non-authoritative feature model.

After outrooting, any surviving historical reference in this scope must be clearly non-active and non-authoritative, or the reference must be removed.

### Affected Files And Surfaces

- `backend/app/services/media_cleanup.py`
- `backend/app/models.py`
- `backend/scripts/media_doctor.py`
- `backend/supabase/migrations/20260331_profile_media_identity_cleanup.sql`
- `backend/supabase/migrations/20260320075542_remote_schema.sql`

### Must Not Touch

- locked baseline slots `0001` through `0019`
- `backend/supabase/baseline_slots.lock.json`
- canonical `profile_media_placements` authority
- mounted unified `runtime_media` authority

### Required Pre-Checks

- confirm `LOF-005` is either complete or independently non-blocking for this cleanup task
- confirm the task does not remove anything still required by the canonical profile/community doctrine
- confirm historical migration handling is separated from canonical baseline authority

### Verification Criteria

- the listed active cleanup and model surfaces no longer use `teacher_profile_media` as live truth
- migration-adjacent residual references in scope are either removed or explicitly non-authoritative
- canonical profile/community authority remains unchanged

## LOF-002

- Action: `isolate`
- Planned wave: `Wave 2`
- Regression risk: `HIGH`

### Post-Condition

The listed raw-table repository and service helpers are no longer able to act as mounted read authority for learner-facing flows.

After outrooting, canonical DB surfaces remain the only mounted read path in the governed area.

### Affected Files And Surfaces

- `backend/app/repositories/courses.py::get_course_public_content`
- `backend/app/repositories/courses.py::upsert_course_public_content`
- `backend/app/repositories/courses.py::list_course_lessons`
- `backend/app/repositories/courses.py::list_lesson_media`
- `backend/app/repositories/courses.py::list_lesson_media_for_studio`
- `backend/app/repositories/courses.py::list_lesson_media_by_ids_for_studio`
- `backend/app/services/courses_service.py::fetch_course_public_content`
- `backend/app/services/courses_service.py::upsert_course_public_content`
- `backend/app/services/courses_service.py::list_course_lessons`
- `backend/app/services/courses_service.py::list_lesson_media`
- `backend/app/services/courses_service.py::list_studio_lesson_media`

### Must Not Touch

- canonical DB surfaces accepted in the locked baseline chain
- mounted learner read authority already proven by the baseline gates
- locked baseline slots `0001` through `0019`
- `backend/supabase/baseline_slots.lock.json`

### Required Pre-Checks

- confirm the task is limited to the listed helper surfaces
- confirm the goal is isolation from mounted authority, not redesign of canonical DB surfaces
- confirm verification can prove that canonical surfaces remain the only mounted path

### Verification Criteria

- the listed helpers no longer function as mounted authority paths
- canonical DB surfaces remain the only mounted authority path for the governed read flows
- no canonical boundary file or mounted canonical doctrine is modified as part of convenience cleanup

## LOF-003

- Action: `isolate`
- Planned wave: `Wave 2`
- Regression risk: `MEDIUM`

### Post-Condition

The listed home-audio fallback branch is either removed from mounted reach or conclusively fenced so it cannot act as an alternate runtime-media resolver path.

After outrooting, unified `runtime_media` remains the only mounted playback doctrine in this area.

### Affected Files And Surfaces

- `backend/app/services/home_audio_service.py::_compose_home_audio_media`
- `backend/app/services/lesson_playback_service.py::resolve_media_asset_playback`

### Must Not Touch

- mounted canonical home-player authority already aligned through unified `runtime_media`
- locked baseline slots `0001` through `0019`
- `backend/supabase/baseline_slots.lock.json`

### Required Pre-Checks

- confirm the task begins by proving whether the listed branch is mounted or only residual
- confirm no edit is framed as a replacement for canonical home-player authority
- confirm verification can prove that no second playback doctrine remains reachable

### Verification Criteria

- the listed branch is no longer mounted as an alternate runtime-media resolver
- unified `runtime_media` remains the only mounted playback doctrine in scope
- no canonical media boundary is modified

## LOF-001

- Action: `collapse transition layer`
- Planned wave: `Wave 3`
- Regression risk: `MEDIUM`

### Post-Condition

The listed membership repository surfaces no longer preserve subscription-oriented helper doctrine or Stripe-era compatibility semantics as a shadow app-entry authority.

After outrooting, canonical membership terminology and authority remain uncontested in the listed scope.

### Affected Files And Surfaces

- `backend/app/repositories/memberships.py::get_latest_subscription`
- `backend/app/repositories/memberships.py::_OPTIONAL_COMPAT_MEMBERSHIP_COLUMNS`
- `backend/app/repositories/memberships.py::get_membership_by_stripe_reference`
- `backend/app/repositories/memberships.py::set_customer_id`
- `backend/app/repositories/memberships.py::upsert_membership_record`
- `backend/app/repositories/subscriptions.py::get_latest_subscription`
- `backend/app/repositories/subscriptions.py::get_membership`

### Must Not Touch

- canonical app-entry authority through memberships
- canonical auth-subject authority
- locked baseline slots `0001` through `0019`
- `backend/supabase/baseline_slots.lock.json`

### Required Pre-Checks

- confirm the task is limited to subscription-era compatibility residue rather than canonical membership truth
- confirm no billing or Stripe migration need is being silently reintroduced into canonical app-entry authority
- confirm verification can prove that only membership authority remains in the listed scope

### Verification Criteria

- the listed scope no longer presents subscription doctrine as shadow authority beside memberships
- canonical membership terminology and ownership remain the only authority path in scope
- no canonical baseline-owned membership shape is rewritten as part of cleanup

## LOF-006

- Action: `replace with canonical path`
- Planned wave: `Wave 4`
- Regression risk: `LOW`

### Post-Condition

The listed broader integration test surface asserts the canonical unified media object doctrine rather than the retired course-cover payload shape.

After outrooting, the test surface no longer encodes the legacy `source` field as truth.

### Affected Files And Surfaces

- `backend/tests/test_course_cover_read_contract.py`

### Must Not Touch

- locked baseline slots `0001` through `0019`
- `backend/supabase/baseline_slots.lock.json`
- canonical media contracts and mounted authority paths

### Required Pre-Checks

- confirm upstream media-path cleanup that affects payload doctrine is already complete or explicitly out of scope for this task
- confirm the task updates assertions only, not canonical media doctrine
- confirm verification can prove the test now asserts the canonical media object shape only

### Verification Criteria

- the listed test surface no longer asserts the legacy `source` field
- the listed test surface asserts only the canonical unified media object doctrine
- no runtime authority is changed by the task

## First Isolated Execution Candidate

If execution is authorized after this plan review, the first isolated outrooting task should be `LOF-005`.

Reason:

- it is `HIGH` priority
- it is the first item in the priority map's opening wave
- it removes the broadest surviving payload transition layer before cleanup and test follow-through

## Stop Condition

This plan stops before implementation.

No execution, mutation, outrooting, or canonical reinterpretation is authorized by this artifact alone.
