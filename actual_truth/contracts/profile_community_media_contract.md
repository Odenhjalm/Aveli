# PROFILE COMMUNITY MEDIA CONTRACT

## STATUS

ACTIVE

## 1. Canonical Authority Statement

This document is the active structured canonical contract for the profile/community media domain.

This contract operates under `SYSTEM_LAWS.md`.

This contract defines:

- feature-specific authored-placement truth for profile/community media
- the domain-owned relation from profile-media placements into canonical runtime projection
- feature-local publication and purpose law for profile/community media

This contract does not define:

- cross-domain media doctrine
- frontend media representation doctrine
- execution response-shape law

## 2. Canonical Scope

This contract covers only:

- feature-specific authored placement truth for profile/community media
- the domain relation from profile-media placement truth into canonical runtime projection
- mounted profile/community feature-source semantics

This contract does not redefine:

- media identity ownership in `app.media_assets`
- lesson-media authored placement ownership
- memberships
- learner-content authority
- storage as source-of-truth
- canonical frontend media representation

## 3. Canonical Feature Entity

The canonical feature entity is:

- `app.profile_media_placements`

`app.profile_media_placements` is the only authored-placement source entity for the profile/community media feature domain under this contract.

Profile and community surfaces do not define separate source-truth entities in this contract.

## 4. Canonical Subject Binding

`app.profile_media_placements` uses:

- `subject_user_id`

`subject_user_id` is a soft external subject reference aligned to the canonical subject identity carried by `auth_subjects.user_id`.

`auth_subjects` does not own profile/community media feature authority and does not replace `app.profile_media_placements` as the feature source entity.

## 5. Minimum Canonical Source Fields

The minimum contract-owned fields on `app.profile_media_placements` are:

- source row identity
- `subject_user_id`
- `media_asset_id`
- `visibility`

Additional feature-local fields may exist only if they do not create a second feature-source path.

## 6. Publication State Model

The canonical publication field is:

- `visibility`

Allowed values:

- `draft`
- `published`

Canonical invariants:

- `visibility` is required
- `visibility` has no implicit default
- invalid input must fail explicitly
- only `published` rows may contribute canonical runtime projection for this feature
- `visibility` does not define runtime readiness
- `visibility` does not define access authority

No visibility rule may be interpreted as permission for raw table access.

## 7. Canonical Media Purpose

The canonical profile/community media purpose value is:

- `profile_media`

No separate `community_media` purpose value exists under this contract.

## 8. Runtime Relation

The domain-owned profile/community placement relation is:

- `app.profile_media_placements`
- canonical runtime projection under `SYSTEM_LAWS.md`

Canonical invariants:

- `app.profile_media_placements` is authored-placement truth only
- only `published` profile-media placements may contribute canonical runtime projection
- no direct application write path may target `runtime_media`
- profile/community surfaces do not create a second feature-source domain

## 9. Mounted Surface Dependency Rule

If mounted profile or community surfaces expose governed media:

- they must consume canonical runtime projection under `SYSTEM_LAWS.md`
- they must not create a second feature-source domain
- they must not read storage-native truth directly

This contract defines no frontend media payload shape.

## 10. Forbidden Legacy Fields And Truth Patterns

The following are forbidden as canonical source truth for profile/community media:

- `cover_image_url`
- `asset_url`
- `storage_path`
- `storage_bucket`
- metadata-blob truth
- map-based identity
- compatibility fallback payloads
- direct storage-object truth

## 11. Baseline And Feature Boundary

Profile/community media remains a non-core feature domain.

Baseline core does not own `app.profile_media_placements` directly.

Any baseline evolution that supports this contract must be append-only and must attach the profile/community media feature above baseline core without mutating canonical core entities into profile/community media owners.

## 12. Final Assertion

This contract preserves one feature-source domain for profile/community media.

It is valid only if future implementation preserves these laws:

- feature source truth remains in `app.profile_media_placements`
- only `published` rows contribute canonical runtime projection for this feature
- no second feature-source domain appears
- no legacy source-truth fields survive as canonical profile/community media truth
