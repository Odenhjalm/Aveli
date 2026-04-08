# TA-010

- TASK_ID: `TA-010`
- TYPE: `GATE`
- CLUSTER: `AUTH_FIX`
- DESCRIPTION: `Validate the auth cluster against canonical register, verification, invite, and reset-password expectations after auth fixes land.`
- TARGET_FILES:
  - `backend/tests/test_auth_email_flows.py`
  - `test_email_verification.py`
- ACTION: `implement`
- DEPENDS_ON:
  - `TA-009`

