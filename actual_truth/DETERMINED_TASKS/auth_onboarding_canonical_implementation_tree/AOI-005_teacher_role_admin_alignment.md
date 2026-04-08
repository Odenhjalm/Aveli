# AOI-005 TEACHER ROLE ADMIN ALIGNMENT

TYPE: `OWNER`  
TASK_TYPE: `BACKEND_ALIGNMENT`  
DEPENDS_ON: `["AOI-001", "AOI-002", "AOI-003"]`

## Goal

Replace legacy teacher-request authority with admin-only teacher-role grant and revoke routes.

## Required Outputs

- `POST /admin/users/{user_id}/grant-teacher-role`
- `POST /admin/users/{user_id}/revoke-teacher-role`
- `role_v2` as truth and `role` as mirror only
- `teacher_role_granted` and `teacher_role_revoked` auth events
- revocation of target user refresh tokens after role change

## Forbidden

- teacher-request lifecycle
- pending teacher state
- `app.certificates` or `app.teacher_approvals` as role authority
- admin-as-teacher shortcuts

## Exit Criteria

- teacher-role mutation is admin-only
- no request/queue semantics remain
- role change authority is fully owned by `app.auth_subjects`
