# BCP-031

- TASK_ID: `BCP-031`
- TYPE: `GATE`
- TITLE: `Lock the DB-surface contract boundary before append-only access work starts`
- PROBLEM_STATEMENT: `Append-only DB-surface work cannot begin until the resolved surface map proves that user-independent and user-scoped reads are separated cleanly and that raw table grants will no longer stand as the final access contract.`
- IMPLEMENTATION_SURFACES:
  - `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-030_resolve_canonical_db_surface_map.md`
  - `actual_truth/contracts/COURSE_DETAIL_VIEW_DETERMINISTIC_RULE.md`
  - `actual_truth/contracts/learner_public_edge_contract.md`
  - `backend/supabase/baseline_slots/0012_canonical_access_policies.sql`
- TARGET_STATE:
  - one deterministic DB-surface map exists
  - public and protected boundaries are explicit
  - raw tables are no longer treated as final access surfaces
  - downstream baseline tasks can materialize surfaces without convenience grouping or mixed semantics
- DEPENDS_ON:
  - `BCP-030`
- VERIFICATION_METHOD:
  - assert one DB-object path for each required surface
  - assert public surfaces exclude lesson content, lesson media, enrollment state, and unlock state
  - assert the protected surface excludes membership-only or visibility-only authority

## GATE ASSERTIONS

- One deterministic DB-object path exists for each required surface:
  - `app.course_discovery_surface`
  - `app.lesson_structure_surface`
  - `app.course_detail_surface`
  - `app.lesson_content_surface`
- Public surface boundaries are explicit and user-independent:
  - `app.course_discovery_surface` exposes only `course_identity`, `course_display`, `course_grouping`, and `course_pricing`
  - `app.lesson_structure_surface` exposes only `lesson_identity` and `lesson_structure`
  - `app.course_detail_surface` is the only composed public detail surface and is discovery-plus-structure plus `short_description`
- Public surfaces must exclude:
  - `lesson_content`
  - `lesson_media`
  - enrollment state
  - unlock state
- Protected surface boundaries are explicit and user-scoped only through:
  - `course_enrollments`
  - `lesson.position <= current_unlock_position`
- Membership-only authority and visibility-only rules are insufficient for `lesson_content_surface`.
- Raw tables and protected-slot grants are implementation substrate only and do not remain the final DB access contract once append-only surface work begins.

## GATE EVIDENCE

- `actual_truth/DETERMINED_TASKS/baseline_completion_plan/BCP-030_resolve_canonical_db_surface_map.md`
  - already resolves one named DB-object path for discovery, public detail, lesson structure, and protected lesson content
  - already marks raw tables and raw grants as non-final objects
- `Aveli_System_Decisions.md`
  - fixes the canonical surface terms and allowed category boundaries
  - fixes course detail as discovery-plus-structure without enrollment
  - fixes `lesson_content_surface` as enrollment-and-unlock scoped only
  - forbids interpreting visibility as raw-table access authority
- `aveli_system_manifest.json`
  - repeats the same surface map, category boundaries, and protected access rule
  - marks `course_detail` as composed from discovery plus lesson structure
- `AVELI_DATABASE_BASELINE_MANIFEST.md`
  - fixes `lesson_structure_surface` to `lessons` only
  - fixes `lesson_content_surface` to `lessons` + `lesson_contents` + `lesson_media`
  - fixes `course_enrollments` as the only protected lesson-content authority
- `actual_truth/contracts/COURSE_DETAIL_VIEW_DETERMINISTIC_RULE.md`
  - fixes `short_description` to `app.course_public_content`
  - forbids course-detail dependence on `course_enrollments`
- `actual_truth/contracts/learner_public_edge_contract.md`
  - keeps learner/public discovery and detail separate from protected lesson content
- `backend/supabase/baseline_slots/0012_canonical_access_policies.sql`
  - still grants raw-table access and therefore demonstrates current non-final substrate drift rather than the locked final contract
- repo mismatch evidence only:
  - mounted repositories and read services still assemble reads from raw tables instead of named canonical surfaces

## GATE DECISION

- The DB-surface map is deterministic enough for append-only surface materialization to proceed.
- Public and protected boundaries are materially separated and no required surface remains ambiguous.
- Raw-table grants are now explicitly classified as temporary substrate expression rather than final access doctrine.
- Because the contract boundary is locked, later append-only work may materialize public and protected surfaces without convenience grouping or mixed semantics.

## EXECUTION LOCK

- EXPECTED_GATE_STATE:
  - downstream surface materialization may rely on one named contract boundary per surface
  - raw-table semantics are no longer the final authority model
- ACTUAL_GATE_STATE_BEFORE_ACTION:
  - `BCP-030` had resolved the surface map, but this gate artifact had not yet certified that the map was safe to materialize append-only
  - protected slot `0012` and mounted runtime still expressed access through raw tables
- DECISION:
  - gate passes
- REMAINING_RISKS:
  - append-only surface ownership still must land in `BCP-032` and `BCP-034`
  - mounted runtime still consumes raw tables until `BCP-036`
- LOCK_STATUS:
  - `PASSED_FOR_BCP-032_AND_BCP-034`
