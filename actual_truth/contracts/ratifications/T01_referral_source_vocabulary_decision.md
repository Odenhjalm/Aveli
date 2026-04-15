# T01 Referral Source Vocabulary Decision

## STATUS

RATIFIED
NO-CODE DECISION GATE

## PURPOSE

This document ratifies the resolved no-code decision for the replacement
non-purchase membership source vocabulary after invite removal.

This document exists to lock the surviving canonical source label before any
contract-corpus rewrite, baseline mutation, backend mutation, fixture rewrite,
or test rewrite begins.

## VERIFIED CURRENT DRIFT

- Current referral-derived membership handoff still uses source bucket
  `invite`.
- Current repo truth still carries invite-shaped non-purchase membership
  vocabulary in contracts, baseline-backed membership constraints, backend
  runtime, fixtures, and tests.
- Current target contract set had not yet locked the surviving replacement
  source label for referral-derived membership grants.

## LOCKED DECISION

- The canonical replacement non-purchase membership source label is
  `referral`.
- `referral` is the only surviving target vocabulary for referral-derived
  membership grants into `app.memberships`.
- `invite` is retired from target vocabulary for referral-derived membership
  grants.
- This decision does not preserve multiple surviving non-purchase source labels
  for referral-derived membership meaning.

## CONSEQUENCES

- Active contracts must later replace referral-derived use of `invite` with
  `referral`.
- Canonical baseline slots must later replace referral-derived non-purchase
  membership vocabulary that still encodes `invite`.
- Backend runtime must later replace referral-derived membership handoff and
  validation paths that still encode `invite`.
- Fixtures and tests must later replace referral-derived membership source
  assumptions that still encode `invite`.
- This decision does not rewrite invite removal across the full contract corpus
  by itself; it locks the surviving label needed for later deterministic
  rewrite.

## NEXT CONTRACT IMPACT

- T04 must apply this ratified vocabulary to the active contract corpus.
- Later baseline, backend, fixture, and test work must treat `referral` as the
  only canonical non-purchase source label for referral-derived grants.
