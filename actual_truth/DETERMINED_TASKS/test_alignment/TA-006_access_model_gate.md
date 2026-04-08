# TA-006

- TASK_ID: `TA-006`
- TYPE: `GATE`
- CLUSTER: `ACCESS_MODEL_REWRITE`
- DESCRIPTION: `Validate that access-model tests no longer rely on implicit intro access, membership-only lesson access, duplicate authorities, or step-based ownership logic, and that they enforce canonical enrollment-source and unlock-position rules only.`
- TARGET_FILES:
  - `backend/tests/test_course_access_authority.py`
  - `backend/tests/test_course_visibility_and_media_access.py`
  - `backend/tests/test_courses_public.py`
  - `backend/tests/test_course_read_access_contract.py`
  - `backend/tests/test_rls_course_entitlements.py`
- ACTION: `implement`
- DEPENDS_ON:
  - `TA-005`

