# 0011E

- TASK_ID: `0011E`
- TYPE: `OWNER`
- TITLE: `Remove profile and community media read surfaces from legacy URL authority`
- PROBLEM_STATEMENT: `Teacher-profile and community media read paths still attach download_url and signed_url inside repositories, absolutize them in routes, and let the frontend choose between those URLs directly.`
- TARGET_STATE:
  - `backend/app/repositories/teacher_profile_media.py`
  - `backend/app/routes/community.py`
  - `backend/app/routes/studio.py`
  - `backend/app/utils/profile_media.py`
  - `frontend/lib/data/models/teacher_profile_media.dart`
  - `frontend/lib/features/community/presentation/teacher_profile_page.dart`
  - profile/community media read surfaces expose backend-authored canonical media objects only
  - repositories do not attach media URLs
  - frontend profile/community rendering does not choose between signed and download URLs
- DEPENDS_ON:
  - `0011A`
- VERIFICATION_METHOD:
  - `rg -n "download_url|signed_url|signed_url_expires_at|absolutize_media_url_items|attach_media_links" backend/app frontend/lib`
  - confirm profile/community read DTOs no longer depend on raw URL pairs
  - confirm route/repository responsibilities match the unified contract

