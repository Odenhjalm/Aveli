# TA-005

- TASK_ID: `TA-005`
- TYPE: `GATE`
- CLUSTER: `ACCESS_MODEL_REWRITE`
- DESCRIPTION: `Rewrite access-model tests to explicit `course.step` plus `course_enrollments.source` rules, remove membership-only lesson access assumptions, and align all access assertions to `course_enrollments` plus `current_unlock_position` authority.`
- TARGET_FILES:
  - `backend/tests/test_course_access_authority.py`
  - `backend/tests/test_course_visibility_and_media_access.py`
  - `backend/tests/test_courses_public.py`
- ACTION: `rewrite`
- DEPENDS_ON:
  - `TA-004`

