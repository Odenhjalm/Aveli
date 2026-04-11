## TASK ID

OEA-E05

## TITLE

PHASE_E_INVITE_REFERRAL - Enforce Invite Profile Completion Flow

## TYPE

FRONTEND_ALIGNMENT

## PURPOSE

Make invite UX land in profile/onboarding completion after identity bootstrap and invite membership grant, without payment capture and without bypassing app-entry law.

## DEPENDS_ON

- OEA-E01
- OEA-E04
- OEA-D02

## TARGET SURFACES

- `frontend/lib/features/auth/presentation/invite_page.dart`
- `frontend/lib/features/auth/presentation/signup_page.dart`
- `frontend/lib/features/onboarding/welcome_page.dart`
- `frontend/lib/core/routing/app_router.dart`

## EXPECTED RESULT

Invite flow skips normal identity capture and payment capture where the invite bootstrap has already supplied that context, then routes to profile/onboarding completion and waits for backend entry truth.

## INVARIANTS

- Invite flow MUST use backend-created membership with `source = 'invite'` and `expires_at`.
- Invite flow MUST NOT require payment capture.
- Invite flow MUST NOT bypass onboarding completion.
- Invite flow MUST NOT infer entry from token, profile, role, admin, or invite token.
- Frontend MUST only reflect backend entry truth.
- OEA-E05 MUST occur after OEA-E01 and OEA-E04.

## VERIFICATION

- Verify invite user without completed onboarding lands in profile/onboarding completion.
- Verify invite user with invite membership and incomplete onboarding cannot enter app routes.
- Verify invite user with invite membership and completed onboarding can enter app routes.
