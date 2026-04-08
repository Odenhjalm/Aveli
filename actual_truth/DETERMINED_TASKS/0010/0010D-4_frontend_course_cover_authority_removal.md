# 0010D-4

- TASK_ID: `0010D-4`
- TYPE: `OWNER`
- TITLE: `Remove frontend course cover resolution authority`
- DEPENDS_ON:
  - `0010D-3`

## problem_statement

Frontend course surfaces still turn `cover_media_id` into URLs client-side through `course_cover_resolver.dart`, which creates dual authority and allows course cover rendering to diverge from backend read truth.

## target_state

- Active learner/public and studio course surfaces render backend-authored `cover.resolved_url`.
- Frontend course rendering does not sign or resolve course cover URLs from `cover_media_id`.
- `course_cover_resolver.dart` is no longer used by active course surfaces for read-time cover rendering.

## verification_method

- `rg -n "resolveCourseSummaryCoverUrl|resolveCourseCoverUrl|resolveStudioCourseCoverUrl" frontend/lib`
- `rg -n "coverMediaId" frontend/lib/features/courses frontend/lib/features/landing frontend/lib/features/studio frontend/lib/shared`
- Run `dart analyze` or a targeted analyzer command if available.
