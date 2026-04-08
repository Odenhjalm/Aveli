# PROFILE PROJECTION CONTRACT

## STATUS

ACTIVE

This contract defines the canonical projection-only domain law for `app.profiles`.
This contract operates under `SYSTEM_LAWS.md`.
This contract composes with `auth_onboarding_contract.md` and `onboarding_teacher_rights_contract.md`.

## 1. PRIMARY AUTHORITY STATEMENT

- This file is the PRIMARY AUTHORITY for `app.profiles` projection semantics.
- `app.profiles` is projection-only.
- `app.profiles` is non-authoritative.
- `app.profiles` is a derived projection from canonical auth + subject state.
- If any other contract, plan, or implementation surface assigns authority to `app.profiles`, this file wins for projection-only law.

## 2. CANONICAL SCOPE

This contract defines only:

- projection-only status for `app.profiles`
- allowed projection fields
- forbidden field families
- write boundary
- read surface
- frontend render-only usage
- the rule that profiles MUST NOT be authority anywhere

This contract does not define:

- auth credential truth
- onboarding authority
- role authority
- admin authority
- membership authority
- Stripe authority
- access logic
- execution response-shape law outside the profile projection boundary

## 3. DERIVATION MODEL

- `app.profiles` is a derived read-model relation.
- `app.profiles` is derived from canonical identity/auth truth and canonical subject state.
- `app.profiles` does not create, elevate, or preserve independent domain authority.
- Missing canonical authority MUST NOT be repaired by reading or inferring from `app.profiles`.
- No partial-authority or mixed-authority mode exists for `app.profiles`.

## 4. ALLOWED PROJECTION FIELDS

The only allowed projection fields are:

- `display_name`
- `email`
- `bio`
- `avatar_media_id`

Canonical rules:

- `email` is display-only inside `app.profiles`.
- `email` in `app.profiles` MUST NOT be treated as identity, credential, or access authority.
- No field outside this allowed list may become canonical profile projection truth without an explicit contract change.

## 5. FORBIDDEN FIELDS AND RULE FAMILIES

The following are explicitly forbidden on `app.profiles` as canonical profile projection truth:

- `onboarding_state`
- `role`
- `role_v2`
- `is_admin`
- `is_teacher`
- membership state
- `stripe_customer_id`
- any access logic

Rules:

- Any field outside the allowed projection field list is forbidden as canonical profile projection truth.
- No onboarding, role, admin, teacher-rights, membership, billing, or access semantics may be stored in or derived from `app.profiles`.

## 6. NON-AUTHORITY LAW

- `app.profiles` MUST NOT be used as authority anywhere.
- `app.profiles` MUST NOT be used for onboarding decisions.
- `app.profiles` MUST NOT be used for role, `role_v2`, teacher-rights, or admin evaluation.
- `app.profiles` MUST NOT be used for membership evaluation or app-entry decisions.
- `app.profiles` MUST NOT be used for billing or Stripe decisions.
- `app.profiles` MUST NOT be used for any access logic.
- There is no fallback authority path through `app.profiles`.

## 7. WRITE BOUNDARY

- The write boundary for `app.profiles` is backend only.
- Backend may create, update, or refresh `app.profiles` only as projection maintenance derived from canonical auth + subject state.
- Frontend must not assign semantic meaning to writes against `app.profiles`.
- Direct authority assignment through `app.profiles` is forbidden.

## 8. READ SURFACE

- `/profiles/me` is the canonical current-user read surface for profile projection consumption.
- `/profiles/me` is a projection read surface only.
- `/profiles/me` does not own onboarding, role, membership, billing, or access truth.
- Reading `/profiles/me` MUST NOT be interpreted as reading any authority-bearing state.

## 9. FRONTEND USAGE

- Frontend usage of `app.profiles` is render only.
- Frontend may render only the allowed projection fields.
- Frontend must treat `email` as display-only.
- Frontend must not use `app.profiles` or `/profiles/me` for auth, onboarding, role, membership, billing, or access decisions.
- Frontend must not infer missing authority from profile projection.

## 10. FORBIDDEN PATTERNS

- Treating `app.profiles` as authority.
- Mixing projection fields with onboarding, role, admin, membership, Stripe, or access state.
- Using `email` from `app.profiles` as credential or identity authority.
- Using `app.profiles` as fallback when canonical authority is missing.
- Introducing mixed state or partial authority into `app.profiles`.
- Assigning access behavior from `app.profiles` or `/profiles/me`.

## 11. FINAL ASSERTION

- This contract is the canonical projection-only domain contract for `app.profiles`.
- `app.profiles` is projection-only, non-authoritative, and derived from auth + subject state.
- The only allowed projection fields are `display_name`, `email`, `bio`, and `avatar_media_id`.
- Profiles MUST NOT be used as authority anywhere.
