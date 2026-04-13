# Checkout Onboarding Payment Surface DAG

## Topological Order

1. COP-001
2. COP-002
3. COP-003
4. COP-004
5. COP-005
6. COP-006
7. COP-007
8. COP-008
9. COP-009
10. COP-010
11. COP-011

## Dependency Edges

- COP-001 -> COP-002
- COP-002 -> COP-003
- COP-003 -> COP-004
- COP-002 -> COP-005
- COP-002 -> COP-006
- COP-002 -> COP-007
- COP-005 -> COP-008
- COP-006 -> COP-008
- COP-007 -> COP-008
- COP-004 -> COP-009
- COP-008 -> COP-010
- COP-009 -> COP-011
- COP-010 -> COP-011

## Blocker Domains Covered

- Live DB schema truth for checkout-critical tables
- Runtime-referenced webhook support tables not baseline-owned
- Schema authority for app.transactions and app.subscriptions
- Bundle checkout frontend drift from mounted backend path
- Unused payment/Supabase SDK residue in checkout/onboarding scope
- Checkout-critical Swedish product copy
- Frontend non-authority for checkout and onboarding payment paths
- Backend webhook settlement, idempotency, and membership creation tests
- Frontend checkout-result refresh and bundle checkout tests

## Non-Blocking Follow-Ups

- Supabase usage outside checkout/onboarding payment scope must be handled by a separate frontend authority cleanup tree if it remains outside COP-007 scope.
- Self-service billing portal, plan changes, and subscription management expansion are deferred unless a later audit proves they are launch-critical.
- Stripe Connect onboarding is deferred because the audit found Connect code present but not mounted in the current active backend route surface.

