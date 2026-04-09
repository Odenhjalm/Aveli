# CMT-008_BUNDLE_PRESERVATION

- TYPE: `OWNER`
- TITLE: `Preserve bundle separation while launch commerce is repaired`
- DOMAIN: `bundle isolation`
- GROUP: `BUNDLE PRESERVATION`

## Problem Statement

The fresh audit confirms that bundle commerce is already order-backed, payment-backed, and membership-neutral, but webhook, route, and legacy cleanup work intersects with bundle checkout and entitlement fulfillment. The bundle domain must remain separated from membership throughout the repair sequence.

## Contract References

- `commerce_membership_contract.md` sections `1`, `3`, `4`, `7`, `13`

## Audit Inputs

- `AUD-15` bundle domain is correct and must be preserved
- `AUD-07` mixed webhook currently processes bundle fulfillment beside membership logic

## Implementation Surfaces Affected

- `backend/app/routes/course_bundles.py`
- `backend/app/services/course_bundles_service.py`
- `backend/app/routes/stripe_webhooks.py`
- `frontend/lib/features/teacher/data/course_bundles_repository.dart`
- `frontend/lib/features/teacher/presentation/course_bundle_page.dart`

## DEPENDS_ON

- `CMT-003_WEBHOOK_REPAIR`

## Acceptance Criteria

- Bundle checkout remains order-backed and payment-backed.
- Bundle fulfillment mutates only course-access state and not `app.memberships`.
- Bundle routes and frontend bundle tooling remain separate from membership launch entrypoints.
- Membership cleanup does not regress teacher bundle creation, listing, or checkout.

## Stop Conditions

- Stop if any required bundle behavior depends on membership authority or a launch-commerce polymorphic path.

## Out Of Scope

- New bundle features
- Connect marketplace expansion
