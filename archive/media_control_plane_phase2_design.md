# Media Control Plane Phase 2 Design

Scope: architecture-only Phase 2 design for converging the Home player and lesson playback into one canonical Media Control Plane runtime. No product code was changed.

## 1. Executive Summary

The current system has two different runtime media architectures:

- The lesson player already behaves like a Control Plane client. It resolves playback from `lesson_media.id` through `POST /api/media/lesson-playback`, which delegates to the canonical resolver in [media_resolver_service.py](/home/rodenhjalm/Aveli-media-control-plane/backend/app/media_control_plane/services/media_resolver_service.py) and playback issuance in [lesson_playback_service.py](/home/rodenhjalm/Aveli-media-control-plane/backend/app/services/lesson_playback_service.py).
- The Home player does not. It consumes a curated feed from `GET /home/audio`, but that feed still carries mixed runtime identities and partially-resolved playback data. Home then branches between `media_asset_id` playback and feed-attached legacy URLs. Evidence: [home.py#L14](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/home.py#L14), [courses.py#L1266](/home/rodenhjalm/Aveli-media-control-plane/backend/app/repositories/courses.py#L1266), [home_dashboard_page.dart#L663](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L663), [home_dashboard_page.dart#L818](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L818).

Phase 2 should converge these into one runtime model with three non-negotiable properties:

1. One canonical runtime identity at the presentation/reference layer, not at the byte-storage layer.
2. One canonical playback API that always resolves through the Media Control Plane.
3. One canonical resolver policy for readiness, auth, storage selection, and legacy fallback.

The core design decision is:

- `media_asset.id` and `media_object.id` must stop being public runtime identities.
- The final runtime identity must be a reference-layer id. In today’s system, `lesson_media.id` is the closest correct model because it already represents “what the user is trying to play” rather than “which bytes happen to back it.”
- But `lesson_media.id` is currently lesson-scoped and cannot cleanly represent Home direct uploads without inventing fake lesson context. Phase 2 should therefore generalize this idea into a single canonical media reference identity. This can be implemented by evolving `lesson_media` into a surface-agnostic reference layer or by introducing a dedicated `runtime_media` table. Either way, the abstraction level is the same: one user-facing media reference id above assets and storage objects.

The correct final playback API is a generalized version of the current lesson endpoint:

- Final API: `POST /api/media/playback`
- Request: `{ runtime_media_id }`
- Response: signed or presigned browser-playable playback URL

`/api/media/lesson-playback` is the correct semantic ancestor and should survive only as a temporary alias during migration. `/api/media/playback-url` and `/media/sign` should not survive as public runtime APIs.

The Home feed should become a Media Control Plane client, but it should keep its strongest stability property: a curated backend read model. The final feed should return canonical media ids plus display and playability metadata, not partially-resolved playback URLs.

## 2. Current Runtime Architectures

### Home Runtime Architecture

Current Home runtime path:

```text
teacher upload or course link
-> home_player_uploads / home_player_course_links
-> GET /home/audio
-> backend query unions linked lesson_media and direct Home uploads
-> feed returns mixed ids + storage metadata + signed/public URLs
-> frontend branches:
   - if mediaAssetId present: POST /api/media/playback-url
   - else: use signedUrl ?? downloadUrl
```

Key evidence:

- Feed route: [home.py#L14](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/home.py#L14)
- Feed assembly: [courses_service.py#L612](/home/rodenhjalm/Aveli-media-control-plane/backend/app/services/courses_service.py#L612)
- Feed query with mixed identities: [courses.py#L1271](/home/rodenhjalm/Aveli-media-control-plane/backend/app/repositories/courses.py#L1271), [courses.py#L1323](/home/rodenhjalm/Aveli-media-control-plane/backend/app/repositories/courses.py#L1323)
- Feed URL attachment: [courses_service.py#L628](/home/rodenhjalm/Aveli-media-control-plane/backend/app/services/courses_service.py#L628)
- Frontend branch logic: [home_dashboard_page.dart#L663](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L663), [home_dashboard_page.dart#L727](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L727), [home_dashboard_page.dart#L818](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L818), [home_dashboard_page.dart#L843](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L843)

Important current properties:

- The Home feed is a stable read model.
- But Home is not a true Control Plane client because playback is still split between direct feed URLs and asset-centric endpoint calls.

### Lesson Runtime Architecture

Current lesson runtime path:

```text
lesson content renders lesson_media item
-> frontend helper resolves lesson_media.id
-> POST /api/media/lesson-playback
-> lesson_playback_service.resolve_lesson_media_playback()
-> canonical MediaResolverService chooses playable source
-> signed/presigned playback URL returned
```

Key evidence:

- Frontend helper: [lesson_media_playback_resolver.dart#L52](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/shared/utils/lesson_media_playback_resolver.dart#L52)
- Endpoint: [api_media.py#L899](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/api_media.py#L899)
- Playback delegation: [lesson_playback_service.py#L391](/home/rodenhjalm/Aveli-media-control-plane/backend/app/services/lesson_playback_service.py#L391)

This is already close to the target architecture.

### Current Media Control Plane Architecture

The current Control Plane is embodied primarily by `MediaResolverService`.

It already provides:

- a canonical contract fetch over `lesson_media`, `media_assets`, and `media_objects`
- normalized kind and content-type inference
- explicit resolution modes: `PIPELINE_ASSET`, `LEGACY_STORAGE`, `NONE`
- explicit reason codes: `ASSET_NOT_READY`, `MISSING_STORAGE_IDENTITY`, `LEGACY_FALLBACK_REQUIRED`, and others

Evidence: [media_resolver_service.py#L17](/home/rodenhjalm/Aveli-media-control-plane/backend/app/media_control_plane/services/media_resolver_service.py#L17), [media_resolver_service.py#L156](/home/rodenhjalm/Aveli-media-control-plane/backend/app/media_control_plane/services/media_resolver_service.py#L156), [media_resolver_service.py#L240](/home/rodenhjalm/Aveli-media-control-plane/backend/app/media_control_plane/services/media_resolver_service.py#L240).

Its main limitation is scope: it resolves only lesson-scoped media references today.

## 3. Architectural Differences

### Identity Models

| Dimension | Home today | Lesson / current MCP |
| --- | --- | --- |
| Public runtime id | Mixed: `lesson_media.id`, `media_asset.id`, `media_object.id` | `lesson_media.id` |
| Byte-storage ids exposed to frontend | Yes | No |
| Feed shape | Includes storage and playback data | Minimal, endpoint-resolved |
| Reference semantics | Inconsistent | Consistent |

Evidence:

- Home linked items use `lesson_media.id`: [courses.py#L1271](/home/rodenhjalm/Aveli-media-control-plane/backend/app/repositories/courses.py#L1271)
- Home direct items use `coalesce(ma.id, mo.id)`: [courses.py#L1323](/home/rodenhjalm/Aveli-media-control-plane/backend/app/repositories/courses.py#L1323)
- Lesson playback uses `lesson_media_id`: [api_media.py#L904](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/api_media.py#L904)

Home also leaks structural placeholders. For direct uploads it fills `lesson_id` and `course_id` with the same byte-record id, which shows that the current Home feed contract is imitating lesson structure rather than expressing a true canonical runtime model. Evidence: [courses.py#L1324](/home/rodenhjalm/Aveli-media-control-plane/backend/app/repositories/courses.py#L1324), [courses.py#L1327](/home/rodenhjalm/Aveli-media-control-plane/backend/app/repositories/courses.py#L1327).

### Playback APIs

There are currently three runtime playback APIs:

1. `POST /media/sign`
2. `POST /api/media/playback-url`
3. `POST /api/media/lesson-playback`

Evidence: [media.py#L563](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/media.py#L563), [api_media.py#L881](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/api_media.py#L881), [api_media.py#L899](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/api_media.py#L899).

The most problematic one is `POST /api/media/playback-url`:

- its request model is named `MediaPlaybackUrlRequest`
- the payload field is `media_id`
- but the endpoint treats it as `media_asset_id`

Evidence: [schemas/__init__.py#L1008](/home/rodenhjalm/Aveli-media-control-plane/backend/app/schemas/__init__.py#L1008), [api_media.py#L883](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/api_media.py#L883), [api_media.py#L887](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/api_media.py#L887).

That ambiguity is exactly the kind of public contract drift Phase 2 should eliminate.

### Storage Resolution

Home today:

- partially resolves storage and playback in the feed itself
- attaches `download_url` and `signed_url` before the frontend asks to play

Evidence: [courses_service.py#L624](/home/rodenhjalm/Aveli-media-control-plane/backend/app/services/courses_service.py#L624), [courses_service.py#L628](/home/rodenhjalm/Aveli-media-control-plane/backend/app/services/courses_service.py#L628).

Lesson / MCP today:

- resolves storage only at playback time
- chooses between pipeline asset and legacy storage in one backend service

Evidence: [media_resolver_service.py#L281](/home/rodenhjalm/Aveli-media-control-plane/backend/app/media_control_plane/services/media_resolver_service.py#L281), [lesson_playback_service.py#L391](/home/rodenhjalm/Aveli-media-control-plane/backend/app/services/lesson_playback_service.py#L391).

### Readiness Enforcement

Home today:

- linked asset-backed rows are filtered to `ready` in SQL
- Home UI disables playback until `mediaState == ready`

Evidence: [courses.py#L1242](/home/rodenhjalm/Aveli-media-control-plane/backend/app/repositories/courses.py#L1242), [home_dashboard_page.dart#L665](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L665).

Lesson / MCP today:

- resolver marks non-ready assets as unplayable
- playback service returns `409 Media is not ready`

Evidence: [media_resolver_service.py#L323](/home/rodenhjalm/Aveli-media-control-plane/backend/app/media_control_plane/services/media_resolver_service.py#L323), [lesson_playback_service.py#L314](/home/rodenhjalm/Aveli-media-control-plane/backend/app/services/lesson_playback_service.py#L314).

### Auth Enforcement

Home today:

- feed query filters visibility by teacher ownership and published-course enrollment
- playback issuance rechecks those rules for asset-backed Home uploads

Evidence: [courses.py#L1249](/home/rodenhjalm/Aveli-media-control-plane/backend/app/repositories/courses.py#L1249), [lesson_playback_service.py#L65](/home/rodenhjalm/Aveli-media-control-plane/backend/app/services/lesson_playback_service.py#L65), [lesson_playback_service.py#L321](/home/rodenhjalm/Aveli-media-control-plane/backend/app/services/lesson_playback_service.py#L321).

Lesson / MCP today:

- playback checks course publication, intro/free-intro rules, and enrollment

Evidence: [lesson_playback_service.py#L44](/home/rodenhjalm/Aveli-media-control-plane/backend/app/services/lesson_playback_service.py#L44).

## 4. Stability Analysis

The Home player remained stable because it optimized for operational determinism, not architectural purity.

The strongest invariants from the audit are:

1. Home uses a curated backend read model instead of ad hoc client resolution.
2. Home curation is explicit: teachers either upload directly or explicitly link lesson media.
3. Home is a narrow runtime surface: audio only, effectively mp3 only at play time.
4. Asset-backed playback is hard-gated on readiness before the user can play.
5. Upload paths are deterministic and validated by prefix.
6. Access rules are simple and repeated both at feed time and at playback time.
7. The frontend has very little branching logic beyond “playable or not” and “asset branch or legacy URL branch.”
8. Home does not require lesson markdown parsing or content-tree reconstruction to find media.

Evidence: [home_dashboard_page.dart#L653](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L653), [home_dashboard_page.dart#L663](/home/rodenhjalm/Aveli-media-control-plane/frontend/lib/features/home/presentation/home_dashboard_page.dart#L663), [studio.py#L609](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/studio.py#L609), [courses.py#L1242](/home/rodenhjalm/Aveli-media-control-plane/backend/app/repositories/courses.py#L1242).

What is missing from the current Media Control Plane, relative to these Home strengths:

- no Home-style canonical read model driven by resolver output
- no single public playback API across surfaces
- no single public runtime identity across surfaces
- no surface-agnostic playability summary that Home can consume without carrying raw URLs
- no unified public contract for Home direct uploads

In short: the Control Plane is already better at resolution, but Home is still better at shaping a stable runtime surface.

## 5. Control Plane Strengths

The current Media Control Plane is superior to the Home runtime in several important ways and these should be preserved.

### Canonical Resolver

`MediaResolverService` already centralizes the hard part:

- normalize media contract
- choose ready asset or legacy storage
- emit explicit resolution mode
- emit structured failure reason

Evidence: [media_resolver_service.py#L156](/home/rodenhjalm/Aveli-media-control-plane/backend/app/media_control_plane/services/media_resolver_service.py#L156), [media_resolver_service.py#L281](/home/rodenhjalm/Aveli-media-control-plane/backend/app/media_control_plane/services/media_resolver_service.py#L281).

### Structured Reason Codes

The resolver already models failure explicitly:

- `ASSET_NOT_READY`
- `MISSING_STORAGE_IDENTITY`
- `LEGACY_OBJECT_NOT_FOUND`
- `LEGACY_FALLBACK_REQUIRED`
- `UNSUPPORTED_MEDIA_CONTRACT`

Evidence: [media_resolver_service.py#L23](/home/rodenhjalm/Aveli-media-control-plane/backend/app/media_control_plane/services/media_resolver_service.py#L23).

This is better than Home’s current implicit contract of “play button appears or not.”

### Centralized Storage Selection

The lesson path already keeps storage selection behind one service instead of exposing it to the frontend. That is the right direction. Evidence: [lesson_playback_service.py#L391](/home/rodenhjalm/Aveli-media-control-plane/backend/app/services/lesson_playback_service.py#L391).

### Legacy Containment

The resolver already treats legacy storage as an internal fallback rather than a public runtime identity. Evidence: [media_resolver_service.py#L279](/home/rodenhjalm/Aveli-media-control-plane/backend/app/media_control_plane/services/media_resolver_service.py#L279), [media_resolver_service.py#L323](/home/rodenhjalm/Aveli-media-control-plane/backend/app/media_control_plane/services/media_resolver_service.py#L323).

### Derived Audio Invariant

The current Control Plane correctly encodes that pipeline-managed lesson audio must resolve to derived audio, not arbitrary original storage. Evidence: [media_resolver_service.py#L385](/home/rodenhjalm/Aveli-media-control-plane/backend/app/media_control_plane/services/media_resolver_service.py#L385), [lesson_playback_service.py#L126](/home/rodenhjalm/Aveli-media-control-plane/backend/app/services/lesson_playback_service.py#L126).

That is a stronger invariant than the current Home runtime and should be preserved.

## 6. Required Convergence

### Canonical Runtime Media Identity

The final runtime identity must be:

- a presentation/reference id
- stable across playback retries and storage migrations
- independent of `media_asset.id` and `media_object.id`
- usable by both lessons and Home

Therefore the correct canonical identity is:

- conceptually: `runtime_media_id`
- semantically: a generalized `lesson_media`-style reference id

Design rule:

- `media_asset.id` is an internal processing/storage identity.
- `media_object.id` is an internal legacy storage identity.
- neither may remain a public runtime id after Phase 2.

Implementation note:

- If the team wants the smallest conceptual leap, treat `lesson_media.id` as the existing prototype of the final identity and extend the reference layer above Home.
- If the team wants the cleanest long-term model, introduce a dedicated canonical reference entity and map both lesson media and Home media into it.

What must be eliminated:

- Home runtime use of `media_asset_id` as a frontend playback key
- Home runtime use of `media_object.id` as a frontend playback key
- mixed public ids in `/home/audio`

### Canonical Playback Endpoint

The final system should expose exactly one public playback API:

```text
POST /api/media/playback
{
  "runtime_media_id": "<canonical-reference-id>"
}
```

Why this is the correct survivor:

- it matches the lesson endpoint’s stronger semantic model
- it hides storage and asset details from clients
- it works for both Home and lessons
- it allows one auth and readiness policy

Endpoint disposition:

- `/api/media/lesson-playback`: temporary alias only
- `/api/media/playback-url`: deprecate and remove
- `/media/sign`: deprecate as a public runtime API and keep only as internal compatibility if needed during transition

### Canonical Resolution Pipeline

The final pipeline should be:

```text
runtime_media_id
-> canonical media reference fetch
-> auth policy evaluation
-> source selection
   - ready media_asset preferred
   - explicit legacy fallback only if policy allows
-> final storage identity verification
-> signed/presigned playback URL
```

This pipeline preserves Control Plane strengths while adopting Home’s runtime simplicity.

### Canonical Readiness Rule

The current `media_state == ready` rule should remain an invariant, but only for asset-backed playback.

Final rule set:

1. If the selected playback source is a `media_asset`, it must be `ready`.
2. If the selected playback source is asset-backed audio, it must resolve to the canonical derived audio path.
3. If the selected playback source is a legacy storage object with no asset row, playability is determined by complete storage identity plus supported content type.
4. The frontend must never guess around readiness; it should only render what the backend says is playable.

This preserves Home’s strict gating without breaking direct legacy MP3 playback.

### Canonical Storage Verification Model

Yes, storage object existence should be verified during playback resolution, but only for the final selected playback candidate.

Recommended policy:

- Do verify signability/object existence at playback issuance time.
- Do not do broad object-existence scans on every feed query.
- Do record structured failure reasons and telemetry when the chosen object is missing.
- Do use asynchronous diagnostics for system-wide storage audits.

Why:

- verifying the final chosen object prevents dead playback URLs
- limiting verification to the final candidate preserves performance
- Home’s stability came from deterministic paths, not from synchronous storage scans in read queries

Current evidence:

- presigning already detects missing objects at the storage layer: [storage_service.py#L86](/home/rodenhjalm/Aveli-media-control-plane/backend/app/services/storage_service.py#L86)
- the resolver models `MISSING_STORAGE_OBJECT`, but does not fully operationalize it yet: [media_resolver_service.py#L29](/home/rodenhjalm/Aveli-media-control-plane/backend/app/media_control_plane/services/media_resolver_service.py#L29)
- runtime diagnostics already exist around missing objects and invariant checks: [media.py#L104](/home/rodenhjalm/Aveli-media-control-plane/backend/app/routes/media.py#L104), [media_resolution_failures.py#L12](/home/rodenhjalm/Aveli-media-control-plane/backend/app/repositories/media_resolution_failures.py#L12)

### Home Feed Integration

The correct answer is A, with one important refinement.

The Home feed should defer playback resolution to the Control Plane, but it should not return bare ids only. It should return:

- `runtime_media_id`
- display metadata: title, duration, kind, created_at
- UI gating metadata: `is_playable`, `playback_state`, `failure_reason`, `content_type`
- Home-specific list metadata: teacher/course/home grouping fields as needed

It should stop returning:

- `media_asset_id`
- `media_id`
- `storage_path`
- `storage_bucket`
- `download_url`
- `signed_url`

Why this is the best merger:

- it preserves Home’s stable read-model behavior
- it removes parallel URL/signing logic from the Home feed
- it keeps the frontend simple
- it makes Home a genuine Control Plane client

## 7. Final Runtime Architecture

### Conceptual Model

```text
frontend surface
  - lesson player
  - Home player
        |
        v
surface-specific read model
  - lesson content render
  - Home curated feed
        |
        v
canonical runtime_media_id
        |
        v
POST /api/media/playback
        |
        v
Media Control Plane
  - canonical reference lookup
  - auth policy
  - readiness policy
  - source selection
  - storage verification
  - URL issuance
        |
        v
media_asset or legacy storage
        |
        v
browser-playable signed URL
```

### Reference Model

The final reference layer should store or derive enough context to make playback deterministic:

- canonical id
- source surface: lesson, Home, or future surfaces
- access context: course/teacher/lesson/home visibility rules
- kind and content type
- `media_asset_id` link if asset-backed
- legacy storage or `media_object` link if compatibility is still needed

This is the key architectural boundary:

- reference layer is public
- asset/object/storage layers are private

### Home in the Final System

Home should remain:

- curated
- audio-only at the UI layer
- readiness-gated
- low-branching

Home should change in one specific way:

- it should resolve playback exactly like lessons do, by canonical id through one playback endpoint

That means the Home frontend logic should eventually become:

```text
selected home item
-> if item.is_playable is false: disable play
-> else call shared playback resolver with runtime_media_id
-> receive browser-playable URL
-> play
```

No more:

- `if mediaAssetId ... else preferredUrl`

### Lesson in the Final System

Lessons should keep their current overall model, but point at the generalized endpoint and identity contract.

The lesson runtime changes less than Home.

## 8. Migration Plan

### 1. Identity Normalization

- Introduce the canonical reference-layer identity for all runtime media.
- Map existing `lesson_media` rows into that identity without changing playback behavior.
- Create canonical reference records for Home direct uploads and Home course links.
- Keep `media_asset.id` and `media_object.id` internal-only from this point forward.

Exit condition:

- every playable Home item and every playable lesson item can be addressed by one canonical runtime id

### 2. Playback API Consolidation

- Implement the generic playback endpoint on top of the existing canonical resolver pattern.
- Make the current lesson playback path delegate into it.
- Make asset-centric playback-url requests delegate internally during migration.
- Stop adding new public callers to `/media/sign` and `/api/media/playback-url`.

Exit condition:

- all new clients use the generic playback endpoint

### 3. Home Player Integration

- Change the Home feed contract to emit canonical ids plus display/playability metadata only.
- Remove feed-attached playback URLs and byte-storage ids from the public Home contract.
- Replace Home’s branchy frontend playback logic with the same shared playback helper pattern used by lessons.

Exit condition:

- Home player is a true Media Control Plane client

### 4. Legacy Path Containment

- Keep `media_object` and direct storage fallback inside the resolver only.
- Add or complete background backfill from legacy references to canonical reference records and assets where appropriate.
- Keep direct legacy MP3 playback working until migration completes.
- Do not force transcoding merely to unify public runtime semantics.

Exit condition:

- legacy storage is no longer exposed through public APIs or feed contracts

### 5. Removal of Redundant Playback Routes

- remove public usage of `/media/sign`
- remove public usage of `/api/media/playback-url`
- remove Home feed playback URL attachment
- optionally keep compatibility aliases temporarily, then delete

Exit condition:

- one public playback API remains

## 9. Risks

### Identity Migration Risk

If the team forces Home direct uploads into fake lesson semantics, the final model may become more confusing than the current one. The canonical identity must live at the reference layer, not be simulated through misleading lesson placeholders.

### Stability Regression Risk

If Home loses its curated read model and becomes dependent on richer client-side resolution, it may lose the very property that kept it stable.

### Auth Drift Risk

Home and lesson access rules are similar in structure but not identical. The final reference layer must carry enough context to let the canonical playback service authorize correctly per source surface.

### Legacy Compatibility Risk

Some Home and legacy lesson items still depend on `media_object` or direct storage fallback. Removing those paths too early would break working playback.

### Performance Risk

If storage existence is verified too early or too broadly, feed queries could become hot-path bottlenecks. Verification belongs at playback issuance for the final chosen object, not across all feed rows.

### Contract Migration Risk

The frontend currently expects different shapes for Home and lesson playback. The migration should keep compatibility shims until both surfaces are on the canonical contract.

## 10. Recommended Next Implementation Step

The next implementation phase should be:

**Build the canonical playback facade and identity mapping layer before changing Home UI behavior.**

Concretely, the next phase should do four things in order:

1. Define the canonical reference-layer runtime id contract.
2. Implement `POST /api/media/playback` on top of a generalized resolver that can serve both lesson and Home references.
3. Add a backend-only compatibility mapping so Home items can be represented by the canonical reference layer without yet changing the Home UI.
4. Only after parity is proven, change `/home/audio` to emit canonical ids and playability metadata instead of URLs and storage ids.

This sequence is the safest because it preserves the Home player’s stability during migration while moving all runtime playback authority into the Control Plane.

## Appendix: Convergence Rules

### What Must Survive From Home

- curated backend read model per runtime surface
- deterministic playability gating
- simple frontend contract
- explicit curation and ownership rules
- narrow Home UI surface

### What Must Survive From the Current Control Plane

- canonical resolver
- structured failure reasons
- centralized storage selection
- centralized auth
- legacy fallback containment
- derived audio invariant

### What Must Be Eliminated

- public use of `media_asset.id` as a playback id
- public use of `media_object.id` as a playback id
- Home feed-attached playback URLs
- multiple public playback endpoints for the same user surface
