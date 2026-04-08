# BCP-035

- TASK_ID: `BCP-035`
- TYPE: `GATE`
- TITLE: `Verify the protected lesson-content DB surface`
- PROBLEM_STATEMENT: `The protected lesson-content surface is invalid if any user can reach lesson content or lesson media without canonical enrollment and unlock truth, or if membership can still substitute for learner-content access.`
- IMPLEMENTATION_SURFACES:
  - `backend/tests/`
  - append-only protected surface slots created by `BCP-034`
  - `backend/app/routes/courses.py`
- TARGET_STATE:
  - verification fails when protected lesson content is read without `course_enrollments`
  - verification fails when protected lesson content is read beyond `current_unlock_position`
  - verification fails when membership or visibility semantics attempt to substitute for learner-content access
- DEPENDS_ON:
  - `BCP-034`
- VERIFICATION_METHOD:
  - add focused DB and backend tests for enrollment and unlock boundaries
  - confirm protected lesson media remains inside protected lesson-content only
  - confirm grep checks show no membership-only or raw-table bypass path
