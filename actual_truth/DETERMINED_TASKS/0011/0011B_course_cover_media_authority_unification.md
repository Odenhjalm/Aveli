# 0011B

- TASK_ID: `0011B`
- TYPE: `OWNER`
- TITLE: `Replace special-case course cover resolution with unified media authority`
- PROBLEM_STATEMENT: `Course cover read composition still uses a separate cover-specific resolver in courses_service and landing still emits a separate resolved_cover_url shape, which violates the unified rule that cover is a media usage rather than a special pipeline.`
- TARGET_STATE:
  - `backend/app/services/courses_service.py`
  - `backend/app/services/courses_read_service.py`
  - `backend/app/routes/courses.py`
  - `backend/app/models.py`
  - `backend/app/schemas/__init__.py`
  - `frontend/lib/features/courses/data/courses_repository.dart`
  - `frontend/lib/features/landing/application/landing_providers.dart`
  - course list, course detail, and landing surfaces expose one backend-authored media object shape for cover
  - no course read surface uses a dedicated `resolve_course_cover()` authority path
  - no course read surface emits `resolved_cover_url` as a parallel cover contract
- DEPENDS_ON:
  - `0011A`
- VERIFICATION_METHOD:
  - `rg -n "resolve_course_cover|resolved_cover_url|cover_media_id|cover:" backend/app frontend/lib`
  - confirm mounted course and landing responses serialize one media object shape for cover
  - confirm frontend course/landing surfaces render backend-authored cover objects only

