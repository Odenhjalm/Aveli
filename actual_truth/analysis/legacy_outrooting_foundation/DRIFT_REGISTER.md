# Drift Register

## Method

This register was built from the completed `baseline_completion_plan` source set, all locked task artifacts under `actual_truth/DETERMINED_TASKS/baseline_completion_plan/`, the aggregate audits `BCP-050_aggregate_append_only_and_substrate_audit.md` and `BCP-051_aggregate_canonical_authority_completion.md`, and the canonical authority documents listed in the run prompt.

Deduplication rule: one register item per root cause. Exact remaining scope is preserved under `scope` and `evidence`.

## Registered Drift

### DRIFT-001: Stripe-era membership compatibility remains outside canonical app-entry authority

- `drift_id`: `DRIFT-001`
- `category`: `code_alignment`
- `type`: `non_authoritative_transition_code`
- `scope`:
  - `backend/app/repositories/memberships.py`
  - optional Stripe-era compatibility columns and helper flows around `plan_interval`, `price_id`, `stripe_customer_id`, and `stripe_subscription_id`
  - compatibility lookup/update paths such as `get_latest_subscription(...)` and `get_membership_by_stripe_reference(...)`
- `status`: `followup_required`
- `future_goal`: `collapse_transition_layer`
- `why_it_is_drift`: mounted app-entry authority was aligned to canonical `app.memberships`, but repository compatibility logic still preserves non-authoritative Stripe-era membership semantics in read and write helpers.
- `baseline_impact`: baseline completion did not require removing billing compatibility so long as app-entry truth was derived only from canonical membership status and end-date semantics. The baseline task explicitly allowed these fields to remain as non-authority compatibility data when present.
- `canonical_rule_reference`:
  - `Aveli_System_Decisions.md:184`
  - `AVELI_DATABASE_BASELINE_MANIFEST.md:77-97`
  - `actual_truth/contracts/onboarding_teacher_rights_contract.md:211`
- `evidence`:
  - `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-013_align_runtime_app_entry_to_memberships.md:50-54`
  - `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-013_align_runtime_app_entry_to_memberships.md:80-82`
  - `backend/app/repositories/memberships.py:23-27`
  - `backend/app/repositories/memberships.py:32`
  - `backend/app/repositories/memberships.py:99`
  - `backend/app/repositories/memberships.py:196-250`
  - `backend/app/repositories/memberships.py:348-354`
- `outrooting_priority`: `MEDIUM`
- `outrooting_reason`: the compatibility layer is no longer canonical, but it still sits close to app-entry ownership and can reintroduce Stripe-shaped authority assumptions if later work does not collapse it deliberately.

### DRIFT-002: Remote-schema and legacy migration lineage still encode non-canonical doctrine

- `drift_id`: `DRIFT-002`
- `category`: `migration_cleanup`
- `type`: `non_authoritative_transition_code`
- `scope`:
  - `backend/supabase/migrations/20260320075542_remote_schema.sql`
  - `backend/supabase/migrations/20260331_profile_media_identity_cleanup.sql`
  - legacy migration surfaces still encoding old membership, profile, teacher-rights, runtime-media fallback, and profile-media table doctrine
- `status`: `followup_required`
- `future_goal`: `replace_with_canonical_path`
- `why_it_is_drift`: the locked canonical local baseline is the append-only slot chain, but the remote-schema lineage still contains legacy membership fields, profile-owned subject authority, `teacher_permissions`, `teacher_profile_media`, `cover_url`, `asset_url`, `fallback_policy`, and `legacy_storage_*` logic that no longer defines canonical authority.
- `baseline_impact`: the baseline plan explicitly resolved canonical ownership by appending new baseline slots above the protected range instead of mutating historical migration lineage. Remote-schema drift was documented as remaining until replay and broader alignment supersede it.
- `canonical_rule_reference`:
  - `Aveli_System_Decisions.md:122-124`
  - `AVELI_DATABASE_BASELINE_MANIFEST.md:92-96`
  - `AVELI_DATABASE_BASELINE_MANIFEST.md:112-118`
  - `AVELI_DATABASE_BASELINE_MANIFEST.md:175-192`
  - `AVELI_DATABASE_BASELINE_MANIFEST.md:197-208`
- `evidence`:
  - `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-012_append_baseline_app_memberships_authority.md:6`
  - `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-012_append_baseline_app_memberships_authority.md:88-90`
  - `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-022_append_baseline_auth_subject_authority.md:57`
  - `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-022_append_baseline_auth_subject_authority.md:91-93`
  - `backend/supabase/migrations/20260320075542_remote_schema.sql:569-572`
  - `backend/supabase/migrations/20260320075542_remote_schema.sql:742-745`
  - `backend/supabase/migrations/20260320075542_remote_schema.sql:842`
  - `backend/supabase/migrations/20260320075542_remote_schema.sql:850-851`
  - `backend/supabase/migrations/20260320075542_remote_schema.sql:881`
  - `backend/supabase/migrations/20260320075542_remote_schema.sql:1081`
  - `backend/supabase/migrations/20260320075542_remote_schema.sql:1093`
  - `backend/supabase/migrations/20260320075542_remote_schema.sql:2960-2969`
  - `backend/supabase/migrations/20260331_profile_media_identity_cleanup.sql:3-80`
- `outrooting_priority`: `HIGH`
- `outrooting_reason`: this lineage is the largest concentration of non-canonical doctrine still visible in repository history and is the highest-risk source of future confusion between production migration history and locked local canonical authority.

### DRIFT-003: Raw-table lesson and media helpers remain outside final mounted read authority

- `drift_id`: `DRIFT-003`
- `category`: `code_alignment`
- `type`: `noncanonical_read_path`
- `scope`:
  - `backend/app/repositories/courses.py::list_course_lessons`
  - `backend/app/repositories/courses.py::list_lesson_media`
  - `backend/app/repositories/courses.py::list_lesson_media_for_asset`
  - remaining sidecar callers in studio and observability-adjacent surfaces
- `status`: `legacy_residual`
- `future_goal`: `isolate`
- `why_it_is_drift`: these helpers still read raw lesson and lesson-media tables directly even though the baseline-owned mounted authority was moved to deterministic DB-surface and read-composition paths. Their continued existence preserves a second, non-authoritative raw-table access shape.
- `baseline_impact`: baseline completion required only that governed mounted endpoints stop using raw-table authority. The task explicitly recorded that remaining raw helpers could persist for studio/write or non-mounted usage provided they stayed outside final mounted authority.
- `canonical_rule_reference`:
  - `Aveli_System_Decisions.md:204-207`
  - `Aveli_System_Decisions.md:453-454`
  - `AVELI_DATABASE_BASELINE_MANIFEST.md:223`
  - `AVELI_DATABASE_BASELINE_MANIFEST.md:249`
- `evidence`:
  - `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-036_align_runtime_reads_to_db_surfaces.md:81`
  - `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-036_align_runtime_reads_to_db_surfaces.md:93-95`
  - `backend/app/repositories/courses.py:436-442`
  - `backend/app/repositories/courses.py:561-610`
  - `backend/app/services/courses_service.py:161-162`
  - `backend/app/services/courses_service.py:292-298`
  - `backend/app/routes/studio.py:905-914`
  - `backend/app/services/verification_observability.py:586-591`
  - `backend/app/services/media_control_plane_observability.py:969`
  - `backend/app/services/media_control_plane_observability.py:1545`
- `outrooting_priority`: `MEDIUM`
- `outrooting_reason`: the residual helpers are explicitly outside final mounted authority, but they remain a reachable raw-table surface that future work must either isolate more sharply or retire to avoid authority drift.

### DRIFT-004: Home-audio legacy direct playback shaping still exists beside the canonical runtime path

- `drift_id`: `DRIFT-004`
- `category`: `runtime_alignment`
- `type`: `adjacent_runtime_drift`
- `scope`:
  - `backend/app/services/home_audio_service.py::_compose_home_audio_media`
  - `backend/app/services/home_audio_service.py::list_home_audio_media`
  - `backend/app/services/lesson_playback_service.py::resolve_media_asset_playback`
- `status`: `legacy_residual`
- `future_goal`: `verify_not_mounted`
- `why_it_is_drift`: the service still shapes playback directly through a separate playback resolver path instead of consuming only the canonical home-audio runtime contract boundary. That preserves a runtime-adjacent alternate composition path.
- `baseline_impact`: baseline task `BCP-043A` completed once mounted cover and home-player reads were aligned to runtime media authority. The task explicitly recorded that `home_audio_service.py` still held legacy direct playback shaping but was not mounted in the runtime path owned by the task.
- `canonical_rule_reference`:
  - `Aveli_System_Decisions.md:391-393`
  - `actual_truth/contracts/home_audio_runtime_contract.md:5`
  - `actual_truth/contracts/home_audio_runtime_contract.md:48-53`
  - `actual_truth/contracts/home_audio_runtime_contract.md:65-73`
- `evidence`:
  - `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-043A_align_cover_and_home_player_reads_to_runtime_media.md:56`
  - `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-043A_align_cover_and_home_player_reads_to_runtime_media.md:106-107`
  - `backend/app/services/home_audio_service.py:25-38`
  - `backend/app/services/home_audio_service.py:54`
  - `backend/app/services/home_audio_service.py:114`
  - `backend/app/services/lesson_playback_service.py:252`
- `outrooting_priority`: `HIGH`
- `outrooting_reason`: even while unmounted, this path keeps a second playback-shaping model near governed home-audio behavior and should be treated as a high-risk remount or regression vector.

### DRIFT-005: Legacy `teacher_profile_media` cleanup and migration residue still survives outside canonical profile-media authority

- `drift_id`: `DRIFT-005`
- `category`: `legacy_outrooting`
- `type`: `legacy_helper`
- `scope`:
  - `backend/app/models.py` cleanup checks against `app.teacher_profile_media`
  - `backend/supabase/migrations/20260320075542_remote_schema.sql` legacy `app.teacher_profile_media` table lineage
  - `backend/supabase/migrations/20260331_profile_media_identity_cleanup.sql`
- `status`: `legacy_residual`
- `future_goal`: `remove`
- `why_it_is_drift`: canonical authored-placement truth is now `app.profile_media_placements`, but cleanup and migration residue still mention the retired `teacher_profile_media` entity. That entity is no longer authoritative for mounted profile/community media truth.
- `baseline_impact`: baseline completion did not require deleting every historical cleanup or migration mention once mounted profile/community read authority was aligned. The task explicitly recorded that non-mounted cleanup helpers and old database references could still mention legacy `teacher_profile_media`.
- `canonical_rule_reference`:
  - `actual_truth/contracts/profile_community_media_contract.md:24`
  - `actual_truth/contracts/profile_community_media_contract.md:53`
  - `actual_truth/contracts/profile_community_media_contract.md:128-132`
  - `AVELI_DATABASE_BASELINE_MANIFEST.md:175-192`
- `evidence`:
  - `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-043_align_read_composition_to_unified_runtime_media.md:121-122`
  - `backend/app/models.py:114`
  - `backend/app/models.py:134`
  - `backend/supabase/migrations/20260320075542_remote_schema.sql:1093-1116`
  - `backend/supabase/migrations/20260320075542_remote_schema.sql:2446-2462`
  - `backend/supabase/migrations/20260331_profile_media_identity_cleanup.sql:3-80`
- `outrooting_priority`: `HIGH`
- `outrooting_reason`: the retired entity name is still present in cleanup and migration surfaces and is likely to attract accidental reuse during future work unless it is deliberately removed from non-authoritative residue.

### DRIFT-006: Legacy media payload fields still survive in upload, URL-normalization, and legacy verification surfaces

- `drift_id`: `DRIFT-006`
- `category`: `code_alignment`
- `type`: `legacy_payload_shape`
- `scope`:
  - `backend/app/routes/studio.py` upload path writing `asset_url`
  - `backend/app/utils/media_urls.py` relative-field normalization for legacy media URL fields
  - legacy cover and runtime-media migration verification surfaces in `backend/tests/test_course_cover_pipeline.py`, `backend/tests/test_media_signer.py`, and `backend/tests/test_runtime_media_migration.py`
- `status`: `followup_required`
- `future_goal`: `replace_with_canonical_path`
- `why_it_is_drift`: canonical media truth is supposed to flow through `runtime_media` and backend read composition, but upload and support surfaces still preserve `asset_url`, `cover_url`, and legacy storage/fallback payload semantics that belong to earlier transition layers.
- `baseline_impact`: baseline completion could finish because these payload remnants were outside the mounted read-authority scope being locked. The aggregate completion report explicitly kept the remaining `asset_url` occurrence and broader legacy upload and migration code outside the canonical authority result.
- `canonical_rule_reference`:
  - `Aveli_System_Decisions.md:192-207`
  - `actual_truth/contracts/media_unified_authority_contract.md:83-84`
  - `actual_truth/contracts/media_unified_authority_contract.md:103`
  - `actual_truth/contracts/COURSE_COVER_READ_CONTRACT.md:7`
  - `actual_truth/contracts/COURSE_COVER_READ_CONTRACT.md:16`
  - `actual_truth/contracts/COURSE_COVER_READ_CONTRACT.md:24`
  - `actual_truth/contracts/profile_community_media_contract.md:152-157`
- `evidence`:
  - `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-051_aggregate_canonical_authority_completion.md:98`
  - `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-051_aggregate_canonical_authority_completion.md:102`
  - `backend/app/routes/studio.py:1533`
  - `backend/app/utils/media_urls.py:7-11`
  - `backend/tests/test_course_cover_pipeline.py:112-136`
  - `backend/tests/test_course_cover_pipeline.py:927-1020`
  - `backend/tests/test_media_signer.py:215-229`
  - `backend/tests/test_runtime_media_migration.py:103-133`
  - `backend/tests/test_runtime_media_migration.py:327-359`
  - `backend/supabase/migrations/20260320075542_remote_schema.sql:234`
  - `backend/supabase/migrations/20260320075542_remote_schema.sql:842`
  - `backend/supabase/migrations/20260320075542_remote_schema.sql:850-851`
  - `backend/supabase/migrations/20260320075542_remote_schema.sql:881`
- `outrooting_priority`: `MEDIUM`
- `outrooting_reason`: these payload remnants no longer define authority, but they still preserve old resolver and storage expectations across upload and verification surfaces and therefore need deliberate replacement rather than incidental drift.
