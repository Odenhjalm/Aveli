# MEDIA_UNIFIED_AUTHORITY CONTRACT

## STATUS

ACTIVE ALIGNMENT CONTRACT

This contract operates under `SYSTEM_LAWS.md` and `media_pipeline_contract.md`.
This file is subordinate to `SYSTEM_LAWS.md` and
`actual_truth/contracts/baseline_v2_authority_freeze_contract.md`.

Cross-domain media doctrine is defined by `SYSTEM_LAWS.md`; this file aligns
media authority classes for domain contracts.

Lesson-media ingest, placement, lifecycle, and lesson-media pipeline law are
defined by `media_pipeline_contract.md`.

## 1. SOURCE TRUTH

Media source truth is owned by canonical source tables:

- `app.media_assets` owns media identity and lifecycle.
- `app.lesson_media` owns lesson-media authored placement.
- `app.home_player_uploads` owns direct home-player upload inclusion.
- `app.home_player_course_links` owns course-linked home-audio inclusion.
- `app.profile_media_placements` owns profile/community authored placement.

Source tables own inclusion and placement truth. Projection/read surfaces must
not become source truth.

## 2. RUNTIME READ PROJECTION

`app.runtime_media` is read-only projection authority where in scope.

`runtime_media` is not source truth. No direct application write path may target
`runtime_media`.

If projection/read state and canonical source truth disagree, source truth wins
and runtime must fail closed rather than invent fallback authority.

## 3. BACKEND COMPOSITION

Backend composition owns final read representation for governed media output.

Frontend-facing governed media representation remains:

```text
media = { media_id, state, resolved_url } | null
```

Frontend surfaces are render-only. They must not resolve, construct, infer, or
normalize media truth.

## 4. HOME PLAYER COURSE-LINK BOUNDARY

`app.home_player_course_links` is canonical source truth for course-linked home
audio inclusion.

Backend aggregation/composition is read authority for course-linked home-audio
output.

`runtime_media` remains read-only projection authority where in scope, but is
not the source table for `app.home_player_course_links`.

This boundary is not an alternate playback truth. It is the approved
source/read separation for the course-linked home-audio path.

## 5. FORBIDDEN MEDIA AUTHORITY

The following are forbidden:

- direct writes to `runtime_media`
- treating projection drift as source truth
- frontend media resolution or access inference
- direct storage delivery as media truth
- storage paths, signed URLs, object URLs, download URLs, or preview URLs as
  canonical media truth
- alternate playback truth outside the accepted source-to-read authority model
- fallback media authority when canonical source/read truth is missing

## 6. FINAL ASSERTION

This contract aligns media source truth, runtime read projection, and backend
composition for Baseline V2.

It does not authorize SQL, baseline slot generation, runtime code edits,
database mutation, runtime mutation, DAG planning, tasktree planning, or
implementation steps.
