# BCP-042A

- TASK_ID: `BCP-042A`
- TYPE: `OWNER`
- TITLE: `Append home-player runtime authority to unified runtime_media`
- PROBLEM_STATEMENT: `BCP-043 cannot legally align mounted home-player runtime reads while the append-only baseline still materializes only lesson media and course cover in app.runtime_media. Canonical documents already declare home-player runtime truth as runtime_media-owned, so the missing baseline authority must land before mounted resolver alignment.`
- IMPLEMENTATION_SURFACES:
  - `backend/supabase/baseline_slots/`
  - `backend/supabase/baseline_slots.lock.json`
  - `backend/supabase/baseline_slots/0017_runtime_media_unified.sql`
  - canonical home-player source tables only where primary documents justify their participation in `runtime_media`
- TARGET_STATE:
  - append-only baseline slot work extends unified `app.runtime_media` to include home-player runtime truth without creating a second runtime-truth object
  - home-player media participates in the same `media_id -> runtime_media -> backend read composition -> API -> frontend` chain as lesson media and course cover
  - the minimum canonical runtime row coverage needed for home-player state and resolution eligibility exists before mounted runtime alignment begins
  - protected slots remain unchanged and no runtime rewiring occurs in this task
- DEPENDS_ON:
  - `BCP-042`
- EXPECTED_OUTCOME_BEFORE_ACTION:
  - `BCP-043` becomes dependency-valid for mounted home-player runtime alignment because baseline authority now exposes the required governed runtime truth
- VERIFICATION_METHOD:
  - confirm append-only slot work above `0012` extends `app.runtime_media` instead of introducing a parallel runtime authority object
  - confirm canonical home-player runtime truth is expressed only through unified `runtime_media` coverage justified by canonical decisions, manifest rules, and contracts
  - confirm no direct application write path, fallback resolver path, or storage-truth bypass is introduced
- CONSTRAINTS:
  - do not reopen or weaken locked outputs in `BCP-040`, `BCP-041`, or `BCP-042`
  - do not perform mounted route, service, repository, or resolver rewiring owned by `BCP-043`
  - do not broaden into memberships, auth-subject work, public DB-surface work, protected lesson-content work, or aggregate audits
  - do not materialize profile/community baseline authority unless primary documents prove it is required to unblock the home-player runtime authority gap
- STOP_CONDITIONS:
  - stop if canonical documents cannot justify the minimum home-player source boundary or runtime row coverage required for `app.runtime_media`
  - stop if append-only evolution would require mutating protected slots or reopening locked `BCP-042` outputs
  - stop if satisfying the missing home-player runtime truth would require mounted runtime alignment before baseline authority exists

## OWNER IMPLEMENTATION

- Appended `backend/supabase/baseline_slots/0018_runtime_media_home_player.sql` above the protected slot boundary and above `0017_runtime_media_unified.sql`.
- Added append-only baseline support for the canonical `home_player_audio` media purpose without mutating protected slot `0001`.
- Added the minimum baseline-owned home-player source table required by the active home-audio contract:
  - `app.home_player_uploads`
  - fields: `id`, `teacher_id`, `media_asset_id`, `active`
- Superseded `app.runtime_media` again with one append-only `create or replace view` so direct-upload home-player rows can participate in unified runtime truth.
- Preserved the existing unified row shape:
  - `lesson_media_id`
  - `lesson_id`
  - `course_id`
  - `media_asset_id`
  - `media_type`
  - `playback_object_path`
  - `playback_format`
  - `state`
- Home-player direct-upload rows are identified only by source-pointer shape:
  - `lesson_media_id IS NULL`
  - `lesson_id IS NULL`
  - `course_id IS NULL`
- `backend/supabase/baseline_slots.lock.json` now includes slot `18` with the verified SHA-256 for `0018_runtime_media_home_player.sql`.

## OWNER EVIDENCE

- `Aveli_System_Decisions.md`
  - home-player runtime truth is still owned by `runtime_media`
  - home player must not introduce bypass paths around `runtime_media` and backend read composition
- `aveli_system_manifest.json`
  - `home_player_runtime_model.runtime_truth_layer = runtime_media`
  - home-player runtime truth must flow through `runtime_media`
  - alternative playback paths and direct storage playback are forbidden
- `actual_truth/contracts/media_unified_authority_contract.md`
  - home player media is a media usage, not a separate resolver system
  - one authority chain only: `media_id -> runtime_media -> backend read composition -> API -> frontend`
- `actual_truth/contracts/home_audio_runtime_contract.md`
  - direct-upload inclusion is controlled by `home_player_uploads.active = true`
  - `media_asset_id` is the only playback identity
  - runtime projection must remain read-only and must not introduce a new playback identity
- `NEW_BASELINE_DESIGN_PLAN.md`
  - `home_player_audio` is a course-baseline purpose value
  - runtime projection non-porting continues to forbid `reference_type`, `auth_scope`, `fallback_policy`, `home_player_upload_id`, `media_object_id`, legacy storage fields, and `kind`
- `backend/supabase/baseline_slots/0017_runtime_media_unified.sql`
  - proved the pre-task baseline still excluded home-player runtime truth even after lesson-media and course-cover unification

## OWNER VERIFICATION

- Verified `backend/supabase/baseline_slots.lock.json` parses and records:
  - `slot = 18`
  - `filename = 0018_runtime_media_home_player.sql`
  - SHA-256 = `bf2172eac273e418121914952d07e8878a315dc3c0234debaf764ba7ac9a3c17`
- Verified `0018_runtime_media_home_player.sql` contains:
  - one append-only `alter type app.media_purpose add value 'home_player_audio'`
  - one append-only `create table if not exists app.home_player_uploads`
  - one `create or replace view app.runtime_media`
  - direct-upload inclusion only when `hpu.active = true`
  - direct-upload runtime rows only when the linked asset has `purpose = home_player_audio` and `media_type = audio`
- Verified `0018_runtime_media_home_player.sql` does not carry forbidden runtime fields:
  - `reference_type`
  - `auth_scope`
  - `fallback_policy`
  - `home_player_upload_id`
  - `media_object_id`
  - `legacy_storage_bucket`
  - `legacy_storage_path`
  - `kind`
  - `resolved_url`
- Verified protected slots `0001-0017` remain unchanged by this task.

## EXECUTION LOCK

- EXPECTED_STATE:
  - append-only baseline ownership extends unified `runtime_media` to the canonically governed home-player direct-upload surface
  - no second runtime-truth object or alternate media authority path is introduced
  - mounted runtime alignment can proceed later without inventing baseline authority
- ACTUAL_STATE:
  - baseline now carries `home_player_audio` in append-only scope
  - `app.home_player_uploads` now exists as the minimum baseline-owned source truth required by the home-audio contract
  - `app.runtime_media` now projects direct-upload home-player rows in the same authority chain as lesson media and course cover
- REMAINING_RISKS:
  - mounted read composition and resolver consumers still need downstream alignment in `BCP-043`
  - profile/community media remains a separate downstream alignment question outside this task's baseline-authority scope
- RESULT:
  - `PASS`
- LOCK_STATUS:
  - `LOCKED_FOR_BCP-043`
