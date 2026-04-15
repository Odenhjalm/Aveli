# Task Tree Execution Controller Contract

## STATUS

ACTIVE
NO-CODE EXECUTION-CONTROLLER CONTRACT

## PURPOSE

This contract defines the canonical execution behavior for a controller that
processes the onboarding domain-alignment task tree deterministically from repo
state.

The controller exists to:

- read the materialized onboarding domain-alignment DAG from repo files
- determine which task is eligible to execute next
- execute only dependency-satisfied tasks
- verify each task result before advancing
- lock each completed task result into repo-visible state before advancing
- continue automatically until a declared stop condition is reached

## AUTHORITY INPUTS

The controller may reason only from the following repo-visible authorities:

1. locked target truth in
   `actual_truth/contracts/onboarding_target_truth_decision.md`
2. canonical domain topology in
   `actual_truth/contracts/application_domain_map_contract.md`
3. ratified decisions in:
   - `actual_truth/contracts/ratifications/T01_referral_source_vocabulary_decision.md`
   - `actual_truth/contracts/ratifications/T02_create_profile_surface_decision.md`
   - `actual_truth/contracts/ratifications/T03_application_subject_naming_decision.md`
4. active contracts in `actual_truth/contracts/`
5. canonical baseline authority in `backend/supabase/baseline_slots/` and
   `backend/supabase/baseline_slots.lock.json`
6. materialized DAG files in
   `actual_truth/DETERMINED_TASKS/onboarding_domain_alignment/`, including:
   - `DAG_SUMMARY.md`
   - `task_manifest.json`
   - task documents `T05` through `T12`

No task may derive authority from chat history, unstored memory, manifests,
notes, readiness docs, frontend hints, or any source outside the repo-visible
authority set above.

## TASK STATUS MODEL

The controller must interpret task status using the following canonical model:

- `resolved_ratified`:
  a decision or gate is locked and is not open for re-execution
- `completed`:
  the task outcome is already materialized and verified in repo-visible state
- `defined_append_only_required`:
  the task has resolved the required mutation path and has produced the task
  definition, but the actual mutation is not yet executed
- `planned`:
  the task is defined but not yet executed
- `eligible`:
  a derived controller state meaning:
  - the task status is executable from repo state
  - all dependencies are satisfied
  - no stop condition is active for that task
- `in_progress`:
  a transient execution state while one task is actively being processed
- `blocked`:
  execution cannot continue because a declared stop condition is active
- `failed_verification`:
  the attempted task result did not satisfy its required verification rules

The controller must not invent additional status meanings that weaken or bypass
the status model above.

## DEPENDENCY RESOLUTION RULES

The controller must resolve dependencies only from `task_manifest.json`.

Dependency satisfaction rules:

- a task dependency is satisfied only when the dependency status is one of:
  - `resolved_ratified`
  - `completed`
  - `defined_append_only_required`, but only when the downstream task depends
    on the resolved path definition rather than the actual mutation result
- a dependency is not satisfied when its status is:
  - `planned`
  - `in_progress`
  - `blocked`
  - `failed_verification`
- if a dependency edge in `task_manifest.json` conflicts with
  `DAG_SUMMARY.md`, the manifest inconsistency is a stop condition

Eligibility rules:

- the controller may execute only a task whose dependencies are satisfied
- the controller must not skip an unsatisfied dependency even if a later task
  appears locally implementable
- the controller must not execute a task outside the materialized DAG

## EXECUTION RULES

Execution must proceed deterministically from repo state.

The controller must:

1. load `task_manifest.json`
2. validate that every referenced task file exists
3. validate that dependency edges are internally consistent
4. derive the set of eligible tasks
5. if exactly one task is eligible, execute that task
6. if multiple tasks are eligible, choose the next task by the deterministic
   topological order already materialized in `task_manifest.json`
7. execute only one task at a time
8. verify the task result before advancing
9. lock the verified result into repo-visible state before advancing
10. recompute eligibility from repo state after each completed task

The controller must not:

- skip tasks
- reorder tasks outside deterministic tie-breaking
- invent alternate flows
- reopen locked T01, T02, T03, T04, or T05 conclusions
- treat planned downstream work as satisfied just because it appears easy

## VERIFICATION RULES

The controller must verify each task result against:

- the task's `verification_requirement` in `task_manifest.json`
- any stricter stop condition in the task document
- locked upstream authorities and contracts

Verification must fail closed.

A task result is verified only when all are true:

- the task mutation scope is respected
- the declared authority inputs still hold
- the task's expected repo-visible artifacts exist
- no forbidden side-effect appears outside allowed scope
- the result does not contradict locked target truth, ratified decisions,
  active contracts, baseline authority, or dependency law

The controller must not advance on partial verification.

## CONTINUATION RULE

The controller must automatically continue to the next eligible task without
manual confirmation after a task result is both:

- verified
- locked into repo-visible state

Automatic continuation is mandatory unless a declared stop condition is active.

The controller must continue task-to-task until:

- no eligible task remains because the DAG is complete
- or a declared stop condition is reached

## STOP CONDITIONS

The controller must stop immediately when any of the following is true:

- a task requires a new target-truth decision
- a contradiction cannot be resolved from declared authorities
- verification fails
- dependency satisfaction fails
- `task_manifest.json` is internally inconsistent
- a required task file is missing
- repo-visible state conflicts with the locked DAG in a way the controller
  cannot resolve from declared authorities
- a task would require reopening T01, T02, T03, T04, or T05
- a task would require skipping an unsatisfied dependency

The controller must not stop for manual confirmation merely because the next
task is substantial. Difficulty alone is not a stop condition.

## MUTATION RECORDING

Before advancing, the controller must lock each completed task result into
repo-visible state.

At minimum, mutation recording must include:

- the task status transition in repo-visible task state
- the repo-visible artifacts created or changed by the task
- enough verification evidence to justify the task as completed
- any remaining blocker record if execution stops

A task is not considered complete until its result is recorded in repo-visible
state.

## FAIL-CLOSED BEHAVIOR

If repo truth is ambiguous, missing, contradictory, or insufficient to justify
advancement, the controller must fail closed.

Fail-closed means:

- do not guess
- do not infer missing authority
- do not continue past failed verification
- do not synthesize alternate dependency edges
- do not downgrade a blocker into a warning
- do not reopen locked decisions as an implicit workaround

When failing closed, the controller must leave the DAG in a repo-visible
blocked state rather than advancing speculatively.

## FINAL ASSERTION

This contract makes the onboarding domain-alignment controller deterministic.

The controller:

- reads the materialized DAG from repo files
- executes only dependency-satisfied tasks
- verifies each task before advancing
- records each completed result into repo-visible state before advancing
- continues automatically to the next eligible task
- stops only on declared blocker conditions

Any controller behavior that skips tasks, invents alternate flows, reopens
locked decisions, or advances without verification is non-canonical.
