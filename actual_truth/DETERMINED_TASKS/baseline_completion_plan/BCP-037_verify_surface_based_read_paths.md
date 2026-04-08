# BCP-037

- TASK_ID: `BCP-037`
- TYPE: `GATE`
- TITLE: `Verify surface-based read paths end to end`
- PROBLEM_STATEMENT: `The access-layer rewrite is incomplete if mounted public or protected endpoints can still bypass canonical DB surfaces or mix surface-based reads with raw-table fallback.`
- IMPLEMENTATION_SURFACES:
  - `backend/tests/`
  - `backend/app/repositories/courses.py`
  - `backend/app/services/courses_service.py`
  - `backend/app/services/courses_read_service.py`
  - `backend/app/routes/courses.py`
- TARGET_STATE:
  - focused verification fails when mounted endpoints bypass canonical DB surfaces
  - focused verification fails when public and protected categories are mixed
  - focused verification fails when raw-table semantics return as the final mounted authority
- DEPENDS_ON:
  - `BCP-036`
- VERIFICATION_METHOD:
  - add focused backend tests for all four canonical read surfaces
  - run grep checks for raw-table fallbacks in mounted course and lesson reads
  - confirm public and protected surface contracts stay disjoint

## GATE IMPLEMENTATION

- Reused the focused public-surface verification already established for:
  - public discovery
  - public course detail
  - public course public-content reads
- Reused the focused protected-surface verification established for:
  - protected lesson content
  - protected lesson structure
- Did not broaden implementation beyond verification:
  - no baseline mutation
  - no route expansion
  - no new authority path

## GATE EVIDENCE

- `backend/tests/test_course_detail_view_contract.py`
  - proves public discovery uses `course_discovery_surface`
  - proves public detail uses `course_detail_surface`
  - proves `/courses/{course_id}/public` reads through public detail rather than raw `course_public_content`
- `backend/tests/test_surface_based_lesson_reads.py`
  - proves mounted learner lesson detail uses protected surface-based content and structure
  - proves mounted learner lesson detail no longer falls back to raw `list_course_lessons(...)` or raw `list_lesson_media(...)`
- `backend/tests/test_protected_lesson_content_surface_gate.py`
  - proves protected lesson-content access remains enrollment- and unlock-bound
- `backend/app/routes/courses.py`
  - mounted public endpoints call `courses_read_service`
  - mounted protected endpoint calls `read_protected_lesson_content_surface(...)`

## GATE VERIFICATION

- `python -m py_compile` passed for:
  - `backend/app/routes/courses.py`
  - `backend/app/services/courses_read_service.py`
  - `backend/app/services/courses_service.py`
  - `backend/tests/test_course_detail_view_contract.py`
  - `backend/tests/test_surface_based_lesson_reads.py`
- Focused end-to-end surface verification passed:
  - `pytest backend/tests/test_course_detail_view_contract.py backend/tests/test_surface_based_lesson_reads.py backend/tests/test_protected_lesson_content_surface_gate.py -q`
  - result: `13 passed`
- Grep verification confirmed mounted route call sites now resolve through:
  - `list_public_course_discovery`
  - `fetch_public_course_detail_rows`
  - `read_public_course_content`
  - `read_protected_lesson_content_surface`
  - `list_course_lesson_structure`
- Grep verification confirmed mounted route and read-service files do not directly query:
  - `app.courses`
  - `app.lessons`
  - `app.lesson_contents`
  - `app.lesson_media`
  as final mounted authority.

## EXECUTION LOCK

- EXPECTED_STATE:
  - mounted public and protected course endpoints are surface-based end to end
  - public and protected categories stay disjoint
  - raw-table semantics do not return as final mounted authority
- ACTUAL_STATE:
  - public discovery, public detail, and public content remain on canonical public surfaces
  - protected learner lesson detail now resolves through canonical protected and structure surfaces
  - mounted route and read-service call sites no longer use raw-table helpers as final read authority
- REMAINING_RISKS:
  - aggregate audits still must confirm append-only and authority boundaries across the full completed plan
- RESULT:
  - `PASS`
- LOCK_STATUS:
  - `PASSED_FOR_BCP-051`
