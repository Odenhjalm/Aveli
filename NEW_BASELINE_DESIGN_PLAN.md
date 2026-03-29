# NEW BASELINE DESIGN PLAN

This document defines a clean-room baseline design for Aveli.

It is based only on:

- `AVELI_COURSE_DOMAIN_SPEC.md`
- `Aveli_System_Decisions.md`
- `aveli_system_manifest.json`

The old baseline is used only as comparison input for discard/replace planning.
It is not an implementation source.

## 1. New Baseline Slot Strategy

The new baseline must use a new canonical slot sequence with clean domain boundaries.
Each slot owns one responsibility and must not carry mixed old/new semantics.

| Slot | Name | Owns | Must Not Own |
| --- | --- | --- | --- |
| `0001` | `canonical_foundation.sql` | app schema preconditions, canonical enums, shared immutable helpers | business tables, legacy compatibility |
| `0002` | `courses_core.sql` | canonical `courses` table and course-level constraints | lesson fields, access fields, fallback fields |
| `0003` | `lessons_core.sql` | canonical `lessons` table and lesson ordering constraints | intro flags, lesson pricing, media state |
| `0004` | `course_enrollments_core.sql` | canonical `course_enrollments` table and drip invariants | membership logic, entitlement fallback |
| `0005` | `media_assets_core.sql` | canonical `media_assets` table and processing-state constraints | lesson linkage, runtime fallback |
| `0006` | `lesson_media_core.sql` | canonical `lesson_media` table and media ordering constraints | storage shortcuts, hybrid legacy linkage |
| `0007` | `runtime_media_projection_core.sql` | read-only `runtime_media` projection boundary | source-of-truth writes, legacy fallback |
| `0008` | `runtime_media_projection_sync.sql` | projection sync functions/triggers from canonical sources | legacy storage logic, dual projections |
| `0009` | `canonical_access_policies.sql` | RLS and access policies using canonical authorities only | compatibility paths, mixed semantics |
| `0010` | `worker_query_support.sql` | worker-only indexes/views needed for canonical audio/drip execution | queue truth tables, business semantics |

Slot laws:

- The new slot sequence is independent from the old baseline slot sequence.
- No old slot may be edited in place and called the new baseline.
- No slot may depend on legacy field aliases or fallback read/write logic.
- Schema exists first.
- Contracts are written against the new schema second.
- Migration happens only after the canonical baseline exists and is verified.

## 2. Canonical Schema Design

### 2.1 Shared Canonical Enums

The clean-room baseline must define these canonical enums in `0001`:

- `course_step = intro | step1 | step2 | step3`
- `course_enrollment_source = purchase | intro_enrollment`
- `media_type = audio | image | video | document`
- `media_purpose = course_cover | lesson_media`
- `media_state = pending_upload | uploaded | processing | ready | failed`

No legacy enum values may be included.

### 2.2 `courses`

The new `courses` table is defined only by canonical laws:

| Field | Type | Constraints |
| --- | --- | --- |
| `id` | uuid | primary key |
| `title` | text | not null |
| `slug` | text | not null, unique |
| `course_group_id` | uuid | not null |
| `step` | `course_step` | not null |
| `price_amount_cents` | integer | nullable |
| `cover_media_id` | uuid | nullable FK -> `media_assets.id` |

Required constraints:

- `step = intro` -> `price_amount_cents IS NULL`
- `step IN (step1, step2, step3)` -> `price_amount_cents > 0`
- `UNIQUE (course_group_id, step)`
- `cover_media_id`, when present, must point to a `media_assets` row with `purpose = course_cover`

Canonical meaning:

- `step` is the only progression field.
- `course_group_id` is the only grouping field.
- `slug` is an identifier only and has no business meaning.

### 2.3 `lessons`

The new `lessons` table is defined only by canonical laws:

| Field | Type | Constraints |
| --- | --- | --- |
| `id` | uuid | primary key |
| `course_id` | uuid | not null FK -> `courses.id` |
| `lesson_title` | text | not null |
| `position` | integer | not null |
| `content_markdown` | text | not null |

Required constraints:

- `position >= 1`
- `UNIQUE (course_id, position)`

Canonical meaning:

- `lesson_title` is the only lesson display name.
- `position` is the only lesson progression index.
- Lessons are valid with zero media.

### 2.4 `course_enrollments`

The new `course_enrollments` table is defined only by canonical laws:

| Field | Type | Constraints |
| --- | --- | --- |
| `id` | uuid | primary key |
| `user_id` | uuid | not null, external soft reference |
| `course_id` | uuid | not null FK -> `courses.id` |
| `source` | `course_enrollment_source` | not null |
| `granted_at` | timestamptz | not null |
| `drip_started_at` | timestamptz | nullable |
| `current_unlock_position` | integer | nullable |

Required constraints:

- `UNIQUE (user_id, course_id)`
- `source = purchase` -> `drip_started_at IS NULL AND current_unlock_position IS NULL`
- `source = intro_enrollment` -> `drip_started_at IS NOT NULL AND current_unlock_position IS NOT NULL`
- `source = intro_enrollment AND current_unlock_position >= 0`

Canonical meaning:

- This is the only course-access authority.
- Purchase and intro access are represented in one table, one concept, one path.
- No app membership truth is duplicated here.

### 2.5 `media_assets`

The new `media_assets` table is defined only by canonical laws:

| Field | Type | Constraints |
| --- | --- | --- |
| `id` | uuid | primary key |
| `media_type` | `media_type` | not null |
| `purpose` | `media_purpose` | not null |
| `original_object_path` | text | not null |
| `ingest_format` | text | not null |
| `state` | `media_state` | not null |

Required constraints:

- `purpose = course_cover` or `purpose = lesson_media` only
- `media_type = audio | image | video | document` only
- `state = pending_upload | uploaded | processing | ready | failed` only

Canonical meaning:

- This table stores canonical media identity and processing truth.
- It does not store lesson ordering.
- It does not store legacy storage fallback fields.
- It does not encode course access.

### 2.6 `lesson_media`

The new `lesson_media` table is defined only by canonical laws:

| Field | Type | Constraints |
| --- | --- | --- |
| `id` | uuid | primary key |
| `lesson_id` | uuid | not null FK -> `lessons.id` |
| `media_asset_id` | uuid | not null FK -> `media_assets.id` |
| `position` | integer | not null |

Required constraints:

- `position >= 1`
- `UNIQUE (lesson_id, position)`

Canonical meaning:

- This table is the only lesson-to-media linkage.
- Ordering is explicit and persistent.
- No hybrid link to media objects, storage paths, or legacy kinds may exist.

### 2.7 `runtime_media` Projection Boundary

`runtime_media` remains a playback authority, but only as a projection.

Projection laws:

- `runtime_media` is not source-of-truth storage.
- `runtime_media` is derived only from canonical `lessons`, `lesson_media`, and `media_assets`.
- `runtime_media` must expose only playback-eligible rows.
- A row is playback-eligible only when the source `media_assets.state = ready`.
- No direct application write path may target `runtime_media`.
- No legacy fallback fields may exist in `runtime_media`.
- No slug/title/access inference may exist in `runtime_media`.

Projection minimum boundary:

- one projected row per canonical `lesson_media`
- canonical linkage back to:
  - `lesson_media`
  - `lesson`
  - `course`
  - `media_asset`
  - canonical `media_type`

The physical shape may be a table plus sync triggers or a projection view, but the boundary is fixed:

- read-only to application code
- no direct writes
- no fallback columns
- no legacy storage bypass

### 2.8 Worker / Process Support

No additional worker truth tables are required by canonical system laws.

The new baseline must not create queue or retry truth tables unless new canonical laws explicitly require them.

Allowed worker support in `0010`:

- indexes
- read-only helper views
- non-business execution helpers

Forbidden:

- queue tables that duplicate business truth
- fallback state tables
- alternative drip or audio authorities

## 3. Explicit Non-Porting List

The following structures, fields, and semantics must not be carried into the new baseline.

### 3.1 Course Non-Porting

- `description`
- `cover_url`
- `video_url`
- `branch`
- `is_free_intro`
- `price_cents`
- `currency`
- `is_published`
- `created_by`
- `stripe_product_id`
- `stripe_price_id`
- `journey_step`

### 3.2 Lesson Non-Porting

- `title`
- `video_url`
- `duration_seconds`
- `is_intro`
- `price_amount_cents`
- `price_currency`

### 3.3 Enrollment / Access Non-Porting

- old table name `enrollments` as canonical access truth
- enrollment `status`
- enrollment sources `free_intro`, `membership`, `grant`
- membership-derived course access
- access grant compatibility surfaces
- legacy entitlement logic
- step-based ownership logic

### 3.4 Lesson-Media Non-Porting

- `media_id`
- `kind`
- `storage_path`
- `storage_bucket`
- `duration_seconds`
- any path-or-object hybrid rule

### 3.5 Media Asset Non-Porting

- `owner_id`
- `course_id`
- `lesson_id`
- `original_content_type`
- `original_filename`
- `original_size_bytes`
- `storage_bucket`
- `streaming_object_path`
- `streaming_format`
- `duration_seconds`
- `codec`
- `error_message`
- `processing_attempts`
- `processing_locked_at`
- `next_retry_at`
- `home_player_audio` as a course-baseline purpose value

### 3.6 Runtime Projection Non-Porting

- `reference_type`
- `auth_scope`
- `fallback_policy`
- `home_player_upload_id`
- `teacher_id`
- `media_object_id`
- `legacy_storage_bucket`
- `legacy_storage_path`
- `kind`
- any direct write path to `runtime_media`

### 3.7 Semantic Non-Porting

- `step_level`
- `course_family`
- slug parsing in runtime
- title parsing in runtime
- dual intro/step state
- fallback grouping logic
- fallback access logic
- runtime-derived progression
- runtime-derived unlock state
- any field added only to preserve backward compatibility

## 4. Implementation Order

The new baseline must be implemented in this order.
Each phase is atomic and must be verified before the next phase starts.

### Phase 1: Freeze Clean-Room Boundary

1. Freeze the new baseline design inputs to the three canonical documents only.
2. Mark the old baseline as comparison-only input.
3. Define the new slot sequence independently from the old slot sequence.

Verification:

- no old slot is reused as the new baseline source
- no compatibility scope is accepted

### Phase 2: Schema Foundation

1. Create `0001 canonical_foundation.sql`.
2. Define all canonical enums.
3. Define shared immutable helpers only if required by canonical constraints.

Verification:

- enums exactly match canonical laws
- no legacy enum values exist

### Phase 3: Core Domain Tables

1. Create `courses`.
2. Create `lessons`.
3. Create `course_enrollments`.
4. Create `media_assets`.
5. Create `lesson_media`.

Verification:

- all canonical fields exist
- all forbidden fields are absent
- all core constraints compile and enforce the canonical model

### Phase 4: Projection Boundary

1. Create `runtime_media` as projection-only boundary.
2. Add sync functions/triggers or equivalent projection mechanism.
3. Ensure playback eligibility is based only on canonical ready-state rows.

Verification:

- application writes to `runtime_media` are impossible
- projection contains no fallback columns
- projection depends only on canonical tables

### Phase 5: Access and RLS

1. Add RLS for `courses`, `lessons`, `course_enrollments`, `media_assets`, and `lesson_media`.
2. Express course access only through `course_enrollments`.
3. Express intro drip boundaries only through `current_unlock_position`.

Verification:

- no course access path exists outside `course_enrollments`
- no lesson access path exists beyond `current_unlock_position`
- no membership-only path grants course access

### Phase 6: Media Pipeline Enforcement

1. Bind audio processing to worker-only execution.
2. Enforce WAV -> MP3 before `state = ready`.
3. Enforce no direct audio `ready` writes.

Verification:

- audio cannot become playback-ready without worker processing
- no alternate audio pipeline exists

### Phase 7: Enrollment and Drip Enforcement

1. Enforce canonical intro enrollment initialization.
2. Implement worker-only drip advancement using the canonical formula.
3. Enforce clamp and idempotence rules.

Verification:

- intro enrollments initialize deterministically
- purchase enrollments have no drip state
- repeated worker runs in the same cron window are no-ops when the stored value is already current

### Phase 8: Contract Rewrite

1. Rewrite backend contracts to use only canonical fields.
2. Rewrite UI contracts to use only canonical fields.
3. Remove all legacy/fallback response fields and payload fields.

Verification:

- API exposes only canonical course, lesson, media, and enrollment semantics
- UI reads/writes only canonical fields
- no title/slug inference remains in runtime behavior

### Phase 9: Migration Execution

1. Migrate content only after the canonical baseline is live.
2. Migrate `courses`, then `lessons`, then `media_assets`, then `lesson_media`.
3. Migrate `course_enrollments` only from separate authoritative access input.
4. Let workers advance audio processing and intro drip after canonical rows exist.

Verification:

- migration writes only canonical tables
- no legacy fields are preserved as stored truth
- projection and worker behavior operate from canonical rows only

## 5. Old Baseline Comparison

The old baseline is comparison input only.

### 5.1 What Must Be Discarded

Discard these old-baseline patterns entirely:

- mixed course progression via `is_free_intro` + `journey_step`
- old `enrollments` source values `free_intro`, `membership`, `grant`
- lesson-level intro/pricing semantics
- hybrid `lesson_media` linkage via `media_id`, `media_asset_id`, or `storage_path`
- `runtime_media` fallback policy and legacy storage fields
- old read-alignment/backfill slots that exist to support mixed truth

### 5.2 What Must Be Replaced

Replace these old-baseline structures with clean-room canonical equivalents:

- old `courses` table -> new canonical `courses`
- old `enrollments` table -> new canonical `course_enrollments`
- old `lessons` table -> new canonical `lessons`
- old hybrid `lesson_media` -> new canonical `lesson_media`
- old `media_assets` superset -> new canonical `media_assets`
- old fallback-capable `runtime_media` -> new projection-only `runtime_media`

### 5.3 What Remains Valid In Principle

These ideas remain valid in principle, but must be reimplemented clean-room:

- unique slug per course
- unique lesson position per course
- unique lesson-media position per lesson
- `cover_media_id` as FK from course to canonical media asset
- `runtime_media` as playback projection
- worker-driven media readiness lifecycle

No old DDL, trigger body, or field list may be copied forward as design truth.

## 6. Verification Checks

The new baseline is valid only if all checks below pass.

### 6.1 Canonicality Check

- every business concept has one authoritative field
- `step` is the only progression field
- `course_group_id` is the only grouping field
- `lesson_title` is the only lesson display field
- `course_enrollments` is the only course-access authority

### 6.2 Forward-Only Check

- no compatibility fields exist
- no legacy aliases exist
- no old source values remain
- no incremental old/new hybrid tables exist

### 6.3 No-Duplication Check

- no dual intro/step state
- no duplicate grouping mechanism
- no duplicate access authority
- no duplicate unlock authority

### 6.4 No-Fallback Check

- no slug/title runtime inference
- no fallback access logic
- no fallback unlock logic
- no fallback playback logic
- no direct writes to `runtime_media`

### 6.5 Legacy Independence Check

- the new baseline can be explained completely without referencing:
  - `is_free_intro`
  - `journey_step`
  - `step_level`
  - `course_family`
  - `price_cents`
  - old `enrollments`
  - old `lesson_media` hybrid linkage
  - legacy storage fallback

### 6.6 Comparison-Domain Check

- old baseline appears only in:
  - discard lists
  - replacement mapping
  - projection principle comparison
- old baseline never appears as implementation source

## 7. Final Design Verdict

This plan describes a truly new baseline if and only if implementation follows these laws:

- canonical laws define the schema
- the old baseline is comparison input only
- no legacy construct is promoted into the new baseline
- contracts are rewritten against the new baseline after schema completion
- migration happens only after canonical schema and contracts are verified

If any old field, fallback path, or dual semantic surface is carried forward, the clean-room baseline is invalid.
