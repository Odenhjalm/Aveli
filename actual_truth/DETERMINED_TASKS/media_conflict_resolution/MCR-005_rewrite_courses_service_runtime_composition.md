# MCR-005

- TASK_ID: `MCR-005`
- TYPE: `OWNER`
- CLUSTER: `RUNTIME_MEDIA_ALIGNMENT`
- DESCRIPTION: `Rewrite backend/app/services/courses_service.py so backend read composition uses canonical runtime_media projection truth and does not emit storage-derived or raw playback payload doctrine.`
- TARGET_FILES:
  - `backend/app/services/courses_service.py`
- ACTION: `rewrite`
- DEPENDS_ON:
  - `MCR-004`

