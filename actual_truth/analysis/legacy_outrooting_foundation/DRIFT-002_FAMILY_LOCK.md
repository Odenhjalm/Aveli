# DRIFT-002 Family Lock

## DEVIATION FAMILY ID

- `DRIFT-002`
- Title: `Remote-schema and legacy migration lineage still encode non-canonical doctrine`
- Seed drift source:
  - `actual_truth/analysis/legacy_outrooting_foundation/DRIFT_REGISTER.md`
  - `actual_truth/analysis/legacy_outrooting_foundation/DRIFT_MANIFEST.json`

## CANONICAL RULES USED

- `Aveli_System_Decisions.md:122-124`
  - `backend/supabase/baseline_slots` is canonical baseline truth.
  - `supabase/migrations/*.sql` does not define canonical local verification truth.
- `Aveli_System_Decisions.md:190-207`
  - media identity, authored placement, runtime truth, and frontend representation each have one authority path.
- `AVELI_DATABASE_BASELINE_MANIFEST.md:92-96`
  - `memberships` is canonical app-entry authority and excludes Stripe-era billing fields.
- `AVELI_DATABASE_BASELINE_MANIFEST.md:112-118`
  - `auth_subjects` owns onboarding, role, and admin authority and excludes profile-owned subject doctrine.
- `AVELI_DATABASE_BASELINE_MANIFEST.md:175-208`
  - `profile_media_placements` is the only canonical profile-media authored-placement source entity.
  - `runtime_media` is canonical runtime truth and projects profile media only from canonical placements.
- `actual_truth/analysis/legacy_outrooting_foundation/CANONICAL_VS_NONAUTHORITATIVE_BOUNDARY.md`
  - locked authority is `backend/supabase/baseline_slots/` plus the active canonical source set.
  - `backend/supabase/migrations/*.sql` is a non-authoritative outrooting target.
- `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-012_append_baseline_app_memberships_authority.md:6,88-90`
  - baseline ownership was appended above the protected boundary instead of mutating remote-schema lineage.
- `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-022_append_baseline_auth_subject_authority.md:57,91-93`
  - remote-schema profile drift remained only as residual drift after canonical auth-subject ownership was appended.
- `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-051_aggregate_canonical_authority_completion.md:84-102`
  - final canonical baseline completion is locked and broader migration/upload residue remains non-authoritative.

## EXPECTED CANONICAL STATE

- Canonical local DB truth is the append-only slot chain in `backend/supabase/baseline_slots/`.
- Canonical authority for the concepts echoed by this family is already owned by:
  - `0013_memberships_core.sql`
  - `0014_auth_subjects_core.sql`
  - `0017_runtime_media_unified.sql`
  - `0019_runtime_media_profile_media.sql`
- Legacy migration history may exist, but it must be explicitly fenced as non-authoritative.
- No active documentation should present `remote_schema` lineage as the source-of-truth shape for governed concepts.

## ACTUAL DRIFT STATE

- `backend/supabase/migrations/20260320075542_remote_schema.sql` still encoded:
  - Stripe-era membership fields
  - `cover_url`
  - `fallback_policy`
  - `legacy_storage_bucket`
  - `legacy_storage_path`
  - `asset_url`
  - `teacher_permissions`
  - `teacher_profile_media`
- `backend/supabase/migrations/20260331_profile_media_identity_cleanup.sql` still encoded retired `teacher_profile_media` cleanup doctrine.
- `backend/supabase/migrations/20260320075057_remote_schema.sql` existed as a zero-byte dead sibling.
- Archive trees `supabase/migrations_legacy_20260325/` and `supabase/migrations_legacy_20260326/` preserved the same retired doctrine across remote-schema and transition-era migration files.
- `docs/media_control_plane_mcp.md` still pointed to `backend/supabase/migrations/20260320075542_remote_schema.sql` as runtime projection source truth.

## DRIFT CLASSIFICATION

| deviation_scope | canonical_path_exists | authority_risk | transition_layer | residual_value | primary_processing_state | canonical_rule_reference | classification_evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `backend/supabase/migrations/20260320075542_remote_schema.sql` | `YES_ADJACENT` | `MEDIUM` | `THICK` | `CONDITIONALLY_REACHABLE` | `ISOLATE_NON_AUTHORITATIVE_SURFACE` | `Aveli_System_Decisions.md:122-124`, `AVELI_DATABASE_BASELINE_MANIFEST.md:92-96,112-118,175-208` | Active-looking migration path, but production tooling ignores `backend/supabase/migrations` and baseline slots already own the canonical concepts. |
| `backend/supabase/migrations/20260331_profile_media_identity_cleanup.sql` | `YES_ADJACENT` | `MEDIUM` | `THIN` | `CONDITIONALLY_REACHABLE` | `ISOLATE_NON_AUTHORITATIVE_SURFACE` | `AVELI_DATABASE_BASELINE_MANIFEST.md:175-208`, `actual_truth/contracts/profile_community_media_contract.md:51-57,128-132` | Historical cleanup path still names retired `teacher_profile_media` doctrine outside canonical profile-media authority. |
| `backend/supabase/migrations/20260320075057_remote_schema.sql` | `YES_ADJACENT` | `LOW` | `NONE` | `DEAD` | `REMOVE_DEAD_SURFACE` | `CANONICAL_VS_NONAUTHORITATIVE_BOUNDARY.md`, `BCP-051_aggregate_canonical_authority_completion.md:97-99` | Zero-byte placeholder with no justified residual value. |
| `supabase/migrations_legacy_20260325/` | `YES_ADJACENT` | `LOW` | `THICK` | `HISTORICAL_ONLY` | `ISOLATE_NON_AUTHORITATIVE_SURFACE` | `Aveli_System_Decisions.md:122-124`, `docs/DEPLOYMENT.md:53-56` | Archive tree repeats remote-schema and transition-era doctrine but is not the production migration source. |
| `supabase/migrations_legacy_20260326/` | `YES_ADJACENT` | `LOW` | `THICK` | `HISTORICAL_ONLY` | `ISOLATE_NON_AUTHORITATIVE_SURFACE` | `Aveli_System_Decisions.md:122-124`, `docs/DEPLOYMENT.md:53-56` | Archive tree repeats remote-schema and transition-era doctrine but is not the production migration source. |
| `docs/media_control_plane_mcp.md` | `YES_DIRECT` | `MEDIUM` | `THIN` | `ACTIVE_NONAUTHORITATIVE` | `REPLACE_WITH_CANONICAL_PATH` | `Aveli_System_Decisions.md:192-207`, `AVELI_DATABASE_BASELINE_MANIFEST.md:197-208` | Active doc echoed `remote_schema` as runtime projection truth even though append-only baseline slots are canonical. |

### Blocker Record

| family_id | seed_drift_id | deviation_scope | replacement_blocker_reason | blocking_evidence | current_processing_state | future_replacement_trigger |
| --- | --- | --- | --- | --- | --- | --- |
| `DRIFT-002` | `DRIFT-002` | `backend/supabase/migrations/20260320075542_remote_schema.sql` and archive trees | No direct canonical production migration replacement path is materialized in the workspace, so historical migration lineage cannot be cleanly replaced without a separate production-migration authority decision. | `docs/DEPLOYMENT.md:53-56`, `backend/scripts/apply_supabase_migrations.sh`, `Test-Path supabase/migrations = False` | `ISOLATE_NON_AUTHORITATIVE_SURFACE` | Re-evaluate only after a canonical production migration source is materialized or an explicit archive-removal task is declared. |

## SEARCH EVIDENCE

### Search Ledger

| family_id | seed_drift_id | search_step | search_type | query_or_concept | surface_searched | hits | included_findings | excluded_findings | reason_for_exclusion |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `DRIFT-002` | `DRIFT-002` | `canonical_diff` | exact_lexical | `teacher_profile_media`, `teacher_permissions`, `fallback_policy`, `legacy_storage_`, `cover_url`, `asset_url`, `stripe_customer_id`, `plan_interval` | local repo | multiple | `backend/supabase/migrations/20260320075542_remote_schema.sql`, `backend/supabase/migrations/20260331_profile_media_identity_cleanup.sql`, `backend/supabase/migrations/20260320075057_remote_schema.sql` | `backend/app/utils/media_urls.py`, test payload surfaces | Better aligned to `DRIFT-006` legacy payload residue, not migration lineage. |
| `DRIFT-002` | `DRIFT-002` | `canonical_diff` | semantic_search | `runtime_media`, `teacher_profile_media`, `cover_url` | GitHub code search | multiple | `backend/app/repositories/runtime_media.py`, `backend/app/repositories/teacher_profile_media.py`, `backend/supabase/migrations/20260320075542_remote_schema.sql`, archive remote-schema files | `runtime_media_reference_design.md` | Reference design, not active doctrine owner. |
| `DRIFT-002` | `DRIFT-002` | `semantic_discovery` | hidden_repetition | duplicate remote-schema and transition-era migration lineage | local repo + GitHub code search | multiple | `supabase/migrations_legacy_20260325/`, `supabase/migrations_legacy_20260326/` | `backend/scripts/runtime_media_baseline_drift_check.sh`, media-control-plane payload tests and backfill helpers | Verification and payload echoes belong with `DRIFT-006` legacy media payload and verification residue. |
| `DRIFT-002` | `DRIFT-002` | `sibling_pattern_expansion` | symbol_and_path | `backend/supabase/migrations`, `migrations_legacy_20260325`, `migrations_legacy_20260326`, `remote_schema` | local repo | multiple | `docs/media_control_plane_mcp.md` as cross-surface doctrine echo | `backend/scripts/fix_schema_migrations.sh`, `docs/DEPLOYMENT.md` | Both already fence remote-schema rather than preserve it as authority. |
| `DRIFT-002` | `DRIFT-002` | `deterministic_classification` | reachability_audit | production tooling and canonical migration path | local repo | focused | `backend/scripts/apply_supabase_migrations.sh` ignores `backend/supabase/migrations`; root `supabase/migrations` path is absent | none | n/a |
| `DRIFT-002` | `DRIFT-002` | `execution_planning` | pre_mutation_gate | exact planned touch set | local repo + GitHub code search | focused | `docs/media_control_plane_mcp.md`, `backend/supabase/migrations`, archive trees | `docs/verify/LAUNCH_READINESS_REPORT.md`, `docs/media_forensic_report_20260123.md` | Historical reports, not active authority surfaces. |
| `DRIFT-002` | `DRIFT-002` | `post_mutation_reverification` | repeated_search | `remote_schema`, canonical baseline slot refs, diagnostic legacy-field boundary, archive fences | local repo + prior GitHub code search evidence | focused | dead sibling remained absent, archive and migration trees remained fenced, doc no longer cited backend remote-schema as source truth | media-control-plane payload fields in docs/tests/services | Remaining payload and verification echoes were explicitly fenced in docs and classified forward to `DRIFT-006`, not reopened into this family. |

## DECISION

- Direct replacement was not lawful for the historical migration lineage because no direct canonical production migration path exists in this workspace.
- The lawful smallest plan was:
  - remove the dead zero-byte sibling
  - fence active-looking legacy migration directories as non-authoritative
  - replace the one active documentation echo with canonical baseline references
- This keeps locked baseline authority unchanged and prevents the drift family from masquerading as truth.

## MUTATION APPLIED

- Deleted dead file:
  - `backend/supabase/migrations/20260320075057_remote_schema.sql`
- Added non-authoritative boundary docs:
  - `backend/supabase/migrations/README.md`
  - `supabase/README.md`
- Replaced the active documentation echo:
  - `docs/media_control_plane_mcp.md`
    - removed `backend/supabase/migrations/20260320075542_remote_schema.sql` as runtime projection source truth
    - pointed the document to canonical append-only baseline slots `0017` through `0019`
    - explicitly fenced remaining diagnostic `fallback_policy` and `legacy_storage_*` fields as non-authoritative observability residue

## VERIFICATION RUN

- Verified the dead sibling was removed:
  - `Test-Path backend/supabase/migrations/20260320075057_remote_schema.sql` -> `False`
- Verified the active doc echo was replaced with canonical references:
  - `rg -n "runtime projection source-of-truth shape|20260320075542_remote_schema.sql|0017_runtime_media_unified|0018_runtime_media_home_player|0019_runtime_media_profile_media" docs/media_control_plane_mcp.md`
- Verified the remaining MCP diagnostic field references are fenced:
  - `rg -n "Diagnostic legacy-field boundary|fallback_policy|legacy_storage_" docs/media_control_plane_mcp.md`
- Verified the new archive fences exist:
  - `rg -n "non-authoritative|historical|baseline_slots|production" backend/supabase/migrations/README.md supabase/README.md`
- Verified the pre-existing fence still holds:
  - `docs/DEPLOYMENT.md:53-56`
  - `backend/scripts/apply_supabase_migrations.sh`
- Re-ran lexical and semantic search after mutation to confirm no active doc still presents backend remote-schema lineage as canonical truth.

## RESULT

- `PASS`
- Family invariant after mutation:
  - legacy migration lineage remains present only as fenced historical residue
  - the dead sibling is gone
  - active documentation no longer points to remote-schema lineage as runtime projection truth
  - any remaining MCP diagnostic legacy-field references are explicitly fenced as non-authoritative observability residue
  - locked canonical baseline authority remained untouched

## LOCK STATUS

- `LOCKED_AS_LAWFULLY_CLASSIFIED_AND_ISOLATED`
- Lock artifact:
  - `actual_truth/analysis/legacy_outrooting_foundation/DRIFT-002_FAMILY_LOCK.md`

## NEXT VALID FAMILY

- `DRIFT-005`
- Reason:
  - `DRIFT-002` is now processed and locked without reopening canonical ambiguity.
  - `DRIFT-005` is the next highest-risk residual family in the priority map that remains outside locked canonical authority.
