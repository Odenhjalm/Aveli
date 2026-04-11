## TASK ID

OEA-E01

## TITLE

PHASE_E_INVITE_REFERRAL - Implement Invite Membership Grant Boundary

## TYPE

BACKEND_ALIGNMENT

## PURPOSE

Implement the locked invite rule: invite is identity bootstrap plus membership grant, not referral redemption and not onboarding completion.

## DEPENDS_ON

- OEA-A08
- OEA-C03
- OEA-D01

## TARGET SURFACES

- `backend/app/routes/auth.py`
- `backend/app/services/email_verification.py`
- `backend/app/services/membership_grant_service.py`
- `backend/app/repositories/memberships.py`
- `backend/app/repositories/auth.py`

## EXPECTED RESULT

When an invite is accepted in the identity bootstrap path, backend creates a canonical `app.memberships` row with `source = 'invite'` and required `expires_at`; onboarding remains incomplete until explicit completion.

## INVARIANTS

- Invite MUST create membership with `source = 'invite'`.
- Invite membership MUST set `expires_at`.
- Invite MUST skip payment capture.
- Invite MUST NOT complete onboarding.
- Invite MUST NOT redeem referral.
- Invite MUST NOT grant app-entry until onboarding state is `completed`.
- OEA-E01 MUST occur after OEA-A08, OEA-C03, and OEA-D01.

## VERIFICATION

- Verify accepted invite creates `app.memberships` with `source = 'invite'` and non-null `expires_at`.
- Verify accepted invite leaves onboarding state `incomplete`.
- Verify invite-created membership plus incomplete onboarding denies app-entry.
