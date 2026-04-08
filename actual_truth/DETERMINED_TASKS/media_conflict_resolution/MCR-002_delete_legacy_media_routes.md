# MCR-002

- TASK_ID: `MCR-002`
- TYPE: `OWNER`
- CLUSTER: `DELETE_LEGACY_MEDIA_PATHS`
- DESCRIPTION: `Delete the legacy media router surfaces /media/sign and /media/stream/{token} from backend/app/routes/media.py so no tokenized sign or stream bypass remains.`
- TARGET_FILES:
  - `backend/app/routes/media.py`
- ACTION: `delete`
- DEPENDS_ON:
  - `MCR-001`

