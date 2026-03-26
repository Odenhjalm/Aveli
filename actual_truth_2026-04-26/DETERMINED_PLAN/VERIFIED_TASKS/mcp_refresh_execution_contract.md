## TASK ID

mcp_refresh_execution_contract

---

## PROBLEM

- Observability contracts still reference outdated example routes and a docs-only VERIFIED_TASK execution gate
- Current mounted MCP stack is implemented in: `backend/app/routes/logs_mcp.py`, `backend/app/routes/domain_observability_mcp.py`, `backend/app/routes/verification_mcp.py`, `backend/app/routes/media_control_plane_mcp.py`
- Equivalent evidence expected in: `actual_truth_2026-04-26/observability/mcp_observability_contract.md`, `docs/observability.md`, `docs/verification_mcp.md`, `docs/domain_observability_mcp.md`, `docs/media_control_plane_mcp.md`

---

## SYSTEM DECISION

- Observability contracts must follow mounted MCP reality
- No new runtime business logic is allowed
- Documentation must not invent unavailable execution guarantees

---

## REQUIRED ACTION

### STEP 1 — Locate candidates

- Open contract source files:
  `actual_truth_2026-04-26/observability/mcp_observability_contract.md`, `docs/observability.md`, `docs/verification_mcp.md`, `docs/domain_observability_mcp.md`, `docs/media_control_plane_mcp.md`, `backend/app/routes/logs_mcp.py`, `backend/app/routes/domain_observability_mcp.py`, `backend/app/routes/verification_mcp.py`, `backend/app/routes/media_control_plane_mcp.py`

- Identify every contract or example that does not match mounted MCP behavior

### STEP 2 — Handler selection

#### STEP 2A — Selection criteria

Selected execution contract MUST:

- match currently mounted MCP routes
- match current API surfaces used in examples
- NOT describe automation that the repo does not implement

#### STEP 2B — Response contract (MANDATORY)

Expected response MUST be defined BEFORE implementation.

Response MUST:

- be markdown contract output
- list current MCP servers and responsibilities
- list current VERIFIED_TASK execution assumptions explicitly
- replace outdated route examples

FOR read routes:
- MUST return structured data (list or object)

FOR write routes:
- MUST return confirmation or created resource

#### STEP 2C — Response validation rules

Selected contract MUST:

- be deterministic
- reflect current mounted code
- NOT treat aspirational automation as implemented behavior

IF response contract is unclear:
→ STOP

#### STEP 2D — Selection rule

IF docs and mounted code disagree:

- prefer mounted code
- keep older examples only as historical notes

- IF still ambiguous:
  → STOP

### STEP 3 — Adapter implementation

#### STEP 3A — Route creation

- Create updated execution-contract artifacts:
  `actual_truth_2026-04-26/observability/mcp_observability_contract.md`
  `docs/observability.md`
  `docs/verification_mcp.md`

#### STEP 3B — Adapter rules

Contract refresh MUST:

- preserve current MCP server responsibilities
- replace outdated `/checkout/session` and old upload examples
- describe VERIFIED_TASK pre-check/post-check behavior exactly as implemented

#### STEP 3C — Request/response passthrough

- Current MCP routes MUST be described unchanged
- Current example API paths MUST be described unchanged
- No speculative transformations allowed

### STEP 4 — Failure handling

IF:

- mounted MCP stack cannot be proven
- execution-gate behavior is ambiguous
- docs require inventing missing automation

→ STOP

---

## DO NOT

- add new MCP servers implicitly
- change MCP runtime behavior
- claim automation that does not exist
- modify product logic

---

## VERIFICATION

After change:

- observability docs match mounted MCP routes
- outdated checkout/upload examples are replaced
- VERIFIED_TASK execution guidance matches actual repo behavior

---

## STOP CONDITIONS

- current MCP stack cannot be proven
- contract requires inventing behavior
- example route ownership is ambiguous

---

## RISK LEVEL

LOW

---

## CATEGORY

observability / contract_refresh

---

## EXECUTION ORDER

- Can be executed independently: true
- Depends on: `api_refresh_usage_diff_current_frontend`

---

## NOTES

- Contract refresh only
- Mounted MCP routes remain canonical
