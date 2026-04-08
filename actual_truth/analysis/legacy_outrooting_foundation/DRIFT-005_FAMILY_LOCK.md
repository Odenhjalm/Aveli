# DRIFT-005 Family Lock

## DEVIATION FAMILY ID

- `DRIFT-005`
- Title: `Legacy teacher_profile_media cleanup and migration residue still survives outside canonical profile-media authority`
- Seed drift source:
  - `actual_truth/analysis/legacy_outrooting_foundation/DRIFT_REGISTER.md`
  - `actual_truth/analysis/legacy_outrooting_foundation/DRIFT_MANIFEST.json`

## CANONICAL RULES USED

- `actual_truth/contracts/profile_community_media_contract.md`
  - Canonical authored placement for profile/community media is `app.profile_media_placements`.
  - Runtime projection flows only from canonical placement truth into `runtime_media`.
- `AVELI_DATABASE_BASELINE_MANIFEST.md:175-208`
  - `profile_media_placements` is the only canonical profile-media authored-placement source entity.
  - `runtime_media` is canonical runtime truth and does not restore retired `teacher_profile_media` doctrine.
- `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-043_align_read_composition_to_unified_runtime_media.md:100-127`
  - Baseline completion explicitly allowed residual non-mounted cleanup helpers and old DB references to still mention `teacher_profile_media`.
- `actual_truth/analysis/legacy_outrooting_foundation/CANONICAL_VS_NONAUTHORITATIVE_BOUNDARY.md`
  - Locked baseline slots are protected canonical authority.
  - Legacy repo/runtime surfaces outside that boundary are outrooting targets.
- `codex/AVELI_OPERATING_SYSTEM.md:832,1139-1202`
  - Local execute/confirm verification must use deterministic replay of `backend/supabase/baseline_slots`.
  - Baseline replay must apply `0001` through latest accepted slot in strict order.
  - If replay fails, baseline is invalid and execution must stop.
- `codex/AVELI_EXECUTION_POLICY.md:122-124,233-237`
  - Codex must align DB schema to `baseline_slots`, replay baseline when mismatch is detected, and stop if environment prevents verification.

## EXPECTED CANONICAL STATE

- Mounted profile/community media truth is owned only by:
  - `app.profile_media_placements`
  - unified `runtime_media`
- Active cleanup, orphan-detection, and doctor tooling must not treat retired `app.teacher_profile_media` as live authority.
- Historical migration residue may remain only if already fenced as non-authoritative.
- Post-mutation verification must run against a valid strict-order replay of the locked baseline slots.

## ACTUAL DRIFT STATE

- `backend/app/models.py` still used `app.teacher_profile_media` as a live cleanup guard for `app.media_objects`.
- `backend/app/services/media_cleanup.py` still preserved the same retired doctrine in orphan cleanup queries.
- `backend/scripts/media_doctor.py` still treated `teacher_profile_media` as an active non-orphan reference surface.
- Migration-adjacent mentions in `backend/supabase/migrations/20260331_profile_media_identity_cleanup.sql` and `backend/supabase/migrations/20260320075542_remote_schema.sql` were already historical-only residue fenced by `DRIFT-002`, not fresh live authority.

## DRIFT CLASSIFICATION

| deviation_scope | canonical_path_exists | authority_risk | transition_layer | residual_value | primary_processing_state | canonical_rule_reference | classification_evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `backend/app/models.py::cleanup_media_object` | `YES_ADJACENT` | `MEDIUM` | `THIN` | `CONDITIONALLY_REACHABLE` | `REMOVE_DEAD_SURFACE` | `profile_community_media_contract.md`, `AVELI_DATABASE_BASELINE_MANIFEST.md:175-208` | Cleanup still blocked deletion on retired `teacher_profile_media`, even though canonical profile media no longer owns `app.media_objects`. |
| `backend/app/services/media_cleanup.py::garbage_collect_media` | `YES_ADJACENT` | `MEDIUM` | `THIN` | `ACTIVE_NONAUTHORITATIVE` | `REMOVE_DEAD_SURFACE` | `profile_community_media_contract.md`, `AVELI_DATABASE_BASELINE_MANIFEST.md:175-208` | Orphan cleanup still treated retired doctrine as if it could keep media objects alive. |
| `backend/scripts/media_doctor.py::fetch_orphan_media_assets` | `YES_ADJACENT` | `LOW` | `THIN` | `ACTIVE_NONAUTHORITATIVE` | `REMOVE_DEAD_SURFACE` | `profile_community_media_contract.md`, `AVELI_DATABASE_BASELINE_MANIFEST.md:175-208` | Diagnostic tooling still joined retired `teacher_profile_media` into active orphan detection. |
| `backend/supabase/migrations/20260331_profile_media_identity_cleanup.sql` | `YES_ADJACENT` | `LOW` | `THIN` | `HISTORICAL_ONLY` | `ISOLATE_NON_AUTHORITATIVE_SURFACE` | `CANONICAL_VS_NONAUTHORITATIVE_BOUNDARY.md`, `DRIFT-002_FAMILY_LOCK.md` | Historical cleanup migration already fenced by `DRIFT-002`; no new lawful mutation needed in this family. |
| `backend/supabase/migrations/20260320075542_remote_schema.sql` | `YES_ADJACENT` | `LOW` | `THICK` | `HISTORICAL_ONLY` | `ISOLATE_NON_AUTHORITATIVE_SURFACE` | `CANONICAL_VS_NONAUTHORITATIVE_BOUNDARY.md`, `DRIFT-002_FAMILY_LOCK.md` | Remote-schema lineage already fenced as non-authoritative by `DRIFT-002`. |

### Blocker Record

| family_id | seed_drift_id | deviation_scope | replacement_blocker_reason | blocking_evidence | current_processing_state | future_replacement_trigger |
| --- | --- | --- | --- | --- | --- | --- |
| `DRIFT-005` | `DRIFT-005` | post-mutation family verification | Locked canonical baseline replay is invalid in strict slot order, so execute-mode reverification cannot complete lawfully. | `backend/supabase/baseline_slots/0006_lesson_media_core.sql` references `app.media_assets` before `backend/supabase/baseline_slots/0007_media_assets_core.sql` creates it; `codex/AVELI_OPERATING_SYSTEM.md:1166-1202` requires strict-order replay and stop on replay failure. | `REMOVE_DEAD_SURFACE` | Re-run family verification only after canonical baseline replay is repaired without mutating accepted baseline slots or after a canonically approved append-only fix restores strict-order replay validity. |

## SEARCH EVIDENCE

### Search Ledger

| family_id | seed_drift_id | search_step | search_type | query_or_concept | surface_searched | hits | included_findings | excluded_findings | reason_for_exclusion |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `DRIFT-005` | `DRIFT-005` | `canonical_diff` | exact_lexical | `teacher_profile_media`, `profile_media_placements`, `cover_media_id`, `media_objects`, `media_asset_id` | local repo | multiple | `backend/app/models.py`, `backend/app/services/media_cleanup.py`, `backend/scripts/media_doctor.py`, `backend/app/repositories/teacher_profile_media.py`, `backend/supabase/migrations/20260331_profile_media_identity_cleanup.sql` | `backend/app/repositories/teacher_profile_media.py`, `backend/app/routes/studio.py`, `backend/app/routes/community.py` | Repository and route names still echo the legacy term, but the underlying SQL already uses canonical `app.profile_media_placements`. |
| `DRIFT-005` | `DRIFT-005` | `canonical_diff` | semantic_search | `teacher_profile_media` | GitHub code search | multiple | `backend/app/repositories/teacher_profile_media.py`, `backend/app/routes/community.py`, `backend/supabase/migrations/20260331_profile_media_identity_cleanup.sql`, `backend/scripts/media_doctor.py`, `backend/app/services/media_cleanup.py` | frontend community/studio payload readers | Frontend readers consume backend output and did not preserve live cleanup doctrine for this family. |
| `DRIFT-005` | `DRIFT-005` | `semantic_discovery` | synonym_and_doctrine | `profile_media_placements subject_user_id visibility` | GitHub code search + local repo | focused | `backend/app/utils/profile_media.py`, `backend/app/repositories/teacher_profile_media.py`, `backend/supabase/baseline_slots/0019_runtime_media_profile_media.sql` | none | Confirmed canonical replacement doctrine exists adjacently and that live naming echoes are not the same cleanup deviation. |
| `DRIFT-005` | `DRIFT-005` | `sibling_pattern_expansion` | hidden_repetition | `cover_media_id media_objects teacher_profile_media` | GitHub code search + local repo | focused | `backend/scripts/media_doctor.py`, `backend/app/services/media_cleanup.py`, `backend/app/models.py` | `backend/supabase/migrations/20260320075542_remote_schema.sql`, archive migration trees | Migration lineage was already fenced and locked under `DRIFT-002`, so it was excluded from fresh mutation scope. |
| `DRIFT-005` | `DRIFT-005` | `execution_planning` | pre_mutation_gate | exact planned touch set | local repo | focused | `backend/app/models.py`, `backend/app/services/media_cleanup.py`, `backend/scripts/media_doctor.py` | tests and canonical slots | Tests and slots are verification surfaces, not mutation targets. |
| `DRIFT-005` | `DRIFT-005` | `post_mutation_reverification` | repeated_search | `app.teacher_profile_media`, `teacher_profile_media tpm`, `cover_media_id = mo.id` | local repo | zero active hits in mutated Python surfaces | active cleanup/script doctrine removed from mutated files | historical migration residue | Historical fenced residue remains recorded under `DRIFT-002`; no surviving active Python cleanup doctrine remained in the touched family scope. |
| `DRIFT-005` | `DRIFT-005` | `post_mutation_reverification` | environment_validation | `auth_subjects`, strict-order baseline replay, `slot dependency` | local repo + local execution | blocking | initial test failure on missing `app.auth_subjects`; strict-order replay failure at slot `0006` due missing `app.media_assets` | none | Execute-mode verification cannot continue when locked baseline replay is invalid. |

## DECISION

- The lawful smallest mutation was to remove active Python cleanup/doctor references that still treated retired `teacher_profile_media` as live truth.
- Migration-adjacent residue was not reopened because `DRIFT-002` already fenced those surfaces as historical-only.
- Family closure was blocked after mutation because canonical execute-mode reverification requires a valid strict-order baseline replay, and the locked replay path failed.

## MUTATION APPLIED

- Updated `backend/app/models.py`
  - removed retired `app.teacher_profile_media` cleanup guards from `cleanup_media_object`
- Updated `backend/app/services/media_cleanup.py`
  - removed retired `app.teacher_profile_media` orphan-protection doctrine from `garbage_collect_media`
- Updated `backend/scripts/media_doctor.py`
  - removed retired `teacher_profile_media` join/filter from orphan-media-asset detection

## VERIFICATION RUN

- Verified active Python cleanup/script references were removed:
  - `rg -n "app\\.teacher_profile_media|teacher_profile_media tpm|cover_media_id = mo.id" backend/app backend/scripts -g "*.py"`
- Ran family-scoped tests:
  - `.\.venv\Scripts\python.exe -m pytest backend/tests/test_media_doctor_report.py backend/tests/test_course_cover_pipeline.py -k "media_doctor or prune_course_cover_assets_skips_shared_lesson_storage or delete_media_asset_and_objects_skips_shared_media_object_storage or garbage_collect_media_reports_remaining_cover_storage_for_deleted_course" -q`
  - `backend/tests/test_media_doctor_report.py` passed
  - `backend/tests/test_course_cover_pipeline.py` failed before reaching the mutated cleanup logic because the local DB was missing canonical `app.auth_subjects`
- Validated local bootstrap readiness:
  - `.\.venv\Scripts\python.exe backend/scripts/bootstrap_gate.py` returned `BOOTSTRAP_GATE_OK=1`
- Attempted canonical baseline replay for lawful execute-mode verification:
  - strict-order replay stopped when `backend/supabase/baseline_slots/0006_lesson_media_core.sql` referenced `app.media_assets` before `backend/supabase/baseline_slots/0007_media_assets_core.sql` created it
- Confirmed the blocker on the local DB after the failed replay:
  - `app.auth_subjects` absent
  - `app.media_assets` absent
  - `app.lesson_media` absent

## RESULT

- `BLOCKED`
- Mutation result inside family scope:
  - active Python cleanup and doctor doctrine no longer treats retired `teacher_profile_media` as live authority
- Verification result:
  - lexical/search reverification passed for the mutated family scope
  - canonical execute-mode runtime verification failed because strict-order baseline replay is invalid

## LOCK STATUS

- `NOT_LOCKED_BLOCKED_CANONICAL_BASELINE_REPLAY_INVALID`
- Family artifact:
  - `actual_truth/analysis/legacy_outrooting_foundation/DRIFT-005_FAMILY_LOCK.md`

## NEXT VALID FAMILY

- `NONE`
- Reason:
  - continuous execution must stop before `DRIFT-004` because `DRIFT-005` did not reach lawful post-mutation closure
  - execute-mode verification cannot proceed while the locked canonical baseline replay is invalid in strict slot order
