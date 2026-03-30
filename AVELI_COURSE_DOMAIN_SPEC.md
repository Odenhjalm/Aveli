# AVELI Course Domain Spec

This document defines the forward-only canonical domain for courses, lessons, and media in Aveli.

It is intentionally independent from historical behavior, compatibility fallbacks, and inferred semantics.

## 1. Core Principles

1. Single source of truth.
   Every business decision must come from stored canonical fields, not from titles, slugs, or hidden compatibility logic.
2. No derived business logic from presentation fields.
   Titles and slugs are identifiers and display values only. They never define progression, grouping, access, or pricing.
3. No fallback logic.
   Missing canonical data is an error. The system must fail explicitly instead of guessing.
4. No duplicated semantics.
   One concept must have one authoritative field.
5. All business semantics are explicit in stored data.
   If the product depends on a value, that value must exist as stored canonical truth.
6. Expansion Principle.
   New features must attach to the system via new canonical entities.
   Core domain entities (`courses`, `lessons`, `lesson_contents`, `course_enrollments`, `media_assets`, `lesson_media`) must not be mutated to support new features.
   Feature-specific data must be modeled in separate domain entities.
   No feature may introduce new fields into core domain entities unless the change is a canonical domain evolution.

## 2. Course Model (Canonical)

Canonical course fields:

| Field | Type | Constraints | Meaning |
| --- | --- | --- | --- |
| `id` | UUID | required | Stable course identity |
| `title` | text | required | Display course title |
| `slug` | text | required, unique | Stable machine identifier with no business meaning |
| `course_group_id` | UUID | required | Canonical explicit grouping identity |
| `step` | enum | required: `intro | step1 | step2 | step3` | The only source of course progression semantics |
| `price_amount_cents` | integer | nullable | Canonical price in cents |
| `drip_enabled` | boolean | required | Canonical course-level drip mode |
| `drip_interval_days` | integer | nullable | Canonical course-level drip interval |
| `cover_media_id` | UUID | nullable FK to `media_assets.id` | Canonical cover linkage |

Canonical rules:

- `step` is the only source of course progression.
- `course_group_id` is the only source of course grouping.
- Drip behavior is defined only by course configuration.
- `intro` means `step == intro`.
- `paid` means `step != intro`.
- `price_amount_cents` must be `NULL` when `step == intro`.
- `price_amount_cents` must be non-null and greater than `0` when `step` is `step1`, `step2`, or `step3`.
- `drip_enabled = true` means the course uses drip progression.
- `drip_enabled = false` means the course unlocks all lessons immediately.
- `drip_interval_days` must be defined when `drip_enabled = true`.
- `drip_interval_days` must be `NULL` when `drip_enabled = false`.
- `cover_media_id`, when present, must reference a `media_assets` row with `purpose = course_cover`.
- UI layout and progression linking between related courses must use `course_group_id`.
- Courses that belong to the same product progression must share the same `course_group_id`.
- Course type, enrollment source, title, and slug never define drip behavior.
- `slug` is never parsed for grouping, progression, pricing, or access.
- `title` is never parsed for grouping, progression, pricing, or access.

## 3. Forbidden Concepts

The following concepts are removed from the canonical course domain and must not exist in schema, API contracts, UI contracts, or runtime logic:

- `step_level`
- `course_family`
- slug-based grouping
- title-based grouping
- any fallback grouping logic
- `price_cents`
- `journey_step ?? step_level`
- `is_free_intro`
- implicit intro access
- entitlement fallback paths
- step-based ownership logic
- any title parsing logic
- any slug parsing logic
- any fallback from missing `step`
- any implicit entitlement rules
- any runtime-derived progression state
- any runtime-derived unlock state
- treating `course_discovery_surface` as enrollment-gated
- hiding course catalog behind enrollment
- treating `lesson_structure_surface` as `lesson_content_surface`
- conflating `course_discovery_surface` or `lesson_structure_surface` with `lesson_content_surface`
- drip tied to `intro_enrollment` vs `purchase`
- hardcoded drip defaults
- fallback drip behavior
- implicit unlock strategies

## 4. Lesson Model

Canonical `lessons` fields:

| Field | Type | Constraints | Meaning |
| --- | --- | --- | --- |
| `id` | UUID | required | Stable lesson identity |
| `course_id` | UUID | required FK to `courses.id` | Parent course |
| `lesson_title` | text | required | Canonical lesson display name |
| `position` | integer | required, unique per course, strict `1..N` | Canonical lesson order |

Canonical rules:

- Lessons belong directly to a course.
- `lesson_title` is the only display name for lessons.
- `position` is the only source of lesson ordering.
- Positions must be continuous within each course: `1, 2, 3, ... N`.
- Lessons are valid without media.
- Lesson validity does not depend on audio, video, image, or document attachments.
- No lesson grouping layer exists between course and lesson.
- `lesson_title` is never inferred from content, file path, or position.
- `lessons` stores lesson identity and structure only.
- `lessons` must never store canonical lesson body content.

Canonical `lesson_contents` fields:

| Field | Type | Constraints | Meaning |
| --- | --- | --- | --- |
| `lesson_id` | UUID | required PK, FK to `lessons.id` | Canonical lesson-content owner |
| `content_markdown` | text | required | Canonical lesson body |

Canonical lesson-content rules:

- `lesson_contents` stores lesson body content only.
- Every canonical lesson body must exist in exactly one `lesson_contents` row.
- `lesson_contents` must not duplicate lesson identity or structural ordering fields.
- `content_markdown` is canonical only on `lesson_contents`.

## 5. Media Model

Canonical `media_assets` fields:

| Field | Type | Constraints | Meaning |
| --- | --- | --- | --- |
| `id` | UUID | required | Stable media identity |
| `media_type` | enum | required: `audio | image | video | document` | Canonical media type |
| `purpose` | enum | required: `course_cover | lesson_media` | Canonical business purpose |
| `original_object_path` | text | required | Canonical source object path |
| `ingest_format` | text | required | Canonical source format |
| `playback_format` | text | nullable | Canonical worker-assigned playback format |
| `state` | enum | required: `pending_upload | uploaded | processing | ready | failed` | Canonical processing state |

Canonical `lesson_media` fields:

| Field | Type | Constraints | Meaning |
| --- | --- | --- | --- |
| `id` | UUID | required | Stable lesson-media identity |
| `lesson_id` | UUID | required FK to `lessons.id` | Parent lesson |
| `media_asset_id` | UUID | required FK to `media_assets.id` | Attached media asset |
| `position` | integer | required, unique per lesson | Canonical media order inside the lesson |

Canonical rules:

- `lesson_media.position` is materialized at write time and then stored explicitly.
- Insertion order means the writer assigns the next integer position before commit.
- After persistence, `position` is the only source of media ordering.
- `runtime_media` is projection only.
- No migration or application path may write directly to `runtime_media`.
- Lesson content must resolve media through canonical lesson-media linkage, not through path parsing.
- `media_assets.purpose = lesson_media` is used for all lesson attachments, including audio.
- Audio behavior is determined by `media_type`, not by a separate lesson-audio semantic field.

## 6. Media Processing Contract

Canonical processing rules:

- WAV input must be converted to MP3 before the asset is considered playback-ready.
- All audio must reach `state = ready` before playback is valid.
- `ready` means the media has completed all required processing for its `media_type` and `purpose`.
- Audio `ready` requires `media_assets.playback_format = mp3`.
- The system must never treat raw uploaded WAV as playback-ready course media.

Canonical processing mode:

- Worker-pipeline mode is the only canonical processing path for audio.
- Migration inserts canonical `media_assets` and `lesson_media`.
- Audio assets enter the worker pipeline.
- The worker performs WAV -> MP3 conversion.
- The worker assigns `media_assets.playback_format = mp3` during canonical audio processing.
- Audio assets become `ready` only after worker processing completes.
- Canonical worker mutation authority for media readiness is a single security-definer function.
- Media readiness mutation must occur only through the canonical worker function.
- The canonical worker function is the only allowed mutation boundary for audio state transitions that lead to `media_assets.state = ready`.

Forbidden processing behavior:

- direct raw-WAV playback
- skipping required audio conversion
- marking audio `ready` before conversion completes
- marking audio `ready` while `media_assets.playback_format <> mp3`
- direct `UPDATE` to `media_assets.state = ready`
- writing `runtime_media` as a substitute for processing completion
- deterministic replication as an alternative to worker processing
- API, migration, trigger, or ad-hoc SQL writes that mark audio `ready` outside the canonical worker function

## 7. Surface Exposure and Canonical Course Content Access Rules

Canonical data categories:

- `course_identity`: stable course identifiers and routing identity
- `course_display`: learner-facing course presentation data
- `course_grouping`: course progression and grouping data
- `course_pricing`: learner-facing course pricing data
- `lesson_identity`: stable lesson identifiers and parent-course linkage
- `lesson_structure`: lesson ordering and structural metadata
- `lesson_content`: gated lesson body content
- `lesson_media`: gated lesson-linked media references delivered with lesson content
- Category definitions are semantic law, not fixed field lists. Future fields must map into these categories without changing surface rules.

Canonical surface types:

- `course_discovery_surface` exposes only allowed categories:
  - `course_identity`
  - `course_display`
  - `course_grouping`
  - `course_pricing`
- Forbidden categories must never appear on `course_discovery_surface`:
  - `lesson_content`
  - `lesson_media`
  - `enrollment_state`
  - `unlock_state`
- `lesson_structure_surface` exposes only allowed categories:
  - `lesson_identity`
  - `lesson_structure`
- `lesson_structure_surface` maps to `lessons` only.
- Forbidden categories must never appear on `lesson_structure_surface`:
  - `lesson_content`
  - `lesson_media`
  - `enrollment_state`
  - `unlock_state`
- `lesson_content_surface` exposes only allowed categories:
  - `lesson_identity`
  - `lesson_structure`
  - `lesson_content`
  - `lesson_media`
- `lesson_content_surface` maps to `lessons` + `lesson_contents` + `lesson_media`.
- `lesson_content_surface` is accessible only when `course_enrollments` AND `lesson.position <= current_unlock_position`.
- `lesson_media` exists only inside `lesson_content_surface`.
- No independent lesson-media surface exists.
- `media_assets` never defines access.
- No rule referring to visibility may be interpreted as permission for raw table access.

Canonical course-content access rules:

- `course_enrollments` is the only source of `canonical_protected_course_content_access` truth.
- `course_enrollments` is not the authority for `course_discovery_surface` or `lesson_structure_surface`.
- `canonical_protected_course_content_access` means a lesson is accessible if and only if:
  - a `course_enrollments` row exists for `(user_id, course_id)`
  - `lesson.position <= current_unlock_position`
- `current_unlock_position` is stored on `course_enrollments`.
- `step = intro` means the required `course_enrollments` row has `source = intro_enrollment`.
- `step = step1`, `step2`, or `step3` means the required `course_enrollments` row has `source = purchase`.
- No lesson content or lesson media access exists outside `course_enrollments` AND `lesson.position <= current_unlock_position`.
- No fallback access logic exists.
- No implicit entitlement rules exist.
- No access rule may be inferred from title, slug, tags, or naming conventions.

## 8. Course Enrollment Model (Canonical)

Canonical `course_enrollments` fields:

| Field | Type | Constraints | Meaning |
| --- | --- | --- | --- |
| `id` | UUID | required | Stable enrollment identity |
| `user_id` | UUID | required | Canonical enrolled user |
| `course_id` | UUID | required FK to `courses.id` | Canonical enrolled course |
| `source` | enum | required: `purchase | intro_enrollment` | Canonical enrollment origin |
| `granted_at` | timestamptz | required | Enrollment creation timestamp |
| `drip_started_at` | timestamptz | required | Canonical stored unlock anchor |
| `current_unlock_position` | integer | required | Canonical persisted highest accessible `lesson.position` |

Canonical enrollment rules:

- Enrollment is not required for `course_discovery_surface` or `lesson_structure_surface`.
- Enrollment is required for `lesson_content_surface` for all courses, including intro courses, and access also requires `lesson.position <= current_unlock_position`.
- Intro enrollment must create a row with `source = intro_enrollment`.
- Purchase must create a row with `source = purchase`.
- No lesson content or lesson media access exists outside `course_enrollments` AND `lesson.position <= current_unlock_position`.
- Enrollment always stores `drip_started_at` and `current_unlock_position`, regardless of source.
- Enrollment state must exist regardless of source.
- Enrollment does not define whether drip applies.
- Enrollment stores state only. Course configuration defines unlock behavior.
- On creation of any enrollment, `drip_started_at = granted_at`.
- On creation of an enrollment for a course with `drip_enabled = true`:
  - if the course has at least one lesson, `current_unlock_position = 1`
  - if the course has zero lessons, `current_unlock_position = 0`
- On creation of an enrollment for a course with `drip_enabled = false`:
  - if the course has at least one lesson, `current_unlock_position = max_lesson_position`
  - if the course has zero lessons, `current_unlock_position = 0`

Canonical drip rules:

- Drip applies only when `course.drip_enabled = true`.
- Enrollment source never defines whether drip applies.
- `drip_started_at` defines the time anchor.
- Lesson unlocking is based on `drip_started_at`, `lessons.position`, and `course.drip_interval_days`.
- `current_unlock_position` must be stored explicitly.
- The system must never derive unlock state dynamically without persistence.
- Worker-based scheduling is the only canonical way to advance drip progression for courses with `drip_enabled = true`.
- Worker execution uses the canonical formula:
  - `unlocked_count = 1 + floor((now - drip_started_at) / (course.drip_interval_days days))`
  - `computed_unlock_position = min(max_lesson_position, unlocked_count)`
- `current_unlock_position` must never exceed the highest existing `lessons.position` in the enrolled course.
- If `current_unlock_position` already equals `max_lesson_position`, worker execution must be a no-op.
- Worker execution must be deterministic.
- Repeated worker executions in the same cron window must produce the same persisted result.
- The worker may update only when `computed_unlock_position > current_unlock_position`.
- The worker must never decrease `current_unlock_position`.

## 9. API Read Contract

Canonical read shapes:

### 9.1 `LessonSummary` (Structure Surface)

Purpose:

- `LessonSummary` is the canonical `lesson_structure_surface` shape for course-detail surfaces.
- `LessonSummary` is sourced from `lessons` only.

Allowed categories:

- `lesson_identity`
- `lesson_structure`

Forbidden categories:

- `lesson_content`
- `lesson_media`
- `enrollment_state`
- `unlock_state`

Access rules:

- `LessonSummary` is exposed via explicit read surface without `course_enrollments`.
- `LessonSummary` must never require `course_enrollments` or `lesson.position <= current_unlock_position`.
- Forbidden categories must never appear in `LessonSummary`.

### 9.2 `LessonContent` (Lesson Content Surface)

Purpose:

- `LessonContent` is the canonical `lesson_content_surface` shape.
- `LessonContent` is sourced from canonical `lessons` + `lesson_contents` + `lesson_media`.

Allowed categories:

- `lesson_identity`
- `lesson_structure`
- `lesson_content`
- `lesson_media`

Forbidden categories:

- `enrollment_state`
- `unlock_state`
- hidden policy evaluation fields

Access rules:

- `LessonContent` is accessible only when `course_enrollments` AND `lesson.position <= current_unlock_position`.
- `LessonContent` must never be returned from `course_discovery_surface` or `lesson_structure_surface`.
- `lesson_media` exists only inside `LessonContent`.
- `media_assets` never defines access.

Canonical endpoint contract:

- `GET /courses` is `course_discovery_surface`.
- `GET /courses/{course_id}` is a course-detail endpoint composed of `course_discovery_surface` and `lesson_structure_surface`, does not require enrollment, and may return lessons only as `LessonSummary[]`.
- `GET /courses/by-slug/{slug}` is a course-detail endpoint composed of `course_discovery_surface` and `lesson_structure_surface`, does not require enrollment, and may return lessons only as `LessonSummary[]`.
- `GET /courses/lessons/{lesson_id}` is `lesson_content_surface` and returns `LessonContent`.
- `lesson_media` exists only inside `lesson_content_surface`.
- No endpoint may return `lesson_content` or `lesson_media` without `course_enrollments` AND `lesson.position <= current_unlock_position`.
- No endpoint using `course_discovery_surface` or `lesson_structure_surface` may return `lesson_content` or `lesson_media`.
- No rule referring to visibility may be interpreted as permission for raw table access.
- `app.lessons` must remain structure-only and `app.lesson_contents` must remain content-only.
- `app.lessons` and `app.lesson_contents` must not be collapsed into one raw-table lesson access surface that bypasses canonical surface boundaries.

## 10. UI Contract

Canonical UI rules:

- UI reads only canonical fields.
- UI writes only canonical fields.
- UI must read course discovery data via `course_discovery_surface` without enrollment-derived gating.
- UI must read lesson structure via `lesson_structure_surface` without enrollment-derived gating.
- UI must read enrollment-and-unlock-backed access state only for `lesson_content_surface`.
- UI must treat `LessonSummary` as a `lesson_structure_surface` shape exposing only `lesson_identity` and `lesson_structure`.
- UI must treat `LessonContent` as a `lesson_content_surface` shape exposing `lesson_identity`, `lesson_structure`, `lesson_content`, and `lesson_media`.
- UI must never expect `lesson_content` or `lesson_media` inside `LessonSummary`.
- UI must never assume lesson body content lives on the lesson-structure row.
- UI must grant intro-course `lesson_content_surface` access by creating an `intro_enrollment` row, not by toggling implicit access.
- UI must read `course_group_id` directly.
- UI must write `course_group_id` directly.
- UI must read `step` directly.
- UI must write `step` directly.
- UI must read `drip_enabled` directly.
- UI must write `drip_enabled` directly.
- UI must read `drip_interval_days` directly.
- UI must write `drip_interval_days` directly.
- UI must read `lesson_title` directly.
- UI must write `lesson_title` directly.
- UI must not maintain separate intro and step state.
- UI must not hide courses behind `course_enrollments`.
- UI must not hide lesson structure behind `course_enrollments`.
- UI must not use a single lesson read shape for both `lesson_structure_surface` and `lesson_content_surface`.
- Any state where `course_discovery_surface`, `lesson_structure_surface`, and `lesson_content_surface` are conflated is forbidden by contract.
- No rule referring to visibility may be interpreted as permission for raw table access.
- UI grouping and progression linking must use `course_group_id` only.
- UI must reflect drip configuration consistently in course cards and course views.
- UI must not infer drip behavior from course type, enrollment source, title, slug, or step.
- UI must not parse `title` or `slug` to infer grouping, pricing, access, or progression.

## 11. Migration Contract

Migration source:

- `reconstruction_metadata_final_v7.json`

### 11.1 Mapped Fields

Canonical course mapping:

- `courses.title <- course.course_title`
- `courses.slug <- course.slug`
- `courses.course_group_id <- deterministic migration-time derivation from course.course_title only`
- `courses.price_amount_cents <- course.pricing.amount_cents` for paid courses
- `courses.drip_enabled <- authoritative explicit course configuration input`
- `courses.drip_interval_days <- authoritative explicit course configuration input`
- `courses.cover_media_id <- generated media asset id for the migrated course cover`

Canonical lesson mapping:

- `lessons.course_id <- generated canonical course id`
- `lessons.lesson_title <- lesson.lesson_title`
- `lessons.position <- lesson.position`
- `lesson_contents.lesson_id <- generated canonical lesson id`
- `lesson_contents.content_markdown <- file contents loaded from lesson.content_path`

Canonical media mapping:

- `media_assets.media_type <- media.type`
- `media_assets.original_object_path <- media.path` for lesson media
- `media_assets.original_object_path <- course.cover.path` for course covers
- `media_assets.ingest_format <- deterministic file extension derived from the source path`
- `media_assets.playback_format <- null on ingest; canonical worker processing assigns mp3 for audio`
- `media_assets.purpose <- course_cover` for course covers
- `media_assets.purpose <- lesson_media` for lesson attachments
- `media_assets.state <- migration execution mode output`
- `lesson_media.lesson_id <- generated canonical lesson id`
- `lesson_media.media_asset_id <- generated canonical media asset id`
- `lesson_media.position <- 1-based enumeration of the source media array`

### 10.2 Dropped Fields

The following reconstruction fields are migration-only input and do not survive into canonical stored truth:

- `course.type`
- `course.cover.path`
- `course.pricing.source`
- `course.pricing.legacy_course_id`
- `lesson.is_intro`
- `lesson.content_path`
- `lesson.migration.media_state`
- `media.file`

### 10.3 Deterministic Derived Values

The following derivations are allowed during migration only. They are not runtime logic.

Course step derivation:

- derive from `course.course_title` only
- if the normalized title contains exactly one recognized `del 1` marker -> `courses.step = step1`
- else if the normalized title contains exactly one recognized `del 2` marker -> `courses.step = step2`
- else if the normalized title contains exactly one recognized `del 3` marker -> `courses.step = step3`
- else -> `courses.step = intro`
- if multiple conflicting step markers are present in the same title, reject the course as invalid migration input

Course group derivation:

- derive from `course.course_title` only
- build a deterministic normalized group root by:
  - lowercasing
  - normalizing diacritics
  - trimming and collapsing whitespace
  - removing a leading `utbildning -` or `utbildning` prefix when present
  - removing the recognized terminal step marker segment used for step derivation
  - normalizing punctuation and separators to a stable canonical token
- derive `courses.course_group_id` deterministically from that normalized group root
- if the normalized group root is empty, reject the course as invalid migration input
- this derivation is allowed only during migration and must not exist in runtime logic

Price derivation:

- if `courses.step == intro` -> `courses.price_amount_cents = NULL`
- else `courses.price_amount_cents = course.pricing.amount_cents`

Media ingest-format derivation:

- derive from the source file extension only
- if no file extension exists, reject the media item as invalid migration input

Media processing-state derivation:

- worker-pipeline mode: insert canonical pre-ready states and let the pipeline advance them

### 11.4 Migration Validity Rules

- Migration must reject any course that cannot produce exactly one canonical `step`.
- Migration must reject any paid course without `pricing.amount_cents`.
- Migration must reject any course without explicit `drip_enabled`.
- Migration must reject any course with `drip_enabled = true` and missing `drip_interval_days`.
- Migration must reject any course with `drip_enabled = false` and non-null `drip_interval_days`.
- Migration must reject any lesson without loadable `content_path`.
- Migration must reject any media item without a valid source path and ingest format.
- Migration must reject any attempt to preserve dropped fields as business truth.
- Content migration must not invent `course_enrollments`.
- Enrollment migration requires a separate authoritative access source and must not be inferred from course content or titles.
- Migration must not infer drip behavior from course type, enrollment source, pricing, title, slug, or step.

## 12. Verification Summary

- Zero duplicated semantics: yes
- Zero fallback paths: yes
- Zero title/slug inference in runtime behavior: yes
- `lesson_title` is canonical: yes
- `course_group_id` is canonical: yes
- course-level drip configuration is canonical: yes
- `course_enrollments` is canonical: yes
- course discovery uses category-based `course_discovery_surface` rules without `course_enrollments`: yes
- lesson structure uses category-based `lesson_structure_surface` rules without `course_enrollments`: yes
- lesson content access requires `course_enrollments` AND `lesson.position <= current_unlock_position`: yes
- no visibility rule is interpreted as permission for raw table access: yes
- `LessonSummary` excludes `lesson_content` and `lesson_media`: yes
- `lessons` remains structure-only: yes
- `lesson_contents` is the only canonical lesson body holder: yes
- `LessonContent` requires enrollment and unlock: yes
- course-detail endpoints return lessons only as `LessonSummary[]`: yes
- drip progression is stored state: yes
- enrollment is state-only for drip semantics: yes
- no source-based drip logic: yes
- no hardcoded drip default: yes
- worker pipeline is the only canonical audio processing path: yes
- Title parsing exists only as an explicit one-time migration derivation rule for `step` and `course_group_id` and is not part of runtime or stored business logic
