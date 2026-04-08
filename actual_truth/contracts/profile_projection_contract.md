# Profile Projection Contract

## STATUS

ACTIVE

This contract defines the canonical projection-only law for `app.profiles`.
This contract composes with:

- `auth_onboarding_contract.md`
- `onboarding_teacher_rights_contract.md`
- `auth_onboarding_baseline_contract.md`

## 1. PRIMARY AUTHORITY STATEMENT

- This file is the PRIMARY AUTHORITY for `app.profiles` projection semantics.
- `app.profiles` is projection-only.
- `app.profiles` is non-authoritative.
- `app.profiles` MUST NOT create, elevate, or repair domain authority.

## 2. CANONICAL SCOPE

This contract defines:

- allowed persisted projection fields
- frontend write boundary
- read-composition rules
- forbidden profile authority patterns

This contract does not define:

- identity truth
- onboarding authority
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
- No field outside this list may become profile truth without explicit contract change.

## 4. WRITE BOUNDARY

- `PATCH /profiles/me` is the only frontend write surface in this contract.
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
- Backend may maintain `app.profiles` only as projection maintenance derived from canonical authority.
- This contract does not authorize a dedicated avatar upload surface.

## 5. READ SURFACE

- `GET /profiles/me` is the canonical current-user projection read surface.
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
- `photo_url` MUST be derived from canonical avatar identity when such identity is available.
- `photo_url` may be absent when no canonical avatar identity is available.

## 6. NON-AUTHORITY LAW

- `app.profiles` MUST NOT be used for onboarding decisions.
- `app.profiles` MUST NOT be used for role, teacher-rights, or admin evaluation.
- `app.profiles` MUST NOT be used for membership, billing, or access decisions.
- There is no fallback authority path through `app.profiles`.

## 7. FORBIDDEN PATTERNS

- Treating `photo_url` as writable authority.
- Treating `avatar_media_id` as user-owned semantic authority.
- Using `/profiles/me/avatar` as canonical Auth + Onboarding authority.
- Using `/api/upload/profile` as canonical Auth + Onboarding authority.
- Introducing binary avatar/media work into Auth + Onboarding implementation planning.
- Using `app.profiles` to infer missing authority.

## 8. FINAL ASSERTION

- `app.profiles` is projection-only and non-authoritative.
- `photo_url` is read composition only.
- `avatar_media_id` is the only canonical persisted avatar identity field in `app.profiles`.
