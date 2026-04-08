# BCP-036

- TASK_ID: `BCP-036`
- TYPE: `OWNER`
- TITLE: `Align mounted runtime reads to canonical DB surfaces`
- PROBLEM_STATEMENT: `Even after append-only DB surfaces exist, mounted runtime remains invalid until repositories, services, and routes stop treating raw tables as the public and protected read authority. Course detail and lesson content consumers must also compose media through the unified runtime_media chain instead of mixing old table reads with new surfaces.`
- IMPLEMENTATION_SURFACES:
  - `backend/app/repositories/courses.py`
  - `backend/app/services/courses_service.py`
  - `backend/app/services/courses_read_service.py`
  - `backend/app/routes/courses.py`
  - mounted learner and public read helpers
- TARGET_STATE:
  - `/courses` consumes the public discovery surface
  - `/courses/{course_id}` and `/courses/by-slug/{slug}` consume the public course-detail plus lesson-structure surfaces
  - `/courses/lessons/{lesson_id}` consumes the protected lesson-content surface
  - mounted runtime no longer treats raw tables as the final read authority for these endpoints
  - course detail and lesson content continue to compose media only through unified `runtime_media`
- DEPENDS_ON:
  - `BCP-033`
  - `BCP-035`
  - `BCP-044`
- VERIFICATION_METHOD:
  - grep mounted runtime for raw-table read authority on `app.courses`, `app.lessons`, `app.lesson_contents`, and `app.lesson_media`
  - confirm read services consume canonical DB surfaces instead of convenience joins
  - confirm `course_public_content` is not consumed outside the public course-detail path

## OWNER IMPLEMENTATION

- Added one protected mounted read path from canonical DB surfaces in `backend/app/repositories/courses.py`:
  - `list_lesson_structure_surface(course_id)`
  - `get_lesson_content_surface_rows(lesson_id, user_id)`
- Bound protected surface reads to canonical subject identity by setting:
  - `request.jwt.claim.sub`
  - in the repository session immediately before querying `app.lesson_content_surface`
- Added surface-based service helpers in `backend/app/services/courses_service.py`:
  - `list_course_lesson_structure(course_id)`
  - `read_protected_lesson_content_surface(lesson_id, user_id)`
- Rebuilt mounted protected lesson media composition from:
  - `lesson_content_surface`
  - `runtime_media`
  - canonical lesson playback
  instead of reading `app.lesson_media` as final mounted authority
- Rewired `/courses/lessons/{lesson_id}` in `backend/app/routes/courses.py` so the mounted learner lesson endpoint now consumes:
  - protected lesson content from `lesson_content_surface`
  - lesson structure from `lesson_structure_surface`
  - backend-authored media objects only
- Added focused mounted-read verification in:
  - `backend/tests/test_surface_based_lesson_reads.py`

## OWNER EVIDENCE

- `backend/app/services/courses_read_service.py`
  - public detail and public content remain surface-based through `course_detail_surface`
- `backend/app/routes/courses.py`
  - mounted learner lesson detail now calls `read_protected_lesson_content_surface(...)`
  - mounted learner lesson detail now calls `list_course_lesson_structure(...)`
  - mounted learner lesson detail no longer uses raw `list_course_lessons(...)` or raw `list_lesson_media(...)`
- `backend/app/repositories/courses.py`
  - protected lesson content now has a repository path through `app.lesson_content_surface`
  - protected lesson structure now has a repository path through `app.lesson_structure_surface`
- `backend/tests/test_surface_based_lesson_reads.py`
  - proves mounted lesson detail prefers surface-based structure and content over raw helper paths
- `backend/tests/test_protected_lesson_content_surface_gate.py`
  - still proves protected lesson content stays enrollment- and unlock-bound

## OWNER VERIFICATION

- `python -m py_compile` passed for:
  - `backend/app/repositories/courses.py`
  - `backend/app/services/courses_service.py`
  - `backend/app/routes/courses.py`
  - `backend/tests/test_surface_based_lesson_reads.py`
- Focused protected-surface verification passed:
  - `pytest backend/tests/test_surface_based_lesson_reads.py backend/tests/test_protected_lesson_content_surface_gate.py -q`
  - result: `6 passed`
- Grep verification confirmed:
  - mounted public detail remains in `courses_read_service`
  - mounted `/courses/{course_id}/public` remains on `courses_read_service.read_public_course_content(...)`
  - mounted learner lesson detail no longer consumes raw `list_course_lessons(...)` or raw `list_lesson_media(...)`
- Remaining raw-table helpers still exist in repository and service scope for studio/write or non-mounted usage, but they are no longer the final mounted authority for the endpoints owned by this task.

## EXECUTION LOCK

- EXPECTED_STATE:
  - mounted public and protected course reads use canonical DB surfaces as final read authority
  - lesson-content responses compose media through unified `runtime_media` rather than raw lesson-media truth
  - `course_public_content` is not mounted outside the public course-detail path
- ACTUAL_STATE:
  - mounted learner lesson detail now consumes `lesson_content_surface` and `lesson_structure_surface`
  - mounted public course detail and public content remain on canonical public surfaces
  - backend media composition for learner lesson reads remains unified-media-based
- REMAINING_RISKS:
  - end-to-end gate `BCP-037` still must prove that no mounted fallback path restores raw-table authority
  - non-mounted raw repository helpers remain in the codebase and must stay outside final mounted authority
- RESULT:
  - `PASS`
- LOCK_STATUS:
  - `LOCKED_FOR_BCP-037`
