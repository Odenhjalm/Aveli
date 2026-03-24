# media_control_plane — planned vs implemented

## planned sources
- media_control_plane_phase2_design.md
- docs/media_control_plane/media_control_plane_plan.md
- docs/media_control_plane/media_pipeline_audit_2026-03-14.md
- homeplayer_audit_for_media_control_plane.md

## implemented sources
- backend/app/media_control_plane/routes/media_admin_router.py
- backend/app/media_control_plane/services/media_resolver_service.py
- backend/app/media_control_plane/README.md
- backend/app/media_control_plane/diagnostics/media_doctor.py
- backend/app/services/lesson_playback_service.py
- backend/tests/test_media_control_plane_resolver.py
- backend/tests/test_media_control_plane_observability.py

## gaps
- The phase-2 design docs describe broader control-plane convergence than what is currently represented in active runtime route and service logic.
- Several runtime files still read as scaffolding/partial implementations.
- Frontend-facing canonical media contract behavior is mostly inferable from audits and tests rather than a single explicit implemented API contract.

## contradictions
- Documentation presents a target architecture with strict cross-surface semantics, while runtime evidence shows smaller active coverage and fewer explicit public API paths.
