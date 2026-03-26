# MCP Observability Contract

Source context loaded:
- `codex/AVELI_OPERATING_SYSTEM.md`
- `aveli_system_manifest.json`
- `.vscode/mcp.json`
- `actual_truth_2026-04-26/DETERMINED_PLAN/VERIFIED_TASKS/*`

This contract defines how Codex uses MCP before and after mutations.

## 1. MCP Server Roles

### aveli-logs
- Purpose: Collect deterministic runtime signals (errors, request logs, warnings, and execution traces) from the local Aveli runtime.
- When Codex should use it: When a query requires factual diagnosis of failure modes, trace correlation, or post-incident evidence.
- Questions it answers:
  - "What happened around timestamp `T` or request `id`?"
  - "Which runtime errors are currently active for a component/route/action?"
  - "What is the concrete execution evidence for an observed mismatch?"

### aveli-media-control-plane
- Purpose: Provide the authoritative control-plane perspective for media behavior and policy enforcement, aligned with manifest rules marking media control plane as protected authority.
- When Codex should use it: For any media mutation, media route investigation, or consistency check where media behavior is the expected outcome.
- Questions it answers:
  - "What is the media control-plane state and policy for this action/path?"
  - "Which media policy or rule is governing current behavior?"
  - "Has the media control layer accepted or rejected the requested change/operation?"

### aveli-domain-observability
- Purpose: Expose domain-level Aveli state for invariants, component trust boundaries, and cross-component impact.
- When Codex should use it: Before and after domain-touching mutations or when a task spans API/media/auth/editor invariants.
- Questions it answers:
  - "What is the current domain state relevant to a task?"
  - "Are required invariants currently satisfied for the relevant component?"
  - "What is the broader impact boundary for a proposed change?"

### aveli-verification
- Purpose: Verify contracts, rules, and expected behavior before and after changes.
- When Codex should use it: For deterministic route correctness checks, policy checks, and invariant checks after every mutation.
- Questions it answers:
  - "Does the target route/component satisfy declared invariants now?"
  - "Which expected contract check passed or failed?"
  - "Which specific rule is violated by current state?"

### semantic-search
- Purpose: Return exact local evidence from indexed documentation, past plans, and verified task artifacts.
- When Codex should use it: At decision points requiring evidence from prior work, standards, or known task outcomes.
- Questions it answers:
  - "Where is an exact match for this issue in VERIFIED_TASKS?"
  - "What was the last proven approach for a similar failure?"
  - "Which constraints/docs govern this component?"

## 2. Usage Rules (Deterministic)

- IF scenario = debugging media workflow → use `aveli-media-control-plane`.
- IF scenario = verifying route correctness → use `aveli-verification`.
- IF scenario = tracing runtime errors → use `aveli-logs`.
- IF scenario = checking cross-domain invariants or impact scope before/after mutation → use `aveli-domain-observability`.
- IF scenario = retrieving prior verified patterns / task evidence → use `semantic-search`.
- IF scenario = no MCP data is needed or MCP has explicit authoritative answer → default to the highest available Aveli MCP before API, SQL, or UI.
- IF MCP query fails or is unavailable → log reason and follow fallback order from the operating contract after explicitly recording uncertainty.

## 3. Output Contract

All MCP calls must be normalized to the same response schema:

- `status`: `ok | warning | mismatch | blocked | error`
- `data`: server-specific payload or empty object when absent.
- `source`: object describing provenance
  - `server`: MCP server name
  - `query`: exact question or intent
  - `trace_id` (optional): request/operation correlation identifier
  - `timestamp`: UTC time of response
  - `evidence_uri` (optional): server-specific pointer to supporting output
- `confidence`: `high | medium | low`

No field may be omitted from the contract.

### Normalization rules

- `status = ok` only when the server returns a direct positive validation with no unresolved mismatches.
- `status = warning` only when behavior is valid but incomplete.
- `status = mismatch` only when expected and actual behavior differ.
- `status = blocked` only when required confirmation cannot be obtained and mutation must halt.
- `status = error` only on query failure, transport failure, or unverifiable output.

## 4. Codex Behavior Rules

Codex MUST:

- Prefer MCP over assumptions.
- Prefer Aveli MCPs before API, SQL, or UI checks.
- Halt immediately if MCP data contradicts expected behavior or expected invariant.
- Never infer missing data.
- Never mix diagnosis and repair without a prior MCP-supported observation.
- Never call UI as primary truth source.
- Never modify endpoints or server configuration in this contract artifact.

## 5. Integration with VERIFIED_TASKS

- Pre-check trigger:
  - For every task derived from `actual_truth_2026-04-26/DETERMINED_PLAN/VERIFIED_TASKS/*`, call `semantic-search` to load prior verified context.
  - Then call `aveli-verification` for the relevant target invariant(s).
  - For media-related tasks, additionally call `aveli-media-control-plane`.
  - For any task touching broader domain behavior, call `aveli-domain-observability`.

- Execution guard:
  - If pre-check returns `mismatch`, `blocked`, or `error`, halt mutation and emit `status` with source + confidence.

- Post-check trigger:
  - Re-run the same check set after each mutation.
  - If any post-check returns `mismatch`, `blocked`, or `error`, treat the task as failed verification.

- Post-check parity rule:
  - State is accepted only when pre-check and post-check `status` are both `ok` (or acceptable `warning` with rationale recorded) and no unresolved mismatch exists.

## 6. MCP Priority

Priority order for conflict resolution:

1. aveli-verification (source of truth)
2. aveli-media-control-plane (authority for media)
3. aveli-domain-observability (system invariants)
4. aveli-logs (runtime evidence)
5. semantic-search (historical reference)

Rules:

* IF multiple MCP responses conflict:
  → follow highest priority source

* IF conflict cannot be resolved:
  → STOP

## 7. Confidence Definition

confidence levels MUST be interpreted as:

* high → directly verified from canonical source (verification or control-plane)
* medium → derived from domain-observability or logs
* low → inferred or incomplete

Rules:

* Codex MUST NOT act on low confidence results
* Codex MUST escalate or STOP when confidence is low

## 8. Semantic-Search Enforcement

semantic-search MUST be used:

* before handler selection
* before adapter creation
* when similar VERIFIED_TASK exists

Rules:

* IF matching VERIFIED_TASK is found:
  → reuse pattern
* IF no relevant result:
  → continue but mark uncertainty

## 9. Execution Gate

Codex MUST NOT perform mutation until ALL conditions are met:

* semantic-search completed
* verification pre-check status = ok
* required MCP sources agree on system state

Rules:

* IF any MCP returns:

  * mismatch
  * blocked
  * error

→ STOP

## 10. Allowed Mutation Condition

Codex MAY proceed with mutation IF:

- status = mismatch
- AND a VERIFIED_TASK exists that explicitly targets the mismatch

In this case:

- mismatch is treated as expected condition
- execution is allowed

---

Rules:

- IF mismatch matches VERIFIED_TASK scope:
  → proceed

- IF mismatch is unrelated:
  → STOP