# BCP-051

- TASK_ID: `BCP-051`
- TYPE: `AGGREGATE`
- TITLE: `Aggregate canonical baseline-completion authority audit`
- PROBLEM_STATEMENT: `The canonical baseline-completion plan is finished only if app entry, auth subject, read access, and unified runtime media all converge on one authority path each and no alternative authority remains in scope.`
- IMPLEMENTATION_SURFACES:
  - `actual_truth/DETERMINED_TASKS/baseline_completion_plan/`
  - mounted backend read and auth surfaces
  - append-only baseline slots introduced by this plan
- TARGET_STATE:
  - app entry is canonical through `app.memberships`
  - auth-subject authority is canonical through the resolved subject entity above Supabase Auth
  - read access is surface-based rather than raw-table-based
  - `runtime_media` is unified and canonical, including course cover
  - no alternative authority path remains in scope
- DEPENDS_ON:
  - `BCP-037`
  - `BCP-050`
- VERIFICATION_METHOD:
  - run the final aggregate audit over all cluster gates and append-only slots
  - confirm every concept in scope has one authority path only
  - confirm the task set can hand off to execute mode without reopening schema or authority ambiguity

## AGGREGATE IMPLEMENTATION

- Reused the already locked aggregate and cluster-gate results for:
  - `BCP-014`
  - `BCP-024`
  - `BCP-033`
  - `BCP-035`
  - `BCP-037`
  - `BCP-044`
  - `BCP-050`
- Reused the append-only baseline authority delivered by:
  - `0013_memberships_core.sql`
  - `0014_auth_subjects_core.sql`
  - `0015_public_course_surfaces.sql`
  - `0016_lesson_content_surface.sql`
  - `0017_runtime_media_unified.sql`
  - `0018_runtime_media_home_player.sql`
  - `0019_runtime_media_profile_media.sql`
- Performed only the final cross-cluster audit:
  - no baseline mutation
  - no runtime mutation
  - no task expansion

## AGGREGATE EVIDENCE

- App entry:
  - `app.memberships` is locked as the sole app-entry authority in baseline and mounted runtime
  - `BCP-014` passed for membership-only authority
- Auth subject:
  - `app.auth_subjects` is locked as the sole subject onboarding, role, and admin authority above Supabase Auth
  - `BCP-024` passed for auth-subject separation and teacher-rights correctness
- Read access:
  - public discovery/detail/structure are locked on canonical DB surfaces
  - protected learner content is locked on `lesson_content_surface`
  - `BCP-037` passed for end-to-end surface-based mounted reads
- Unified media:
  - `runtime_media` is locked as the sole runtime truth layer across course cover, home-player, and profile/community media
  - `profile_community_media_contract.md` is active and keeps profile/community media inside the same unified doctrine
  - `BCP-044` passed for governed media shape and runtime-media authority
- Aggregate substrate law:
  - `BCP-050` passed for append-only evolution and substrate-only boundaries

## AGGREGATE VERIFICATION

- Final focused authority suite passed:
  - `pytest backend/tests/test_membership_app_entry_gate.py backend/tests/test_auth_subject_authority_gate.py backend/tests/test_course_detail_view_contract.py backend/tests/test_protected_lesson_content_surface_gate.py backend/tests/test_runtime_media_authority_gate.py backend/tests/test_surface_based_lesson_reads.py backend/tests/test_teacher_profile_media_truth_alignment.py -q`
  - result: `22 passed`
- Cross-cluster doctrine verification passed:
  - app entry has one authority path only: `memberships`
  - auth-subject authority has one path only: `auth_subjects`
  - mounted read access has one path only: canonical DB surfaces
  - runtime media truth has one path only: `runtime_media` feeding backend read composition
- Scope audit passed:
  - no alternative authority path remains in scope for the governed mounted surfaces covered by this plan
  - the remaining `asset_url` occurrence in studio upload flow is a write/upload concern outside the mounted read-authority scope of this aggregate audit
- Schema/authority ambiguity audit passed:
  - active contracts now include an activation-ready `profile_community_media_contract.md`
  - the completed task set no longer requires reopening schema or authority ambiguity for concepts in scope

## EXECUTION LOCK

- EXPECTED_STATE:
  - app entry is canonical only through `app.memberships`
  - auth-subject authority is canonical only through `app.auth_subjects`
  - mounted reads are surface-based rather than raw-table-based
  - `runtime_media` is unified and canonical across governed media surfaces
  - no alternative authority path remains in scope
- ACTUAL_STATE:
  - membership, auth-subject, DB-surface, and unified-media clusters all passed their gates and aggregate audit
  - append-only baseline slots `0013` through `0019` now cover the full authority set required by the plan
  - active contracts and mounted verification agree on one authority path per concept in scope
  - the completed plan can now hand off without reopening schema or authority ambiguity
- REMAINING_RISKS:
  - broader legacy upload and migration code outside the plan scope still exists and should continue to be treated as non-authoritative until separately retired
- RESULT:
  - `PASS`
- LOCK_STATUS:
  - `FINAL_CANONICAL_BASELINE_COMPLETION_LOCKED`
