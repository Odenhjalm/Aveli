# T11 - Define Retrieval Contract Read Only

TYPE: design
OS_ROLE: OWNER
EXECUTION_STATUS: PASS
DEPENDS_ON: [T07, T09, T10]

## Purpose

Define the canonical read-only retrieval behavior for indexed repository search.

## Scope

Design only. Do not run retrieval, create caches, or inspect `.repo_index` as an
active retrieval source.

## Authority References

- `actual_truth/contracts/retrieval/retrieval_contract.md`
- `actual_truth/contracts/retrieval/evidence_contract.md`
- `actual_truth/contracts/retrieval/determinism_contract.md`
- T07 artifact model
- T09 lexical contract
- T10 vector contract

## Dependencies

- T07
- T09
- T10

## Expected Outcome

The retrieval contract defines this order: normalize query, validate healthy
index artifacts, read lexical candidates from persistent lexical index, read
vector candidates from persistent Chroma index, union by canonical `doc_id`,
bounded rerank if declared by manifest, deterministic sort by descending score
then ascending normalized file path then ascending `doc_id`, and emit canonical
evidence objects only.

## Stop Conditions

- Query path writes cache or memory artifacts.
- Query path scans corpus files.
- Query path rebuilds or repairs artifacts.
- Query path downloads or initializes models per request.
- Missing or corrupt index falls back to another search path.
- Evidence object shape is changed.

## Verification Requirements

- Same query and same healthy index produce byte-identical ordered evidence.
- No authoritative artifact changes during query.
- Output evidence has exactly `file`, `layer`, `snippet`, `source_type`, `score`.

## Mutation Rules

No runtime mutation is allowed in retrieval. Retrieval is read-only. Controller
execution may update this task status and write `T11_execution_result.md` only.

## Output Artifacts

- `T11_execution_result.md`

## Next Transitions

- T12
- T13
