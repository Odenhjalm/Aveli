# RPAR-E01_CORPUS_AUTHORITY

## TASK_ID

RPAR-E01

## TYPE

CORPUS_AUTHORITY

## OWNER

OWNER

## CANONICAL_OWNER

corpus authority

## DEPENDS_ON

- `RPAR-D01`

## GOAL

Materialize the future corpus-authority remediation that prevents historical
task narratives from being treated as active LAW or active current truth during
retrieval.

The locked truth for this slice is:

- active authority and historical narrative must be explicitly separated
- evidence output may not present stale narrative as current truth
- corpus authority must be governed, not query-suppressed ad hoc

## AUTHORITY INPUTS

- `codex/AVELI_OPERATING_SYSTEM.md`
- `actual_truth/contracts/task_tree_execution_controller_contract.md`
- `actual_truth/contracts/retrieval/ingestion_contract.md`
- `actual_truth/contracts/retrieval/evidence_contract.md`
- `actual_truth/contracts/retrieval/retrieval_contract.md`
- `tools/index/build_vector_index.py`
- `tools/index/search_code.py`
- `.repo_index/index_manifest.json`

## VALIDATED ISSUE BASIS

Current classification rules can elevate `actual_truth` and related paths to
`LAW`, and the retrieval evidence path can emit chunks from historical
`actual_truth/DETERMINED_TASKS` documents as if they were current authority.

## SCOPE

- `tools/index/build_vector_index.py`
- `tools/index/search_code.py`
- any directly coupled retrieval authority/evidence contract surface required
  to make the hierarchy explicit

## EXACT REQUIRED OUTCOME

When `RPAR-E01` executes later, implement only the corpus-authority work
required to guarantee all of the following:

- historical task documents are not classified as active LAW by default
- the authority hierarchy for contracts, manifests, execution records, and
  historical narratives is explicit
- retrieval evidence cannot surface stale historical narrative as active
  current truth

## FORBIDDEN ACTIONS

- Do not execute this slice before `RPAR-A01` and `RPAR-B01` are complete.
- Do not rely on hidden query suppression or manual deny-lists as the primary
  fix.
- Do not change runtime freshness logic.
- Do not change build CUDA or integrity logic.
- Do not add tests in this slice.

## ACCEPTANCE CRITERIA

- Historical task documents are demoted, labeled, or excluded under an
  explicit authority rule.
- Queries that previously surfaced stale narrative no longer present it as
  active truth.
- Current contracts and active runtime authority remain retrievable.
- Evidence output makes the authority class explicit where required.

## STOP CONDITIONS

- `RPAR-A01` or `RPAR-B01` is incomplete.
- The authority hierarchy is not fully explicit.
- The slice requires hidden runtime fallback or query-specific suppression to
  pass.
- Current active authority becomes less retrievable than historical narrative.

## VERIFICATION STEPS

- Run targeted retrieval queries that previously surfaced historical task
  narratives.
- Inspect authority labels and evidence payloads.
- Confirm current contracts still rank as active authority.
- Confirm historical narratives no longer surface as active LAW or active
  current truth.

## PROMPT

```text
Execute RPAR-E01 as the corpus-authority slice only. Define the explicit authority hierarchy for retrieval corpus classes so historical task documents cannot surface as active LAW or active current truth, while current contracts and active runtime authority remain retrievable. Do not change runtime freshness, observability schemas, build truthfulness, vector integrity logic, or tests in this slice.
```
