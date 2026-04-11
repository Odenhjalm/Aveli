## TASK ID

OEA-A08

## TITLE

PHASE_A_DRIFT_REMOVAL - Lock Corrected Invite Authority Rule

## TYPE

CONTRACT_ALIGNMENT

## PURPOSE

Record the corrected canonical invite rule for all later tasks: invite is identity bootstrap plus membership grant, with `membership.source = 'invite'` and required `membership.expires_at`. Invite does not complete onboarding and does not grant entry until onboarding is completed.

## DEPENDS_ON

- OEA-A01

## TARGET SURFACES

- `actual_truth/contracts/onboarding_entry_authority_contract.md`
- `backend/app/routes/auth.py`
- `backend/app/services/email_verification.py`
- `backend/app/services/membership_grant_service.py`
- `backend/app/repositories/memberships.py`
- `frontend/lib/features/auth/presentation/invite_page.dart`
- `frontend/lib/features/onboarding/welcome_page.dart`

## EXPECTED RESULT

All later backend, frontend, baseline, and test tasks use the corrected invite law. This task is the DAG prerequisite for invite implementation and every downstream invite-dependent task.

## INVARIANTS

- Invite MUST create membership with `source = 'invite'`.
- Invite membership MUST set `expires_at`.
- Invite MUST NOT complete onboarding.
- Invite MUST NOT grant app-entry until `app.auth_subjects.onboarding_state = 'completed'`.
- Invite MUST NOT share referral parameter handling.
- OEA-A08 MUST appear before OEA-B01, OEA-C02, OEA-C03, OEA-E01, OEA-E05, and OEA-G03 in the DAG.

## VERIFICATION

- Verify downstream tasks refer to invite as identity bootstrap plus membership grant.
- Verify OEA-E01 depends on OEA-A08.
- Verify all invite-dependent frontend and test tasks depend on OEA-E01 or its downstream chain.
