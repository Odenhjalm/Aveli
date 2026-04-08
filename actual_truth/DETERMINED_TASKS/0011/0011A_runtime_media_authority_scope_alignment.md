# 0011A

- TASK_ID: `0011A`
- TYPE: `OWNER`
- TITLE: `Align runtime_media authority scope with MEDIA_UNIFIED_AUTHORITY contract`
- PROBLEM_STATEMENT: `The canonical contract requires governed media surfaces to resolve through runtime_media, but the current canonical projection only materializes ready lesson_media rows and the mounted runtime still contains callers that assume cover and home-player runtime participation without a matching projection owner.`
- TARGET_STATE:
  - `actual_truth/contracts/media_unified_authority_contract.md`
  - `backend/supabase/newbaseline_slots/runtime_media_projection_core.sql`
  - `backend/app/repositories/runtime_media.py`
  - `backend/app/media_control_plane/services/media_resolver_service.py`
  - mounted callers define one identical authority scope for `app.runtime_media`
  - every governed media usage either has an explicit runtime_media projection owner or is explicitly excluded from runtime_media with a canonical reason
  - no caller expects cover or home-player runtime rows unless the projection actually defines them
- DEPENDS_ON:
  - `0011A-0`
- VERIFICATION_METHOD:
  - `rg -n "runtime_media|home_player_upload_id|cover_media_id" actual_truth/contracts backend/supabase/newbaseline_slots backend/app/repositories/runtime_media.py backend/app/media_control_plane/services/media_resolver_service.py`
  - confirm runtime_media projection shape, repository API, resolver API, and contract scope all match exactly
  - confirm no mounted caller depends on nonexistent runtime rows
