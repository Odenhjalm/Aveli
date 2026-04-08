# RCD-001_RUNTIME_ROUTE_AUTHORITY_SYNC

- TYPE: `authority-doc`
- TITLE: `Sync primary runtime-route authority to mounted repo truth`
- DOMAIN: `runtime route authority`

## Problem Statement

`actual_truth/system_runtime_rules.md` is the primary runtime-route authority, but it no longer matches the actively mounted routers in `backend/app/main.py`. The file omits mounted auth, email-verification, profiles, home, `studio.router`, and MCP routers, and it incorrectly states that only `studio.course_lesson_router` and `studio.lesson_media_router` are active from `backend/app/routes/studio.py`.

## Primary Authority Reference

- `actual_truth/system_runtime_rules.md`
- `backend/app/main.py`

## Implementation Surfaces Affected

- `actual_truth/system_runtime_rules.md`
- `backend/app/main.py`
- `backend/app/routes/studio.py`
- `backend/app/routes/auth.py`
- `backend/app/routes/profiles.py`
- `backend/app/routes/email_verification.py`

## DEPENDS_ON

- None

## Acceptance Criteria

- `actual_truth/system_runtime_rules.md` enumerates the currently mounted routers in `backend/app/main.py`.
- The rule file explicitly states that `studio.router` is active because `backend/app/main.py` mounts it.
- The rule file distinguishes mounted runtime truth from unmounted route inventory.
- No route module is treated as active unless it is mounted in `backend/app/main.py`.

## Stop Conditions

- Stop if `backend/app/main.py` has multiple runtime entrypoints with conflicting router mounts.
- Stop if route mounting is performed dynamically outside `backend/app/main.py` in a way that cannot be deterministically audited from repo code.

## Out Of Scope

- Any runtime code change
- Any route removal
- Any endpoint behavior change
