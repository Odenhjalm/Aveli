# 0009B

STATUS: DEPRECATED (LEGACY MODEL)

- TASK_ID: `0009B`
- TYPE: `OWNER`
- TITLE: `Historical runtime_media projection step`
- PURPOSE: `Historical task record from a narrow-scope media era. It must not be used as current doctrine because runtime_media is runtime truth for all governed media surfaces and is not the final frontend representation.`
- HISTORICAL_SCOPE:
  - `backend/supabase/baseline_slots/0008_runtime_media_projection_core.sql`
  - `backend/supabase/baseline_slots/0009_runtime_media_projection_sync.sql`
  - `backend/app/repositories/runtime_media.py`
- DEPENDS_ON:
  - `0009A`
- REPLACED_BY:
  - `actual_truth/contracts/media_unified_authority_contract.md`
  - `actual_truth/NEW_BASELINE_DESIGN_PLAN.md`
- CURRENT_LAW:
  - runtime truth belongs to `app.runtime_media`
  - frontend representation belongs to backend read composition
  - one chain serves cover, lesson, home, and profile/community surfaces

runtime_media provides canonical runtime truth.
The backend read composition layer is the sole authority for media representation to frontend.
Frontend must render only and must not resolve or construct media.

- VALIDATION:
  - treat this file as historical lineage only
  - do not use this task as active runtime-media doctrine
  - EXECUTION_STATUS: `COMPLETE (HISTORICAL)`
