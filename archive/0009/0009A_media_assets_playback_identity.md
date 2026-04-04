# 0009A

STATUS: DEPRECATED (LEGACY MODEL)

- TASK_ID: `0009A`
- TYPE: `OWNER`
- TITLE: `Historical media_assets public-identity step`
- PURPOSE: `Historical task record from a narrow-scope media era. It must not be used as current doctrine because app.media_assets is media identity, not frontend representation authority.`
- HISTORICAL_SCOPE:
  - `backend/supabase/baseline_slots/0007_media_assets_core.sql`
  - `backend/supabase/baseline_slots/0010_worker_query_support.sql`
  - `backend/app/repositories/media_assets.py`
- DEPENDS_ON:
  - none
- REPLACED_BY:
  - `actual_truth/contracts/media_unified_authority_contract.md`
  - `actual_truth/NEW_BASELINE_DESIGN_PLAN.md`
- CURRENT_LAW:
  - `app.media_assets` is media identity.
  - `app.lesson_media` is authored placement.
  - `app.runtime_media` is runtime truth.
  - frontend representation belongs only to backend read composition.

runtime_media provides canonical runtime truth.
The backend read composition layer is the sole authority for media representation to frontend.
Frontend must render only and must not resolve or construct media.

- VALIDATION:
  - treat this file as historical lineage only
  - do not use this task as active media doctrine
  - EXECUTION_STATUS: `COMPLETE (HISTORICAL)`
