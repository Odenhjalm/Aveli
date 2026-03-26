## TASK ID

mcp_resolve_semantic_search_gap

---

## PROBLEM

- Current observability contract requires `semantic-search` as a mandatory pre-check source
- Repo-local MCP implementation only exposes logs, media-control-plane, verification, and domain-observability servers
- Equivalent evidence expected in: `codex/AVELI_OPERATING_SYSTEM.md`, `actual_truth_2026-04-26/observability/mcp_observability_contract.md`, `backend/app/routes/logs_mcp.py`, `backend/app/routes/domain_observability_mcp.py`, `backend/app/routes/verification_mcp.py`, `backend/app/routes/media_control_plane_mcp.py`

---

## SYSTEM DECISION

- Contracts must not require unavailable local infrastructure
- No hidden fallback is allowed
- No new business logic is allowed

---

## TASK VALIDITY

- is_real_problem: true
- already_satisfied: false
- requires_code_change: false

---

## PROBLEM TYPE

problem_type: observability_issue

classification_reason: The gap is a contract-level false requirement in the observability docs, not a missing runtime architecture layer. The local MCP stack exposes four Aveli servers, while `semantic-search` is only documented as mandatory.

---

## REQUIRED ACTION

### STEP 1 — Locate candidates

- Open contract source files:
  `codex/AVELI_OPERATING_SYSTEM.md`, `actual_truth_2026-04-26/observability/mcp_observability_contract.md`, `backend/app/routes/logs_mcp.py`, `backend/app/routes/domain_observability_mcp.py`, `backend/app/routes/verification_mcp.py`, `backend/app/routes/media_control_plane_mcp.py`

- Identify whether `semantic-search` is intended to be external, planned, or missing

### STEP 2 — Handler selection

#### STEP 2A — Selection criteria

Selected resolution MUST:

- remove the mandatory `semantic-search` requirement from contracts unless local availability can be proven
- NOT leave the gap implicit

#### STEP 2B — Response contract (MANDATORY)

Expected response MUST be defined BEFORE implementation.

Response MUST:

- be markdown contract output
- state whether `semantic-search` is external, historical, or removed from mandatory local execution rules
- preserve deterministic pre-check requirements

FOR read routes:
- MUST return structured data (list or object)

FOR write routes:
- MUST return confirmation or created resource

#### STEP 2C — Response validation rules

Selected resolution MUST:

- be explicit
- NOT depend on hidden infrastructure
- NOT claim local availability without evidence

IF response contract is unclear:
→ STOP

#### STEP 2D — Selection rule

IF repo code does not provide semantic-search:

- prefer explicit contract correction

- IF still ambiguous:
  → STOP

### STEP 3 — Adapter implementation

#### STEP 3A — Route creation

- Create explicit semantic-search resolution artifact in:
  `actual_truth_2026-04-26/observability/mcp_observability_contract.md`
  and dependent determined-plan docs

#### STEP 3B — Adapter rules

Resolution MUST:

- preserve current MCP stack truth
- NOT add implied runtime servers
- NOT weaken the no-assumption rule

#### STEP 3C — Request/response passthrough

- Current MCP server list MUST remain unchanged
- Semantic-search status MUST be stated unchanged from evidence
- No speculative transformations allowed

### STEP 4 — Failure handling

IF:

- semantic-search ownership cannot be proven
- contract cannot be corrected without guesswork
- resolution requires hidden infrastructure assumptions

→ STOP

---

## DO NOT

- pretend semantic-search exists locally
- invent a fallback
- modify current MCP runtime code without proof
- weaken explicit stop conditions

---

## VERIFICATION

After change:

- semantic-search requirement is either implemented explicitly or removed explicitly from the mandatory contract
- no hidden dependency remains in VERIFIED_TASK execution guidance

---

## STOP CONDITIONS

- semantic-search ownership is unknown
- contract correction requires guessing
- hidden infrastructure assumptions are required

---

## RISK LEVEL

MEDIUM

---

## CATEGORY

observability / contract_refresh

---

## EXECUTION ORDER

- Can be executed independently: true
- Depends on: `mcp_refresh_execution_contract`

---

## NOTES

- Contract-correction task
- No new MCP server should be implied
