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
  identity, legacy uniform drip field locations, and drip schedule entity
  boundaries
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

- `app.course_families`
- `app.courses`
- `app.course_custom_drip_configs`
- `app.course_custom_drip_lesson_offsets`
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
- `course_entry_gateway_surface`
- `lesson_content_surface`

`course_discovery_surface` and `lesson_structure_surface` are not protected by
course enrollment. `lesson_content_surface` is protected by course enrollment
and lesson unlock position.

`course_entry_gateway_surface` is a backend-composed learner decision surface.
It may include course structure, user access/enrollment state, per-lesson
availability/progression state, next recommended lesson, backend-authored CTA
state, and backend-authored pricing display payloads. It MUST NOT expose
lesson content or lesson media.

## 3. CANONICAL FIELD DEFINITIONS

### Course Fields

`app.courses` owns course identity and structure fields:

- `id`: canonical course identity.
- `slug`: canonical course lookup/display slug.
- `title`: canonical course display title.
- `course_group_id`: canonical course progression-group identity.
- `group_position`: canonical course progression position.
- `cover_media_id`: canonical course-cover media asset identity, or `null`.
- `price_amount_cents`: canonical course price amount for course display and
  course pricing rules.
- `drip_enabled`: canonical legacy uniform drip flag.
- `drip_interval_days`: canonical legacy uniform drip interval when legacy drip
  is enabled; `null` when legacy drip is disabled.

Detailed drip semantics, mode resolution, enrollment initialization, worker
advancement, invalid-state handling, and post-enrollment schedule locks are
owned only by `course_drip_schedule_contract.md`.

### Course Family Terms

Canonical course-grouping terminology is locked:

- `course family` means only `app.courses.course_group_id`.
- `course position` means only `app.courses.group_position`.

No alternate persisted field, derived field, response alias, write alias, or
compatibility alias is canonical course-family or course-position authority.
Human-facing labels may vary, but they remain non-authoritative and MUST map
back to `course_group_id` and `group_position` without changing meaning.

Accepted baseline ownership and monetization fields on `app.courses` are:

- `teacher_id`
- `stripe_product_id`
- `active_stripe_price_id`
- `sellable`

These fields do not alter lesson, content, media, progression, or access
meaning. Their monetization and ownership authority remains governed by the
active course monetization and commerce contracts.

Accepted baseline course-access classification metadata on `app.courses` is:

- `required_enrollment_source`: `purchase | intro | null`.

`required_enrollment_source` is the only canonical course-owned metadata that
classifies whether protected course content requires a `purchase` enrollment or
an `intro` enrollment. `null` means the course is not classified for
protected content access and protected access MUST fail closed. This field MUST
NOT be derived from `sellable`, `price_amount_cents`, Stripe state, order
state, payment state, or frontend state.

Canonical values are:

- `intro`
- `purchase`
- `null`

`intro_enrollment` is legacy/migration-only language. It MUST NOT appear in
new runtime contracts, new API payloads, new frontend branching, or new
baseline-owned canonical truth.

Publish-time workflows may use `app.courses.group_position` only as structural
or defaulting input before persisting `required_enrollment_source`. Runtime
intro/purchase/sellability/access authority MUST use persisted backend-owned
state, not course position.

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
- `content_document`: canonical rebuilt-editor lesson document body.

`content_document` is canonical only on `app.lesson_contents`.

Legacy `content_markdown` may exist only as compatibility/import/export data
until removed. It is not rebuilt-editor authority.

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
- `source`: `purchase | intro`.
- `granted_at`: canonical access grant timestamp.
- `drip_started_at`: canonical drip start timestamp; equal to `granted_at`.
- `current_unlock_position`: canonical highest accessible lesson position.

### Custom Drip Scheduling Entities

`app.course_custom_drip_configs` owns the custom lesson-offset schedule root for
a course.

`app.course_custom_drip_lesson_offsets` owns per-lesson custom unlock offsets.

Detailed scheduling semantics for those entities are defined only by
`course_drip_schedule_contract.md`.

## 4. RELATION GRAPH (authoritative)

The authoritative course-domain relation graph is:

```text
app.course_families.id
  -> app.courses.course_group_id

app.courses.course_group_id + app.courses.group_position
  -> course family membership and deterministic family order

app.courses.id
  -> app.course_custom_drip_configs.course_id

app.course_custom_drip_configs.course_id
  -> app.course_custom_drip_lesson_offsets.course_id

app.lessons.id
  -> app.course_custom_drip_lesson_offsets.lesson_id

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
  -> lesson document media nodes by lesson_media_id

app.media_assets.id
  -> app.runtime_media.media_asset_id

app.course_enrollments.course_id + app.course_enrollments.user_id
  -> protected course-content access for one user and one course

app.course_enrollments.current_unlock_position
  -> highest accessible app.lessons.position
```

No other course-domain relation is canonical unless another active contract
explicitly declares it without weakening this graph.

## 5. CONTENT MODEL (lesson_document_v1)

Rebuilt lesson text content is canonical `lesson_document_v1` JSON stored only
in `app.lesson_contents.content_document`.

Inline text is represented as explicit text nodes.

Inline formatting is represented as explicit marks:

- `bold`
- `italic`
- `underline`
- `link`

Block content is represented as explicit block nodes:

- `paragraph`
- `heading`
- `bullet_list`
- `ordered_list`
- `media`
- `cta`

Media-backed content is represented only by typed document media nodes that
reference `lesson_media_id`.

Media nodes MUST reference `app.lesson_media.id`. They MUST NOT reference:

- `media_asset_id`
- `runtime_media`
- storage bucket names
- storage object paths
- signed URLs
- public URLs
- preview URLs
- playback URLs
- download URLs

Raw HTML media tags are forbidden in persisted lesson documents.
Raw Markdown image URLs are forbidden in persisted lesson documents.
Internal storage links are forbidden in persisted lesson documents.
Frontend-resolved URLs are forbidden in persisted lesson documents.
Markdown media tokens are forbidden as rebuilt-editor authority.
Quill Delta is forbidden as rebuilt-editor authority.

Lesson content reads and writes MUST NOT redefine lesson structure. Lesson
structure reads and writes MUST NOT expose or mutate `content_document`.
Lesson structure reads and writes MUST NOT expose or mutate legacy
`content_markdown`.

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

## 7. PROGRESSION MODEL (course family + course order + lesson ordering)

Course family and course order are defined only by:

- `app.courses.course_group_id`
- `app.courses.group_position`

No other persisted field, view field, write field, response field, or
compatibility field may become canonical course-family or course-order
authority.

A course family is a canonical row in `app.course_families`.
`app.courses.course_group_id` MUST reference `app.course_families.id`.
A course family MAY exist before it contains courses.
A course family MAY remain persisted after its last course is removed.

Course family invariants:

- every course family MUST have exactly one canonical `app.course_families.id`
- every course family MUST have exactly one non-blank canonical
  `app.course_families.name`
- every course family MUST have exactly one canonical
  `app.course_families.teacher_id`
- every course MUST have exactly one non-null `course_group_id`
- every course MUST have exactly one non-null `group_position`
- `group_position` MUST be an integer `>= 0`
- `(course_group_id, group_position)` MUST be unique
- within one `course_group_id` containing `n` courses, valid positions are
  exactly `0..(n-1)`
- sparse family positions are forbidden
- duplicate family positions are forbidden
- negative family positions are forbidden

Position `0` law:

- position `0` is the reserved intro slot of a course family in structural
  sequencing only
- exactly one course may occupy position `0` in a family
- position `0` means only "first course in the family sequence"
- position `0` MUST NOT mean free access, paid access, public visibility,
  enrollability, purchasability, `intro`, `purchase`, sellability,
  or bundle membership

Within a `course_group_id`, family order is strictly defined by
`group_position`.
`course_group_id` MUST NOT be used for categories, tags, discovery filters, or
arbitrary grouping.

The legacy public/domain field name `step` MUST NOT be emitted or accepted as a
course progression authority. It MUST NOT be used as the Baseline V2 course
access classification authority.

Canonical family transitions are:

### CREATE COURSE

- no implicit default course family exists
- explicit course-family creation MAY happen before any course is authored
- course creation MUST provide explicit `course_group_id`
- caller-authored `group_position` is forbidden on canonical create surfaces
- creating into an existing family MUST append at the current family size `n`
- compatibility create paths MAY seed a canonical `app.course_families` row
  before insert when the submitted `course_group_id` is unused; the committed
  result MUST still reference `app.course_families.id`
- the committed result of create MUST leave the target family contiguous as
  `0..n` after the new course is inserted
- the caller supplies authoring intent; backend validation and persistence are
  the only authority allowed to commit resulting canonical family order

### MOVE COURSE BETWEEN FAMILIES

- a move between families MUST specify explicit target `course_group_id`
- moving a course to the same `course_group_id` is a reorder, not a
  cross-family move
- moving a course into a different existing family MUST append at the target
  family end position `n`
- moving into a family that does not exist canonically is invalid on canonical
  move surfaces
- a cross-family move MUST commit atomically across both affected families and
  MUST NOT persist duplicate or sparse positions as committed truth

### REORDER WITHIN FAMILY

- reorder within a family applies only when `course_group_id` is unchanged
- reorder within a family is valid only when the target `group_position` is
  within `0..(n-1)` for the current family size `n`
- reordering from old position `a` to new position `b` within the same family
  MUST leave the family contiguous as `0..(n-1)`
- if `b > a`, courses with positions `(a+1)..b` MUST shift by `-1`
- if `b < a`, courses with positions `b..(a-1)` MUST shift by `+1`
- the moved course MUST persist at position `b`
- reorder MUST commit atomically and MUST NOT persist an intermediate duplicate,
  sparse, or ambiguous family order as committed truth

### DELETE COURSE

- deleting a course removes that `app.courses` row from canonical truth
- after delete, every remaining course in the same family with position above
  the deleted position MUST shift by `-1`
- delete MUST NOT leave a position gap in the remaining family
- deleting the final course in a family removes course membership from that
  family but does not by itself delete the canonical `app.course_families` row

Cross-domain alignment rules:

- `group_position` MUST NOT grant access
- `group_position` may be structural/defaulting input at publish time only
- `group_position` MUST NOT grant protected content access by itself
- `group_position` MUST NOT replace persisted `required_enrollment_source`
- `group_position` MUST NOT replace
  `app.course_enrollments.current_unlock_position`
- `course_group_id` and `group_position` MUST NOT define order state, payment
  state, membership state, bundle composition, or bundle order
- bundle composition and bundle order are not course-family authority and MUST
  NOT be inferred from course-family order

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

Legacy uniform drip field locations on `app.courses` are:

- `drip_enabled = true` requires `drip_interval_days`
- `drip_enabled = false` requires `drip_interval_days = null`

Custom lesson-offset scheduling entities are:

- `app.course_custom_drip_configs`
- `app.course_custom_drip_lesson_offsets`

Detailed drip semantics, mode resolution, enrollment initialization, worker
advancement, invalid-state fail-closed behavior, and post-enrollment schedule
locks are defined only by `course_drip_schedule_contract.md`.

Drip behavior MUST NOT be inferred from course type, enrollment source, or
frontend state.

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

`lesson_content_surface` is protected and requires all of:

- a canonical `app.course_enrollments` row for `(user_id, course_id)`
- either:
  - `app.course_enrollments.source = app.courses.required_enrollment_source`
  - `app.course_enrollments.source = purchase` with backend-validated
    purchase/package entitlement override that does not create a fake intro
    enrollment
- `app.lessons.position <= app.course_enrollments.current_unlock_position`

Courses classified with `required_enrollment_source = intro` require
explicit enrollment with `source = intro` before protected lesson
content can be accessed.

Courses classified with `required_enrollment_source = purchase` require
explicit enrollment with `source = purchase` before protected lesson content can
be accessed.

No endpoint, view, frontend model, token claim, membership state, purchase state,
or media state may provide protected lesson content or lesson media without the
required `lesson_content_surface` conditions.

## 8A. COURSE ENTRY / GATEWAY MODEL

Backend read composition owns canonical Course Entry/Gateway state.

Canonical endpoint:

```text
GET /courses/{course_id_or_slug}/entry-view
```

The Course Entry/Gateway response MUST include backend-authored:

- course identity
- full course description payload
- lesson structure
- user access and enrollment state
- per-lesson availability and progression state
- next recommended lesson
- CTA decision
- pricing payload when relevant

The frontend MUST render only this response for Course Entry/Gateway decisions.
Frontend MUST NOT decide CTA type, intro eligibility, purchase eligibility,
price visibility, price formatting, lesson lock state, current/upcoming/
completed state, or next recommended lesson.

The backend-authored CTA decision MUST use only:

- `enroll`
- `buy`
- `continue`
- `blocked`
- `unavailable`

Every CTA decision MUST include:

- `type`
- `label`
- `enabled`
- `reason_code`
- `reason_text`
- `price` when relevant
- `action` when relevant

Backend lesson progression projection MUST author:

- locked/unlocked availability
- current/upcoming/completed state
- `next_unlock_at`
- previous/next navigation state
- locked reason

Frontend MUST NOT compare lesson positions or reconstruct drip state.

Backend pricing payloads are the only learner-facing course price authority.
Frontend MUST NOT hide, format, repair, or infer price display from intro,
premium, sellable, Stripe, or position-based logic.

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
- creating or moving a course into a new family with `group_position <> 0`
- creating, moving, reordering, or deleting a course in a way that leaves a
  family sparse instead of contiguous
- using a family position outside the valid contiguous range for that family
- allowing multiple courses to occupy the same `group_position` within one
  `course_group_id`
- allowing `course_group_id` or `group_position` to be missing on a canonical
  course row
- introducing a second canonical family or course-order owner outside
  `app.courses`
- using `app.course_bundles`, `app.course_bundle_courses`, or
  `app.bundle_order_courses` as course-family authority
- using `group_position` as protected-access, bundle, order, payment, or
  membership authority
- treating `course_discovery_surface` as enrollment-gated
- treating `lesson_structure_surface` as `lesson_content_surface`
- conflating `course_discovery_surface` or `lesson_structure_surface` with
  `lesson_content_surface`
- exposing `lesson_content` on a structure surface
- exposing `lesson_media` on a structure surface
- returning `lesson_content_surface` data from course-detail endpoints
- collapsing `app.lessons` and `app.lesson_contents` into one semantic surface
- putting `content_document` on lesson structure write or read surfaces
- putting legacy `content_markdown` on lesson structure write or read surfaces
- putting `lesson_title`, `position`, or `course_id` on lesson content write
  surfaces
- treating raw joined lesson rows as canonical when they mix structure and
  content
- storing raw HTML media tags in lesson documents
- storing raw Markdown media URLs in lesson documents
- storing storage paths or resolved URLs in lesson documents
- using `media_asset_id` instead of `lesson_media_id` in lesson document media
  nodes
- using Markdown media tokens as rebuilt-editor authority
- using Quill Delta as rebuilt-editor authority
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
- mixed lesson rows containing both structure and `content_document`
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
- make Markdown a parallel rebuilt-editor authority
- make Quill Delta a parallel rebuilt-editor authority
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

Course family authority is fully specified only by
`app.courses.course_group_id`.
Course position authority is fully specified only by
`app.courses.group_position`.
The invariants, transitions, and forbidden states for course families and
course order are fully locked by this contract and MUST NOT be redefined
elsewhere.

This contract is deterministic, enforcement-ready, and suitable as a blocking
authority for future audits and implementations.
