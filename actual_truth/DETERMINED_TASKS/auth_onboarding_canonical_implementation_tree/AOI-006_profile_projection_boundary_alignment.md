# AOI-006 PROFILE PROJECTION BOUNDARY ALIGNMENT

TYPE: `OWNER`  
TASK_TYPE: `BACKEND_ALIGNMENT`  
DEPENDS_ON: `["AOI-003"]`

## Goal

Align backend profile surfaces to the projection-only contract.

## Required Outputs

- `PATCH /profiles/me` writes only `display_name` and `bio`
- `/profiles/me` remains projection-only
- `photo_url` is read composition only
- `avatar_media_id` remains persisted projection only

## Forbidden

- any avatar upload implementation task
- writable `photo_url`
- profile-owned onboarding, role, admin, or membership state

## Exit Criteria

- backend profile writes cannot create domain authority
- no Auth + Onboarding surface owns avatar upload behavior
- deferred avatar/media work remains out of scope
