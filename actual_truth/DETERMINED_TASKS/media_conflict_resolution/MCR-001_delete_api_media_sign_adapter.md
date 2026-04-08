# MCR-001

- TASK_ID: `MCR-001`
- TYPE: `OWNER`
- CLUSTER: `DELETE_LEGACY_MEDIA_PATHS`
- DESCRIPTION: `Delete the /api/media/sign adapter so backend/app/routes/api_media.py no longer forwards signing requests into the removed legacy media route surface.`
- TARGET_FILES:
  - `backend/app/routes/api_media.py`
- ACTION: `delete`
- DEPENDS_ON: `[]`

