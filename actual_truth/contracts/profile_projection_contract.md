# Profile Projection Contract

## STATUS

ACTIVE

This contract defines the canonical projection-only law for `app.profiles`.
This contract composes with:

- `onboarding_entry_authority_contract.md`
- `auth_onboarding_contract.md`
- `onboarding_teacher_rights_contract.md`
- `auth_onboarding_baseline_contract.md`
- `profile_community_media_contract.md`

## 1. PRIMARY AUTHORITY STATEMENT

- This file is the PRIMARY AUTHORITY for `app.profiles` projection semantics.
- `app.profiles` is projection-only.
- `app.profiles` is non-authoritative.
- `app.profiles` MUST NOT create, elevate, or repair domain authority.

## 2. CANONICAL SCOPE

This contract defines:

- allowed persisted projection fields
- projection-owned write boundary
- read-composition rules
- forbidden profile authority patterns

This contract does not define:

- identity truth
- onboarding authority
- post-auth entry authority
- routing authority
- bootstrap dependency
- role authority
- admin authority
- referral redemption
- binary avatar/media upload authority

## 3. ALLOWED PERSISTED FIELDS

The only allowed persisted fields on `app.profiles` are:

- `user_id`
- `display_name`
- `bio`
- `avatar_media_id`
- `created_at`
- `updated_at`

Rules:

- `email` is not persisted profile truth.
- `photo_url` is not a persisted profile field.
- No field outside this list may become profile truth without explicit
  contract change.

## 4. WRITE BOUNDARY

- `PATCH /profiles/me` is the only projection-owned frontend write surface in
  this contract.
- `PATCH /profiles/me` may write only:
  - `display_name`
  - `bio`
- `PATCH /profiles/me` MUST NOT write:
  - `photo_url`
  - `avatar_media_id`
  - onboarding fields
  - role fields
  - admin fields
  - membership fields
  - referral fields
- `POST /auth/onboarding/create-profile` under `auth_onboarding_contract.md`
  may collect required `display_name` and optional `bio` for the onboarding
  step while persisting them to `app.profiles` without transferring authority
  away from onboarding for the step itself.
- Optional image during create-profile is media-mediated only and MUST NOT turn
  `PATCH /profiles/me` into media authority.
- Backend may maintain `app.profiles` only as projection maintenance derived
  from canonical authority.
- This contract does not itself authorize or own a dedicated avatar upload
  surface.
- A dedicated avatar upload or attach surface may be authorized only by the
  media-owned profile/community media boundary.
- Such a surface MUST NOT widen `PATCH /profiles/me` and MUST NOT move binary
  media authority into Auth + Onboarding.

## 5. READ SURFACE

- `GET /profiles/me` is the canonical current-user projection read surface.
- `GET /profiles/me` is projection-only and is not a routing surface.
- `/profiles/me` may expose:
  - `user_id`
  - `email`
  - `display_name`
  - `bio`
  - `avatar_media_id`
  - `photo_url`
  - `created_at`
  - `updated_at`
- `email` on `/profiles/me` MUST come from `auth.users`.
- `photo_url` on `/profiles/me` is read composition only.
- `photo_url` MUST be derived from canonical avatar identity when such identity
  is available.
- `photo_url` may be absent when no canonical avatar identity is available.
- `display_name` may be used only for non-authoritative UX selection after
  `GET /entry-state` has already been evaluated.

## 6. NON-AUTHORITY LAW

- `app.profiles` MUST NOT be used for onboarding decisions.
- `app.profiles` MUST NOT be used for create-profile step authority.
- `app.profiles` MUST NOT be used for role, teacher-rights, or admin
  evaluation.
- `app.profiles` MUST NOT be used for membership, billing, or access decisions.
- `/profiles/me` MUST NOT be used as a bootstrap dependency.
- `/profiles/me` MUST NOT be used as a routing input.
- `/profiles/me` MUST NOT be required before post-auth routing decisions.
- `/profiles/me` MUST NOT repair, infer, replace, or bypass `GET /entry-state`.
- Post-auth routing authority is owned only by
  `onboarding_entry_authority_contract.md`.
- There is no fallback authority path through `app.profiles`.

## 7. FORBIDDEN PATTERNS

- Treating `/profiles/me` as bootstrap truth.
- Treating `/profiles/me` as routing input.
- Treating `/profiles/me` as create-profile authority.
- Treating `photo_url` as writable authority.
- Treating `avatar_media_id` as user-owned semantic authority.
- Using `/profiles/me/avatar` as canonical Auth + Onboarding authority.
- Using `/api/upload/profile` as canonical Auth + Onboarding authority.
- Introducing binary avatar/media work into Auth + Onboarding implementation
  planning.
- Using `app.profiles` to infer missing authority.

## 8. FINAL ASSERTION

- `app.profiles` is projection-only and non-authoritative.
- `/profiles/me` is not a bootstrap dependency, routing input, create-profile
  surface, or entry-decision surface.
- `photo_url` is read composition only.
- `avatar_media_id` is the only canonical persisted avatar identity field in
  `app.profiles`.
- `avatar_media_id` may be maintained only from a validated media-owned avatar
  binding and never as user-owned `/profiles/me` patch authority.
