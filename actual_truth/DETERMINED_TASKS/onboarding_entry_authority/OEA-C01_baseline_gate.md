## TASK ID

OEA-C01

## TITLE

PHASE_C_BASELINE_ALIGNMENT - Baseline Completeness Gate

## TYPE

VERIFICATION

## PURPOSE

Perform a baseline completeness audit for every authority in scope before schema-dependent implementation continues.

## DEPENDS_ON

- OEA-B01

## TARGET SURFACES

- `backend/supabase/baseline_slots/*`
- `backend/supabase/newbaseline_slots/*`
- `backend/app/repositories/*`
- `backend/app/services/*`

## EXPECTED RESULT

Every runtime authority in scope maps to an existing clean-replay substrate or to an explicit baseline-owner task.

## INVARIANTS

- `app.auth_subjects` MUST own onboarding state.
- `app.memberships` MUST own global app-entry membership state.
- `app.course_enrollments` MUST own protected course access.
- `app.referral_codes` MUST own referral authority.
- Invite membership grants MUST be backed by `app.memberships`.
- Missing baseline substrate MUST block downstream implementation until an owner task exists.

## VERIFICATION

- Verify the authority to substrate to owner-task chain for identity, onboarding, membership, course access, invite, and referral.
- Verify no runtime authority lacks a baseline substrate.
- Verify missing `backend/supabase/newbaseline_slots` is classified without blocking accepted baseline owner tasks.
