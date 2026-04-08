# Auth + Onboarding Baseline Contract

## STATUS

ACTIVE

This contract defines the exact physical baseline objects required for canonical Auth + Onboarding behavior.
This contract composes with:

- `auth_onboarding_contract.md`
- `onboarding_teacher_rights_contract.md`
- `profile_projection_contract.md`

## 1. REQUIRED OBJECTS

The following physical objects are required:

- schema `auth`
- table `auth.users`
- table `app.auth_subjects`
- table `app.profiles`
- table `app.refresh_tokens`
- table `app.auth_events`
- table `app.admin_bootstrap_state`
- function `app.bootstrap_first_admin(target_user_id uuid)`

## 2. REQUIRED OBJECT SEMANTICS

### `auth.users`

- owns identity, credentials, and canonical email-verification truth
- is external auth substrate, not business-domain projection

### `app.auth_subjects`

- owns:
  - `onboarding_state`
  - `role_v2`
  - `role`
  - `is_admin`

### `app.profiles`

- owns only:
  - `user_id`
  - `display_name`
  - `bio`
  - `avatar_media_id`
  - `created_at`
  - `updated_at`

### `app.refresh_tokens`

- required minimum fields:
  - `jti`
  - `user_id`
  - `token_hash`
  - `issued_at`
  - `expires_at`
  - `last_used_at`
  - `rotated_at`
  - `revoked_at`
- owns refresh-token persistence, rotation lineage, and revocation state

### `app.auth_events`

- required minimum fields:
  - `event_id`
  - `actor_user_id`
  - `subject_user_id`
  - `event_type`
  - `metadata`
  - `created_at`
- owns canonical audit/event persistence for Auth + Onboarding mutations

Required event families:

- `admin_bootstrap_consumed`
- `onboarding_completed`
- `teacher_role_granted`
- `teacher_role_revoked`

### `app.admin_bootstrap_state`

- owns one-time first-admin bootstrap availability
- MUST support exactly one logical bootstrap key for the first-admin grant
- MUST record whether bootstrap has been consumed

### `app.bootstrap_first_admin(target_user_id uuid)`

- is the only canonical mutation surface for establishing the first admin
- is operator-controlled only
- MUST set `app.auth_subjects.is_admin = true` for an existing `auth.users.id`
- MUST mark bootstrap as consumed in `app.admin_bootstrap_state`
- MUST record `admin_bootstrap_consumed` in `app.auth_events`
- MUST NOT be exposed as a public app-runtime route

## 3. OPTIONAL OBJECTS

The following remain optional for Auth + Onboarding:

- additional indexes that do not redefine authority
- additional views that do not redefine authority
- storage substrate required only by a separate media contract

## 4. FORBIDDEN OBJECTS AND DEPENDENCIES

The following are forbidden as Auth + Onboarding requirements:

- `app.certificates`
- `app.teacher_approvals`
- any `teacher_request` or pending teacher-queue table
- a persisted `photo_url` field in `app.profiles`
- `app.media_objects` or any avatar/media table as a prerequisite for Auth + Onboarding alignment
- runtime schema introspection as a replacement for baseline truth

## 5. FINAL ASSERTION

- Auth + Onboarding baseline truth is limited to the objects named in this contract.
- Any implementation dependency outside this set is either optional by explicit contract or drift.
