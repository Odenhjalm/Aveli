# MCR-007

- TASK_ID: `MCR-007`
- TYPE: `OWNER`
- CLUSTER: `MEDIA_ASSET_HELPERS_ALIGNMENT`
- DESCRIPTION: `Implement canonical media-asset helpers in backend/app/repositories/media_assets.py for uploaded-state transition and worker-bound readiness enforcement without direct ready writes or passthrough-ready shortcuts.`
- TARGET_FILES:
  - `backend/app/repositories/media_assets.py`
- ACTION: `implement`
- DEPENDS_ON:
  - `MCR-006`

