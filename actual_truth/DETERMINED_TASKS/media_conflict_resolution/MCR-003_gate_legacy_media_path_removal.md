# MCR-003

- TASK_ID: `MCR-003`
- TYPE: `GATE`
- CLUSTER: `DELETE_LEGACY_MEDIA_PATHS`
- DESCRIPTION: `Validate that backend/app/routes/api_media.py and backend/app/routes/media.py no longer expose /api/media/sign, /media/sign, or /media/stream/{token}.`
- TARGET_FILES:
  - `backend/app/routes/api_media.py`
  - `backend/app/routes/media.py`
- ACTION: `implement`
- DEPENDS_ON:
  - `MCR-002`

