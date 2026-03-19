# Media Control Plane

This workspace now documents the backend-authoritative lesson media contract
used by Studio authoring, editor preview, and runtime playback.

## Canonical model

- `lesson_media.id` is the only authored lesson-media identity.
- `runtime_media` is the delivery and authorization read model.
- `media_assets` owns bytes, lifecycle, ingest, and derivatives.
- `storage.objects` is the physical existence source of truth.
- `media_objects` remains a temporary legacy read-compatibility layer only.
- `course-media` is the canonical private bucket.
- `public-media` is reserved for explicitly public assets and derivatives.
- `lesson_media.storage_path` stores object keys only.
  Bucket prefixes inside `storage_path` are invalid.

## Authoring contract

- New lesson content writes must persist typed refs only:
  - `!image(<lesson_media_id>)`
  - `!audio(<lesson_media_id>)`
  - `!video(<lesson_media_id>)`
- Backend lesson writes normalize supported legacy image/audio/video refs to
  typed lesson-media ids and reject unresolved raw media refs.
- Upload completion must return the canonical `lesson_media` row needed by the
  UI immediately. The client must not reconcile by filename, recency, or local
  path guesses.
- Editor-facing lesson media responses must provide backend-issued, absolute,
  already-authorized URLs. Frontends must not construct storage paths, buckets,
  or `/api/files/{bucket}/{path}` URLs.

## Audited write surfaces

- Lesson create/update: `backend/app/routes/studio.py` ->
  `backend/app/services/courses_service.py`
- Lesson audio upload completion: `backend/app/routes/api_media.py`
- Direct lesson media completion: `backend/app/routes/studio.py`
- Lesson image upload compatibility path: `backend/app/routes/upload.py`
- Frontend authoring serializer: `frontend/lib/editor/adapter/editor_to_markdown.dart`
- Frontend Studio upload flow: `frontend/lib/features/studio/data/studio_repository.dart`

Inactive but still dangerous if revived:

- `frontend/lib/features/editor/widgets/media_toolbar.dart`
  still contains raw HTML media insertion and should be removed once the
  migration is fully settled.

## Temporary legacy bridges

- `media_objects` still backs legacy reads while runtime-media migration and
  storage backfill telemetry remain in place.
- Legacy `/studio/media/{id}`, `/media/stream/{token}`, and `/api/files/...`
  references are normalized on import/write for supported image/audio/video
  cases, but must not be persisted by new writes.
- PDF/document markdown links remain a temporary exception because this
  migration does not introduce a new document token type.

## Follow-up removals after telemetry/backfill

- Remove `media_objects` and legacy storage fallback from resolver paths once
  runtime-media coverage is complete.
- Delete dormant raw-HTML insertion code in
  `frontend/lib/features/editor/widgets/media_toolbar.dart`.
- Remove remaining legacy document-link write behavior once a canonical
  document ref type is introduced.

## Related context

- `docs/media_control_plane/media_pipeline_audit_2026-03-14.md`
