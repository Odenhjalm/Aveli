# T02 Create-Profile Surface Decision

## STATUS

RATIFIED
NO-CODE DECISION GATE

## PURPOSE

This document ratifies the resolved no-code decision for the canonical
create-profile execution surface and ownership split in the target onboarding
model.

This document exists to lock the create-profile step before any active
contract rewrite, backend rewrite, frontend rewrite, or test rewrite begins.

## VERIFIED CURRENT DRIFT

- Current repo truth does not define a dedicated onboarding-owned
  create-profile execution surface.
- Current frontend create-profile flow writes through `/profiles/me`, which is
  projection-only in contract truth.
- Current runtime couples onboarding completion to profile-name presence.
- `POST /auth/onboarding/complete` currently exists as the explicit
  onboarding-completion surface, but it is not the canonical create-profile
  mutation surface.

## LOCKED DECISION

- The canonical create-profile execution surface is
  `POST /auth/onboarding/create-profile`.
- `POST /auth/onboarding/create-profile` is a dedicated onboarding-owned
  auth/onboarding surface.
- `POST /auth/onboarding/complete` remains completion-only.
- `/profiles/me` remains projection-only.
- Create-profile is onboarding-owned and not profile-projection authority.
- Required name is onboarding-required and is persisted to
  `app.profiles.display_name`.
- Optional bio is onboarding-collected and is persisted to `app.profiles.bio`.
- Optional image is handed off to Media authority and is attached only through
  a profile/media boundary.

## CONSEQUENCES

- Active contracts must later define `POST /auth/onboarding/create-profile` as
  the canonical onboarding-owned mutation surface.
- Active contracts must later preserve `/profiles/me` as projection-only and
  must not let it own create-profile authority.
- Active contracts must later preserve `POST /auth/onboarding/complete` as the
  canonical completion-only surface.
- Backend, frontend, and tests must later stop treating profile writes as the
  canonical create-profile execution surface.
- Media authority must later remain separate from onboarding authority even
  when optional create-profile image handling is implemented.

## NEXT CONTRACT IMPACT

- T04 and later contract work must encode create-profile as onboarding-owned,
  completion as separate, and `/profiles/me` as projection-only.
- Later backend, frontend, and test work must align execution paths and
  ownership boundaries to this ratified split.
