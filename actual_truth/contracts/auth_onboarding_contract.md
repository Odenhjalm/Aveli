# Auth + Onboarding Contract

## 1. CONTRACT LAW

- This contract defines the canonical Auth + Onboarding flow, route, and auth-behavior truth.
- Identity authority is owned only by Supabase Auth in `auth.users`.
- Subject authority is owned only by `app.auth_subjects`.
- Profile projection is owned only by `app.profiles`.
- No endpoint or flow outside this document may be used as Auth + Onboarding flow truth.
- No fallback path is allowed.
- No legacy endpoint is allowed.
- Membership, Stripe, and course-access logic are outside this contract.

## 2. AUTHORITY MODEL

- `auth.users` owns identity creation, authentication, credential truth, and canonical email identity.
- `app.profiles` remains projection-only and non-authoritative.
- Persisted `app.profiles` field semantics are governed by `profile_projection_contract.md`.
- `/profiles/me` may expose composed profile read fields, but `email` on that surface comes from `auth.users`, not from `app.profiles`.
- Canonical onboarding and teacher-rights field authority is defined only by `onboarding_teacher_rights_contract.md`.

## 3. CANONICAL ENTRYPOINTS

- Registration: `POST /auth/register`
- Login: `POST /auth/login`
- Forgot password: `POST /auth/forgot-password`
- Reset password: `POST /auth/reset-password`
- Refresh token: `POST /auth/refresh`
- Send verification: `POST /auth/send-verification`
- Verify email: `GET /auth/verify-email`
- Validate invite: `GET /auth/validate-invite`
- Current profile read: `GET /profiles/me`
- Current profile update: `PATCH /profiles/me`
- Teacher approval: `POST /admin/teacher-requests/{user_id}/approve`
- Teacher rejection: `POST /admin/teacher-requests/{user_id}/reject`

Entrypoint responsibilities:

- `/auth/*` owns credential and email-verification flows.
- `/profiles/me` owns current-user profile projection and editable profile fields.
- `/admin/teacher-requests/*` owns teacher-rights assignment decisions.

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
- `GET /profiles/me`
  - No request body.
- `PATCH /profiles/me`
  - Request shape: `{ "display_name"?: string, "bio"?: string, "photo_url"?: string }`
  - Forbidden fields:
    - `membership_active`
    - `is_teacher`
- `POST /admin/teacher-requests/{user_id}/approve`
  - No request body.
- `POST /admin/teacher-requests/{user_id}/reject`
  - No request body.

## 5. RESPONSE CONTRACTS

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
- `GET /profiles/me`
  - Response shape: `{ "user_id": string, "email": string, "display_name"?: string, "bio"?: string, "photo_url"?: string, "avatar_media_id"?: string, "created_at": string, "updated_at": string }`
  - Forbidden response fields:
    - `membership_active`
    - `is_teacher`
- `PATCH /profiles/me`
  - Response shape matches `GET /profiles/me`
- `POST /admin/teacher-requests/{user_id}/approve`
  - Response: `204 No Content`
- `POST /admin/teacher-requests/{user_id}/reject`
  - Response: `204 No Content`

## 6. ONBOARDING FLOW

1. Client calls `POST /auth/register`.
2. Backend creates the identity in `auth.users`.
3. Backend ensures a canonical subject row in `app.auth_subjects`.
4. Backend creates the profile row in `app.profiles`.
5. Backend returns access and refresh tokens.
6. Client may call `POST /auth/login` to authenticate against `auth.users`.
7. Client may call `POST /auth/send-verification`, then `GET /auth/verify-email`.
8. Client reads current profile through `GET /profiles/me`, where email is composed from `auth.users` and profile projection fields come from `app.profiles`.
9. Client updates editable profile fields only through `PATCH /profiles/me`.
10. Admin teacher approval uses `POST /admin/teacher-requests/{user_id}/approve`.
11. Admin teacher rejection uses `POST /admin/teacher-requests/{user_id}/reject`.

## 7. FIELD AUTHORITY POINTER

Canonical onboarding and teacher-rights field authority is defined only by `onboarding_teacher_rights_contract.md`.

This contract defines no field semantics, allowed values, precedence, mutation rules, or fallback behavior for those fields.

## 8. FORBIDDEN PATTERNS

- `/auth/me` as current-user authority.
- `/auth/request-password-reset` as canonical password-reset initiation.
- `/admin/teachers/{user_id}/approve`
- `/admin/teachers/{user_id}/reject`
- Duplicate `api_auth.py` auth surfaces as canonical truth.
- Duplicate `api_profiles.py` profile surfaces as canonical truth.
- Cross-domain Auth + Onboarding fields such as:
  - `membership_active`
  - `is_teacher`

## 9. FRONTEND ALIGNMENT TARGET

- Frontend must use:
  - `POST /auth/register`
  - `POST /auth/login`
  - `POST /auth/forgot-password`
  - `POST /auth/reset-password`
  - `POST /auth/refresh`
  - `POST /auth/send-verification`
  - `GET /auth/verify-email`
  - `GET /auth/validate-invite`
  - `GET /profiles/me`
  - `PATCH /profiles/me`
- Frontend must remove:
  - `/auth/request-password-reset`
  - `/auth/me`

## 10. IMPLEMENTATION DRIFT OUTSIDE CONTRACT

- `backend/app/main.py` does not currently mount the canonical admin teacher-request routes.
- Frontend still references rejected current-user and password-reset paths.
- Auth schema still exposes legacy or extra request/response fields outside the locked contract.
- Tests still assume mixed current-user surfaces.
- Legacy admin frontend calls still target `/admin/teachers/*`.
- Non-Swedish user-facing or runtime text still exists in Auth + Onboarding code paths.

## 11. NO FALLBACK RULE

There is no fallback behavior in Auth + Onboarding.

- No alternative endpoints

## 12. FINAL ASSERTION

- This contract is the canonical Auth + Onboarding flow, route, and auth-behavior truth.
- It is lockable as a contract artifact.
- Contract truth and implementation drift are intentionally separated.
- The contract is ready to drive deterministic implementation task trees.
- The current repo is not yet fully aligned to this contract, but that misalignment is implementation drift, not contract ambiguity.
