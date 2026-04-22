# BASELINE V2 RELEASE CUTOVER CONTRACT

## STATUS

ACTIVE CANONICAL EXECUTE-MODE CUTOVER AUTHORITY.

This contract defines the only accepted non-destructive production cutover path
for Baseline V2 slot promotions that must preserve live business state.

It operates under:

- `actual_truth/contracts/baseline_v2_authority_freeze_contract.md`
- `actual_truth/contracts/production_deployment_contract.md`
- `actual_truth/contracts/deployment_guardrail_policy.md`
- `actual_truth/AVELI_DATABASE_BASELINE_MANIFEST.md`
- `backend/supabase/baseline_v2_slots.lock.json`

Execute-mode cutover inputs are:

- `backend/supabase/baseline_v2_slots.lock.json`
- `backend/bootstrap/baseline_v2_cutover.py`
- `fly.toml`

## 1. Purpose

This contract exists because normal runtime boot is intentionally strict:

- `backend.bootstrap.run_server` must verify the live DB against the shipped V2
  lock before startup.
- `backend.bootstrap.run_worker` must verify the live DB against the shipped V2
  lock before startup.

Therefore a release that carries a new lock cannot safely boot first against a
production DB that is still on the previous accepted state.

## 2. Canonical Mechanism

The canonical cutover mechanism is:

1. build the exact release artifact that carries the new V2 lock
2. run a one-shot Fly `release_command` in a temporary release Machine using
   that exact artifact
3. execute `python -m backend.bootstrap.baseline_v2_cutover`
4. allow app and worker Machines to update only if the cutover succeeds

This is the only accepted execute-mode production mutation path for Baseline V2
single-slot promotions.

## 3. Verification Law Preservation

Normal runtime verification is not weakened.

- `run_server.py` and `run_worker.py` remain strict and unchanged.
- The cutover path is not an alternate normal boot path.
- The cutover path is release-machine-only and must fail closed unless
  `RELEASE_COMMAND=1`.
- The cutover script must run `verify_v2_runtime()` after applying the exact
  next slot and before allowing deploy continuation.

The release cutover exists to align the DB to the new lock before app and
worker replacement. It does not authorize runtime drift tolerance.

## 4. Lock-Owned Cutover Authority

`backend/supabase/baseline_v2_slots.lock.json` is the canonical cutover
manifest for the current release artifact.

It must define:

- the ordered accepted slot chain
- the final runtime schema hash and counts
- the cutover state hash algorithm for promotion detection
- the post-state hash and counts for every accepted slot

Interpretation rule:

- slot `post_state_hash` is owned by
  `release_cutover_verification.state_hash_algorithm`, not by
  `schema_verification.expected_schema_hash`

The cutover script must:

- derive the live current slot from the production DB by exact match against
  the lock-carried slot post-state metadata
- derive the target slot as the exact next slot in the lock
- require the release artifact final slot to be either:
  - the current slot, for a deterministic no-op
  - or the exact next slot, for a deterministic single-slot promotion

Forbidden:

- slot-specific cutover branches
- external per-release cutover plan files
- open-ended hash allowlists
- multi-slot replay
- normal boot bypasses
- silent fallback to app startup mutation

## 5. Release-Machine Rules

The release-machine cutover must fail closed unless all are true:

- the lock verifies
- runtime DB target validation passes
- the live DB matches exactly one accepted lock slot post-state
- the release artifact final slot is either the current slot or the exact next
  slot
- if promotion is required, only the exact next slot file is executed
- existing app-table row counts remain unchanged
- the observed post-state hash and counts match the target slot entry exactly
- final `verify_v2_runtime()` succeeds against the top-level lock target

If any check fails:

- the release command exits non-zero
- Fly deployment must stop
- app and worker Machines must not be replaced

## 6. Reuse Rule

This mechanism is reusable for future Baseline V2 promotions without redesign
only when all are true:

- each release adds at most one new accepted slot
- the same change updates `backend/supabase/baseline_v2_slots.lock.json`
  with the new slot entry and its post-state metadata
- Fly keeps `release_command = "python -m backend.bootstrap.baseline_v2_cutover"`
- no manual production SQL is used

Future reuse must keep all of the following:

- release-machine-only execution
- exact current-slot matching
- exact `N -> N+1` enforcement
- append-only slot execution
- strict post-state verification
- final runtime verification
- fail-closed deployment stop on any mismatch

## 7. Final Assertion

- Production hard reset remains forbidden.
- Historical slots remain immutable.
- Production slot promotion remains append-only and exact.
- Runtime verification remains strict on normal boot.
- The release-machine cutover is the only accepted path that may bridge a
  predecessor production DB state to the lock carried by the new release.
- All future Baseline V2 promotions must use the release-command `N -> N+1`
  cutover mechanism. Manual production SQL is forbidden.
