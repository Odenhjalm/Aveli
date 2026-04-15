# T05 Append-Only Baseline Referral Vocabulary Alignment

## STATUS

DRAFT
NO-CODE APPEND-ONLY BASELINE MUTATION TASK

## PURPOSE

This task defines the required append-only baseline mutation needed to align
baseline vocabulary and constraints with the post-invite canonical contract
corpus.

This task does not create the slot yet.
This task does not mutate baseline yet.
This task does not rewrite contracts, backend code, frontend code, or tests.

## AUTHORITY LOAD

This task is governed by:

- `actual_truth/contracts/onboarding_target_truth_decision.md`
- `actual_truth/contracts/application_domain_map_contract.md`
- `actual_truth/contracts/ratifications/T01_referral_source_vocabulary_decision.md`
- rewritten active contracts after T04
- canonical baseline authority in `backend/supabase/baseline_slots/`

## VERIFIED CURRENT DRIFT

- `backend/supabase/baseline_slots/0032_memberships_fail_closed_constraints.sql`
  is the only baseline slot currently encoding `invite` as active canonical
  non-purchase vocabulary.
- In `0032`, drift exists in both constraint/value law and baseline comments:
  - `memberships_source_supported_check` still allows `invite`
  - `memberships_invite_expires_at_check` still encodes invite-specific
    time-bounded grant law
  - baseline comments still state that referral is not a membership source
    and still describe invite as the active time-bounded non-purchase grant
    doctrine
- `backend/supabase/baseline_slots/0031_referral_codes_core.sql` is aligned
  with canonical referral identity/lifecycle law and is not the drift source
  for this task.
- `backend/supabase/baseline_slots.lock.json` does not define conflicting law
  by itself; it will require derived update only when a future slot is actually
  created.

## REQUIRED MUTATION

A new append-only baseline slot is required.

The new slot must:

- align membership-source vocabulary with the canonical surviving
  non-purchase source label `referral`
- remove invite as active canonical baseline doctrine
- align baseline comments and constraints with the rewritten active contract
  corpus after T04
- replace the active baseline effect of invite-shaped non-purchase membership
  source law with referral-shaped non-purchase membership source law
- align time-bounded non-purchase grant constraint language with referral
  rather than invite

## MUTATION BOUNDARY

The future append-only slot must change only what is necessary to align
baseline-backed membership vocabulary and constraints.

The future slot must not:

- introduce unrelated schema redesign
- mutate purchase/payment doctrine
- mutate course-access doctrine
- outrun locked contract law
- rewrite historical slot `0032` in place
- mutate referral identity/lifecycle law outside the membership-vocabulary
  alignment required by this task

## APPEND-ONLY REQUIREMENT

Baseline alignment must not edit historical slot
`backend/supabase/baseline_slots/0032_memberships_fail_closed_constraints.sql`
in place.

In-place editing is forbidden because baseline law is append-only and
historical slots are part of canonical local schema history.

Therefore:

- a new append-only baseline slot is required
- the new slot must carry the alignment forward from current baseline drift
- `backend/supabase/baseline_slots.lock.json` must be updated only as a
  derived effect when that future slot is actually created

## VERIFICATION REQUIREMENT

The future mutation defined by this task is correct only when all are true:

- `0032_memberships_fail_closed_constraints.sql` remains unchanged as
  historical residue
- a new append-only slot is introduced instead of in-place editing
- baseline-supported membership-source vocabulary aligns to `referral` as the
  canonical surviving non-purchase label
- invite no longer survives as active canonical baseline doctrine
- baseline comments no longer conflict with the post-T04 contract corpus
- no unrelated doctrine is changed

## STOP CONDITIONS

Stop if any of the following becomes necessary:

- reopening T01 referral source vocabulary
- reopening T04 active-contract doctrine
- mutating historical slot `0032` in place
- introducing broader membership redesign beyond vocabulary/constraint
  alignment
- changing purchase/payment or course-access law as part of this task

## NEXT STEP

Draft the actual append-only baseline slot mutation prompt that will:

- create the new baseline slot
- align membership-source constraints and comments from `invite` to
  `referral`
- leave historical slot `0032` untouched
- update `backend/supabase/baseline_slots.lock.json` only when the slot is
  actually created
