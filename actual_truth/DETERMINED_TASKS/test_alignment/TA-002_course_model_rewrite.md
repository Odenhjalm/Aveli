# TA-002

- TASK_ID: `TA-002`
- TYPE: `GATE`
- CLUSTER: `COURSE_MODEL_REWRITE`
- DESCRIPTION: `Rewrite remaining legacy course tests to canonical `course.step`, `course_group_id`, `price_amount_cents`, `drip_enabled`, and `drip_interval_days` truth, and remove `is_free_intro`, `step_level`, `course_family`, `price_cents`, and `free_intro` assumptions.`
- TARGET_FILES:
  - `backend/tests/test_api_smoke.py`
  - `backend/tests/test_course_checkout.py`
  - `backend/tests/test_courses_enroll.py`
  - `backend/tests/test_courses_me.py`
  - `backend/tests/test_courses_public.py`
  - `backend/tests/test_courses_studio.py`
  - `backend/tests/test_home_audio_feed.py`
  - `backend/tests/test_home_audio_opt_in_gate.py`
  - `backend/tests/test_landing_popular_courses_filters_demo.py`
  - `backend/tests/test_wav_upload_concurrency.py`
- ACTION: `rewrite`
- DEPENDS_ON:
  - `TA-001`

