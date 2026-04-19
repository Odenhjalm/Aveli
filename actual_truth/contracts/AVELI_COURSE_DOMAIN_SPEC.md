# AVELI COURSE DOMAIN SPEC

## STATUS

ACTIVE

This contract is the canonical course-domain authority for Aveli. It consolidates
existing course, lesson, content, progression, access, and governed media truth
from active contracts, DECISIONS, SYSTEM_LAWS, and accepted baseline schema.

This contract creates no new domain concepts, no new tables, and no new fields.
If this contract conflicts with implementation, the implementation is drift.
If this contract conflicts with SYSTEM_LAWS, SYSTEM_LAWS prevails.

## 1. PURPOSE

The purpose of this contract is to define the Aveli course domain in a
deterministic, enforcement-ready form.

This contract owns the following course-domain boundaries:

- course identity, structure, display, grouping, pricing display, cover
  identity, and drip configuration
- lesson identity, structure, and ordering
- lesson text content authority
- lesson media placement authority
- protected lesson content access authority
- frontend course and lesson media representation shape
- fail-closed behavior for ambiguous or invalid course-domain state
- migration boundary for legacy course, lesson, content, and media shapes

This contract does not own:

- app-entry membership authority
- completed purchase authority
- Stripe runtime authority
- profile/community media authority
- home-player domain authority
- storage as business truth
- frontend rendering as domain truth
- legacy restore artifacts as canonical truth

All course-domain implementations and audits MUST treat this contract as a
blocking authority.

## 2. CORE DOMAIN MODEL

The canonical course-domain entities are:

- `app.courses`
- `app.course_public_content`
- `app.lessons`
- `app.lesson_contents`
- `app.lesson_media`
- `app.course_enrollments`
- `app.media_assets`
- `app.runtime_media`

The canonical domain meanings are:

- A course is a direct container of lessons.
- A lesson belongs directly to one course.
- Lesson structure and lesson content are separate authorities.
- Lesson media placement and media asset identity are separate authorities.
- Runtime media and frontend media representation are separate authorities.
- Protected lesson content access is explicit course-enrollment state.

No module abstraction exists in canonical course truth.

The canonical learner/public surfaces are:

- `course_discovery_surface`
- `lesson_structure_surface`
- `lesson_content_surface`

`course_discovery_surface` and `lesson_structure_surface` are not protected by
course enrollment. `lesson_content_surface` is protected by course enrollment
and lesson unlock position.

## 3. CANONICAL FIELD DEFINITIONS

### Course Fields

`app.courses` owns course identity and structure fields:

- `id`: canonical course identity.
- `slug`: canonical course lookup/display slug.
- `title`: canonical course display title.
- `course_group_id`: canonical course progression-group identity.
- `step`: canonical course progression step.
- `cover_media_id`: canonical course-cover media asset identity, or `null`.
- `price_amount_cents`: canonical course price amount for course display and
  course pricing rules.
- `drip_enabled`: canonical course-level drip configuration flag.
- `drip_interval_days`: canonical course-level drip interval when drip is
  enabled; `null` when drip is disabled.

Accepted baseline ownership and monetization fields on `app.courses` are:

- `teacher_id`
- `stripe_product_id`
- `active_stripe_price_id`
- `sellable`

These fields do not alter lesson, content, media, progression, or access
meaning. Their monetization and ownership authority remains governed by the
active course monetization and commerce contracts.

Public course read composition may project teacher display data as:

```text
teacher = { user_id, display_name } | null
```

`teacher.user_id` is derived from `app.courses.teacher_id`.
`teacher.display_name` is derived from `app.profiles.display_name`.
Frontend surfaces MUST NOT infer teacher identity or synthesize teacher display
data from unrelated profile, landing, community, or auth surfaces.

### Public Course Content Field

`app.course_public_content.short_description` is sibling public course content.
It is not course structure and is not lesson content.

### Lesson Fields

`app.lessons` owns lesson identity and structure fields:

- `id`: canonical lesson identity.
- `course_id`: canonical parent course identity.
- `lesson_title`: canonical lesson display title.
- `position`: canonical lesson ordering value within a course.

`title` is forbidden as a runtime lesson authority.

### Lesson Content Fields

`app.lesson_contents` owns lesson body content:

- `lesson_id`: canonical lesson content owner identity.
- `content_markdown`: canonical lesson text/content body.

`content_markdown` is canonical only on `app.lesson_contents`.

### Lesson Media Fields

`app.lesson_media` owns authored lesson-media placement:

- `id`: canonical lesson-media placement identity.
- `lesson_id`: canonical parent lesson identity.
- `media_asset_id`: canonical media asset identity used by the placement.
- `position`: canonical placement ordering value within a lesson.

The semantic name for `app.lesson_media.id` is `lesson_media_id`. Any existing
transport field named `id` for a lesson-media item is only the owning
surface-defined serialization of `app.lesson_media.id`; it is not a second
domain identity.

### Media Asset Fields

`app.media_assets` owns canonical media identity and media lifecycle state:

- `id`: canonical media asset identity.
- `media_type`: `audio | image | video | document`.
- `purpose`: `course_cover | lesson_media`.
- `original_object_path`: internal source storage coordinate.
- `ingest_format`: internal ingest format.
- `playback_object_path`: internal playback storage coordinate.
- `playback_format`: internal playback format.
- `state`: `pending_upload | uploaded | processing | ready | failed`.

Storage coordinates and formats are internal dependency data. They are not
frontend truth and are not media identity.

### Runtime Media Fields

`app.runtime_media` owns runtime media state and resolution eligibility. For the
course domain it projects lesson media and course covers from canonical
references into runtime truth.

Runtime media is not frontend representation. Backend read composition is the
only authority allowed to produce frontend-facing governed media output.

### Enrollment Fields

`app.course_enrollments` owns protected course-content access:

- `id`: canonical course-enrollment identity.
- `user_id`: protected access subject identity.
- `course_id`: protected access course identity.
- `source`: `purchase | intro_enrollment`.
- `granted_at`: canonical access grant timestamp.
- `drip_started_at`: canonical drip start timestamp; equal to `granted_at`.
- `current_unlock_position`: canonical highest accessible lesson position.

## 4. RELATION GRAPH (authoritative)

The authoritative course-domain relation graph is:

```text
app.courses.course_group_id + app.courses.step
  -> course progression set and course progression order

app.courses.id
  -> app.lessons.course_id

app.courses.cover_media_id
  -> app.media_assets.id

app.courses.id
  -> app.course_public_content.course_id

app.lessons.id
  -> app.lesson_contents.lesson_id

app.lessons.id
  -> app.lesson_media.lesson_id

app.lesson_media.media_asset_id
  -> app.media_assets.id

app.lesson_media.id
  -> lesson content media tokens by lesson_media_id

app.media_assets.id
  -> app.runtime_media.media_asset_id

app.course_enrollments.course_id + app.course_enrollments.user_id
  -> protected course-content access for one user and one course

app.course_enrollments.current_unlock_position
  -> highest accessible app.lessons.position
```

No other course-domain relation is canonical unless another active contract
explicitly declares it without weakening this graph.

## 5. CONTENT MODEL (Markdown + token system)

Lesson text content is canonical Markdown stored only in
`app.lesson_contents.content_markdown`.

Inline text is represented directly as Markdown text.

Media-backed content is represented only by typed Markdown media tokens that
reference `lesson_media_id`:

- `!image(<lesson_media_id>)`
- `!audio(<lesson_media_id>)`
- `!video(<lesson_media_id>)`
- `!document(<lesson_media_id>)`

Media tokens MUST reference `app.lesson_media.id`. They MUST NOT reference:

- `media_asset_id`
- `runtime_media`
- storage bucket names
- storage object paths
- signed URLs
- public URLs
- preview URLs
- playback URLs
- download URLs

Raw HTML media tags are forbidden in persisted lesson Markdown.
Raw Markdown image URLs are forbidden in persisted lesson Markdown.
Internal storage links are forbidden in persisted lesson Markdown.
Frontend-resolved URLs are forbidden in persisted lesson Markdown.

Lesson content reads and writes MUST NOT redefine lesson structure. Lesson
structure reads and writes MUST NOT expose or mutate `content_markdown`.

## 6. MEDIA MODEL (identity, placement, runtime separation)

The media authority chain is:

```text
app.media_assets.id
  -> app.lesson_media.media_asset_id or app.courses.cover_media_id
  -> app.runtime_media
  -> backend read composition
  -> media = { media_id, state, resolved_url } | null
```

The identities are distinct:

- `media_asset_id` identifies the canonical media asset.
- `lesson_media_id` identifies authored placement of a media asset in a lesson.
- `cover_media_id` identifies the media asset assigned as a course cover.
- `runtime_media` defines runtime state and resolution eligibility.
- `resolved_url` is derived delivery output, not identity.

Media ingest creates media asset identity. It does not create lesson placement.
Lesson placement creates lesson-media placement. It does not create media asset
identity. Neither ingest nor placement may directly write runtime media truth.

`app.media_assets.state = ready` is not sufficient by itself to establish
frontend playback. Runtime eligibility and backend read composition are still
required.

Storage is physical persistence only. Storage objects, buckets, object paths,
storage metadata, signed URLs, public URLs, preview URLs, playback URLs, and
download URLs never become media identity, runtime truth, access truth, orphan
authority, or frontend contract output.

Course covers are course structure assignment through `app.courses.cover_media_id`.
Media ingest and media worker behavior MUST NOT assign, replace, or clear
`app.courses.cover_media_id`.

## 7. PROGRESSION MODEL (course + lesson ordering)

Course progression is defined only by:

- `app.courses.course_group_id`
- `app.courses.step`

Valid `step` values are:

- `intro`
- `step1`
- `step2`
- `step3`

Within a `course_group_id`, progression order is strictly defined by `step`.
`course_group_id` MUST NOT be used for categories, tags, discovery filters, or
arbitrary grouping.

Lesson ordering is defined only by `app.lessons.position`.

Rules:

- lesson position MUST be `>= 1`
- `(course_id, position)` MUST be unique
- course detail lesson arrays MUST be ordered by `position ASC`
- lesson ordering MUST be stable for identical reads

Lesson media placement ordering is defined only by `app.lesson_media.position`.

Rules:

- lesson-media position MUST be `>= 1`
- `(lesson_id, position)` MUST be unique

Drip behavior is course-level configuration only:

- `drip_enabled = true` requires `drip_interval_days`
- `drip_enabled = false` requires `drip_interval_days = null`
- drip behavior MUST NOT be inferred from course type, enrollment source, or
  frontend state

Protected unlock progression is stored only in
`app.course_enrollments.current_unlock_position`.

Rules:

- `current_unlock_position` MUST NOT be negative
- `current_unlock_position` MUST NOT exceed the highest existing lesson
  position for the course
- `current_unlock_position` MUST NOT decrease
- advancement is worker-owned and MUST NOT be computed by frontend state

## 8. ACCESS CONTROL MODEL (enrollment gating)

Protected lesson content access is owned only by `app.course_enrollments`.

Membership alone never grants protected course content.
Purchase state alone never grants protected course content.
Stripe runtime state never grants protected course content.
Frontend state never grants protected course content.
Media identity never grants protected course content.

`course_discovery_surface` is public course structure/display/pricing discovery
and is not governed by course enrollment.

`lesson_structure_surface` is public lesson identity/structure discovery and is
not governed by course enrollment.

`lesson_content_surface` is protected and requires both:

- a canonical `app.course_enrollments` row for `(user_id, course_id)`
- `app.lessons.position <= app.course_enrollments.current_unlock_position`

Intro courses still require explicit enrollment with `source = intro_enrollment`
before protected lesson content can be accessed.

Paid courses require explicit enrollment with `source = purchase` before
protected lesson content can be accessed.

No endpoint, view, frontend model, token claim, membership state, purchase state,
or media state may provide protected lesson content or lesson media without the
two required `lesson_content_surface` conditions.

## 9. FRONTEND CONTRACT (strict media shape)

Frontend is render-only for governed media. Frontend MUST NOT resolve,
construct, infer, normalize, rewrite, or repair governed media truth.

The only canonical frontend-facing governed media representation is:

```text
media = { media_id, state, resolved_url } | null
```

Field meaning:

- `media_id`: canonical `app.media_assets.id`
- `state`: canonical media state projected through runtime/read composition
- `resolved_url`: backend-authored delivery URL or `null`

Course cover output MUST use:

```text
cover_media_id: UUID | null
cover: { media_id, state, resolved_url } | null
```

If no resolved cover object is available, `cover` MUST be `null`. Field
omission is forbidden for declared cover fields.
Placeholder cover objects are forbidden. When `cover` is an object, it MUST
represent a contract-valid ready course-cover image and `resolved_url` MUST be a
nonblank backend-authored delivery URL.

Learner/public lesson content media output MUST contain a media item array, and
each item MUST contain the governed `media` field.

Lesson audio, video, document, and image media surfaces MUST NOT emit
storage-adjacent or legacy media fields as contract output.

Forbidden frontend-facing media fields include:

- `storage_path`
- `object_path`
- `signed_url`
- `public_url`
- `preview_ready`
- `resolved_preview_url`
- `download_url`
- `playback_url`
- `playback_format`
- `image_url`
- raw `media_assets` storage fields

Frontend MUST NOT infer lesson content from lesson structure lists.
Frontend MUST NOT infer structure mutations from content responses.
Frontend MUST NOT invent lesson semantics.
Frontend MUST NOT use `title` as lesson authority.
Frontend MUST NOT use `is_intro` as lesson authority.

## 10. RUNTIME RULES (fail-closed media resolution)

Runtime media resolution MUST follow this chain:

```text
media_asset_id -> runtime_media -> backend read composition -> frontend media object
```

A domain surface may start from its own canonical reference, such as
`lesson_media_id` or `cover_media_id`, only to locate the canonical
`media_asset_id`. Resolution behavior MUST still pass through `runtime_media`.

Resolver behavior MUST:

- use `runtime_media` as runtime truth for state and resolution eligibility
- use only `media_asset_id`, the matching runtime media row, and an explicitly
  declared delivery policy
- construct only `media = { media_id, state, resolved_url } | null`
- return `resolved_url = null` for non-ready media where the owning surface
  allows non-ready items
- fail closed or exclude the item, according to the owning surface contract,
  when `state = ready` but delivery cannot be resolved

Resolver behavior MUST NOT:

- hardcode media state
- hardcode bucket authority
- branch on raw storage paths as business truth
- inspect `media_assets` as a replacement for `runtime_media`
- play directly from Supabase Storage as business truth
- fall back to source objects
- fall back to legacy media objects
- fall back to public URLs
- fall back to signed URLs
- fall back to preview URLs
- fall back to download URLs
- rely on frontend reconstruction

Ready-state media rules:

- `ready` requires `playback_object_path`
- audio `ready` requires `playback_format = mp3`
- direct request-surface transition to `ready` is forbidden
- direct `UPDATE app.media_assets SET state = 'ready'` is forbidden
- storage existence alone MUST NOT repair or create ready media truth

## 11. FORBIDDEN PATTERNS (explicit rejection list)

The following patterns are forbidden:

- introducing modules as canonical course structure
- treating remaining module references as domain truth
- using `title` as lesson runtime authority
- using `is_intro` as lesson authority
- using categories, tags, or arbitrary grouping as `course_group_id` meaning
- treating `course_discovery_surface` as enrollment-gated
- treating `lesson_structure_surface` as `lesson_content_surface`
- conflating `course_discovery_surface` or `lesson_structure_surface` with
  `lesson_content_surface`
- exposing `lesson_content` on a structure surface
- exposing `lesson_media` on a structure surface
- returning `lesson_content_surface` data from course-detail endpoints
- collapsing `app.lessons` and `app.lesson_contents` into one semantic surface
- putting `content_markdown` on lesson structure write or read surfaces
- putting `lesson_title`, `position`, or `course_id` on lesson content write
  surfaces
- treating raw joined lesson rows as canonical when they mix structure and
  content
- storing raw HTML media tags in lesson Markdown
- storing raw Markdown media URLs in lesson Markdown
- storing storage paths or resolved URLs in lesson Markdown
- using `media_asset_id` instead of `lesson_media_id` in lesson Markdown media
  tokens
- using frontend state as media, access, pricing, progression, or content
  authority
- using `Map<String, dynamic>` or metadata blobs as runtime truth
- using storage as media identity, runtime truth, access truth, orphan truth, or
  frontend truth
- emitting preview, playback, download, storage, or resolver payload fields as
  canonical media output
- direct frontend-authored media state mutation
- direct ready insertion
- direct `pending_upload -> ready`
- direct `uploaded -> ready` from any request surface
- deleting `app.media_assets` from lesson delete, placement delete,
  course-cover clear, runtime projection, backend read composition, or frontend
  rendering
- using absence from `runtime_media` as sole orphan proof
- using storage cleanup success as proof of canonical DB cleanup
- deriving protected course content access from membership alone
- deriving protected course content access from purchase/payment state without
  `app.course_enrollments`
- deriving protected course content access from media state
- implicit lesson content access by inferred tags, hidden rules, or fallback
  defaults
- default values that hide missing required data
- silent correction of ambiguous course-domain state
- legacy fallback behavior as canonical truth

## 12. FAILURE MODEL (fail-closed behavior)

Course-domain failures MUST fail closed.

If a required authority cannot be identified, the result is invalid.
If an authority boundary is ambiguous, the result is invalid.
If a canonical relation cannot be checked, the result is invalid for any action
that depends on that relation.

Failure rules:

- missing course identity MUST NOT be repaired from lesson, media, storage, or
  frontend data
- missing lesson identity MUST NOT be repaired from content, media, storage, or
  frontend data
- missing lesson content MUST NOT be synthesized from lesson structure
- missing lesson structure MUST NOT be synthesized from lesson content
- missing enrollment or unlock proof MUST deny protected lesson content access
- unknown enrollment state MUST deny protected lesson content access
- non-ready media MUST NOT emit a fabricated playable URL
- ready media whose delivery cannot be resolved MUST fail closed or be excluded
  according to the owning surface contract
- broken storage for `uploaded`, `processing`, or `ready` media MUST NOT fall
  back to source objects or legacy URLs
- unknown orphan status MUST prevent media asset deletion
- cleanup failure MUST NOT create frontend fallback behavior
- serialization shape drift MUST be treated as contract failure
- field omission where a surface declares required presence MUST be treated as
  contract failure
- legacy field presence MUST NOT be accepted as alternate authority

Fail-closed behavior MUST preserve authority separation. It MUST NOT create a
new fallback path, compatibility authority, or derived truth source.

## 13. MIGRATION BOUNDARY (legacy handling)

Legacy course, lesson, content, media, and restore structures may be used only
as migration inputs or historical references.

Legacy structures MUST NOT redefine canonical domain truth.

Non-authoritative legacy structures include:

- module-based course structure
- lesson `title` aliases
- lesson `is_intro`
- mixed lesson rows containing both structure and `content_markdown`
- raw joined studio lesson lists that expose content on structure surfaces
- legacy media objects
- legacy runtime media fallback rows
- storage-only media references
- raw Supabase Storage paths
- preview URLs
- download URLs
- playback URLs
- frontend-resolved URLs
- restore extraction artifacts
- metadata blobs
- raw maps used as compatibility payloads

Migration may map legacy data into canonical authorities only when the mapping
is explicit, deterministic, and lossless with respect to this contract.

Migration MUST NOT:

- preserve legacy fields as parallel authority
- create alternate access rules
- create alternate media resolution rules
- create alternate content token systems
- create alternate course or lesson ordering rules
- use fallback defaults to hide missing canonical data
- mutate core entities to support unrelated features

After migration into canonical tables, only the canonical tables, surfaces, and
contracts named by this contract may be used as course-domain authority.

Final assertion:

The Aveli course domain is fully specified by this contract for course,
lesson, content, media, progression, access, frontend media shape, runtime
resolution, fail-closed behavior, and legacy migration boundaries.

This contract is deterministic, enforcement-ready, and suitable as a blocking
authority for future audits and implementations.
