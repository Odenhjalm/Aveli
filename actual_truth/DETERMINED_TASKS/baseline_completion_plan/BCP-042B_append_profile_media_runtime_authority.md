# BCP-042B

- TASK_ID: `BCP-042B`
- TYPE: `OWNER`
- TITLE: `Append profile-media runtime authority to unified runtime_media`
- PROBLEM_STATEMENT: `BCP-043 cannot legally align the remaining mounted profile/community media consumers while the append-only baseline still lacks the active profile-media authority now declared by canonical contract truth. The approved contract defines app.profile_media_placements, subject_user_id, visibility, the profile_media purpose, and one append-only path into runtime_media, so that missing baseline authority must land before mounted alignment.`
- IMPLEMENTATION_SURFACES:
  - `backend/supabase/baseline_slots/`
  - `backend/supabase/baseline_slots.lock.json`
  - `AVELI_DATABASE_BASELINE_MANIFEST.md`
  - `actual_truth/contracts/profile_community_media_contract.md`
  - canonical profile-media source tables and `runtime_media` projection work only where active contract truth justifies them
- TARGET_STATE:
  - append-only baseline adds the canonical `profile_media` media-purpose value without mutating protected slots
  - append-only baseline adds `app.profile_media_placements` above baseline core with the minimum contract-owned fields only
  - append-only baseline extends `app.runtime_media` so only `published` profile-media placements may contribute runtime rows
  - community does not gain a separate source-truth domain or separate purpose value
  - protected slots and mounted runtime remain unchanged in this task
- DEPENDS_ON:
  - `BCP-042A`
- EXPECTED_OUTCOME_BEFORE_ACTION:
  - `BCP-043` becomes dependency-valid for the remaining mounted profile/community alignment because baseline authority now exposes the approved profile-media source and append-only runtime projection path
- VERIFICATION_METHOD:
  - confirm append-only slot work above `0012` adds `profile_media` and `app.profile_media_placements` without mutating protected slots
  - confirm `app.runtime_media` projects profile-media runtime rows only from `published` placements linked to canonical `profile_media` assets
  - confirm the minimum contract-owned source fields are preserved and no second profile/community source-truth domain is introduced
  - confirm no legacy storage/path fields, fallback payload fields, or direct frontend representation fields enter baseline truth
- CONSTRAINTS:
  - do not reopen or weaken locked outputs in `BCP-040`, `BCP-041`, `BCP-042`, `BCP-042A`, or `BCP-043A`
  - do not perform mounted route, repository, service, or resolver rewiring owned by `BCP-043`
  - do not create a separate `community_media` purpose value or a separate community source entity
  - do not broaden into memberships, auth-subject work, DB-surface work, or aggregate audits
- STOP_CONDITIONS:
  - stop if append-only evolution would require mutating protected baseline slots
  - stop if the active contract cannot be expressed with the minimum baseline-owned source fields only
  - stop if satisfying profile-media authority would require mounted runtime alignment or frontend payload changes inside current scope

## OWNER IMPLEMENTATION

- Appended `backend/supabase/baseline_slots/0019_runtime_media_profile_media.sql` above the protected slot boundary and above `0018_runtime_media_home_player.sql`.
- Added append-only baseline support for the canonical `profile_media` media purpose without mutating protected slot `0001`.
- Added the minimum baseline-owned profile-media source table required by the active contract:
  - `app.profile_media_placements`
  - fields: `id`, `subject_user_id`, `media_asset_id`, `visibility`
- Preserved `subject_user_id` as a soft external subject reference and did not turn `auth_subjects` into the feature owner.
- Superseded `app.runtime_media` again with one append-only `create or replace view` so published profile-media placements can participate in the unified runtime truth chain.
- Preserved the existing unified runtime row shape:
  - `lesson_media_id`
  - `lesson_id`
  - `course_id`
  - `media_asset_id`
  - `media_type`
  - `playback_object_path`
  - `playback_format`
  - `state`
- Profile-media runtime rows are gated only by active contract source truth:
  - `profile_media_placements.visibility = 'published'`
  - linked asset purpose = `profile_media`
- Updated `AVELI_DATABASE_BASELINE_MANIFEST.md` so the accepted baseline authority now records:
  - canonical `profile_media` purpose coverage
  - minimum `profile_media_placements` source fields
  - profile-media contribution into `runtime_media`

## OWNER EVIDENCE

- `actual_truth/contracts/profile_community_media_contract.md`
  - canonical feature entity = `app.profile_media_placements`
  - canonical subject binding = `subject_user_id`
  - canonical publication field = `visibility`
  - canonical purpose value = `profile_media`
  - community does not become a separate source-truth domain
- `Aveli_System_Decisions.md`
  - profile media is a separate feature domain and must use an explicit structured contract
  - `runtime_media` remains the only runtime truth layer
  - backend read composition remains the only frontend media representation authority
- `aveli_system_manifest.json`
  - `profile_media_contract.explicit_structured_contract_required = true`
  - runtime-media bypass and backend-read-composition bypass remain forbidden
- `AVELI_DATABASE_BASELINE_MANIFEST.md`
  - non-core features must attach through separate feature-specific schema/contracts above baseline core
  - `auth_subjects.user_id` is the canonical subject identity pattern and remains a soft reference
- `actual_truth/analysis/profile_community_media_decision_package/RECOMMENDED_DECISION_SET.md`
  - approved one-model profile-media direction
  - approved `visibility = draft | published`
  - approved append-only path into `runtime_media`
- `backend/supabase/baseline_slots/0018_runtime_media_home_player.sql`
  - proved the pre-task baseline still lacked active contract-owned profile-media authority even after home-player runtime authority landed

## OWNER VERIFICATION

- Verified `backend/supabase/baseline_slots.lock.json` parses and records:
  - `slot = 19`
  - `filename = 0019_runtime_media_profile_media.sql`
  - SHA-256 = `242c047101907e6933cd5cc724d03b410f6fd5c1994411707d447509c86e73f7`
- Verified `0019_runtime_media_profile_media.sql` contains:
  - one append-only `alter type app.media_purpose add value 'profile_media'`
  - one append-only `create table if not exists app.profile_media_placements`
  - one `create or replace view app.runtime_media`
  - profile-media runtime inclusion only when `visibility = 'published'`
  - asset-purpose filtering only when `ma.purpose::text = 'profile_media'`
- Verified `0019_runtime_media_profile_media.sql` does not carry forbidden baseline truth fields:
  - `community_media`
  - `cover_image_url`
  - `asset_url`
  - `storage_path`
  - `storage_bucket`
  - `resolved_url`
  - `reference_type`
  - `auth_scope`
  - `fallback_policy`
  - `teacher_id`
  - `media_object_id`
  - `kind`
  - `published_at`
- Verified `AVELI_DATABASE_BASELINE_MANIFEST.md` now records the approved profile-media purpose, source table, and runtime-media projection rule without mutating protected slots `0001-0018`.

## EXECUTION LOCK

- EXPECTED_STATE:
  - append-only baseline ownership extends unified `runtime_media` to the active contract-owned profile-media surface
  - no separate community source-truth domain or second media-purpose taxonomy is introduced
  - mounted profile/community alignment can proceed later without inventing missing baseline authority
- ACTUAL_STATE:
  - baseline now carries `profile_media` in append-only scope
  - `app.profile_media_placements` now exists as the minimum baseline-owned source truth required by the active profile-media contract
  - `app.runtime_media` now projects published profile-media rows in the same unified authority chain as lesson media, course cover, and home-player media
- REMAINING_RISKS:
  - mounted profile/community routes, repositories, schemas, and read-composition helpers still need downstream alignment in `BCP-043`
  - the current runtime still mounts legacy `teacher_profile_media` surfaces that must be repaired toward the newly active feature contract
- RESULT:
  - `PASS`
- LOCK_STATUS:
  - `LOCKED_FOR_BCP-043`
