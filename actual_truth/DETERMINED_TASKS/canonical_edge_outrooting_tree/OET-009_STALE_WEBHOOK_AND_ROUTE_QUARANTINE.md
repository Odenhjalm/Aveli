# OET-009 STALE WEBHOOK AND ROUTE QUARANTINE

- TYPE: `OWNER`
- GROUP: `INACTIVE / DEAD-CODE QUARANTINE`
- REQUIRED BEFORE FUTURE CORE FEATURE WORK: `NO`
- EXECUTION CLASS: `OPTIONAL LATER HARDENING`

## Problem Statement

Stale webhook support branches and multiple unmounted near-runtime route trees still survive in the repository even though mounted runtime truth does not use them.

This is inactive drift, not current core breakage, but it remains a future reactivation hazard.

## Contract References

- [commerce_membership_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/commerce_membership_contract.md)
- [supabase_integration_boundary_contract.md](/C:/Users/aveli/Aveli/actual_truth/contracts/supabase_integration_boundary_contract.md)

## Audit Inputs

- `OEA-10`

## Implementation Surfaces Affected

- `backend/app/services/stripe_webhook_support_service.py`
- `backend/app/routes/stripe_webhooks.py`
- `backend/app/routes/api_context7.py`
- `backend/app/routes/api_feed.py`
- `backend/app/routes/api_media.py`
- `backend/app/routes/api_orders.py`
- `backend/app/routes/api_services.py`
- `backend/app/routes/community.py`
- `backend/app/routes/connect.py`
- `backend/app/routes/landing.py`
- `backend/app/routes/livekit_webhooks.py`

## Depends On

- `OET-011`

## Acceptance Criteria

- no scoped dormant route or ignored webhook-support branch can be mistaken for a canonical mounted surface
- the `account.*` support branch is either removed or explicitly quarantined behind a documented inactive boundary
- no scoped change touches canonical checkout, billing, webhook, membership, or course-access runtime
- route inventory in scope becomes unambiguous about what is mounted versus inactive

## Stop Conditions

- stop if the task would modify the canonical mounted checkout or webhook core
- stop if dormant route cleanup requires inventing new runtime behavior
- stop if inactive route or support branches remain ambiguous after completion

## Out Of Scope

- mounted studio or events cleanup
- JWT claims
- sessions and alias residue
- contract-law changes
