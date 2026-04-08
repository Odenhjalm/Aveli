# AOC-006_AUTH_TEXT_LANGUAGE_REPLACEMENT

- TYPE: `OWNER`
- TITLE: `Replace remaining non-Swedish Auth + Onboarding user-facing and runtime text on canonical surfaces`
- DOMAIN: `language alignment`
- CLASSIFICATION: `REPLACE`

## Problem Statement

The contract explicitly calls out remaining non-Swedish text in Auth + Onboarding paths as implementation drift. Canonical email subjects, email bodies, and runtime errors still contain English strings.

## Primary Authority Reference

- `actual_truth/contracts/auth_onboarding_contract.md:191-198`
- `actual_truth/Aveli_System_Decisions.md:490`

## Drift Evidence

- `backend/app/services/email_verification.py:15-17` uses English email subjects.
- `backend/app/services/email_verification.py:42` and `backend/app/services/email_verification.py:81` use English email body text.
- `backend/app/routes/auth.py:158`, `202`, and `212` use English runtime details.
- `backend/app/permissions.py:22` and `backend/app/permissions.py:36` use English permission errors.
- `backend/app/routes/profiles.py:24`, `40`, `52`, and `62` use English profile errors.

## Implementation Surfaces Affected

- `backend/app/services/email_verification.py`
- `backend/app/routes/auth.py`
- `backend/app/routes/profiles.py`
- `backend/app/permissions.py`
- `backend/app/email_templates/verify_email.html`
- `backend/app/email_templates/reset_password.html`
- `backend/app/email_templates/invite_email.html`
- `frontend/lib/features/auth/presentation`

## DEPENDS_ON

- `AOC-005`

## Exact Implementation Steps

1. Inventory all remaining Auth + Onboarding user-facing and runtime text on canonical kept surfaces.
2. Replace English strings with Swedish equivalents.
3. Do not localize deleted legacy surfaces; remove them instead.
4. Update tests that assert user-facing text so they lock to the kept Swedish copy.

## Acceptance Criteria

- No English user-facing or runtime text remains in canonical Auth + Onboarding surfaces.
- Kept email and runtime text is Swedish and consistent across backend and frontend.
- No deleted legacy surface receives replacement copy.

## Stop Conditions

- Stop if a string belongs to another domain and not to Auth + Onboarding scope.
- Stop if text replacement would preserve a legacy surface that should instead be removed.

## Out Of Scope

- Global i18n outside Auth + Onboarding scope
