# BASELINE_COMPLETION_PLAN TASK TREE

## SECTION: TASK TREE

### 1. APP_ENTRY_AUTHORITY

- `BCP-010` -> resolve the minimum canonical `app.memberships` shape that may own app entry
- `BCP-011` -> gate the resolved membership boundary against onboarding, enrollment, and subject drift
- `BCP-012` -> append baseline ownership for canonical `app.memberships`
- `BCP-013` -> align runtime app-entry reads and writes to `app.memberships`
- `BCP-014` -> verify that `app.memberships` is the sole app-entry authority

### 2. AUTH_SUBJECT_AUTHORITY

- `BCP-020` -> resolve the canonical auth-subject entity above Supabase Auth
- `BCP-021` -> gate the resolved auth-subject boundary against membership and learner-content drift
- `BCP-022` -> append baseline ownership for the canonical auth-subject entity
- `BCP-023` -> align runtime auth, onboarding, and teacher-rights reads and writes to the auth-subject entity
- `BCP-024` -> verify that auth-subject authority is canonical and separate from app entry

### 3. DB_SURFACES

- `BCP-030` -> resolve the canonical DB-surface object map for discovery, detail, structure, and protected content
- `BCP-031` -> gate the DB-surface map against raw-table semantics
- `BCP-032` -> materialize the public user-independent DB surfaces
- `BCP-033A` -> align mounted public runtime reads to the canonical public DB surfaces
- `BCP-033` -> verify the public DB surfaces
- `BCP-034` -> materialize the protected lesson-content DB surface
- `BCP-035` -> verify the protected lesson-content DB surface
- `BCP-036` -> align mounted runtime reads to canonical DB surfaces
- `BCP-037` -> verify surface-based read paths end to end

### 4. RUNTIME_MEDIA_UNIFICATION

- `BCP-040` -> resolve the unified `runtime_media` expansion boundary above the protected lesson-only projection
- `BCP-041` -> gate the unified `runtime_media` boundary
- `BCP-042` -> append baseline ownership for the expanded unified `runtime_media`
- `BCP-042A` -> append the missing home-player runtime authority to unified `runtime_media`
- `BCP-042B` -> append the approved profile-media runtime authority to unified `runtime_media`
- `BCP-043A` -> align mounted course-cover and home-player reads to unified `runtime_media`
- `BCP-043` -> align the remaining profile/community media consumers to unified `runtime_media`
- `BCP-044` -> verify unified `runtime_media` authority across governed media surfaces

### 5. AGGREGATE_AUDITS

- `BCP-050` -> aggregate append-only and substrate-only audit
- `BCP-051` -> aggregate canonical baseline-completion authority audit

## DEPENDENCY SUMMARY

- Roots: `BCP-010`, `BCP-020`, `BCP-030`, `BCP-040`
- Each root owns a blocking contract-resolution step because the locked direction is fixed while the exact implementation boundary is still missing from the authoritative source set.
- Public and protected DB-surface materialization may run in parallel only after `BCP-031` passes.
- Mounted public read alignment must land before the public DB-surface gate can be re-run: `BCP-032 -> BCP-033A -> BCP-033`.
- Mounted dependency-valid runtime-media alignment must first land for course cover and home-player: `BCP-042 -> BCP-042A -> BCP-043A`.
- Active contract-owned profile-media authority must land append-only before remaining profile/community alignment: `BCP-042A -> BCP-042B -> BCP-043`.
- Remaining profile/community runtime-media alignment stays downstream of both the mounted dependency-valid work and the new profile-media authority work: `BCP-043A -> BCP-043`, `BCP-042B -> BCP-043`, `BCP-043 -> BCP-044`.
- Runtime read alignment for course and lesson endpoints must still wait for both DB-surface gates and unified `runtime_media` verification: `BCP-033 -> BCP-036`, `BCP-035 -> BCP-036`, `BCP-044 -> BCP-036`.
- Final closure is linear: `BCP-050 -> BCP-051`.

## MATERIALIZED FILES

- [DAG_SUMMARY.md](/c:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/baseline_completion_plan/DAG_SUMMARY.md)
- [task_manifest.json](/c:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/baseline_completion_plan/task_manifest.json)
- [BCP-010_resolve_minimal_app_memberships_shape.md](/c:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-010_resolve_minimal_app_memberships_shape.md)
- [BCP-020_resolve_canonical_auth_subject_entity.md](/c:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-020_resolve_canonical_auth_subject_entity.md)
- [BCP-030_resolve_canonical_db_surface_map.md](/c:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-030_resolve_canonical_db_surface_map.md)
- [BCP-033A_align_mounted_public_reads_to_public_db_surfaces.md](/c:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-033A_align_mounted_public_reads_to_public_db_surfaces.md)
- [BCP-040_resolve_unified_runtime_media_expansion.md](/c:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-040_resolve_unified_runtime_media_expansion.md)
- [BCP-042A_append_home_player_runtime_media_authority.md](/c:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-042A_append_home_player_runtime_media_authority.md)
- [BCP-042B_append_profile_media_runtime_authority.md](/c:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-042B_append_profile_media_runtime_authority.md)
- [BCP-043A_align_cover_and_home_player_reads_to_runtime_media.md](/c:/Users/aveli/Aveli/actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-043A_align_cover_and_home_player_reads_to_runtime_media.md)
