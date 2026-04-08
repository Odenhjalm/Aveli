# MCR-004

- TASK_ID: `MCR-004`
- TYPE: `OWNER`
- CLUSTER: `RUNTIME_MEDIA_ALIGNMENT`
- DESCRIPTION: `Rewrite backend/app/routes/api_media.py so runtime_media is consumed only as the canonical read-only projection and no code assumes id, home_player_upload_id, active, created_at, or updated_at columns.`
- TARGET_FILES:
  - `backend/app/routes/api_media.py`
- ACTION: `rewrite`
- DEPENDS_ON:
  - `MCR-003`

