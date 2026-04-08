# BCP-040

- TASK_ID: `BCP-040`
- TYPE: `OWNER`
- TITLE: `Resolve the unified runtime_media expansion boundary`
- PROBLEM_STATEMENT: `Protected slot 0008 still defines app.runtime_media as a lesson-only ready-state projection, while the locked direction requires unified runtime truth for relevant visibility, state, and resolution, including course cover. The authoritative source set does not yet define the exact expanded row model or governed-surface coverage needed for append-only implementation.`
- IMPLEMENTATION_SURFACES:
  - `actual_truth/contracts/media_unified_authority_contract.md`
  - `actual_truth/contracts/COURSE_COVER_READ_CONTRACT.md`
  - `actual_truth/contracts/learner_public_edge_contract.md`
  - `Aveli_System_Decisions.md`
  - `backend/supabase/baseline_slots/0008_runtime_media_projection_core.sql`
  - `backend/supabase/baseline_slots/0009_runtime_media_projection_sync.sql`
- TARGET_STATE:
  - the expanded `runtime_media` row model is resolved from authoritative sources
  - course cover is included in the same runtime truth chain as other governed media surfaces
  - authored identity remains owned by canonical authored entities such as `app.lesson_media` and `app.courses.cover_media_id`
  - `runtime_media` remains runtime truth only and not the final frontend representation
  - no separate cover resolver or alternate media truth path remains in the resolved boundary
- DEPENDS_ON:
  - `none`
- VERIFICATION_METHOD:
  - compare the resolved boundary against DECISIONS and active media contracts
  - confirm every governed surface in scope attaches to one `runtime_media` chain
  - stop if required runtime truth fields are still ambiguous after source review

## RESOLVED CANONICAL RUNTIME_MEDIA EXPANSION BOUNDARY

- `app.runtime_media` remains the read-only runtime truth layer and expands above the protected lesson-only projection without becoming frontend representation.
- Active baseline-owned runtime-media source usages in the current completion scope are exactly:
  - lesson media, sourced from `app.lesson_media` -> `app.lessons` -> `app.media_assets`
  - course cover, sourced from `app.courses.cover_media_id` -> `app.media_assets`
- `app.courses.cover_media_id` remains pointer-only identity. Course-cover runtime rows do not make `app.courses` the media-truth owner.
- `app.lesson_media` remains authored placement authority. Lesson-media runtime rows do not collapse authored placement into runtime truth.
- The exact minimal expanded row model is:
  - `course_id` required
  - `lesson_id` nullable and populated only for lesson-media rows
  - `lesson_media_id` nullable and populated only for lesson-media rows
  - `media_asset_id` required
  - `media_type` required
  - `state` required
  - `playback_object_path` nullable
  - `playback_format` nullable
- `state` is an inferred field name from canonical source alignment: the primary sources require runtime truth for media state but do not separately rename it away from the canonical `app.media_assets.state` term.
- No separate synthetic usage discriminator is canonical in the new baseline row model. In current scope, row meaning is determined only by source-pointer shape:
  - lesson-media row: `lesson_media_id IS NOT NULL` and `lesson_id IS NOT NULL`
  - course-cover row: `lesson_media_id IS NULL` and `lesson_id IS NULL`
- No separate synthetic runtime identifier is canonically required for the current-scope row model. Identity remains source-derived:
  - lesson-media row identity = `lesson_media_id`
  - course-cover row identity = (`course_id`, `media_asset_id`) derived from `app.courses.cover_media_id`
- A runtime row is valid only when:
  - the canonical source pointer or authored attachment exists
  - the linked `app.media_assets` row exists
  - the linked asset purpose matches the source usage
    - lesson-media rows require `app.media_assets.purpose = lesson_media`
    - course-cover rows require `app.media_assets.purpose = course_cover`
- Non-ready governed media still project runtime rows when the canonical source pointer or attachment exists. Those rows carry canonical `state` while `playback_object_path` and `playback_format` remain null until runtime resolution eligibility is valid.
- Ready rows remain bound by existing canonical asset invariants. In particular, audio ready rows require `playback_format = mp3`.
- `app.runtime_media` continues to feed backend read composition only. Backend read composition alone emits `{ media_id, state, resolved_url } | null`.

## RESOLVED BOUNDARY RULES

- `app.runtime_media` owns runtime truth for state and resolution eligibility only. It does not own authored identity, access control, or frontend payload representation.
- Course cover must use the same `media_asset_id -> runtime_media -> backend read composition` chain as lesson media. No cover-specific resolver doctrine may exist.
- Row existence may express canonical media usage visibility only in the sense that a governed source pointer or attachment exists. It must not be treated as permission, enrollment, or raw-table access authority.
- Public versus protected read authority remains outside `runtime_media`:
  - course-cover exposure remains public through public read composition
  - lesson-media exposure remains protected through `lesson_content_surface`
- Append-only baseline work after this task may supersede the protected lesson-only `runtime_media` view, but must not mutate protected slots `0008` or `0009` in place.

## EXPLICIT EXCLUSIONS

- non-porting runtime fields from legacy/runtime drift:
  - `reference_type`
  - `auth_scope`
  - `fallback_policy`
  - `home_player_upload_id`
  - `teacher_id`
  - `media_object_id`
  - `legacy_storage_bucket`
  - `legacy_storage_path`
  - `kind`
- frontend-representation fields:
  - `resolved_url`
  - signed URLs
  - storage buckets as frontend truth
- direct application write paths to `app.runtime_media`
- separate cover-resolver ownership
- alternate media-truth paths outside `runtime_media`
- profile/community runtime row sources in the current baseline completion scope
  - canonical sources require an explicit structured profile-media contract before those surfaces can materialize baseline-owned shape
- home-player direct-upload runtime row sources in the current baseline completion scope
  - the protected baseline owns only `course_cover` and `lesson_media` purposes, so direct-upload home-player origins are not baseline-owned row sources in this task

## RESOLUTION EVIDENCE

- `Aveli_System_Decisions.md`
  - `runtime_media` is the runtime truth layer for media state and resolution eligibility, not frontend representation.
  - course cover, lesson media, and home player must not introduce alternate media authorities or bypasses around `runtime_media`.
  - no layer may bypass `runtime_media`, and fallback is forbidden.
- `aveli_system_manifest.json`
  - runtime truth authority is `runtime_media`.
  - frontend representation authority is `backend_read_composition`.
  - home-player runtime truth must still flow through `runtime_media`.
  - runtime-media bypass is forbidden.
- `actual_truth/contracts/media_unified_authority_contract.md`
  - one authority chain exists: `media_id -> runtime_media -> backend read composition -> API -> frontend`.
  - course cover is a media usage, not a separate resolver system.
  - future surfaces must attach to the same authority chain.
- `actual_truth/contracts/COURSE_COVER_READ_CONTRACT.md`
  - `app.courses.cover_media_id` is pointer-only identity.
  - learner/public `cover` must be derived from canonical runtime truth in `app.runtime_media`.
- `actual_truth/contracts/learner_public_edge_contract.md`
  - `cover` is backend-authored representation attached through read composition from `runtime_media`.
  - learner/public lesson media also uses backend-authored media objects only.
- `backend/supabase/baseline_slots/0002_courses_core.sql`
  - `app.courses` already owns `cover_media_id` as structural pointer only.
- `backend/supabase/baseline_slots/0006_lesson_media_core.sql`
  - `app.lesson_media` already owns lesson-media authored attachment identity with required `media_asset_id`.
- `backend/supabase/baseline_slots/0007_media_assets_core.sql`
  - canonical media identity and state already live in `app.media_assets`.
  - protected baseline purpose scope is only `course_cover` and `lesson_media`.
  - ready playback invariants already exist at the asset layer.
- `backend/supabase/baseline_slots/0008_runtime_media_projection_core.sql`
  - current protected view is lesson-only, ready-only, and lacks runtime state plus course-cover coverage.
- `NEW_BASELINE_DESIGN_PLAN.md`
  - `runtime_media` must include `playback_object_path` and `playback_format`.
  - runtime projection non-porting explicitly forbids carrying forward `reference_type`, `auth_scope`, `fallback_policy`, `home_player_upload_id`, `teacher_id`, `media_object_id`, legacy storage fields, and `kind`.
- Repo mismatch evidence only:
  - `backend/app/services/courses_service.py` still resolves course cover through media-asset and storage-adjacent logic instead of unified runtime truth.
  - `backend/app/media_control_plane/services/media_resolver_service.py` and `backend/app/repositories/runtime_media.py` still assume lesson-only runtime identity.

## EXECUTION LOCK

- The unified baseline-owned `runtime_media` expansion boundary is resolved and locked for append-only implementation.
- Downstream implementation may add only the minimum append-only baseline ownership needed to materialize:
  - lesson-media runtime rows with canonical state
  - course-cover runtime rows with canonical state
  - shared backend-read-composition input fields only
- Downstream implementation must not:
  - reintroduce non-porting runtime fields
  - create a separate cover resolver
  - treat home-player direct uploads or profile/community media as baseline-owned row sources without a separate canonical contract
- LOCK STATUS: `LOCKED_FOR_BCP-041_AND_BCP-042`
