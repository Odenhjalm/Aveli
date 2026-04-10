# CMT-009_TEST_AND_GATE

- TYPE: `AGGREGATE`
- TITLE: `Add contract gates for purchase authority, webhook settlement, access logic, and bundle separation`
- DOMAIN: `verification`
- GROUP: `TEST + GATE`

## Problem Statement

The current repo has no visible gate proving that launch commerce now follows the contract end-to-end. A final aggregate task is required so repaired purchase, webhook, access, route, frontend, and bundle behaviors cannot drift back to Stripe authority or legacy surfaces.

## Contract References

- `commerce_membership_contract.md` sections `1` through `16`

## Audit Inputs

- `AUD-01` through `AUD-16`

## Implementation Surfaces Affected

- Backend tests covering billing, checkout, webhook, events, notifications, and bundles
- Frontend tests covering return/deeplink and checkout result behavior
- Any repo-local contract gate or verification harness that protects launch commerce

## DEPENDS_ON

- `CMT-000_PURCHASE_SUBSTRATE_BASELINE_FOUNDATION`
- `CMT-001_BASELINE_MEMBERSHIP_FOUNDATION`
- `CMT-002_MEMBERSHIP_PURCHASE_REPAIR`
- `CMT-003_WEBHOOK_REPAIR`
- `CMT-004_ACCESS_LOGIC_REPAIR`
- `CMT-005_ROUTE_ALIGNMENT`
- `CMT-006_FRONTEND_ALIGNMENT`
- `CMT-007_LEGACY_REMOVAL`
- `CMT-008_BUNDLE_PRESERVATION`

## Acceptance Criteria

- Tests prove membership purchase is order-backed and payment-backed.
- Tests prove webhook settlement occurs before membership mutation.
- Tests prove access logic implements only the contract's canonical lifecycle and audience rules.
- Tests prove frontend success/cancel handling remains non-authoritative.
- Tests prove bundle flows stay separate from membership authority.
- A failing contract gate exists for any reintroduction of polymorphic checkout, orderless membership purchase, or Stripe-runtime membership authority.

## Stop Conditions

- Stop if any repaired contract invariant cannot be deterministically asserted from local tests or repo-local verification gates.

## Out Of Scope

- New product behavior
- Non-commerce test expansion
