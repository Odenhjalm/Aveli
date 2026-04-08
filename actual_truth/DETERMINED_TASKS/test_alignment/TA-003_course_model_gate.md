# TA-003

- TASK_ID: `TA-003`
- TYPE: `GATE`
- CLUSTER: `COURSE_MODEL_REWRITE`
- DESCRIPTION: `Validate that the course-model rewrite cluster no longer references removed course fields or intro-only surfaces and that rewritten tests assert only canonical Newbaseline course truth.`
- TARGET_FILES:
  - `backend/context7/tests/test_tool_call.py`
  - `backend/tests/test_api_smoke.py`
  - `backend/tests/test_course_checkout.py`
  - `backend/tests/test_course_cover_read_contract.py`
  - `backend/tests/test_courses_enroll.py`
  - `backend/tests/test_courses_me.py`
  - `backend/tests/test_courses_public.py`
  - `backend/tests/test_courses_studio.py`
  - `backend/tests/test_home_audio_feed.py`
  - `backend/tests/test_home_audio_opt_in_gate.py`
  - `backend/tests/test_landing_popular_courses_filters_demo.py`
  - `backend/tests/test_wav_upload_concurrency.py`
- ACTION: `implement`
- DEPENDS_ON:
  - `TA-002`

