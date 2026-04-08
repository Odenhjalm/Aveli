## Profile/Community Media Contract Proposal

### Purpose

This document defines the strongest single structured contract candidate that can be derived from the current canonical source set for profile/community media, without implementation and without inventing behavior outside the documents.

### Canonical Scope

The proposal covers only the profile/community media feature domain and its relationship to:

- canonical media identity
- unified `runtime_media`
- backend read composition
- mounted profile/community surfaces

The proposal does not cover:

- memberships
- auth-subject authority
- course purchase authority
- lesson content authority
- storage as a source of truth
- baseline-core ownership of profile/community feature entities

### Canonical Source Entity or Entities

The strongest current canonical candidate is:

- profile/community media must originate from **a separate typed feature-specific authored-placement source model above baseline core**
- that source model must not be embedded into core baseline entities such as `courses`, `lessons`, `course_enrollments`, `media_assets`, or `lesson_media`
- that source model must feed unified `runtime_media` rather than bypass it

Current canonical documents support a **shared contract family** for profile/community media, but they do **not** fully lock:

- the exact source entity name
- the exact number of source entities
- whether profile and community are one physical source model or two closely related source models

### Authored Identity

The strongest current canonical candidate is:

- authored placement identity belongs to the profile/community feature-domain source model
- media identity remains the canonical media identity that flows into `runtime_media`
- frontend identity must never be based on storage paths, signed URLs, metadata blobs, or map-shaped payload truth

Current canonical documents do not fully lock:

- the exact authored owner reference
- the exact source-row identity shape
- the exact publication-state fields for profile/community media placement

### Runtime Truth Model

The runtime truth model is fully canonical in one respect:

- profile/community media, when mounted, must resolve through the unified chain `media_id -> runtime_media -> backend read composition -> API -> frontend`

The source-boundary input that feeds that runtime truth is not yet fully canonical.

### Backend Read Composition Boundary

Backend read composition must be the sole authority for frontend-facing media representation on profile/community surfaces.

That means:

- mounted profile/community endpoints must consume backend-authored media objects
- mounted profile/community endpoints must not expose storage-native fields as truth
- mounted profile/community endpoints must not create a separate profile-media resolver doctrine

### Allowed Purpose Values

The current canonical source set does **not** fully define allowed profile/community-specific `media_purpose` values.

What is currently canonical:

- `course_cover`
- `lesson_media`
- `home_player_audio`

What is **not** currently canonical:

- any dedicated profile/community media purpose value

Therefore, the strongest valid proposal is:

- profile/community media purpose coverage is required by doctrine
- but the exact purpose value or values are not yet fully canonical

### Forbidden Legacy Fields

The following frontend or payload truth shapes are forbidden for canonical profile/community media:

- `cover_image_url`
- `asset_url`
- `storage_path`
- `storage_bucket`
- signed URL truth
- download URL truth
- metadata blobs as truth
- map-based identity
- fallback image fields as authority
- direct storage objects as frontend truth

### Mounted Surface Implications

If profile/community media is mounted on teacher profiles, community cards, seminar/community feeds, or similar read surfaces:

- those surfaces must consume unified `runtime_media` through backend read composition
- those surfaces must not read media truth directly from storage references
- those surfaces must not expose alternative authority paths

### Relationship to Unified `runtime_media`

The relationship is canonical in principle:

- the profile/community source model is the authored-placement authority
- unified `runtime_media` is the runtime truth layer
- backend read composition is the API-facing representation authority

The source model may place media, but it does not replace `runtime_media`.

### Dependency on Baseline

The current canonical documents indicate that profile/community media is **not baseline-core truth** in the current minimal baseline.

Therefore:

- profile/community media requires a separate explicit typed contract above baseline core
- baseline core must not be distorted by embedding profile/community feature truth into core entities
- any future baseline or above-baseline expansion must preserve append-only authority law and unified media doctrine

### Open Questions

These open questions are unavoidable because the current canonical source set does not fully answer them:

1. What is the exact profile/community source entity name or names?
2. Do profile and community share one physical source model or require separate source models?
3. What exact `media_purpose` value or values govern profile/community media?
4. What exact authored owner reference and publication-state fields belong to the source model?
