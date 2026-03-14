# Media Control Plane

This package is the isolated backend workspace for the future Aveli Media
Control Plane.

Its purpose is to give the repository a clear implementation boundary for the
next phase of media work without changing the current media runtime contract.

The Media Control Plane is intended to formalize the relationship between the
existing media layers:

- `lesson_media`: authored identity and lesson-facing reference surface.
- `media_assets`: byte identity, processing state, and canonical asset record.
- `media_objects`: legacy compatibility layer that still appears in the current
  media pipeline and must be understood during migration.
- `storage.objects`: object existence layer and the final source of truth for
  whether a referenced file is physically present in storage.

The intended contract for the control plane is:

- `lesson_media.id` = authored identity
- `media_assets` = byte identity
- storage = object existence layer

The current-state analysis that motivates this workspace lives in:

- `docs/media_control_plane/media_pipeline_audit_2026-03-14.md`

This directory currently contains scaffolding only. No runtime media resolution,
contract enforcement, migrations, or repair logic lives here yet.
