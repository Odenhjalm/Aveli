# TA-004

- TASK_ID: `TA-004`
- TYPE: `GATE`
- CLUSTER: `ACCESS_MODEL_REWRITE`
- DESCRIPTION: `Delete tests that enforce forbidden duplicate course-content authorities or forbidden step-based ownership shortcuts with no canonical replacement.`
- TARGET_FILES:
  - `backend/tests/test_course_read_access_contract.py`
  - `backend/tests/test_rls_course_entitlements.py`
- ACTION: `delete`
- DEPENDS_ON:
  - `TA-003`

