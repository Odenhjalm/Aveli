# RCD-002_MEDIA_WRITE_AUTHORITY_DECISION

- TYPE: `authority-doc`
- TITLE: `Decide and document one canonical lesson-media write surface`
- DOMAIN: `media upload/write authority`

## Problem Statement

Primary media contracts define canonical media shape and the unified authority chain, but they do not currently define one exact active lesson-media write surface. The repo contains one mounted working lesson-media upload flow under `lesson_media_router`, plus multiple legacy or disabled studio lesson-media write surfaces. This leaves media write authority ambiguous.

## Primary Authority Reference

- `actual_truth/contracts/lesson_media_edge_contract.md`
- `actual_truth/contracts/media_unified_authority_contract.md`
- `actual_truth/system_runtime_rules.md`

## Implementation Surfaces Affected

- `actual_truth/contracts/lesson_media_edge_contract.md`
- `backend/app/routes/studio.py`
- `backend/app/routes/upload.py`
- `backend/app/routes/api_media.py`

## DEPENDS_ON

- `RCD-001_RUNTIME_ROUTE_AUTHORITY_SYNC`

## Acceptance Criteria

- One lesson-media write surface is declared as canonical in primary contract documentation.
- Every other lesson-media write surface is explicitly classified as one of:
  - legacy disabled
  - inert inventory
  - helper-only implementation support
- The chosen write surface is consistent with the unified media authority chain.
- No primary contract leaves media write authority ambiguous.

## Stop Conditions

- Stop if mounted runtime truth still cannot determine which lesson-media write surface is active and non-disabled.
- Stop if the chosen write surface would require inventing a route or behavior not present in repo evidence.

## Out Of Scope

- Any route implementation change
- Any client update
- Any upload execution or test
