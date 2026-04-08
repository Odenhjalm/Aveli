# MCR-012

- TASK_ID: `MCR-012`
- TYPE: `GATE`
- CLUSTER: `HOME_AUDIO_ALIGNMENT`
- DESCRIPTION: `Validate that home audio is composed through control-plane curation plus unified media authority and that no invented runtime_media columns or raw playback payloads leak into the route contract.`
- TARGET_FILES:
  - `backend/app/routes/home.py`
  - `backend/app/services/courses_service.py`
- ACTION: `implement`
- DEPENDS_ON:
  - `MCR-011`

