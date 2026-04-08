# RCD-007_MEDIA_READ_COMPOSITION_ALIGNMENT

- TYPE: `runtime`
- TITLE: `Align learner and studio media reads to the unified backend composition chain`
- DOMAIN: `media render/read authority`

## Problem Statement

The unified media contract requires `media_id -> runtime_media -> backend read composition -> API -> frontend`, but repo read paths still expose legacy preview fields and direct storage-derived cover resolution. Course cover reads currently use `media_assets` plus direct public URLs, and studio lesson-media reads still expose `preview_ready`, `original_name`, and preview-specific payloads alongside the canonical `media` object.

## Primary Authority Reference

- `actual_truth/contracts/media_unified_authority_contract.md`
- `actual_truth/contracts/lesson_media_edge_contract.md`
- `AVELI_DATABASE_BASELINE_MANIFEST.md`

## Implementation Surfaces Affected

- `backend/app/services/courses_service.py`
- `backend/app/repositories/courses.py`
- `backend/app/services/lesson_playback_service.py`
- `backend/app/repositories/runtime_media.py`
- `backend/app/routes/studio.py`

## DEPENDS_ON

- `RCD-002_MEDIA_WRITE_AUTHORITY_DECISION`
- `RCD-006_MEDIA_WRITE_ROUTE_ALIGNMENT`

## Acceptance Criteria

- Learner and studio media payloads are emitted through canonical backend composition.
- Course cover reads no longer bypass canonical media authority with direct storage-derived public URLs.
- Legacy preview fields are removed or explicitly demoted from contract truth.
- `runtime_media` remains read-only runtime truth instead of becoming a second frontend contract.

## Stop Conditions

- Stop if any governed media surface still depends on direct storage identity as frontend truth.
- Stop if cover, lesson, or studio media require separate resolver doctrines after alignment.

## Out Of Scope

- Worker execution changes
- Upload route selection
- Control-plane redesign
