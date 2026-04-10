# Baseline Completion Plan DAG Summary

## Final State

- STATUS: `TASKS_READY`

## Task IDs

- `BCP-010`
- `BCP-011`
- `BCP-012`
- `BCP-013`
- `BCP-014`
- `BCP-020`
- `BCP-021`
- `BCP-022`
- `BCP-023`
- `BCP-024`
- `BCP-030`
- `BCP-031`
- `BCP-032`
- `BCP-033A`
- `BCP-033`
- `BCP-034`
- `BCP-035`
- `BCP-036`
- `BCP-037`
- `BCP-040`
- `BCP-041`
- `BCP-042`
- `BCP-042A`
- `BCP-042AA`
- `BCP-042B`
- `BCP-043A`
- `BCP-043`
- `BCP-044`
- `BCP-050`
- `BCP-051`

## Dependency Graph In Topological Order

1. `BCP-010`
2. `BCP-020`
3. `BCP-030`
4. `BCP-040`
5. `BCP-011`
6. `BCP-021`
7. `BCP-031`
8. `BCP-041`
9. `BCP-012`
10. `BCP-022`
11. `BCP-032`
12. `BCP-033A`
13. `BCP-034`
14. `BCP-042`
15. `BCP-042A`
16. `BCP-042AA`
17. `BCP-042B`
18. `BCP-043A`
19. `BCP-013`
20. `BCP-023`
21. `BCP-033`
22. `BCP-035`
23. `BCP-043`
24. `BCP-014`
25. `BCP-024`
26. `BCP-044`
27. `BCP-036`
28. `BCP-037`
29. `BCP-050`
30. `BCP-051`

## Smallest Safe Execution Entrypoints

- `BCP-010`
- `BCP-020`
- `BCP-030`
- `BCP-040`

Rationale:

- The locked direction is already decided, but the authoritative source set still lacks exact minimum implementation boundaries for `app.memberships`, the canonical auth-subject entity, the DB-surface object map, and the expanded `runtime_media` row model.

## Highest-Risk Tasks

- `BCP-012`
  - Baseline-owned `app.memberships` must be introduced append-only above protected slot `0012` without inventing extra authority fields or reintroducing legacy subscription doctrine.
- `BCP-022`
  - The canonical auth-subject entity must replace authority uses of `app.profiles` without collapsing back into legacy profile logic or violating the external-reference rule for `auth.users`.
- `BCP-032` and `BCP-034`
  - Protected slot `0012` currently expresses raw table grants as the active access boundary, so append-only DB surfaces must supersede that authority cleanly.
- `BCP-033A`
  - Mounted public course reads still bypass the append-only public DB surfaces through raw repository and service composition, so the public-surface gate cannot pass until public runtime alignment lands before `BCP-033`.
- `BCP-042`
  - Protected slot `0008` currently defines lesson-only `runtime_media`, so unified media truth including course cover must be introduced without mutating the protected projection in place.
- `BCP-042A`
  - Canonical documents already place home-player runtime truth under `runtime_media`, but the append-only baseline still lacks home-player runtime rows, so the missing authority must land before `BCP-043`.
- `BCP-042AA`
  - Active contract and mounted runtime still use `app.home_player_course_links` for course-link inclusion, but replay treats the table as optional today and stored `teacher_id` must not be mistaken for course-ownership authority.
- `BCP-042B`
  - The newly active profile-media contract now defines a lawful append-only source and runtime path, but the baseline still lacks `profile_media` purpose coverage, `app.profile_media_placements`, and runtime projection rows for published profile media.
- `BCP-043A`
  - `BCP-043` was over-broad: course cover and home-player can already align to unified `runtime_media`, but profile/community still lacks dependency-valid structured baseline authority.
- `BCP-036`
  - Mounted read paths currently read raw tables in repositories and services, so consumer alignment must avoid partial migrations that leave duplicate authorities mounted.

## Audit Notes That Drive The DAG

- `backend/supabase/baseline_slots.lock.json` protects slots `0001` through `0012`, so baseline evolution must be append-only.
- The protected baseline has no `app.memberships` owner slot even though current runtime code reads and writes `app.memberships`.
- The protected baseline has no separate canonical auth-subject entity; runtime code still reads onboarding and role authority from `app.profiles` and JWT claims.
- Protected slot `0012_canonical_access_policies.sql` grants raw table access on `app.courses`, `app.lessons`, `app.lesson_contents`, `app.lesson_media`, `app.media_assets`, `app.course_enrollments`, and `app.runtime_media`, which conflicts with the locked DB-surface direction.
- Protected slot `0008_runtime_media_projection_core.sql` still defines `app.runtime_media` as a lesson-only ready-state projection and excludes course cover.
- Append-only slot `0017_runtime_media_unified.sql` extends `app.runtime_media` to lesson media and course cover, but still excludes the home-player runtime truth already declared by canonical media law.
- Append-only slot `0018_runtime_media_home_player.sql` extends `app.runtime_media` to home-player direct uploads, but the baseline still lacks the active profile-media source contract and runtime rows required before `BCP-043`.
- Active home-audio contract and mounted runtime still use `app.home_player_course_links` for course-link inclusion, but the append-only baseline has no explicit owner task or locked slot for that substrate and replay treats it as optional.
- `backend/app/services/courses_service.py` still resolves course cover from media-asset and storage-adjacent logic instead of one unified `runtime_media` chain.
- `backend/app/services/home_audio_service.py` and `backend/app/services/courses_service.py` still shape mounted home-player media through direct media-asset playback instead of unified `runtime_media`.
- `backend/app/repositories/courses.py` and `backend/app/services/courses_read_service.py` still build public and protected reads from raw tables rather than canonical DB surfaces.
- `BCP-033` failed on mounted public runtime bypass because `/courses/{course_id}`, `/courses/by-slug/{slug}`, and `/courses/{course_id}/public` still read through raw repository and service paths instead of the public DB surfaces materialized by `BCP-032`.
- `BCP-043` remains blocked for profile/community until append-only baseline authority extends `app.runtime_media` to the active contract-owned profile-media surface.
