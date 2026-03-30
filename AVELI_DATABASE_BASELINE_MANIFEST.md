# AVELI Database Baseline Manifest

This document defines the canonical database baseline for course-level drip configuration and deterministic surface-boundary interpretation.

It exists to keep DB shape deterministic while preventing the database from inventing business behavior.

## 1. Canonical Boundary

- Drip is controlled only by course configuration.
- Enrollment stores state only.
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
- `lesson_media` exists only inside `lesson_content_surface`.
- No independent lesson-media surface exists.
- `media_assets` never defines access.
- No rule referring to visibility may be interpreted as permission for raw table access.
- The database enforces field shape, nullability contracts, and local row invariants.
- The database does not infer business meaning from enrollment source, course type, title, slug, or legacy concepts.
- The database must not introduce fallback logic.

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
| `playback_format` | text | nullable | Canonical worker-assigned playback format |
| `state` | enum | required | Canonical processing state |

Canonical media rules:

- `ingest_format` stores the canonical source format.
- `playback_format` stores the canonical playback format assigned by worker processing.
- Audio rows may become `ready` only when `playback_format = mp3`.

## 3. DB Enforcement Rules

- DB enforces shape only:
  - `drip_enabled = true` -> `drip_interval_days IS NOT NULL`
  - `drip_enabled = false` -> `drip_interval_days IS NULL`
- DB may enforce local field validity such as required storage shape, non-negative stored unlock positions, and `playback_format = mp3` for audio `ready` rows.
- DB access policies must expose `courses` through `course_discovery_surface` without requiring `course_enrollments`, limited to the allowed discovery categories only.
- DB access policies must expose lesson structure through `lesson_structure_surface` without requiring `course_enrollments`, limited to the allowed structure categories only.
- DB access policies must make `lesson_content_surface` accessible only when `course_enrollments` AND `lesson.position <= current_unlock_position`.
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

## 5. Verification Targets

- Drip is controlled only by `courses.drip_enabled` and `courses.drip_interval_days`.
- Enrollment is state-only for drip semantics.
- `course_discovery_surface` remains defined by allowed and forbidden categories without `course_enrollments`.
- `lesson_structure_surface` remains defined by allowed and forbidden categories without `course_enrollments`.
- `lesson_content_surface` requires `course_enrollments` AND `lesson.position <= current_unlock_position`.
- `lessons` remains structure-only and `lesson_contents` remains content-only.
- Discovery and structure surfaces never expose `lesson_content` or `lesson_media`.
- No visibility rule is interpreted as permission for raw table access.
- No source-based drip logic exists in the DB baseline.
- No default drip behavior is hardcoded in the DB baseline.
- UI, backend, and DB can share the same course-configured drip model without fallback logic.
