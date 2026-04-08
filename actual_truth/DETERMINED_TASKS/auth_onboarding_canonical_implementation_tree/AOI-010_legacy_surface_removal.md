# AOI-010 LEGACY SURFACE REMOVAL

TYPE: `OWNER`  
TASK_TYPE: `LEGACY_REMOVAL`  
DEPENDS_ON: `["AOI-004", "AOI-005", "AOI-006", "AOI-007", "AOI-008", "AOI-009"]`

## Goal

Remove forbidden legacy Auth + Onboarding surfaces and hidden authority sources after canonical replacements exist.

## Removal Set

- `/admin/teacher-requests/*`
- teacher-request UI and pending-state assumptions
- `app.certificates` and `app.teacher_approvals` as auth/onboarding dependencies
- `/profiles/me/avatar`
- `/api/upload/profile`
- `/auth/change-password`
- legacy onboarding-state families beyond `incomplete` and `completed`
- auth referral coupling

## Exit Criteria

- no forbidden canonical-scope routes remain mounted or consumed
- no legacy hidden authority remains in backend, frontend, or scripts
- no deferred avatar/media work was introduced while removing legacy surfaces
