# Auth + Onboarding Contract

## STATUS

ACTIVE

This contract defines the canonical Auth + Onboarding execution surface.
This contract composes with:

- `onboarding_teacher_rights_contract.md`
- `profile_projection_contract.md`
- `referral_membership_grant_contract.md`
- `auth_onboarding_failure_contract.md`
- `auth_onboarding_baseline_contract.md`

## 1. CONTRACT LAW

- `auth.users` is the only identity and credential authority.
- `app.auth_subjects` is the only onboarding, non-admin role, and admin-override authority.
- `app.profiles` is projection-only and non-authoritative.
- Contracts under `actual_truth/contracts/` are the only truth for Auth + Onboarding.
- Runtime schema introspection, frontend claims, tests, legacy routes, and remote runtime state MUST NOT redefine authority.
- Membership, commerce, referral redemption, and binary media handling remain outside Auth + Onboarding except where this contract names an explicit boundary.

## 2. AUTHORITY MODEL

- `auth.users` owns:
  - identity creation
  - authentication
  - credential truth
  - canonical email identity
  - canonical email-verification state
- `app.auth_subjects` owns:
  - `onboarding_state`
  - `role_v2`
  - `role`
  - `is_admin`
- `app.profiles` remains projection-only and is governed by `profile_projection_contract.md`.
- `POST /auth/onboarding/complete` is the single canonical onboarding-completion authority.
- First-admin bootstrap is operator-controlled only and has no app-runtime route.
- Teacher role assignment and revocation are admin-only and are limited to the canonical routes in this contract.
- `photo_url` is read composition only and never write authority.
- `referral_code` remains forbidden on `POST /auth/register`.

## 3. CANONICAL ENTRYPOINTS

- Registration: `POST /auth/register`
- Login: `POST /auth/login`
- Forgot password: `POST /auth/forgot-password`
- Reset password: `POST /auth/reset-password`
- Refresh token: `POST /auth/refresh`
- Send verification: `POST /auth/send-verification`
- Verify email: `GET /auth/verify-email`
- Validate invite: `GET /auth/validate-invite`
- Onboarding completion: `POST /auth/onboarding/complete`
- Current profile read: `GET /profiles/me`
- Current profile update: `PATCH /profiles/me`
- Grant teacher role: `POST /admin/users/{user_id}/grant-teacher-role`
- Revoke teacher role: `POST /admin/users/{user_id}/revoke-teacher-role`

Entrypoint responsibilities:

- `/auth/*` owns credential, token, email-verification, and onboarding-completion execution.
- `/profiles/me` owns current-user projection read and editable profile text fields only.
- `/admin/users/*` owns admin-only teacher-role mutation only.

## 4. REQUEST CONTRACTS

- `POST /auth/register`
  - Request shape: `{ "email": string, "password": string, "display_name": string, "invite_token"?: string }`
  - Required fields:
    - `email`
    - `password`
    - `display_name`
  - Forbidden fields:
    - `referral_code`
- `POST /auth/login`
  - Request shape: `{ "email": string, "password": string }`
  - Required fields:
    - `email`
    - `password`
- `POST /auth/forgot-password`
  - Request shape: `{ "email": string }`
  - Required fields:
    - `email`
- `POST /auth/reset-password`
  - Request shape: `{ "token": string, "new_password": string }`
  - Required fields:
    - `token`
    - `new_password`
- `POST /auth/refresh`
  - Request shape: `{ "refresh_token": string }`
  - Required fields:
    - `refresh_token`
- `POST /auth/send-verification`
  - Request shape: `{ "email": string }`
  - Required fields:
    - `email`
- `GET /auth/verify-email`
  - Request shape: query parameter `token`
  - Required fields:
    - `token`
- `GET /auth/validate-invite`
  - Request shape: query parameter `token`
  - Required fields:
    - `token`
- `POST /auth/onboarding/complete`
  - No request body.
- `GET /profiles/me`
  - No request body.
- `PATCH /profiles/me`
  - Request shape: `{ "display_name"?: string, "bio"?: string }`
  - Forbidden fields:
    - `photo_url`
    - `avatar_media_id`
    - `onboarding_state`
    - `role`
    - `role_v2`
    - `is_admin`
    - `membership_active`
    - `is_teacher`
    - `referral_code`
- `POST /admin/users/{user_id}/grant-teacher-role`
  - No request body.
- `POST /admin/users/{user_id}/revoke-teacher-role`
  - No request body.

## 5. SUCCESS RESPONSE CONTRACTS

- `POST /auth/register`
  - Response shape: `{ "access_token": string, "token_type": "bearer", "refresh_token": string }`
  - Required fields:
    - `access_token`
    - `token_type`
    - `refresh_token`
- `POST /auth/login`
  - Response shape: `{ "access_token": string, "token_type": "bearer", "refresh_token": string }`
  - Required fields:
    - `access_token`
    - `token_type`
    - `refresh_token`
- `POST /auth/forgot-password`
  - Response shape: `{ "status": "ok" }`
- `POST /auth/reset-password`
  - Response shape: `{ "status": "password_reset" }`
- `POST /auth/refresh`
  - Response shape: `{ "access_token": string, "token_type": "bearer", "refresh_token": string }`
  - Required fields:
    - `access_token`
    - `token_type`
    - `refresh_token`
- `POST /auth/send-verification`
  - Response shape: `{ "status": "ok" }`
- `GET /auth/verify-email`
  - Response shape: `{ "status": "verified" }` or `{ "status": "already_verified" }`
- `GET /auth/validate-invite`
  - Response shape: `{ "status": "valid", "email": string }`
- `POST /auth/onboarding/complete`
  - Response shape: `{ "status": "completed", "onboarding_state": "completed", "token_refresh_required": true }`
  - Required fields:
    - `status`
    - `onboarding_state`
    - `token_refresh_required`
- `GET /profiles/me`
  - Response shape: `{ "user_id": string, "email": string, "display_name"?: string, "bio"?: string, "photo_url"?: string, "avatar_media_id"?: string, "created_at": string, "updated_at": string }`
  - Forbidden response fields:
    - `membership_active`
    - `is_teacher`
    - `role`
    - `role_v2`
    - `is_admin`
    - `onboarding_state`
- `PATCH /profiles/me`
  - Response shape matches `GET /profiles/me`
- `POST /admin/users/{user_id}/grant-teacher-role`
  - Response: `204 No Content`
- `POST /admin/users/{user_id}/revoke-teacher-role`
  - Response: `204 No Content`

All non-2xx responses on owned surfaces are governed only by `auth_onboarding_failure_contract.md`.

## 6. ONBOARDING COMPLETION LAW

- `POST /auth/onboarding/complete` is the only canonical transition surface for `incomplete -> completed`.
- Onboarding completion is explicit-action-derived only.
- `PATCH /profiles/me` MUST NOT mutate onboarding state.
- Email verification, referral transport, membership state, webhooks, and profile projection writes MUST NOT implicitly complete onboarding.
- `app.auth_subjects.onboarding_state` owns the persisted transition.
- `completed -> completed` is allowed as an idempotent success.
- The completion route does not mint new tokens.
- After a successful completion response, the client must call `POST /auth/refresh` before relying on refreshed auth context.

## 7. ADMIN BOOTSTRAP BOUNDARY

- The first admin is established only through the operator-controlled bootstrap defined by `auth_onboarding_baseline_contract.md`.
- No public app-runtime route exists for mutating `is_admin`.
- After bootstrap, `is_admin` remains operator-controlled only.
- Tests, seeds, frontend flows, and legacy routes MUST NOT create admin authority.

## 8. TEACHER ROLE BOUNDARY

- No teacher-request lifecycle exists.
- No pending or request state exists for teacher rights.
- Teacher role may be assigned only through `POST /admin/users/{user_id}/grant-teacher-role`.
- Teacher role may be revoked only through `POST /admin/users/{user_id}/revoke-teacher-role`.
- Teacher role state remains owned by `app.auth_subjects` under `onboarding_teacher_rights_contract.md`.

## 9. PROFILE AND REFERRAL BOUNDARY

- Profile projection semantics are governed only by `profile_projection_contract.md`.
- `photo_url` on `/profiles/me` is read composition only.
- Auth + Onboarding routes MUST NOT own referral redemption.
- `referral_code` remains transport-only pre-redemption context under `referral_membership_grant_contract.md`.
- `POST /auth/register` MUST continue to reject `referral_code`.

## 10. FORBIDDEN PATTERNS

- `/auth/me` as canonical current-user authority.
- `/auth/change-password` as canonical Auth + Onboarding authority.
- `/auth/request-password-reset` as canonical password-reset initiation.
- `/profiles/me/avatar`
- `/api/upload/profile`
- `/admin/teacher-requests/*`
- `/admin/teachers/*`
- Accepting `referral_code` on `POST /auth/register`.
- Any profile-derived onboarding completion.
- Any certificate-, approval-, or queue-based teacher-role authority.
- Any fallback authority through runtime schema introspection.

## 11. FINAL ASSERTION

- This contract is the canonical Auth + Onboarding execution contract.
- Contract truth is separate from implementation state.
- The canonical surface is now closed enough to drive deterministic implementation planning.
