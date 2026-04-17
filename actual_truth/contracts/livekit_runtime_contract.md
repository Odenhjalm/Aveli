# LIVEKIT RUNTIME CONTRACT

## STATUS

ACTIVE

This contract defines the canonical authority model for the LiveKit runtime
surface.

This contract operates under:

- `SYSTEM_LAWS.md`
- `actual_truth/AVELI_DATABASE_BASELINE_MANIFEST.md`
- `actual_truth/Aveli_System_Decisions.md`

This contract does not activate LiveKit runtime behavior. It defines the
fail-closed paused model that must be satisfied before any later activation
planning can proceed.

## 1. Purpose

The purpose of this contract is to define the authority boundary for:

- `app.livekit_webhook_jobs`
- LiveKit webhook worker startup and execution
- LiveKit webhook queue mutation
- LiveKit-derived mutation of Aveli domain state
- LiveKit relationship to canonical truth and baseline replay

LiveKit webhook handling is a runtime integration surface only. It is not
canonical business truth, not canonical media truth, not access truth, not
course-content truth, not membership truth, and not profile truth.

## 2. Classification

LiveKit webhook runtime classification is:

```text
PAUSED
```

`app.livekit_webhook_jobs` is classified as:

```text
RUNTIME / PAUSED / INERT STRUCTURE
```

The table may exist as accepted baseline structure, but the existence of the
table does not authorize queue execution, worker execution, webhook ingestion,
or canonical mutation.

## 3. Owner Surface

Canonical ownership is split as follows:

| Surface | Owner | Authority |
| --- | --- | --- |
| `app.livekit_webhook_jobs` physical schema | database baseline manifest and baseline slot `0021` | inert runtime queue structure only |
| LiveKit runtime contract | this file | paused authority boundary for LiveKit runtime behavior |
| Worker execution authority | not assigned while paused | no execution allowed |
| Webhook ingestion authority | not assigned while paused | no enqueue or mutation allowed |
| Domain mutation authority | not assigned to LiveKit while paused | no direct or indirect canonical mutation allowed |
| Observability reads | logs/observability surfaces | read-only status and queue inspection only |

No active product domain currently owns LiveKit webhook mutation authority.
Until a later active contract assigns an owner, lifecycle, mutation surface,
worker behavior, and replay requirements, LiveKit webhook runtime remains
paused.

## 4. Allowed Runtime Behavior

The following behavior is allowed while LiveKit is paused:

- baseline replay may create `app.livekit_webhook_jobs` from accepted baseline
  authority
- the table may remain present as inert runtime support structure
- read-only observability may inspect worker status and queue counts
- read-only observability may report stopped, disabled, partial, blocked, or
  drift states
- static code references may exist as implementation drift only, provided they
  are not active startup, ingestion, queue mutation, or domain mutation paths

Allowed observability must not mutate canonical state and must not redefine
LiveKit runtime authority.

## 5. Forbidden Behavior

The following behavior is forbidden while LiveKit is paused:

- automatic worker startup
- manual worker startup for runtime processing
- idle worker startup used to make the surface appear healthy
- webhook ingestion that creates queue rows
- enqueueing rows into `app.livekit_webhook_jobs`
- releasing, locking, fetching, processing, retrying, failing, or deleting
  `app.livekit_webhook_jobs` rows as runtime behavior
- treating queue rows as canonical truth
- treating LiveKit event payloads as canonical truth
- mutating seminar, session, attendee, activity, recording, media, access,
  membership, onboarding, course, lesson, profile, or billing state from
  LiveKit events
- calling external LiveKit room lifecycle APIs from webhook worker execution
- activating LiveKit behavior by environment default, local MCP mode, backend
  startup side effect, or fallback path
- using tests, logs, observed queue state, or endpoint presence to promote
  LiveKit into active runtime authority

Implementation code that contains any forbidden behavior is implementation
drift unless and until a later active contract explicitly replaces this paused
model.

## 6. Worker Execution

Worker execution is not allowed while LiveKit is paused.

Required paused worker state:

```text
worker_running = false
```

The worker must not poll, lock, process, retry, fail, delete, or otherwise
advance jobs in `app.livekit_webhook_jobs`.

No-write verification mode does not activate LiveKit. If the LiveKit worker is
started in a no-write or idle mode, that is still not aligned with this paused
contract unless the observable worker state remains stopped or disabled.

## 7. Canonical Mutation

Canonical mutation from LiveKit is not allowed while paused.

LiveKit must not mutate canonical truth directly or indirectly.

Forbidden canonical mutation targets include, but are not limited to:

- `app.livekit_webhook_jobs`
- seminar/session state
- attendee presence
- activity records
- recording records
- media identity or runtime media truth
- course, lesson, enrollment, membership, auth, onboarding, profile, commerce,
  referral, billing, or access state

Non-canonical logging and telemetry may occur only if it remains isolated from
canonical authority and does not create domain truth.

## 8. Replay And Baseline Relationship

Baseline slot `0021_livekit_webhook_jobs_operational_queue.sql` may materialize
`app.livekit_webhook_jobs` as accepted paused runtime structure.

Baseline replay proves only that the inert queue substrate exists. It does not
prove that LiveKit is active, safe to execute, or authorized to mutate any
canonical state.

Future activation requires all of the following before runtime execution:

- an explicit active contract update or replacement
- an assigned domain owner
- a defined webhook lifecycle
- a defined worker lifecycle
- exact allowed mutation boundaries
- exact forbidden mutation boundaries
- baseline replay requirements for every required substrate
- manifest reconciliation
- clean verification that runtime behavior matches the active contract

If future activation requires schema changes, those changes must be append-only
baseline evolution and must update the baseline lock according to baseline
policy.

## 9. Fail-Closed Conditions

The LiveKit runtime surface must fail closed if any of the following are true:

- current worker state cannot be observed
- MCP/observability continuity cannot be established for worker health
- `app.livekit_webhook_jobs` is missing from a clean accepted baseline replay
- the LiveKit worker is running
- writes are not suppressed on a running LiveKit worker
- webhook ingestion can enqueue jobs
- queue processing can lock, retry, fail, or delete jobs
- LiveKit events can mutate canonical or domain state
- active code paths disagree with this contract
- manifest, baseline, runtime code, and observability evidence disagree
- any surface attempts to treat LiveKit as active without a later active
  contract and manifest reconciliation

Fail-closed outcome:

```text
SYSTEM BLOCKED FOR LIVEKIT RUNTIME ACTIVATION
```

## 10. Verification Requirements

Verification must be read-only unless a later execute-mode task explicitly
authorizes scoped reconciliation.

Required verification evidence:

- `ops/mcp_bootstrap_gate.ps1` passes in the current session before MCP-backed
  worker evidence is trusted
- `/healthz` is reachable when runtime evidence is required
- `/mcp/logs` is reachable when worker evidence is required
- `get_worker_health` reports `livekit_webhooks.worker_running = false`
- no active startup path starts `livekit_events.start_worker`
- no active mounted webhook route can call `handle_livekit_webhook` and enqueue
  jobs while paused
- no active LiveKit worker path can mutate canonical or domain state
- `app.livekit_webhook_jobs` remains classified as `RUNTIME / PAUSED`
- no baseline slot, lock file, manifest, source code, or database mutation is
  performed by verification

If verification finds `livekit_webhooks.worker_running = true`, then runtime is
not aligned to this contract.

If verification finds `write_suppressed = false` while the worker is running,
then runtime is not aligned to this contract.

If verification evidence is insufficient, the result is `UNKNOWN` or `BLOCKED`,
not activation.

## 11. Final Assertion

Canonical LiveKit webhook runtime state is paused.

`app.livekit_webhook_jobs` is inert runtime structure only.

Worker execution is forbidden.

Canonical mutation is forbidden.

Runtime activation is forbidden until a later active contract and manifest
reconciliation explicitly replace this paused authority model.
