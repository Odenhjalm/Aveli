# TA-009

- TASK_ID: `TA-009`
- TYPE: `OWNER`
- CLUSTER: `AUTH_FIX`
- DESCRIPTION: `Implement auth and email-flow fixes so canonical register, verify-email, invite-validation, and reset-password surfaces satisfy runtime expectations without introducing legacy auth paths.`
- TARGET_FILES:
  - `backend/app/main.py`
  - `backend/app/routes/auth.py`
  - `backend/app/routes/email_verification.py`
  - `backend/app/services/email_verification.py`
- ACTION: `implement`
- DEPENDS_ON: `[]`

