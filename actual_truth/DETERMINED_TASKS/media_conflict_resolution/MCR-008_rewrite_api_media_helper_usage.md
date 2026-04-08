# MCR-008

- TASK_ID: `MCR-008`
- TYPE: `OWNER`
- CLUSTER: `MEDIA_ASSET_HELPERS_ALIGNMENT`
- DESCRIPTION: `Rewrite backend/app/routes/api_media.py so route logic uses canonical media-asset helper boundaries only and no longer relies on mark_media_asset_ready_passthrough or alternate repository payload semantics.`
- TARGET_FILES:
  - `backend/app/routes/api_media.py`
- ACTION: `rewrite`
- DEPENDS_ON:
  - `MCR-007`

