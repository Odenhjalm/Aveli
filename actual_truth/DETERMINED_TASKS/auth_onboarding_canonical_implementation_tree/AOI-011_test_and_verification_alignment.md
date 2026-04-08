# AOI-011 TEST AND VERIFICATION ALIGNMENT

TYPE: `GATE`  
TASK_TYPE: `TEST_ALIGNMENT`  
DEPENDS_ON: `["AOI-001", "AOI-002", "AOI-003", "AOI-004", "AOI-005", "AOI-006", "AOI-007", "AOI-008", "AOI-009", "AOI-010"]`

## Goal

Rewrite tests and verification scripts so they assert only canonical Auth + Onboarding truth.

## Required Coverage

- baseline object presence
- onboarding completion route and token-refresh consequence
- admin bootstrap boundary
- teacher grant/revoke behavior
- profile projection boundary
- referral separation
- failure envelope
- elimination of teacher-request and avatar-write authority

## Forbidden

- direct SQL authority assumptions outside the canonical operator/bootstrap plane
- tests that encode legacy onboarding states
- tests that require deferred avatar/media work

## Exit Criteria

- tests validate only contract-owned surfaces and baseline-owned objects
- legacy behavior is no longer encoded as test truth
