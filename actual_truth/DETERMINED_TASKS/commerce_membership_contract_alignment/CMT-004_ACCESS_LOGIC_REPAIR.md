# CMT-004_ACCESS_LOGIC_REPAIR

- TYPE: `OWNER`
- TITLE: `Replace legacy membership status logic with canonical access and audience rules`
- DOMAIN: `membership access authority`
- GROUP: `ACCESS LOGIC REPAIR`
- CURRENT STATUS: `HISTORICAL / VERIFIED COMPLETE`

## Historical Note

The problem statement below records the pre-execution audit state and is retained only as historical task context.

## Problem Statement

Repo access logic still treats `active|trialing` as membership-active and does not implement `status = canceled AND current_time < expires_at`. Events, notifications, observability, and background jobs all inherit that non-canonical logic.

## Contract References

- `commerce_membership_contract.md` sections `10`, `11`, `12`, `13`

## Audit Inputs

- `AUD-10` legacy access helper and downstream consumers
- `AUD-12` frontend status leakage rooted in non-canonical lifecycle terms

## Implementation Surfaces Affected

- `backend/app/utils/membership_status.py`
- `backend/app/routes/api_events.py`
- `backend/app/routes/api_notifications.py`
- `backend/app/services/domain_observability/user_inspection.py`
- `backend/app/services/membership_expiry_warnings.py`

## DEPENDS_ON

- `CMT-001_BASELINE_MEMBERSHIP_FOUNDATION`
- `CMT-003_WEBHOOK_REPAIR`

## Acceptance Criteria

- Backend access logic implements only the contract's canonical membership statuses.
- `past_due` is non-access-granting with no inferred grace period.
- `canceled` access is granted only while the contract-defined expiry boundary remains valid.
- Notification audiences use membership only for app/member-wide targeting and course enrollments only for course audiences.
- Observability output preserves canonical status semantics instead of collapsing them to `active/inactive`.

## Stop Conditions

- Stop if a current consumer requires lifecycle semantics not defined in the contract and no separate contract exists.

## Out Of Scope

- Membership purchase initiation
- Frontend endpoint wiring
