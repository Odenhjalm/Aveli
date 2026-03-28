# AVELI Execution Workflow

This file is mandatory for all Codex work inside Aveli.

Codex MUST follow this workflow exactly.
Codex MUST NOT skip phases.
Codex MUST NOT implement before verified tasks exist.

---

## Purpose

This workflow exists to prevent:
- premature implementation
- missing audit steps
- stale truth models
- dependency mistakes
- false launch readiness

Codex MUST behave as a deterministic system operator.

---

## Phase Order

### Phase 0 — Preconditions
Before work starts, Codex MUST confirm:

- repository is available
- `codex/AVELI_OPERATING_SYSTEM.md` is loaded
- this workflow file is available
- repo search tools are available
- current truth source is available
- local verification paths are available if needed

If required inputs are missing:
- STOP

---

### Phase 1 — Rebuild `actual_truth/`
Goal:
Produce a fresh, evidence-backed snapshot of the system.

Codex MUST:

1. remove existing `actual_truth/`
2. recreate `actual_truth/`
3. inspect each domain in order
4. write evidence files only
5. NOT generate implementation changes
6. NOT generate verified tasks yet

Required domains:

- auth
- courses
- api_layer
- playback
- media_control_plane
- media_upload_pipeline
- homeplayer
- editor
- observability

For each domain, Codex MUST write:

- `comparison.md`
- `relevant_files.md`
- `metadata.json`
- `tasks.md`

Per domain method:

1. read SYSTEM_LAWS
2. fetch CURRENT_TRUTH from Supabase
3. map EMERGENT_TRUTH from repo and local runtime
4. use semantic search to connect logic
5. use MCP only to validate contradictions
6. classify findings:
   - aligned
   - mismatch
   - drift
   - violation
   - unknown
   - blocked

Codex MUST NOT implement anything in this phase.

Exit criteria:
- all domains written
- no missing required files
- evidence is traceable

---

### Phase 2 — Create `actual_truth/DETERMINED_TASKS/`
Goal:
Derive raw task candidates from audited truth.

Codex MUST:

1. create `actual_truth/DETERMINED_TASKS/`
2. derive tasks only from evidence in `actual_truth/`
3. create one task file per task

Each determined task MUST include:

- task_id
- title
- domain
- problem_type
  - mismatch
  - drift
  - violation
  - blocked
- problem_statement
- evidence_sources
- impacted_files
- current_truth
- emergent_truth
- target_state
- verification_method
- dependencies
- launch_impact

Codex MUST NOT implement in this phase.

Exit criteria:
- all task candidates exist
- every task is traceable to actual_truth evidence

---

### Phase 3 — Create `verified_tasks/`
Goal:
Convert raw task candidates into execution-grade tasks.

Codex MUST:

1. create or replace `verified_tasks/`
2. read all `actual_truth/DETERMINED_TASKS/`
3. deduplicate
4. merge overlap
5. detect blockers
6. sort by dependency order
7. classify launch criticality

Each verified task MUST include:

- task_id
- title
- domain
- severity
  - launch_blocker
  - critical
  - medium
  - later
- problem_statement
- why_this_matters
- evidence_sources
- impacted_files
- dependencies
- prerequisite_tasks
- acceptance_criteria
- verification_steps
- rollout_risk
- batch_group

Codex MUST NOT implement in this phase.

Exit criteria:
- all verified tasks are dependency-ordered
- launch blockers are explicit
- no duplicate tasks remain

---

### Phase 4 — Build `implementation_plan.md`
Goal:
Create execution batches from verified tasks.

Codex MUST:

1. read all `verified_tasks/`
2. build dependency-safe batches
3. write `implementation_plan.md`

The plan MUST include:

- batch order
- task membership
- dependency justification
- pre-verification required
- post-verification required
- rollback notes

Codex MUST NOT implement tasks not present in `verified_tasks/`.

Exit criteria:
- all launch-blocking work is covered
- no batch violates dependency order

---

### Phase 5 — Implement Batch by Batch
Goal:
Apply changes safely and verify after each batch.

Codex MUST for each batch:

1. verify preconditions
2. implement only tasks in the current batch
3. run targeted verification
4. update task statuses
5. stop if verification fails

Codex MUST NOT:
- skip to later batches
- mix unrelated tasks
- silently continue after failed verification

Exit criteria:
- batch passes verification
- task statuses updated

---

### Phase 6 — Full Verification
Goal:
Prove the launch scope works end-to-end.

Codex MUST run:

- local backend verification
- DB verification
- MCP verification
- targeted API verification
- Playwright verification for critical user journeys

Required Playwright scope:

- login / authenticated entry if in scope
- course access happy path
- denied access path
- playback happy path
- any launch-critical checkout/access path in scope

Codex MUST use Playwright only in this phase unless a task is explicitly UI-only.

Exit criteria:
- all critical verification passes
- no launch blockers remain unresolved

---

### Phase 7 — Launch Readiness
Goal:
Declare whether the system is ready.

Codex MAY write `launch_readiness_report.md`.

A launch-ready verdict is allowed only if:

- no launch blockers remain
- all launch-critical verified tasks are done
- Playwright critical paths pass
- backend/runtime verification passes
- DB and service logic are aligned in launch scope

If not true:
- report NOT READY

---

## Tool Usage Rules

### Repo tools
Codex MUST use:

- `build_repo_index.sh`
- `build_vector_index.py` only when required
- `search_code.py`
- `analyze_results.py`

### Supabase
Supabase is CURRENT_TRUTH.

Use it for:
- schema truth
- row truth
- enforcement truth
- existence truth

### MCP
Use MCP for targeted validation only.

Preferred order:
1. verification
2. media control plane
3. logs
4. domain observability

### Playwright
Use only in Phase 6 unless task is explicitly UI-only.

---

## Rebuild Rules

Codex MUST rebuild vector index only if:
- index missing
- embeddings invalid
- repo changed enough to invalidate search
- explicit rebuild requested

Codex MUST NOT casually rebuild expensive indexes.

---

## No-Skip Rules

Codex MUST NOT:
- implement before Phase 3 is complete
- create verified tasks before actual_truth exists
- call the system ready before Phase 6 passes
- use docs as stronger truth than runtime enforcement
- replace phases with intuition

---

## Success Definition

The system is successful only when:

- actual_truth is fresh
- determined tasks are derived from evidence
- verified tasks are dependency-ordered
- implementation follows verified tasks
- Playwright confirms critical paths
- launch readiness is explicit and justified