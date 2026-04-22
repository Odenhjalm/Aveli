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

- `backend/supabase/baseline_v2_production_cutover.json`
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
slot deltas of this class.

## 3. Verification Law Preservation

Normal runtime verification is not weakened.

- `run_server.py` and `run_worker.py` remain strict and unchanged.
- The cutover path is not an alternate normal boot path.
- The cutover path is release-machine-only and must fail closed unless
  `RELEASE_COMMAND=1`.
- The cutover script must run `verify_v2_runtime()` after applying the bounded
  slot delta and before allowing deploy continuation.

The release cutover exists to align the DB to the new lock *before* app and
worker replacement. It does not authorize runtime drift tolerance.

## 4. Bounded Cutover Plan Authority

`backend/supabase/baseline_v2_production_cutover.json` is the canonical bounded
cutover plan for the current release artifact.

It must define:

- the exact predecessor schema hash and counts that are allowed
- the exact target schema hash and counts that must equal the current lock
- the exact slot files that may be applied
- the exact slot order
- any non-destructive invariants that must remain true after promotion

Forbidden:

- open-ended hash allowlists
- normal boot bypasses
- silent fallback to app startup mutation
- release-machine behavior that is not encoded in the cutover plan

## 5. Release-Machine Rules

The release-machine cutover must fail closed unless all are true:

- the lock verifies
- the cutover plan verifies against the lock
- runtime DB target validation passes
- the live DB is already at the target state, or exactly at the cutover plan's
  predecessor state
- only the cutover plan's listed slot files are executed
- each executed step reaches its expected post-step schema hash and counts
- required non-destructive invariants hold
- final `verify_v2_runtime()` succeeds against the target lock

If any check fails:

- the release command exits non-zero
- Fly deployment must stop
- app and worker Machines must not be replaced

## 6. Reuse Rule

This mechanism is reusable for future slot promotions of the same class only by
updating the bounded cutover plan to the next exact predecessor -> target delta.

Future reuse must keep all of the following:

- release-machine-only execution
- exact predecessor state matching
- exact slot-list matching
- strict post-step verification
- final runtime verification
- fail-closed deployment stop on any mismatch

## 7. Final Assertion

- Production hard reset remains forbidden.
- Historical slots remain immutable.
- Production slot promotion remains append-only and exact.
- Runtime verification remains strict on normal boot.
- The release-machine cutover is the only accepted path that may bridge a
  predecessor production DB state to the lock carried by the new release.
