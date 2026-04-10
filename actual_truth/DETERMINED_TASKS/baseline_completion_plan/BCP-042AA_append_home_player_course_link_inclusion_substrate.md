# BCP-042AA

- TASK_ID: `BCP-042AA`
- TYPE: `OWNER`
- TITLE: `Append baseline ownership for home-player course-link inclusion substrate`
- PROBLEM_STATEMENT: `Active contract and mounted runtime truth still rely on app.home_player_course_links as the source surface for home-audio course-link inclusion, but the baseline completion plan does not yet explicitly own or materialize that substrate. OET-001 therefore cannot legally clean legacy created_by ownership drift until the substrate itself has an explicit append-only baseline owner.`
- IMPLEMENTATION_SURFACES:
  - `backend/supabase/baseline_slots/`
  - `backend/supabase/baseline_slots.lock.json`
  - `app.home_player_course_links`
- TARGET_STATE:
  - append-only baseline ownership exists for `app.home_player_course_links` as the canonical home-audio inclusion substrate for course-linked home audio
  - `enabled` and `lesson_media_id` remain the active source surface for course-link inclusion
  - `teacher_id` is explicitly treated as a derived mirror only and never as course-ownership authority
  - canonical course ownership remains `app.courses.teacher_id -> app.auth_subjects.user_id`
  - mismatched stored `teacher_id` values are treated as drift and not as authority
  - no second inclusion substrate, no runtime-media substitute surface, and no new ownership fields are introduced
- DEPENDS_ON:
  - `BCP-042A`
- EXPECTED_OUTCOME_BEFORE_ACTION:
  - downstream cleanup tasks can depend on an explicit baseline owner for `app.home_player_course_links` instead of assuming the substrate already exists lawfully
- VERIFICATION_METHOD:
  - confirm the append-only baseline plan materializes `app.home_player_course_links` without mutating protected slots
  - confirm `enabled` and `lesson_media_id` remain the only inclusion-truth fields for course-link inclusion under the active contract
  - confirm any retained `teacher_id` column is documented and implemented only as a mirror validated from `lesson_media -> lessons.course_id -> courses.teacher_id`
  - confirm no alternate inclusion table, fallback resolver, or second course-ownership authority is introduced
- CONSTRAINTS:
  - do not reopen or reinterpret canonical course ownership already ratified at `app.courses.teacher_id -> app.auth_subjects.user_id`
  - do not shift course-link inclusion authority into `app.runtime_media`, `app.lesson_media`, or any new substrate
  - do not perform mounted runtime rewiring, route cleanup, or repository changes owned elsewhere
  - do not add new schema fields, fallback inclusion logic, or alternate owner aliases
- STOP_CONDITIONS:
  - stop if active contract truth no longer requires `app.home_player_course_links`
  - stop if append-only baseline materialization would require redefining course ownership instead of consuming `app.courses.teacher_id`
  - stop if `teacher_id` cannot remain mirror-only without reopening the home-audio domain
  - stop if satisfying the missing substrate owner would require runtime implementation inside this task

## CANONICAL SUBSTRATE DEFINITION

- `app.home_player_course_links` is the canonical home-audio inclusion substrate for course-linked home audio.
- It owns inclusion intent only:
  - `enabled`
  - `lesson_media_id`
- It does not own:
  - course ownership
  - lesson access
  - runtime playback truth
  - media identity outside the existing `lesson_media -> media_assets` chain
- `teacher_id` is retained only as a derived mirror scoped to the current course owner.
- Canonical course ownership remains:
  - `app.courses.teacher_id -> app.auth_subjects.user_id`
- Existing or future rows whose stored `teacher_id` does not match the derived ownership chain
  - `lesson_media -> lessons.course_id -> courses.teacher_id`
  are drift, not authority.
- No alternate substrate may replace `app.home_player_course_links` for course-link inclusion in this scope.

## OWNER DEFINITION EVIDENCE

- `actual_truth/contracts/home_audio_aggregation_contract.md`
  - course-link inclusion participates only when `home_player_course_links.enabled = true`
  - `lesson_media` identity is the source pointer for course-link participation
  - course-link access is canonical lesson access, not teacher ownership
- `backend/app/repositories/home_audio_runtime.py`
  - mounted learner runtime still reads `app.home_player_course_links` directly
- `backend/app/routes/studio.py`
  - mounted studio writes and edits the table today, proving the substrate is active and cannot be treated as dead code
- `backend/app/repositories/home_audio_sources.py`
  - current mounted ownership drift still scopes rows by stored `teacher_id` and still resolves owner through legacy `c.created_by`
- `backend/scripts/replay_baseline.sh`
  - baseline replay treats `app.home_player_course_links` as optional, proving the substrate lacks explicit baseline ownership today
- `backend/supabase/baseline_slots.lock.json`
  - no locked baseline slot currently materializes `app.home_player_course_links`

## EXECUTION LOCK

- This task owns only the missing append-only baseline authority for `app.home_player_course_links`.
- Runtime ownership cleanup remains out of scope and stays owned by `OET-001`.
- LOCK_STATUS: `DEFINED_FOR_FUTURE_APPEND_ONLY_BASELINE_MATERIALIZATION`
