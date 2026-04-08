# BCP-032

- TASK_ID: `BCP-032`
- TYPE: `OWNER`
- TITLE: `Materialize public user-independent DB surfaces`
- PROBLEM_STATEMENT: `Protected slot 0012 currently expresses public reads through raw table grants. The canonical plan requires append-only public DB surfaces that own discovery, public course detail, and public lesson structure without relying on enrollment or user-specific filtering.`
- IMPLEMENTATION_SURFACES:
  - `backend/supabase/baseline_slots/`
  - `backend/supabase/baseline_slots.lock.json`
  - `backend/supabase/baseline_slots/0011_course_public_content_core.sql`
- TARGET_STATE:
  - append-only slot(s) above `0012` materialize the resolved public discovery surface
  - append-only slot(s) above `0012` materialize the resolved public course-detail surface
  - append-only slot(s) above `0012` materialize the resolved public lesson-structure surface
  - `course_public_content.short_description` flows only through the public course-detail surface
  - public surfaces remain user-independent and exclude `lesson_content`, `lesson_media`, enrollment state, and unlock state
- DEPENDS_ON:
  - `BCP-031`
- VERIFICATION_METHOD:
  - refresh and verify `backend/supabase/baseline_slots.lock.json`
  - confirm public surfaces are append-only additions above the protected range
  - confirm raw table grants are no longer the final public read contract

## OWNER IMPLEMENTATION

- Appended `backend/supabase/baseline_slots/0015_public_course_surfaces.sql` above the protected slot boundary.
- The new slot materializes:
  - `app.course_discovery_surface`
  - `app.lesson_structure_surface`
  - `app.course_detail_surface`
- `app.course_discovery_surface` exposes only canonical course discovery fields from `app.courses`.
- `app.lesson_structure_surface` exposes only lesson identity and structure fields from `app.lessons`.
- `app.course_detail_surface` composes:
  - `app.course_discovery_surface`
  - `app.lesson_structure_surface`
  - `app.course_public_content`
- `course_public_content.short_description` now flows to public reads only through `app.course_detail_surface`.
- The new views are granted `select` to `public` and use `security_invoker = true`.
- `backend/supabase/baseline_slots.lock.json` now includes slot `15` with the verified SHA-256 for `0015_public_course_surfaces.sql`.

## OWNER EVIDENCE

- `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-031_lock_db_surface_contract_boundary.md`
  - already passed the DB-surface gate and fixed one named public path for discovery, lesson structure, and public course detail
- `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-030_resolve_canonical_db_surface_map.md`
  - already locked `app.course_discovery_surface`, `app.lesson_structure_surface`, and `app.course_detail_surface` as the canonical public surface objects
  - already locked `app.course_detail_surface` as the only public expression for `app.course_public_content.short_description`
- `Aveli_System_Decisions.md`
  - fixes `course_discovery_surface` and `lesson_structure_surface` as public user-independent surfaces
  - fixes course-detail endpoints as composed discovery-plus-structure without enrollment
  - forbids `lesson_content`, `lesson_media`, enrollment state, and unlock state on public surfaces
- `actual_truth/contracts/COURSE_DETAIL_VIEW_DETERMINISTIC_RULE.md`
  - fixes `short_description` as a sibling-composed projection of `app.course_public_content`
  - fixes course detail as independent of user identity
- `actual_truth/contracts/learner_public_edge_contract.md`
  - fixes `CourseDiscoveryCourse` as the canonical public course shape
  - forbids learner/public media resolver drift and raw storage payloads on public surfaces
- `backend/supabase/baseline_slots/0011_course_public_content_core.sql`
  - owns `app.course_public_content` without exposing it directly as a learner/public surface
- `backend/supabase/baseline_slots/0012_canonical_access_policies.sql`
  - still grants raw-table public access and therefore remained substrate drift before this append-only surface slot landed
- Deterministic inference used by this task:
  - `app.course_detail_surface` is materialized as a flat relational projection rather than JSON aggregation because the canonical source set requires one named composed DB object but does not authorize metadata/blob surface contracts

## OWNER VERIFICATION

- Parsed `backend/supabase/baseline_slots.lock.json` after mutation and confirmed:
  - `protected_max_slot = 12`
  - new slot = `15`
  - `0015_public_course_surfaces.sql` hash matches the recorded SHA-256
- Verified `0015_public_course_surfaces.sql` contains all three public surface views and public grants.
- Verified `0015_public_course_surfaces.sql` does not contain:
  - `course_enrollments`
  - `lesson_contents`
  - `lesson_media`
  - `media_assets`
  - `runtime_media`
  - unlock-state or user-identity policy expressions
- Verified public grants now exist for:
  - `app.course_discovery_surface`
  - `app.lesson_structure_surface`
  - `app.course_detail_surface`
- Verified no public grant exists for `app.course_public_content`, so `short_description` cannot become an independent public surface.
- Verified protected slots `0001-0014` remain unchanged by this task.

## EXECUTION LOCK

- EXPECTED_STATE:
  - append-only public DB surfaces exist above `0012` for discovery, lesson structure, and public course detail
  - public surfaces remain user-independent and exclude lesson content, lesson media, enrollment state, and unlock state
  - `short_description` reaches public reads only through the course-detail surface
- ACTUAL_STATE:
  - baseline ownership now exists in `0015_public_course_surfaces.sql`
  - named public surfaces are queryable without relying on raw-table contract names
  - `app.course_detail_surface` is the only new public surface that composes `short_description`
- REMAINING_RISKS:
  - protected raw-table grants still exist as substrate until later consumer alignment and gate verification
  - mounted runtime still reads raw tables until `BCP-036`
- RESULT:
  - `PASS`
- LOCK_STATUS:
  - `LOCKED_FOR_BCP-033`
