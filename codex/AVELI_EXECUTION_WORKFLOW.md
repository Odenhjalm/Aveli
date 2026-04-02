# AVELI Execution Workflow

This file is mandatory for all Codex work inside Aveli.

Codex MUST follow this workflow exactly.
Codex MUST NOT skip, reorder, merge, or duplicate stages.
Codex MUST NOT use any legacy or alternative flow.

---

## Preconditions

Before work starts, Codex MUST confirm:

- repository is available
- `codex/AVELI_OPERATING_SYSTEM.md` is loaded
- this workflow file is available
- task input is explicit
- mode input is explicit

If OS confirmation is missing:

- STOP

If any required input is missing:

- STOP

---

## Task Input Model

Every execution MUST start with a task.

Task defines:

- scope
- retrieval queries
- evaluation criteria

No system operation may run without an explicit task context.

Every run MUST begin with:

`input(task, mode)`

---

## Canonical Pipeline

The canonical pipeline is:

`input(task, mode) -> ingestion -> index -> retrieval -> evidence -> contract -> verification`

Codex MUST execute this pipeline in the exact order shown above.

Rules:

- task is the primary input driver for the entire retrieval pipeline
- retrieval MUST remain task-scoped
- evidence MUST remain canonical
- contract MUST always be applied before verification
- no phase may duplicate another phase's responsibility
- no fallback flow exists

---

## Stage Definitions

### `input(task, mode)`

Purpose:

- bind explicit task context
- bind explicit execution mode

MUST:

- reject missing task context
- reject missing mode
- reject mode changes after start

---

### `ingestion`

Purpose:

- load the authoritative inputs required by the task

MUST:

- ingest only task-relevant authoritative sources
- preserve task scope exactly
- avoid contract interpretation

MUST NOT:

- verify
- generate fallback scope

---

### `index`

Purpose:

- bind the task to the active canonical retrieval index

MUST:

- use the active authoritative index
- follow the OS vector index policy exactly

MUST NOT:

- rebuild index unless the OS allows it
- broaden task scope

---

### `retrieval`

Purpose:

- execute task-scoped retrieval

MUST:

- use only the task-defined scope
- use only the task-defined retrieval queries
- return only retrieval output relevant to the task

MUST NOT:

- perform broad exploratory search outside task scope
- substitute a different task

---

### `evidence`

Purpose:

- convert retrieval output into canonical evidence

MUST:

- keep evidence traceable
- keep evidence canonical
- keep evidence task-scoped

MUST NOT:

- reinterpret contract
- validate implementation

---

### `contract`

Purpose:

- diff canonical evidence against canonical truth

MUST:

- produce deterministic contract diff
- define what verification must evaluate

MUST NOT:

- verify before diff exists
- produce alternate truth models

---

### `verification`

verification = mode-driven final stage

- generate -> task generation
- execute -> task validation
- confirm -> system truth assertion

MUST:

- consume contract output only after contract stage completes
- stay within task scope
- fail if required evidence or contract inputs are missing

MUST NOT:

- run before contract
- duplicate ingestion, retrieval, evidence, or contract responsibilities

---

## Execution Modes

### MODE: generate

purpose:

- produce tasks from contract diff

output:

- deterministic task set

MUST:

- not assume implementation
- not mutate system state

---

### MODE: execute

purpose:

- validate implementation against contract

output:

- pass/fail per task

MUST:

- use canonical evidence
- not reinterpret contracts

---

### MODE: confirm

purpose:

- assert system matches canonical truth

output:

- PASS or FAIL

MUST:

- fail on any deviation
- not produce new tasks

---

## Enforcement Rules

- Mode MUST be explicit for every run
- Mode MUST NOT change during execution
- Mixing modes in one run is forbidden
- Contract MUST always be applied before verification
- No legacy phase chain, verified-task gate, batch flow, or alternate workflow remains
- Any conflict with `codex/AVELI_OPERATING_SYSTEM.md` is a blocking error

---

## Consistency Target

The workflow is valid only when all are true:

- pipeline uses task as input
- retrieval is task-scoped
- evidence remains canonical
- contract is applied before verification
- no phase overlaps responsibility
- no fallback flow exists

If any check fails:

- STOP
