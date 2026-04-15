# T03 Application Subject Naming Decision

## STATUS

RATIFIED
NO-CODE DECISION GATE

## PURPOSE

This document ratifies the resolved no-code decision for canonical
application-subject naming across the active contract corpus.

This document exists to lock the required naming rule before any active
contract rewrite begins.

## VERIFIED CURRENT DRIFT

- Active contracts currently name `app.auth_subjects` through a mix of field
  ownership language, truth-carrier language, and partial authority language.
- Active contracts do not yet consistently name `app.auth_subjects` as the
  canonical application subject authority.
- Six active contracts require later wording updates to align with the locked
  naming decision:
  - `auth_onboarding_contract.md`
  - `auth_onboarding_baseline_contract.md`
  - `onboarding_entry_authority_contract.md`
  - `onboarding_teacher_rights_contract.md`
  - `referral_membership_grant_contract.md`
  - `supabase_integration_boundary_contract.md`

## LOCKED DECISION

- `app.auth_subjects` must be named across the active contract corpus as the
  canonical application subject authority.
- The naming must explicitly cover:
  - onboarding subject state
  - app-level role subject fields
  - app-level admin subject fields
- No other domain may be left implicitly sharing canonical application-subject
  authority.

## CONSEQUENCES

- Later active-contract wording updates must replace field-only or
  truth-carrier-only naming where it fails to state the canonical
  application-subject authority directly.
- Later contract rewrites must preserve `auth.users` as identity-only and must
  not imply that identity owns application-subject state.
- Later contract rewrites must preserve `/profiles/me` as projection-only and
  must not imply that profile projection owns onboarding or subject truth.
- This decision does not itself rewrite the active corpus; it locks the naming
  rule required for deterministic contract alignment.

## NEXT CONTRACT IMPACT

- T04 and later contract rewrite work must apply this naming rule consistently
  across the six identified active contracts.
- Subsequent contract audits must treat any omission or competing subject-owner
  language as drift unless this ratified decision is explicitly revised first.
