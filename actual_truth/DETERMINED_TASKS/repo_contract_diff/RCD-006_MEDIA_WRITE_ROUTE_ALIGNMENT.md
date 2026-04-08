# RCD-006_MEDIA_WRITE_ROUTE_ALIGNMENT

- TYPE: `route-runtime`
- TITLE: `Reduce lesson-media writes to one mounted canonical route surface`
- DOMAIN: `media upload/write authority`

## Problem Statement

The mounted runtime currently exposes one working lesson-media upload flow under `lesson_media_router`, while `studio.router` still exposes active but hard-disabled legacy lesson-media write endpoints. Unmounted route modules also contain additional upload/write flows. The repo needs one mounted canonical lesson-media write path and explicit isolation of the others.

## Primary Authority Reference

- `actual_truth/contracts/lesson_media_edge_contract.md`
- `actual_truth/contracts/media_unified_authority_contract.md`
- `actual_truth/system_runtime_rules.md`

## Implementation Surfaces Affected

- `backend/app/routes/studio.py`
- `backend/app/main.py`
- `backend/app/routes/upload.py`
- `backend/app/routes/api_media.py`

## DEPENDS_ON

- `RCD-001_RUNTIME_ROUTE_AUTHORITY_SYNC`
- `RCD-002_MEDIA_WRITE_AUTHORITY_DECISION`

## Acceptance Criteria

- Exactly one mounted lesson-media write flow remains canonical.
- Active but disabled legacy lesson-media endpoints are either removed from mounted runtime or explicitly isolated as non-canonical.
- No active lesson-media write path bypasses canonical `media_assets` and `lesson_media` mutation boundaries.
- Unmounted write modules remain non-authoritative inventory only.

## Stop Conditions

- Stop if more than one mounted lesson-media write surface remains behaviorally active after alignment.
- Stop if the chosen canonical write surface cannot represent all governed lesson-media types without fallback.

## Out Of Scope

- Frontend client rewiring
- Media worker processing changes
- Media read composition changes
