# MCR-006

- TASK_ID: `MCR-006`
- TYPE: `GATE`
- CLUSTER: `RUNTIME_MEDIA_ALIGNMENT`
- DESCRIPTION: `Validate that api_media and courses_service consume runtime_media only through canonical projection columns and no mutable-table assumptions remain.`
- TARGET_FILES:
  - `backend/app/routes/api_media.py`
  - `backend/app/services/courses_service.py`
- ACTION: `implement`
- DEPENDS_ON:
  - `MCR-005`

