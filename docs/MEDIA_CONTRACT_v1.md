# Media Contract v1 (Content Media)

## 1. Purpose & Scope
- This contract MUST define the canonical content-media model, storage rules, resolver rules, and rendering invariants for course lesson media.
- This contract MUST cover editor media listing, insertion eligibility, and preview safety.
- This contract MUST cover student playback eligibility for published lesson media.
- This contract MUST cover WAV ingestion into an asynchronous pipeline that produces MP3 derivatives for playback.
- This contract MUST cover Supabase Storage as the canonical byte store for content media.
- This contract MUST NOT cover live/session media (SFU rooms, live playback, live recordings) beyond Section 8.
- This contract MUST NOT cover third-party/external media hosting as a primary storage backend.
- This contract MUST NOT define UI layout, styling, or product workflows beyond the safety guarantees in Section 5.

## 2. Canonical Models
### 2.1 Terms
- "Object Storage" MUST mean Supabase Storage.
- "Bucket" MUST mean a Supabase Storage bucket.
- "Object key" MUST mean the object name within a bucket.
- "Storage identity" MUST mean the tuple `(storage_bucket, storage_path)`.

### 2.2 `media_object`
- A `media_object` MUST represent exactly one stored blob in object storage.
- A `media_object` MUST have `id`.
- A `media_object` MUST have `storage_bucket`.
- A `media_object` MUST have `storage_path` as the object key.
- A `media_object` MUST have `content_type`.
- A `media_object` SHOULD have `byte_size`.
- A `media_object` MAY have `checksum`.

### 2.3 `media_derivative`
- A `media_derivative` MUST represent exactly one derived output produced from a source `media_object` or a pipeline asset.
- A `media_derivative` MUST have a `format`.
- A `media_derivative` MUST support `format == mp3` for WAV-derived audio playback.
- A `media_derivative` MUST have `storage_bucket`.
- A `media_derivative` MUST have `storage_path` as the object key.
- A `media_derivative` MUST have `content_type`.
- A `media_derivative` MUST have a `state` that MUST be one of `uploaded`, `processing`, `ready`, `failed`.
- A `media_derivative` MUST be treated as playable only when `state == ready`.

### 2.4 `lesson_media`
- A `lesson_media` item MUST represent one attachment of media to one lesson.
- A `lesson_media` item MUST have `id`.
- A `lesson_media` item MUST have `lesson_id`.
- A `lesson_media` item MUST have `position`.
- A `lesson_media` item MUST have `kind` that MUST be one of `image`, `video`, `audio`, `pdf`, `other`.
- A `lesson_media` item MUST have either:
  - legacy/direct identity via `storage_bucket` + `storage_path`, OR
  - pipeline identity via `media_asset_id` + `media_state`, plus storage identity for the playable object when applicable.
- A `lesson_media` item SHOULD include `original_name`.
- A `lesson_media` item MAY include `content_type`.
- A `lesson_media` item MAY include `ingest_format`.
- A `lesson_media` item MAY include `duration_seconds`.
- A `lesson_media` item MAY include `is_intro`.
- A `lesson_media` item MUST include computed flags:
  - `resolvable_for_editor`
  - `resolvable_for_student`
- A `lesson_media` item MUST include diagnostics fields when not fully healthy:
  - `robustness_status`
  - `robustness_recommended_action`
  - `issue_reason`

### 2.5 Roles and Positions
- The system MUST distinguish at least `editor` and `student` roles for resolvability and authorization.
- `position` MUST be an integer `>= 1`.
- `position` MUST be unique per `lesson_id`.
- Reordering MUST preserve uniqueness and MUST be reflected in subsequent lists.

## 3. Upload & Storage Rules
### 3.1 Allowed Upload Flows
- WAV lesson audio ingestion MUST use an asynchronous pipeline that MUST:
  - MUST accept WAV source bytes.
  - MUST produce an MP3 derivative for playback.
  - MUST expose pipeline state as `media_state`.
  - MUST reach `media_state == ready` before any playback is considered resolvable.
- Non-WAV lesson media (image/video/pdf/other) MAY use a direct-to-storage upload flow.
- Any upload flow that attaches bytes to a lesson MUST create a `lesson_media` item.

### 3.2 Buckets
- The system MUST treat `public-media` as the canonical public bucket.
- The system MUST treat `course-media` as the canonical private/source bucket for lesson content media.
- Objects stored in `public-media` MUST be publicly retrievable without authentication.
- Objects stored outside `public-media` MUST NOT be publicly retrievable without authorization.

### 3.3 `storage_path` (Storage Key) Format
- `storage_path` MUST equal the object key inside `storage_bucket`.
- `storage_path` MUST use `/` separators.
- `storage_path` MUST NOT start with `/`.
- `storage_path` MUST NOT include a bucket prefix.
- `storage_path` MUST match the object name in storage exactly.

### 3.4 Storage Invariants
- For any `lesson_media` with `resolvable_for_* == true`, at least one backend-verified storage candidate MUST exist and MUST yield retrievable bytes.
- Candidate selection MUST be deterministic for a given `lesson_media` snapshot.
- Legacy drift MUST be surfaced via diagnostics and MUST NOT silently degrade to UI playback attempts.

## 4. Resolver & Playback Rules
### 4.1 Supported Kinds
- A `lesson_media.kind` MUST be considered supported only when `kind` MUST be one of `image`, `video`, `audio`, `pdf`.
- A `lesson_media.kind == other` MUST NOT be resolvable for editor or student playback.

### 4.2 Determination of `resolvable_for_editor` and `resolvable_for_student`
- `resolvable_for_editor` MUST be `true` only when the backend can verify supported kind and retrievable bytes, and MUST include `media_state == ready` for pipeline items.
- `resolvable_for_student` MUST be `true` only when the backend can verify supported kind and retrievable bytes, and MUST include `media_state == ready` for pipeline items.
- Resolvable flags MUST be derived from backend-verifiable storage existence rather than frontend heuristics.

### 4.3 Playback URL Sources
- Clients MUST treat `playback_url`, `signed_url`, and `download_url` as opaque.
- The backend MUST provide a playable URL for resolvable media in a permitted context via one of:
  - `playback_url`.
  - `signed_url` + `signed_url_expires_at`.
  - a pipeline playback URL issuance operation for `media_asset_id` when applicable.
- The backend MUST NOT provide `playback_url` for editor listings when preview is blocked.

### 4.4 Legacy Signing and Streaming
- The backend MUST support a signing operation that MAY return `signed_url` and `signed_url_expires_at` for authorized lesson media access.
- The backend MUST support a signed streaming operation that MUST:
  - MUST validate token integrity and expiry.
  - MUST return bytes for valid tokens.
  - MUST support HTTP Range requests for audio/video playback.
- The signing operation MUST enforce course publication and entitlements for student access.
- The signing operation MUST NOT issue signed URLs for unauthorized users.

### 4.5 Pipeline Audio Playback
- Pipeline audio playback MUST use the MP3 derivative as the canonical playable representation.
- Pipeline audio playback URL issuance MUST enforce authorization.
- Pipeline audio playback URL issuance MUST NOT succeed when `media_state != ready`.

### 4.6 Legacy Handling
- Legacy or broken media items MUST remain listable for diagnostics and delete.
- Legacy or broken media items MUST be non-previewable when not resolvable.

## 5. Frontend Rendering Guarantees
### 5.1 Editor Rendering for Blocked Media
- The editor MUST treat a media item as preview-blocked when `preview_blocked == true` OR `resolvable_for_editor == false`.
- The editor MUST NOT attempt playback URL resolution for preview-blocked items.
- The editor MUST NOT initialize any audio controller, video controller, image decode, texture, or WebGL path for preview-blocked items.
- The editor MUST render a static placeholder for preview-blocked items.
- The placeholder MUST surface an issue string derived from `issue_reason` and/or `robustness_status`.
- The editor MUST keep preview-blocked items visible for delete and diagnostics.

### 5.2 Panel Robustness
- A single preview-blocked item MUST NOT disable preview or Insert for other valid media items.
- Insert MUST be disabled when `resolvable_for_editor == false`.
- Insert MUST remain enabled for valid items independent of adjacent broken items.

## 6. Error Handling & Observability
### 6.1 Telemetry
- The backend MUST record a `media_resolution_failures` event when a requested media stream/resolve operation fails to produce bytes.
- Telemetry `mode` MUST be one of `editor_insert`, `editor_preview`, `student_render`.
- Telemetry `reason` MUST be one of `missing_object`, `bucket_mismatch`, `key_format_drift`, `cannot_sign`, `unsupported`.
- Telemetry details MUST include `storage_bucket` and `storage_path`.
- Telemetry details SHOULD include attempted candidate `(bucket, key)` pairs when available.
- Telemetry MUST be best-effort and MUST NOT break media serving when telemetry storage is unavailable.

### 6.2 Invariant Logging
- The backend MUST emit invariant diagnostics when backend-verifiable storage metadata indicates bytes should exist but bytes are not retrievable at stream time.
- Invariant diagnostics SHOULD include candidate pairs and the subset that storage metadata reports as existing.

### 6.3 Surfacing Broken Media
- The backend MUST surface broken media via `robustness_status`, `robustness_recommended_action`, and `issue_reason`.
- The frontend MUST surface broken media as preview-blocked placeholders rather than attempting playback.

## 7. Explicit Invariants
- The backend MUST NOT set `resolvable_for_editor == true` when no storage candidate yields retrievable bytes.
- The backend MUST NOT set `resolvable_for_student == true` when no storage candidate yields retrievable bytes.
- The backend MUST require `media_state == ready` for pipeline-derived playback.
- The backend MUST require supported `kind` for resolvability.
- `storage_path` MUST NOT include a bucket prefix.
- `public-media` objects MUST be public.
- Private-bucket objects MUST NOT be public.
- Editor listings MUST include `preview_blocked` and MUST omit `playback_url` when `preview_blocked == true`.
- The editor MUST NOT initialize any media decode/controller path for preview-blocked items.
- A single broken media item MUST NOT disable Insert for valid items.
- Signed streaming MUST support HTTP Range requests for audio/video playback.

## 8. Future Extensions
- Live/session recordings MUST integrate by producing `media_object` and optional `media_derivative` entities that satisfy the storage invariants in this contract.
- Live/session media MUST remain out of scope for `lesson_media` until a later contract version defines cross-linking.
- Storage providers MAY change without breaking this contract when resolvability semantics, byte retrievability guarantees, and authorization invariants remain satisfied.
- Live/session product behavior MAY change without breaking this contract when content-media fields and invariants in Sections 2-7 remain satisfied.

