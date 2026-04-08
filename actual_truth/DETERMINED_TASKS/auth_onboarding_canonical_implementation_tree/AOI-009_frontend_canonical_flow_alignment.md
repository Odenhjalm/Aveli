# AOI-009 FRONTEND CANONICAL FLOW ALIGNMENT

TYPE: `OWNER`  
TASK_TYPE: `FRONTEND_ALIGNMENT`  
DEPENDS_ON: `["AOI-004", "AOI-005", "AOI-006", "AOI-007", "AOI-008"]`

## Goal

Align frontend Auth + Onboarding flows to the canonical backend surface and failure contract.

## Required Outputs

- onboarding completion uses `POST /auth/onboarding/complete` then `POST /auth/refresh`
- admin UI calls grant/revoke teacher-role routes only
- register flow stops sending `referral_code`
- profile flow treats `photo_url` as read-only output
- client error parsing uses the canonical error envelope only

## Forbidden

- avatar upload work inside Auth + Onboarding scope
- frontend authority based on JWT legacy claims
- routing based on eliminated onboarding states

## Exit Criteria

- frontend consumes only canonical routes
- frontend no longer depends on legacy auth/onboarding authority
