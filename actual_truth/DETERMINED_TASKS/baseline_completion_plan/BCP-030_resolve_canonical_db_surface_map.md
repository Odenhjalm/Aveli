# BCP-030

- TASK_ID: `BCP-030`
- TYPE: `OWNER`
- TITLE: `Resolve the canonical DB-surface object map for learner and public reads`
- PROBLEM_STATEMENT: `The locked direction requires canonical DB surfaces for public discovery, public course detail, public lesson structure, and protected lesson content, but the authoritative source set does not yet define the exact DB-object map that replaces raw table semantics. Protected slot 0012 still exposes raw table grants, so execution would otherwise guess the surface boundary.`
- IMPLEMENTATION_SURFACES:
  - `Aveli_System_Decisions.md`
  - `aveli_system_manifest.json`
  - `AVELI_DATABASE_BASELINE_MANIFEST.md`
  - `actual_truth/contracts/COURSE_DETAIL_VIEW_DETERMINISTIC_RULE.md`
  - `actual_truth/contracts/learner_public_edge_contract.md`
  - `backend/supabase/baseline_slots/0011_course_public_content_core.sql`
  - `backend/supabase/baseline_slots/0012_canonical_access_policies.sql`
- TARGET_STATE:
  - the DB-object map is resolved for public discovery, public course detail, public lesson structure, and protected lesson content
  - public surfaces are explicitly user-independent
  - the protected lesson-content surface is explicitly user-scoped and bound to `course_enrollments` plus `lesson.position <= current_unlock_position`
  - `course_public_content` is represented only through the public course-detail surface
  - raw table access is explicitly marked as non-final contract expression
- DEPENDS_ON:
  - `none`
- VERIFICATION_METHOD:
  - compare the resolved surface map against DECISIONS, MANIFEST, baseline manifest, and contracts
  - confirm no surface invents new data categories
  - stop if public course detail versus composed discovery-plus-structure semantics remain ambiguous

## RESOLVED CANONICAL DB-SURFACE OBJECT MAP

- `app.course_discovery_surface`
  - source boundary: `app.courses`
  - scope: public and user-independent
  - allowed categories: `course_identity`, `course_display`, `course_grouping`, `course_pricing`
- `app.lesson_structure_surface`
  - source boundary: `app.lessons`
  - scope: public and user-independent
  - allowed categories: `lesson_identity`, `lesson_structure`
- `app.course_detail_surface`
  - composed source boundary: `app.course_discovery_surface` + `app.lesson_structure_surface` + `app.course_public_content`
  - scope: public and user-independent
  - canonical purpose: express `CourseDetailResponse` as discovery-plus-structure plus `short_description`
  - `app.course_public_content` is not an independent learner/public surface and flows only through this composed surface
- `app.lesson_content_surface`
  - source boundary: `app.lessons` + `app.lesson_contents` + `app.lesson_media`
  - scope: protected and user-scoped
  - access boundary: `app.course_enrollments` AND `lesson.position <= current_unlock_position`
  - allowed categories: `lesson_identity`, `lesson_structure`, `lesson_content`, `lesson_media`

## RESOLVED BOUNDARY RULES

- Public surfaces are user-independent and must not vary by enrollment, unlock state, membership, or caller identity.
- `app.course_detail_surface` is the only public detail expression for `app.course_public_content.short_description`.
- `app.lesson_content_surface` is the only protected learner-content DB surface.
- `membership` does not scope any DB read surface in this map.
- `visibility` does not create DB-surface access by itself.
- `app.media_assets` and `app.runtime_media` are not independent learner/public DB surfaces in this map.
- Raw tables and raw-table grants remain implementation substrate only until append-only surfaces supersede them.

## EXPLICIT NON-FINAL OBJECTS

- `app.courses`
- `app.lessons`
- `app.lesson_contents`
- `app.lesson_media`
- `app.media_assets`
- `app.course_enrollments`
- `app.runtime_media`
- direct grants in protected slot `0012`

## RESOLUTION EVIDENCE

- DECISIONS:
  - `course_discovery_surface`, `lesson_structure_surface`, and `lesson_content_surface` are canonical surface terms with fixed allowed categories.
  - `GET /courses/{course_id}` and `GET /courses/by-slug/{slug}` are composed discovery-plus-structure endpoints and must not require enrollment.
  - `GET /courses/lessons/{lesson_id}` is `lesson_content_surface` and requires `course_enrollments` AND `lesson.position <= current_unlock_position`.
  - `course_discovery_surface` and `lesson_structure_surface` are separate from `lesson_content_surface`.
- MANIFEST:
  - repeats the same surface model, endpoint map, allowed categories, and protected-access rule.
- BASELINE MANIFEST:
  - `lesson_structure_surface` maps to `lessons` only.
  - `lesson_content_surface` maps to `lessons` + `lesson_contents` + `lesson_media`.
  - DB access must express discovery, structure, and protected content through surface boundaries rather than raw-table meaning.
- CONTRACTS:
  - `COURSE_DETAIL_VIEW_DETERMINISTIC_RULE.md` fixes course detail as discovery-plus-structure plus `short_description` from `app.course_public_content`, with no user identity dependence.
  - `learner_public_edge_contract.md` fixes `CourseDiscoveryCourse`, `CourseDetailResponse`, and learner/public media law without separate resolver paths.
- CURRENT BASELINE EVIDENCE:
  - slot `0011` owns only `app.course_public_content`
  - slot `0012` still grants raw select access on `app.courses`, `app.lessons`, `app.lesson_contents`, `app.lesson_media`, `app.media_assets`, `app.course_enrollments`, and `app.runtime_media`, so raw-table semantics are active but non-final

## EXECUTION LOCK

- EXPECTED_CANONICAL_STATE:
  - one deterministic DB-object path exists for discovery, public detail, lesson structure, and protected lesson content
  - public surfaces are user-independent and protected lesson content is enrollment-and-unlock scoped only
- ACTUAL_STATE_BEFORE_ACTION:
  - canonical surface semantics were defined, but the DB-object map that should replace raw-table grants was not locked
  - protected slot `0012` still expressed access through raw tables rather than final named surfaces
- DECISION:
  - resolved and locked four canonical DB surfaces, with `app.course_detail_surface` as the only composed public detail surface and `app.lesson_content_surface` as the only protected learner-content surface
- REMAINING_RISKS:
  - append-only baseline still has to materialize these surfaces in `BCP-032` and `BCP-034`
  - mounted runtime still reads raw tables until `BCP-036`
- LOCK_STATUS:
  - `LOCKED_FOR_BCP-031_BCP-032_AND_BCP-034`
