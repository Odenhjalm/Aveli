# AVELI Database Baseline Manifest

This document defines the canonical database baseline for app-entry authority, course-level drip configuration, and deterministic surface-boundary interpretation.

It exists to keep DB shape deterministic while preventing the database from inventing business behavior.

## 1. Canonical Boundary

- Drip is controlled only by course configuration.
- App entry is controlled only by memberships.
- Subject onboarding and role authority is controlled only by auth_subjects.
- Enrollment stores state only.
- The baseline database is shape-only for canonical core domain truth.
- Canonical data categories are:
  - `course_identity`
  - `course_display`
  - `course_grouping`
  - `course_pricing`
  - `lesson_identity`
  - `lesson_structure`
  - `lesson_content`
  - `lesson_media`
- Category definitions are semantic law, not fixed field lists. Future fields must map into these categories without changing surface rules.
- `course_discovery_surface` allows only `course_identity`, `course_display`, `course_grouping`, and `course_pricing`.
- Forbidden categories must never appear on `course_discovery_surface`: `lesson_content`, `lesson_media`, `enrollment_state`, `unlock_state`.
- `lesson_structure_surface` allows only `lesson_identity` and `lesson_structure`.
- `lesson_structure_surface` maps to `lessons` only.
- Forbidden categories must never appear on `lesson_structure_surface`: `lesson_content`, `lesson_media`, `enrollment_state`, `unlock_state`.
- `lesson_content_surface` allows only `lesson_identity`, `lesson_structure`, `lesson_content`, and `lesson_media`.
- `lesson_content_surface` maps to `lessons` + `lesson_contents` + `lesson_media`.
- `lesson_content_surface` requires `course_enrollments` AND `lesson.position <= current_unlock_position`.
- `course_enrollments` is the only authority for `canonical_protected_course_content_access`.
- For learner/public surfaces, `lesson_media` exists only inside `lesson_content_surface`.
- No independent lesson-media surface exists for learner/public surfaces. Studio has a separate lesson-media edge for authoring and pipeline interaction.
- `media_assets` never defines access.
- No rule referring to visibility may be interpreted as permission for raw table access.
- The database enforces field shape, nullability contracts, and local row invariants.
- The database does not infer business meaning from enrollment source, course type, title, slug, or legacy concepts.
- The database must not introduce fallback logic.
- The database must not hide missing data through defaults, implicit coercion, or inferred values.
- The database baseline does not directly define non-core feature domains such as profile media or studio sessions.
- Non-core features must attach through separate feature-specific schema/contracts above the baseline rather than by mutating core baseline tables.
- Transition-layer behavior is not a database concern and must not be encoded as fallback fields, metadata blobs, or compatibility defaults in the baseline.

## 2. Allowed DB Fields

### `courses`

The canonical `courses` table must allow these drip-configuration fields:

| Field | Type | Constraints | Meaning |
| --- | --- | --- | --- |
| `drip_enabled` | boolean | required | Canonical course-level drip mode |
| `drip_interval_days` | integer | nullable | Canonical course-level drip interval |

Canonical shape rules:

- `drip_enabled = true` -> `drip_interval_days IS NOT NULL`
- `drip_enabled = false` -> `drip_interval_days IS NULL`

### `course_enrollments`

The canonical `course_enrollments` table must allow these stored-state fields:

| Field | Type | Constraints | Meaning |
| --- | --- | --- | --- |
| `drip_started_at` | timestamptz | required stored state | Canonical persisted unlock anchor |
| `current_unlock_position` | integer | required stored state | Canonical persisted highest accessible `lesson.position` |

Canonical storage rules:

- Every enrollment row stores `drip_started_at`.
- Every enrollment row stores `current_unlock_position`.
- Enrollment rows store state regardless of `source`.
- `source` remains access-origin metadata only and must not define drip behavior.

### `memberships`

The canonical `memberships` table must allow these app-entry authority fields:

| Field | Type | Constraints | Meaning |
| --- | --- | --- | --- |
| `membership_id` | uuid | required PK | Stable membership identity |
| `user_id` | uuid | required unique soft reference to `auth.users.id` | Canonical subject binding for app entry |
| `status` | text | required | Canonical app-entry state |
| `end_date` | timestamptz | nullable | Canonical app-entry expiry boundary |
| `created_at` | timestamptz | required | Canonical membership creation timestamp |
| `updated_at` | timestamptz | required | Canonical membership update timestamp |

Canonical membership rules:

- `memberships` is the sole canonical app-entry authority.
- `memberships` is global and must keep one row per `user_id`.
- `user_id` remains a soft reference to `auth.users(id)` and must not gain a database foreign key.
- `memberships` must not store onboarding, role, admin, enrollment, or lesson-content access authority.
- Billing, Stripe, and legacy subscription fields are not part of the baseline-owned canonical `memberships` shape.

### `auth_subjects`

The canonical `auth_subjects` table must allow these subject-authority fields:

| Field | Type | Constraints | Meaning |
| --- | --- | --- | --- |
| `user_id` | uuid | required PK, soft reference to `auth.users.id` | Canonical subject binding above Supabase Auth |
| `onboarding_state` | text | required, allowed values `incomplete` or `completed` | Canonical onboarding authority |
| `role_v2` | text | required, allowed values `learner` or `teacher` | Canonical role authority |
| `role` | text | required, allowed values `learner` or `teacher` | Compatibility role fallback |
| `is_admin` | boolean | required | Canonical admin override authority |

Canonical auth-subject rules:

- `auth_subjects` is the canonical owner of subject onboarding, role, and admin authority.
- `user_id` remains a soft reference to `auth.users(id)` and must not gain a database foreign key.
- `role_v2` owns role truth.
- `role` exists for compatibility only and does not replace `role_v2`.
- `is_admin` is a separate admin override and does not create teacher rights.
- `app.profiles` is not the canonical owner for these authority fields.
- `auth_subjects` must not store membership authority, enrollment authority, or lesson-content access authority.

### `lessons`

The canonical `lessons` table must allow these structure fields:

| Field | Type | Constraints | Meaning |
| --- | --- | --- | --- |
| `id` | uuid | required | Stable lesson identity |
| `course_id` | uuid | required FK to `courses.id` | Parent course |
| `lesson_title` | text | required | Canonical lesson display name |
| `position` | integer | required | Canonical lesson order |

Canonical structure rules:

- `lessons` stores lesson identity and structure only.
- `lessons` must not store canonical lesson body content.

### `lesson_contents`

The canonical `lesson_contents` table must allow these content fields:

| Field | Type | Constraints | Meaning |
| --- | --- | --- | --- |
| `lesson_id` | uuid | required PK, FK to `lessons.id` | Canonical lesson-content owner |
| `content_markdown` | text | required | Canonical lesson body |

Canonical content rules:

- `lesson_contents` is the only canonical holder of lesson body content.
- `lesson_contents` must not duplicate lesson identity or structure fields.

### `media_assets`

The canonical `media_assets` table must allow these media-processing fields:

| Field | Type | Constraints | Meaning |
| --- | --- | --- | --- |
| `id` | uuid | required | Stable media identity |
| `media_type` | enum | required | Canonical media type |
| `purpose` | enum | required | Canonical media purpose |
| `original_object_path` | text | required | Canonical source object path |
| `ingest_format` | text | required | Canonical source format |
| `playback_object_path` | text | nullable | Canonical playback object path |
| `playback_format` | text | nullable | Canonical worker-assigned playback format |
| `state` | enum | required | Canonical processing state |

Canonical media rules:

- `ingest_format` stores the canonical source format.
- `playback_object_path` stores the canonical playback object path assigned during processing.
- `playback_object_path` lifecycle is `NULL` -> set during processing -> immutable.
- `playback_format` stores the canonical playback format assigned by worker processing.
- Audio rows may become `ready` only when `playback_format = mp3`.
- `home_player_audio` is a canonical media purpose value for home-player direct-upload sources that remain in the unified media domain.
- `profile_media` is a canonical media purpose value for profile-media placements that remain in the unified media domain.

### `profile_media_placements`

The canonical `profile_media_placements` feature table must allow these authored-placement fields:

| Field | Type | Constraints | Meaning |
| --- | --- | --- | --- |
| `id` | uuid | required PK | Stable profile-media placement identity |
| `subject_user_id` | uuid | required soft subject reference | Canonical profile-media subject binding |
| `media_asset_id` | uuid | required FK to `media_assets.id` | Canonical media identity pointer |
| `visibility` | text | required, allowed values `draft` or `published`, no implicit default | Canonical publication state |

Canonical profile-media rules:

- `profile_media_placements` is the only canonical authored-placement source entity for the profile-media feature domain.
- `subject_user_id` remains a soft external subject reference and must not gain a database foreign key to `auth.users`.
- `auth_subjects` does not own profile-media feature authority.
- only `published` profile-media placements may feed `runtime_media`.
- no separate `community_media` purpose value exists in the current canonical baseline scope.
- community surfaces consume the same source model through backend read composition rather than a separate source-truth domain.

### `runtime_media` projection

The canonical `runtime_media` projection is the runtime truth layer.

runtime_media is not the final frontend representation.
The backend read composition layer constructs the frontend-facing media object.

The canonical `runtime_media` projection must:

- include `playback_object_path`
- include `playback_format`
- express runtime truth without joining `media_assets` for frontend representation
- project direct-upload home-player runtime rows only from explicit `home_player_uploads.active = true` source truth linked to canonical `home_player_audio` assets
- project profile-media runtime rows only from explicit `profile_media_placements.visibility = published` source truth linked to canonical `profile_media` assets

## 3. DB Enforcement Rules

- DB enforces shape only:
  - `drip_enabled = true` -> `drip_interval_days IS NOT NULL`
  - `drip_enabled = false` -> `drip_interval_days IS NULL`
- DB may enforce local field validity such as required storage shape, non-negative stored unlock positions, and `playback_format = mp3` for audio `ready` rows.
- DB access policies must expose `courses` through `course_discovery_surface` without requiring `course_enrollments`, limited to the allowed discovery categories only.
- DB access policies must expose lesson structure through `lesson_structure_surface` without requiring `course_enrollments`, limited to the allowed structure categories only.
- DB access policies must make `lesson_content_surface` accessible only when `course_enrollments` AND `lesson.position <= current_unlock_position`.
- DB must keep `memberships.user_id` as a soft external reference without a database foreign key to `auth.users`.
- DB must keep `auth_subjects.user_id` as a soft external reference without a database foreign key to `auth.users`.
- DB must not expose forbidden categories through `course_discovery_surface` or `lesson_structure_surface`.
- `app.lessons` must remain structure-only and `app.lesson_contents` must remain content-only.
- `app.lessons` and `app.lesson_contents` must not be collapsed into one raw-table lesson access surface that bypasses canonical surface boundaries.
- No rule referring to visibility may be interpreted as permission for raw table access.
- DB must not infer drip behavior.
- DB must not infer unlock behavior from `intro_enrollment` vs `purchase`.
- DB must not enforce progression correctness across tables.
- DB must not derive `current_unlock_position` from `lessons.position`.
- DB must not decide whether all lessons are unlocked. That is application and worker logic using canonical course configuration.

## 4. Forbidden DB Behavior

The database baseline must explicitly forbid:

- tying drip logic to `intro_enrollment` vs `purchase`
- hardcoded drip defaults
- fallback drip behavior
- duplicate app-entry authorities parallel to `memberships`
- reusing `app.profiles` as canonical onboarding, role, or admin authority
- duplicate auth-subject authorities parallel to `auth_subjects`
- database foreign keys from baseline-owned tables to external auth subjects
- implicit unlock strategies
- treating `course_discovery_surface` as enrollment-gated
- hiding course catalog behind enrollment
- treating `lesson_structure_surface` as `lesson_content_surface`
- conflating `course_discovery_surface` or `lesson_structure_surface` with `lesson_content_surface`
- exposing `lesson_content` or `lesson_media` in discovery or structure surfaces
- storing canonical lesson body content on `app.lessons`
- using `app.lessons` or a collapsed `app.lessons` + `app.lesson_contents` raw-table surface to bypass the canonical lesson split
- inferred drip behavior from course type
- inferred drip behavior from course step
- inferred drip behavior from title or slug
- cross-table progression enforcement that attempts to replace canonical application or worker logic
- metadata blobs as contract truth
- default values that hide missing required data
- implicit coercion that converts invalid shapes into accepted state
- map-like compatibility contracts in baseline-owned schema

## 5. Verification Targets

- Drip is controlled only by `courses.drip_enabled` and `courses.drip_interval_days`.
- Enrollment is state-only for drip semantics.
- App entry is canonical only through `memberships`.
- Subject onboarding, role, and admin authority are canonical only through `auth_subjects`.
- The database baseline remains shape-only and does not invent feature behavior.
- `memberships` keeps exactly one global app-entry row per `user_id` without an `auth.users` foreign key.
- `auth_subjects` keeps exactly one subject-authority row per `user_id` without an `auth.users` foreign key.
- `course_discovery_surface` remains defined by allowed and forbidden categories without `course_enrollments`.
- `lesson_structure_surface` remains defined by allowed and forbidden categories without `course_enrollments`.
- `lesson_content_surface` requires `course_enrollments` AND `lesson.position <= current_unlock_position`.
- `lessons` remains structure-only and `lesson_contents` remains content-only.
- Discovery and structure surfaces never expose `lesson_content` or `lesson_media`.
- No visibility rule is interpreted as permission for raw table access.
- No source-based drip logic exists in the DB baseline.
- No default drip behavior is hardcoded in the DB baseline.
- No non-core feature contract is smuggled into core baseline tables.
- No metadata blob, map-style contract, or compatibility default is used as baseline truth.
- `runtime_media` contains `playback_object_path` and `playback_format`, and acts as the runtime truth layer rather than the frontend representation layer.
- UI, backend, and DB can share the same course-configured drip model without fallback logic.
