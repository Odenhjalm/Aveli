# T00 Execution Controller

## STATUS

ACTIVE
NO-CODE EXECUTION TASK

## PURPOSE

This task defines the canonical execution loop that uses the task-tree
execution controller contract to drive the onboarding domain-alignment DAG
end-to-end from repo state.

Execution under this task must:

- inspect `task_manifest.json`
- inspect `DAG_SUMMARY.md`
- inspect repo-visible task statuses
- choose the next eligible task deterministically
- execute that task according to its task definition
- verify the result
- update repo-visible task state
- continue automatically until blocked or complete

This task does not reopen locked decisions.
This task does not authorize skipping tasks.
This task does not authorize code changes by itself; it defines the controller
loop that governs downstream task execution.

## AUTHORITY LOAD

This task is governed by:

- `actual_truth/contracts/task_tree_execution_controller_contract.md`
- `actual_truth/contracts/onboarding_target_truth_decision.md`
- `actual_truth/contracts/application_domain_map_contract.md`
- `actual_truth/contracts/ratifications/T01_referral_source_vocabulary_decision.md`
- `actual_truth/contracts/ratifications/T02_create_profile_surface_decision.md`
- `actual_truth/contracts/ratifications/T03_application_subject_naming_decision.md`
- active contracts in `actual_truth/contracts/`
- canonical baseline authority in `backend/supabase/baseline_slots/` and
  `backend/supabase/baseline_slots.lock.json`
- `actual_truth/DETERMINED_TASKS/onboarding_domain_alignment/task_manifest.json`
- `actual_truth/DETERMINED_TASKS/onboarding_domain_alignment/DAG_SUMMARY.md`
- repo-visible task documents `T05` through `T12`

No execution decision may derive authority from chat-only memory, implied
intent outside the repo, or any source not named above.

## EXECUTION LOOP

The controller must execute the onboarding domain-alignment DAG by repeating
the following loop:

1. load `task_manifest.json`
2. load `DAG_SUMMARY.md`
3. inspect repo-visible task statuses
4. derive the set of tasks whose dependencies are satisfied
5. choose the next eligible task deterministically
6. execute that task according to its task definition and allowed mutation
   boundary
7. verify the result against its verification requirement and controlling
   authorities
8. update repo-visible task state
9. continue automatically to the next eligible task without manual
   confirmation unless a declared stop condition is active

The loop must continue until one of the declared stop conditions occurs.

## NEXT-TASK SELECTION RULE

The controller must select the next task only from tasks whose dependencies are
satisfied.

The controller must not:

- execute a task with an unsatisfied dependency
- skip over an earlier eligible task
- invent an alternate dependency edge
- reopen T01, T02, T03, T04, or T05 as part of next-task selection

If multiple tasks become eligible at the same time, the controller must
preserve deterministic ordering by using the canonical task order already
materialized in `task_manifest.json`.

If no task is eligible, the controller must not guess. It must classify the
state as either DAG complete or DAG blocked according to the controlling
authorities and current task statuses.

## VERIFICATION RULE

Before advancing, the controller must verify each executed task result against:

- the execution controller contract
- the task's own definition
- the task's verification requirement in `task_manifest.json`
- locked target truth
- ratified decisions
- active contracts
- canonical baseline authority

Verification must fail closed.

The controller must not advance when:

- the result is only partially verified
- the result contradicts locked repo truth
- the result exceeds the task's mutation scope
- the result leaves repo-visible task state ambiguous

## TASK-STATE UPDATE RULE

After a task result is verified, the controller must update repo-visible task
state before advancing.

Repo-visible task-state update must record:

- which task was executed
- the resulting task status
- the repo-visible artifacts that justify that status
- whether execution is continuing or stopping
- if stopping, the exact stop reason

The controller must not advance to another task until the current task result
is reflected in repo-visible task state.

## STOP CONDITIONS

Execution stops only when one of the following is true:

- no eligible task remains and the DAG is complete
- no eligible task remains and the DAG is blocked by a real unresolved blocker
- a real blocker appears that cannot be resolved from locked decisions, active
  contracts, baseline authority, or task dependencies
- verification fails

Execution must also stop if:

- dependency satisfaction cannot be established
- repo-visible task state is internally inconsistent with `task_manifest.json`
  or `DAG_SUMMARY.md`
- continuing would require reopening a locked decision
- continuing would require skipping a task
- repo truth is ambiguous and cannot justify deterministic advancement

## OUTPUT REQUIREMENT

When execution stops, the controller must report which of the following
occurred:

- the DAG completed
- the DAG is blocked
- a verification failure occurred
- no eligible next task exists

The output must be grounded in repo-visible state and must identify the task at
which execution stopped, if any.

## NEXT STEP

Use this controller task together with
`actual_truth/contracts/task_tree_execution_controller_contract.md` to drive
the onboarding domain-alignment DAG from the next eligible task forward,
continuing automatically until completion or a real blocker is reached.
