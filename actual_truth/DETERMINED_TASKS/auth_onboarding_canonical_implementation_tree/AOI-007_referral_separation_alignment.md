# AOI-007 REFERRAL SEPARATION ALIGNMENT

TYPE: `OWNER`  
TASK_TYPE: `BACKEND_ALIGNMENT`  
DEPENDS_ON: `["AOI-003"]`

## Goal

Remove referral behavior from Auth + Onboarding execution surfaces so auth remains auth-only.

## Required Outputs

- `POST /auth/register` rejects `referral_code`
- auth persistence paths do not redeem referrals
- auth persistence paths do not grant membership

## Forbidden

- referral redemption during register
- referral-driven onboarding completion
- membership writes hidden inside auth repositories

## Exit Criteria

- auth routes own only auth concerns
- referral transport and redemption remain outside Auth + Onboarding
