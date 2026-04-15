# T01 Execution Result - Canonical Corpus Authority

TASK_ID: T01
EXECUTION_STATUS: PASS
MODE: execute
CONTROLLER_SCOPE: retrieval_indexing_controller

## Authority Load

- `codex/AVELI_OPERATING_SYSTEM.md`
- `actual_truth/Aveli_System_Decisions.md`
- `actual_truth/aveli_system_manifest.json`
- `actual_truth/contracts/retrieval/determinism_contract.md`
- `actual_truth/contracts/retrieval/evidence_contract.md`
- `actual_truth/contracts/retrieval/index_structure_contract.md`
- `actual_truth/contracts/retrieval/ingestion_contract.md`
- `actual_truth/contracts/retrieval/retrieval_contract.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T00_execution_controller.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T01_resolve_canonical_corpus_authority.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/task_manifest.json`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/DAG_SUMMARY.md`
- `tools/index/*`
- `tools/mcp/semantic_search_server.py`

## Controller State Before T01

- Task tree status was `NOT_STARTED`.
- DAG next allowed task was `T01`.
- `T01` had no dependencies.
- `.repo_index` was absent and was not created.

## Canonical Authority Decision

`.repo_index/index_manifest.json` is the only valid corpus authority and the
only valid retrieval/indexing configuration authority.

No other file list, runtime scan, cache, vector-store metadata, lexical metadata,
or MCP wrapper output may define corpus membership.

## Current Authority Source Classification

`index_manifest.json`:

- Classification: canonical authority.
- Owns: corpus membership, corpus hash, chunk settings, model policy, ranking
  policy, candidate limits, artifact bindings, classification policy, device
  policy, and version policy.

`search_manifest.txt`:

- Classification: deprecated, non-authoritative.
- Allowed future role: optional derived export or debug artifact only.
- Forbidden role: corpus authority, hash authority, or retrieval input authority.

`searchable_files.txt`:

- Classification: deprecated, non-authoritative.
- Allowed future role: optional inventory/export/debug artifact only.
- Forbidden role: corpus authority or required authoritative artifact.

`rg --files`:

- Classification: inspection/build helper only.
- Allowed future role: controlled implementation detail for candidate discovery
  before manifest validation, if later permitted by controller task.
- Forbidden role: canonical corpus source or query-time discovery source.

Chroma metadata:

- Classification: derived vector artifact metadata.
- Allowed future role: parity verification against `index_manifest.json` and
  `chunk_manifest.jsonl`.
- Forbidden role: corpus membership authority, model authority, or ranking
  authority.

Lexical index metadata:

- Classification: derived lexical artifact metadata.
- Allowed future role: parity verification against `index_manifest.json` and
  `chunk_manifest.jsonl`.
- Forbidden role: corpus membership authority or ranking authority.

MCP semantic-search wrapper:

- Classification: transport only.
- Allowed future role: call canonical retrieval and wrap canonical evidence.
- Forbidden role: own corpus, ranking, embedding, cache, or rebuild behavior.

## Contract Drift Identified

- `ingestion_contract.md` names `.repo_index/search_manifest.txt` as the
  canonical ingestion manifest.
- `index_structure_contract.md` names `.repo_index/searchable_files.txt` as an
  authoritative artifact.
- `determinism_contract.md` requires `.repo_index/index_manifest.json` as the
  single canonical configuration authority.
- `evidence_contract.md` requires `.repo_index/index_manifest.json` as the
  canonical classification authority.
- `build_repo_index.sh` creates and validates `search_manifest.txt` and
  `searchable_files.txt`.
- `build_vector_index.py` reads `search_manifest.txt` and computes corpus hash
  from it.
- `search_code.py` includes `search_manifest.txt` in required artifact checks.
- `semantic_search_server.py` currently exposes a ripgrep wrapper surface and is
  not yet a thin canonical retrieval wrapper.

## Required Corrections

- Update retrieval contracts so `index_manifest.json` is the only corpus and
  configuration authority.
- Deprecate `search_manifest.txt` and `searchable_files.txt` as authority.
- Retain those legacy files only as optional non-authoritative exports if a
  later task explicitly permits them.
- Prohibit query-time corpus discovery.
- Prohibit Chroma, lexical index, cache, and MCP surfaces from owning corpus
  membership.

## Verification Result

T01 passed because the canonical authority conflict is resolved without
ambiguity:

- One canonical authority is declared.
- Legacy authority surfaces are classified as non-authoritative.
- Current contract drift is identified.
- No index was built.
- `.repo_index` was not created.
- No model was downloaded or executed.
- CUDA was not used.
- No retrieval query was executed.
- T02 was not executed.

## Next Transition

Only `T02` may execute next, under controller governance.
