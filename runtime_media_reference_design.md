# Runtime Media Reference Design

Scope: architecture-only design for the canonical runtime reference layer that unifies lesson playback and Home playback. No product code was changed.

`runtime_media.id` should become the only public runtime playback identity in Aveli. `lesson_media.id` remains a source-specific authoring/reference row, while `media_asset.id` and `media_object.id` stay internal processing and storage identities.

## 1. `runtime_media` Table Schema

`app.runtime_media` is the new canonical reference table. It sits above `lesson_media`, `home_player_uploads`, `media_assets`, and `media_objects`, and below surface-specific read models such as lesson rendering and `/home/audio`.

Proposed schema:

```sql
create table if not exists app.runtime_media (
  id uuid primary key default gen_random_uuid(),

  -- Which source table owns this canonical reference.
  reference_type text not null
    check (reference_type in ('lesson_media', 'home_player_upload')),

  -- Which auth policy family resolves playback for this row.
  auth_scope text not null
    check (auth_scope in ('lesson_course', 'home_teacher_library')),

  -- Explicit migration-era fallback policy.
  fallback_policy text not null
    check (fallback_policy in ('never', 'if_no_ready_asset', 'legacy_only')),

  -- Exactly one origin row must be present.
  lesson_media_id uuid unique
    references app.lesson_media(id) on delete cascade,
  home_player_upload_id uuid unique
    references app.home_player_uploads(id) on delete cascade,

  -- Auth routing context. These are not ACL snapshots.
  teacher_id uuid not null references app.profiles(user_id),
  course_id uuid references app.courses(id) on delete set null,
  lesson_id uuid references app.lessons(id) on delete set null,

  -- Internal media links only. Never public API ids.
  media_asset_id uuid references app.media_assets(id) on delete set null,
  media_object_id uuid references app.media_objects(id) on delete set null,

  -- Legacy storage fallback mirror for lesson rows that still rely on direct
  -- storage identity or where the object row is incomplete/missing.
  legacy_storage_bucket text,
  legacy_storage_path text,

  -- Canonical normalized media kind.
  kind text not null
    check (kind in ('audio', 'video', 'image', 'document', 'other')),

  -- Soft activity flag. For Home uploads this mirrors hpu.active.
  active boolean not null default true,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint runtime_media_one_origin check (
    ((lesson_media_id is not null)::int + (home_player_upload_id is not null)::int) = 1
  ),

  constraint runtime_media_legacy_storage_pair check (
    legacy_storage_path is null or legacy_storage_bucket is not null
  ),

  constraint runtime_media_auth_shape check (
    (
      auth_scope = 'lesson_course'
      and lesson_media_id is not null
      and course_id is not null
      and lesson_id is not null
    )
    or
    (
      auth_scope = 'home_teacher_library'
      and home_player_upload_id is not null
    )
  )
);

create index if not exists idx_runtime_media_teacher_active
  on app.runtime_media(teacher_id, active);

create index if not exists idx_runtime_media_course
  on app.runtime_media(course_id);

create index if not exists idx_runtime_media_lesson
  on app.runtime_media(lesson_id);

create index if not exists idx_runtime_media_asset
  on app.runtime_media(media_asset_id);

create index if not exists idx_runtime_media_object
  on app.runtime_media(media_object_id);
```

Design notes:

- The table is intentionally lean. It stores canonical identity, routing context, and internal source links, not feed titles, signed URLs, readiness snapshots, or storage verification results.
- `kind` is canonicalized here. In particular, current lesson `pdf` should map to runtime `document`.
- `fallback_policy` makes migration behavior explicit instead of burying it in source-specific conditionals.
- `teacher_id`, `course_id`, and `lesson_id` are routing context for auth and telemetry. They do not replace authoritative policy checks against the current course, lesson, enrollment, or publication state.
- If later performance work needs more denormalized display fields, add a view or read model on top of `runtime_media` rather than turning this table into a surface-specific feed cache.

## 2. Relationship To `lesson_media`

`lesson_media` remains the lesson authoring and placement table. It still owns lesson-specific concerns such as:

- lesson membership
- lesson ordering / `position`
- markdown/token references that already point at lesson media
- source-specific legacy storage details that still exist during migration

`runtime_media` has a 1:1 relationship with `lesson_media`:

- `runtime_media.lesson_media_id` is nullable but unique
- every active `lesson_media` row gets exactly one `runtime_media` row
- deletes should cascade from `lesson_media` to `runtime_media`

This means:

- `lesson_media.id` is no longer the long-term public playback id
- but `lesson_media` is still the correct source row for lesson content authoring
- `POST /api/media/lesson-playback` can survive as a temporary alias by resolving `runtime_media.id` from `lesson_media_id` and delegating to the new canonical playback facade

Important design rule:

- Home course links must reuse the same lesson-backed `runtime_media` row
- they must not create a second runtime identity for the same lesson item

That keeps one canonical identity for one playable reference, even when the same lesson item appears both inside lessons and inside Home.

## 3. Relationship To `home_player_uploads`

`home_player_uploads` remains the Home-specific library/editor table. It should keep:

- teacher ownership
- Home title
- Home active/inactive curation state
- Home-specific created/updated timestamps
- Home upload management APIs

`runtime_media` has a 1:1 relationship with direct Home uploads:

- `runtime_media.home_player_upload_id` is nullable but unique
- every `home_player_uploads` row gets exactly one `runtime_media` row
- the public playback id for that upload becomes `runtime_media.id`
- `course_id` and `lesson_id` stay null for these rows; the design must not invent fake lesson or course placeholders

This is the key fix for Home uploads:

- Home uploads stop exposing `media_asset_id` and `media_object.id` as runtime ids
- object-backed uploads and asset-backed uploads both resolve through the same stable `runtime_media.id`
- if an upload migrates from legacy object-backed storage to pipeline-backed asset storage, only the internal links on `runtime_media` change; the public id does not

Important non-goal:

- `home_player_course_links` should not get their own `runtime_media` rows
- those rows are curation links to lesson-backed runtime media, not separate playable references

## 4. Relationship To `media_assets`

`media_assets` remains the authoritative processing and ready-state table.

`runtime_media.media_asset_id` is:

- optional
- internal-only
- many-to-one

It must not be unique because future reuse is allowed. Multiple runtime references may legitimately point at the same processed asset if the product later supports that.

Resolver policy:

- if `media_asset_id` exists, the resolver checks `media_assets.state` live
- ready asset storage comes from `media_assets.streaming_object_path` or `media_assets.original_object_path`
- lesson audio still preserves the derived-audio invariant for `purpose = 'lesson_audio'`
- `media_assets.state` should stay authoritative in `app.media_assets`, not be copied into `runtime_media` as a stale snapshot

Public API rule:

- `media_asset.id` never appears in public playback request or response payloads after rollout

## 5. Relationship To `media_objects`

`media_objects` remains the authoritative legacy storage-object table.

`runtime_media.media_object_id` is:

- optional
- internal-only
- used only for legacy fallback or legacy-only playback during migration

`runtime_media` also stores `legacy_storage_bucket` and `legacy_storage_path` because current lesson media can still rely on direct storage identity that is not cleanly represented by a surviving `media_objects` row. That mirror allows the canonical resolver to keep one contract shape even while the legacy model is being retired.

Resolver policy:

- prefer ready `media_asset`
- fall back to `media_object` or the mirrored legacy storage tuple only when `fallback_policy` allows it
- verify the final chosen object at playback issuance time, not at feed-query time

Public API rule:

- `media_object.id` never appears in public playback request or response payloads after rollout

## 6. Migration Mapping Plan

Backfill rules:

| Current source case | `reference_type` | `auth_scope` | `fallback_policy` | Internal links |
| --- | --- | --- | --- | --- |
| Lesson row with ready/pending asset-backed lesson audio | `lesson_media` | `lesson_course` | `never` | `media_asset_id` from `lesson_media.media_asset_id`; optional legacy tuple mirrored for diagnostics only |
| Lesson row with legacy-only storage | `lesson_media` | `lesson_course` | `legacy_only` | `media_object_id` and/or `legacy_storage_bucket/path` |
| Lesson row with non-audio asset + legacy object fallback | `lesson_media` | `lesson_course` | `if_no_ready_asset` | both asset and legacy links |
| Home direct upload backed only by `media_object` | `home_player_upload` | `home_teacher_library` | `if_no_ready_asset` | `media_object_id` from `home_player_uploads.media_id` |
| Home direct upload backed by `media_asset` | `home_player_upload` | `home_teacher_library` | `if_no_ready_asset` | `media_asset_id` from `home_player_uploads.media_asset_id`; keep `media_object_id` if present for migration fallback |
| Home course link to lesson media | no new row | inherits lesson row | inherits lesson row | `home_player_course_links` joins to the existing lesson-backed `runtime_media` |

Migration sequence:

1. Create `app.runtime_media`.
2. Backfill one row per `lesson_media`.
3. Backfill one row per `home_player_uploads`.
4. Add dual-write behavior so create/update/delete on `lesson_media` and `home_player_uploads` keeps `runtime_media` in sync.
5. Add repair diagnostics for mismatches between source rows and runtime rows.

Recommended backfill invariants:

- `count(app.runtime_media where lesson_media_id is not null) = count(app.lesson_media)`
- `count(app.runtime_media where home_player_upload_id is not null) = count(app.home_player_uploads)`
- no `home_player_course_links` row creates a second runtime id for an already-backed lesson row

## 7. Resolver Integration

The current `MediaResolverService` is already the right semantic core. The design change is to make `runtime_media` the primary contract input.

Recommended service evolution:

- add `resolve_runtime_media(runtime_media_id: str)` as the primary entrypoint
- rename the result model to `RuntimeMediaResolution`
- rename source-agnostic failure reasons where needed, for example `RUNTIME_MEDIA_NOT_FOUND` instead of `LESSON_MEDIA_NOT_FOUND`
- keep `resolve_lesson_media(lesson_media_id: str)` as a compatibility adapter during migration

Resolver fetch shape:

```text
runtime_media
-> left join lesson_media when reference_type = lesson_media
-> left join home_player_uploads when reference_type = home_player_upload
-> left join media_assets
-> left join media_objects
-> emit one normalized contract row
```

Resolution algorithm:

1. Fetch the `runtime_media` contract row.
2. If `active = false`, return unplayable.
3. If `media_asset_id` exists and the asset is `ready`, resolve pipeline playback.
4. If the asset is missing or not ready and `fallback_policy` permits it, try legacy fallback.
5. If the selected source is lesson audio, enforce the existing derived-audio invariant.
6. Verify signability/object existence for the final chosen storage object.
7. Return a normalized resolution with `runtime_media_id`, internal source ids, playback mode, playability, and failure reason.

Playback API target:

```http
POST /api/media/playback
{
  "runtime_media_id": "<uuid>"
}
```

Compatibility behavior during migration:

- `POST /api/media/lesson-playback` looks up `runtime_media` by `lesson_media_id` and delegates
- `POST /api/media/playback-url` may temporarily map `media_asset_id -> runtime_media_id` internally for old callers, but it stops being the canonical public contract

## 8. Feed Integration

The Home feed should become a Media Control Plane client without losing its curated backend read model.

Recommended query model:

- linked lesson items:
  `home_player_course_links -> lesson_media -> runtime_media`
- direct Home uploads:
  `home_player_uploads -> runtime_media`

Recommended `/home/audio` response fields:

- `runtime_media_id`
- `title`
- `duration_seconds`
- `kind`
- `created_at`
- Home grouping/display fields such as teacher/course metadata
- `is_playable`
- `playback_state`
- `failure_reason`
- `content_type`

Fields that should be removed from the public Home feed:

- `media_asset_id`
- `media_id`
- `storage_bucket`
- `storage_path`
- `download_url`
- `signed_url`

Frontend effect:

```text
selected Home item
-> if is_playable is false: disable play
-> else POST /api/media/playback { runtime_media_id }
-> play returned URL
```

This also means the current Home branch between asset playback and legacy URL playback can be deleted once migration is complete.

Studio/library endpoints may still expose source-table ids for editing and curation, but they should also include `runtime_media_id` so studio preview and debug tools use the same playback identity as production surfaces.

## 9. Auth Context Handling

`runtime_media` should carry auth routing context, not a cached ACL snapshot.

That means the table stores:

- `auth_scope`
- `teacher_id`
- `course_id`
- `lesson_id`

But it does not store authoritative answers for:

- `is_published`
- `is_intro`
- `is_free_intro`
- enrollment status
- whether a given user can access the row

Playback-time auth routing:

- `auth_scope = 'lesson_course'`
  Use the existing lesson/course policy path. Re-check teacher ownership, course publication, intro/free-intro rules, and enrollment at request time.
- `auth_scope = 'home_teacher_library'`
  Use the existing Home upload policy path. Re-check teacher ownership or enrollment in any published course by that teacher at request time.

Important consequence:

- Home course links do not invent a third auth policy
- they reuse `lesson_course` because curation in Home must not widen lesson access

This preserves current security behavior while still giving the resolver and playback facade enough information to pick the correct authorization routine.

## 10. Rollout Plan

Recommended rollout order:

1. Add `app.runtime_media` and backfill it for all existing `lesson_media` and `home_player_uploads`.
2. Add dual-write synchronization so source-table changes update `runtime_media` immediately.
3. Extend the resolver with `resolve_runtime_media()` and add `POST /api/media/playback`.
4. Make `POST /api/media/lesson-playback` delegate through the runtime lookup.
5. Update `/home/audio` to emit `runtime_media_id` plus playability metadata instead of URLs and byte-storage ids.
6. Switch Home frontend playback to the shared runtime-media playback helper.
7. Remove public reliance on `POST /api/media/playback-url` and `POST /media/sign`.

Recommended exit criteria:

- every lesson playback request can be resolved from `runtime_media.id`
- every direct Home upload can be resolved from `runtime_media.id`
- Home course links reuse lesson-backed runtime ids
- no public playback API accepts `media_asset.id` or `media_object.id`
- `/home/audio` exposes only canonical runtime ids and metadata

Final architectural boundary:

- `runtime_media` is the public runtime reference layer
- `lesson_media` and `home_player_uploads` are source/editorial layers
- `media_assets`, `media_objects`, and raw storage paths are internal resolver inputs
