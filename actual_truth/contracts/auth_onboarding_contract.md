# Auth + Onboarding Contract

## STATUS

ACTIVE

This contract defines the canonical Auth + Onboarding execution surface.
This contract composes with:

- `onboarding_entry_authority_contract.md`
- `onboarding_teacher_rights_contract.md`
- `profile_projection_contract.md`
- `referral_membership_grant_contract.md`
- `auth_onboarding_failure_contract.md`
- `auth_onboarding_baseline_contract.md`

## 1. CONTRACT LAW

- `auth.users` is the only identity and credential authority.
- `app.auth_subjects` is the canonical application subject authority for:
  - onboarding subject state
  - app-level role subject fields
  - app-level admin subject fields
- `app.profiles` is projection-only and non-authoritative.
- `POST /auth/onboarding/create-profile` is the canonical onboarding-owned
  create-profile surface.
- `POST /auth/onboarding/complete` is the canonical onboarding-completion
  surface.
- Contracts under `actual_truth/contracts/` are the only truth for Auth +
  Onboarding.
- Membership, commerce, referral redemption, and binary media handling remain
  outside Auth + Onboarding except where this contract names an explicit
  boundary.
- Post-auth routing authority is delegated to
  `onboarding_entry_authority_contract.md` through `GET /entry-state`.

## 2. AUTHORITY MODEL

- `auth.users` owns identity creation, authentication, credential truth,
  canonical email identity, and canonical email-verification state.
- `app.auth_subjects` owns `onboarding_state`, `role_v2`, `role`, and
  `is_admin`.
- `app.profiles` remains projection-only and is governed by
  `profile_projection_contract.md`.
- `POST /auth/onboarding/create-profile` owns onboarding-step execution for
  required name plus optional bio input.
- Optional image input at create-profile is media-mediated only and MUST NOT
  move media authority into Auth + Onboarding.
- `POST /auth/onboarding/complete` is the single canonical onboarding
  transition authority.
- First-admin bootstrap is operator-controlled only and has no app-runtime
  route.
- Teacher role assignment and revocation are admin-only and are limited to the
  canonical routes in this contract.

## 3. CANONICAL ENTRYPOINTS

This section lists Auth + Onboarding execution surfaces only. It does not
define post-auth entry authority. Post-auth routing must use delegated
`GET /entry-state` under `onboarding_entry_authority_contract.md`.

- Registration: `POST /auth/register`
- Login: `POST /auth/login`
- Forgot password: `POST /auth/forgot-password`
- Reset password: `POST /auth/reset-password`
- Refresh token: `POST /auth/refresh`
- Send verification: `POST /auth/send-verification`
- Verify email: `GET /auth/verify-email`
- Create profile: `POST /auth/onboarding/create-profile`
- Onboarding completion: `POST /auth/onboarding/complete`
- Current profile projection read: `GET /profiles/me`
- Current profile projection update: `PATCH /profiles/me`
- Delegated post-auth routing: `GET /entry-state`
- Grant teacher role: `POST /admin/users/{user_id}/grant-teacher-role`
- Revoke teacher role: `POST /admin/users/{user_id}/revoke-teacher-role`

Entrypoint responsibilities:

- `/auth/*` owns credential, token, email-verification, and onboarding
  execution surfaces.
- Successful registration creates identity and token transport only. It does
  not guarantee create-profile routing, app-entry, membership, onboarding
  completion, or any post-auth route.
- After registration or login, post-auth routing is governed only by
  `GET /entry-state` plus the Post-Auth Routing Precedence rule in
  `onboarding_entry_authority_contract.md`.
- For ordinary self-signup, checkout is required before create-profile:
  register -> checkout -> create-profile -> welcome -> onboarding-complete -> app.
- `POST /auth/onboarding/create-profile` owns the onboarding step that captures
  required name and optional bio while remaining non-authoritative for
  routing.
- `POST /auth/onboarding/create-profile` MUST NOT own binary image upload or
  media lifecycle authority.
- `/profiles/me` owns current-user projection read and editable profile text
  fields only.
- `/profiles/me` MUST NOT be used for create-profile authority, routing,
  bootstrap, or entry decision.
- `/admin/users/*` owns admin-only teacher-role mutation only.

## 4. REQUEST CONTRACTS

- `POST /auth/register`
  - Request shape: `{ "email": string, "password": string }`
  - Required fields:
    - `email`
    - `password`
  - Forbidden fields:
    - `display_name`
    - `invite_token`
    - `referral_code`
- `POST /auth/login`
  - Request shape: `{ "email": string, "password": string }`
- `POST /auth/forgot-password`
  - Request shape: `{ "email": string }`
- `POST /auth/reset-password`
  - Request shape: `{ "token": string, "new_password": string }`
- `POST /auth/refresh`
  - Request shape: `{ "refresh_token": string }`
- `POST /auth/send-verification`
  - Request shape: `{ "email": string }`
- `GET /auth/verify-email`
  - Request shape: query parameter `token`
- `POST /auth/onboarding/create-profile`
  - Request shape: `{ "display_name": string, "bio"?: string }`
  - Required fields:
    - `display_name`
  - Forbidden fields:
    - `photo_url`
    - `avatar_media_id`
    - onboarding fields
    - role fields
    - admin fields
    - membership fields
    - referral fields
    - binary media payload fields
- `POST /auth/onboarding/complete`
  - No request body.
  - Invoked only by explicit confirmation on the welcome step.
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

## 5. SUCCESS RESPONSE CONTRACTS

- `POST /auth/register`
  - Response shape:
    `{ "access_token": string, "token_type": "bearer", "refresh_token": string }`
- `POST /auth/login`
  - Response shape:
    `{ "access_token": string, "token_type": "bearer", "refresh_token": string }`
- `POST /auth/forgot-password`
  - Response shape: `{ "status": "ok" }`
- `POST /auth/reset-password`
  - Response shape: `{ "status": "password_reset" }`
- `POST /auth/refresh`
  - Response shape:
    `{ "access_token": string, "token_type": "bearer", "refresh_token": string }`
- `POST /auth/send-verification`
  - Response shape: `{ "status": "ok" }`
- `GET /auth/verify-email`
  - Response shape:
    `{ "status": "verified" }` or `{ "status": "already_verified" }`
- `POST /auth/onboarding/create-profile`
  - Response shape matches `GET /profiles/me`
- `POST /auth/onboarding/complete`
  - Response shape:
    `{ "status": "completed", "onboarding_state": "completed", "token_refresh_required": true }`
- `GET /profiles/me`
  - Response shape:
    `{ "user_id": string, "email": string, "display_name"?: string, "bio"?: string, "photo_url"?: string, "avatar_media_id"?: string, "created_at": string, "updated_at": string }`
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

All non-2xx responses on owned surfaces are governed only by
`auth_onboarding_failure_contract.md`.

## 6. CREATE-PROFILE LAW

- `POST /auth/onboarding/create-profile` is the only canonical onboarding-owned
  create-profile surface.
- Required name belongs at create-profile and MUST NOT be required by
  `POST /auth/register`.
- Optional bio may be collected at create-profile and persisted to
  `app.profiles.bio`.
- Optional image at create-profile is media-mediated only and may be attached
  only through the profile/media boundary defined by media contracts.
- `POST /auth/onboarding/create-profile` MUST NOT become profile-projection
  authority, media authority, routing authority, or entry authority.
- Successful create-profile persists required name and optional bio projection
  data and moves `app.auth_subjects.onboarding_state` to `welcome_pending`.
- Successful create-profile does not complete onboarding.

## 7. ONBOARDING COMPLETION LAW

- `POST /auth/onboarding/complete` is the only canonical transition surface for
  `welcome_pending -> completed`.
- Onboarding completion is explicit welcome-confirmation-derived only.
- `POST /auth/onboarding/create-profile` is an onboarding step but does not by
  itself complete onboarding.
- The required welcome confirmation text is exactly:
  `Jag förstår hur Aveli fungerar`.
- `PATCH /profiles/me` MUST NOT mutate onboarding state.
- Email verification, referral transport, referral redemption, membership
  state, webhooks, media writes, and profile projection writes MUST NOT
  implicitly complete onboarding.
- `app.auth_subjects.onboarding_state` owns the persisted transition.
- Onboarding completion MUST NOT be derived from profile-name presence.
- After a successful completion response, the client must call
  `POST /auth/refresh` before relying on refreshed auth context.

## 8. ADMIN BOOTSTRAP BOUNDARY

- The first admin is established only through the operator-controlled bootstrap
  defined by `auth_onboarding_baseline_contract.md`.
- No public app-runtime route exists for mutating `is_admin`.
- After bootstrap, `is_admin` remains operator-controlled only.

## 9. TEACHER ROLE BOUNDARY

- Teacher role may be assigned only through
  `POST /admin/users/{user_id}/grant-teacher-role`.
- Teacher role may be revoked only through
  `POST /admin/users/{user_id}/revoke-teacher-role`.
- Teacher role state remains owned by `app.auth_subjects` under
  `onboarding_teacher_rights_contract.md`.

## 10. PROFILE, REFERRAL, AND MEDIA BOUNDARY

- Profile projection semantics are governed only by
  `profile_projection_contract.md`.
- Auth + Onboarding routes MUST NOT own referral redemption.
- `referral_code` remains transport-only pre-redemption context under
  `referral_membership_grant_contract.md`.
- `POST /auth/register` MUST continue to reject `referral_code`.
- Referral email transport may bring the user into onboarding at the
  create-profile step, but it does not create identity, authenticate a user,
  complete onboarding, or grant membership by itself.
- Referral context is the explicit exception to ordinary self-signup
  checkout-first routing:
  register -> create-profile -> redeem -> welcome -> onboarding-complete -> app.
  The exception is owned by `onboarding_entry_authority_contract.md` routing
  precedence and `referral_membership_grant_contract.md`, not by
  `POST /auth/register`.
- Auth + Onboarding routes MUST NOT own binary media upload authority.

## 11. FORBIDDEN PATTERNS

- `GET /auth/validate-invite`
- Accepting `invite_token` on `POST /auth/register`
- Requiring `display_name` on `POST /auth/register`
- `/auth/me` as canonical current-user authority
- `/profiles/me/avatar`
- `/api/upload/profile`
- Accepting `referral_code` on `POST /auth/register`
- Any profile-derived onboarding completion
- Any create-profile-derived onboarding completion
- Any checkout-derived onboarding completion

## 12. FINAL ASSERTION

- This contract is the canonical Auth + Onboarding execution contract.
- `app.auth_subjects` is the canonical application subject authority for
  onboarding subject state, app-level role subject fields, and app-level admin
  subject fields.
- `POST /auth/onboarding/create-profile` is the canonical onboarding-owned
  create-profile surface.
- `POST /auth/onboarding/complete` is welcome-confirmation completion-only.
- `/profiles/me` is projection-only and remains non-authoritative.
- Post-auth entry authority is owned only by
  `onboarding_entry_authority_contract.md` through `GET /entry-state`.
- Registration is identity-only and never guarantees create-profile routing;
  post-auth routing is delegated to `GET /entry-state` plus canonical routing
  precedence.
