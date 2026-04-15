# T11 Execution Result - Retrieval Contract Read Only

TASK_ID: T11
EXECUTION_STATUS: PASS
MODE: execute
CONTROLLER_SCOPE: retrieval_indexing_controller

## Authority Load

- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/task_manifest.json`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/DAG_SUMMARY.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T11_define_retrieval_contract_read_only.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T01_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T02_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T03_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T04_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T05_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T06_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T07_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T08_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T09_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T10_execution_result.md`
- `codex/AVELI_OPERATING_SYSTEM.md`
- `actual_truth/Aveli_System_Decisions.md`
- `actual_truth/aveli_system_manifest.json`
- `actual_truth/contracts/retrieval/determinism_contract.md`
- `actual_truth/contracts/retrieval/evidence_contract.md`
- `actual_truth/contracts/retrieval/index_structure_contract.md`
- `actual_truth/contracts/retrieval/ingestion_contract.md`
- `actual_truth/contracts/retrieval/retrieval_contract.md`
- `tools/index/ENVIRONMENT_SETUP.sh`
- `tools/index/analyze_results.py`
- `tools/index/ast_extract.py`
- `tools/index/build_repo_index.sh`
- `tools/index/build_vector_index.py`
- `tools/index/codex_query.py`
- `tools/index/device_utils.py`
- `tools/index/requirements.txt`
- `tools/index/run_codex.py`
- `tools/index/run_codex_auto.py`
- `tools/index/search_code.py`
- `tools/index/semantic_search.sh`
- `tools/index/test_build_vector_index_manifest_bootstrap.py`
- `tools/index/validate_codex.py`
- `tools/mcp/semantic_search_server.py`

## Controller State Before T11

- `T01` was repo-visible `PASS`.
- `T02` was repo-visible `PASS`.
- `T03` was repo-visible `PASS`.
- `T04` was repo-visible `PASS`.
- `T05` was repo-visible `PASS`.
- `T06` was repo-visible `PASS`.
- `T07` was repo-visible `PASS`.
- `T08` was repo-visible `PASS`.
- `T09` was repo-visible `PASS`.
- `T10` was repo-visible `PASS`.
- `T11` was repo-visible `NOT_STARTED`.
- `DAG_SUMMARY.md` allowed only `T11` as the next executable task.
- `.repo_index` was absent and was not created.

## Executive Verdict

PASS with CONTRACT_DRIFT identified for later correction.

T11 defines the canonical read-only retrieval contract for controller-governed
repository search. It does not run retrieval, does not inspect `.repo_index` as
an active retrieval source, does not create cache or memory artifacts, does not
create `.repo_index`, does not install dependencies, does not download or load
models, does not execute CUDA, and does not build an index.

## T11 Execution Plan

T11 execution was limited to:

1. no-code audit of controller state and authority inputs.
2. verification that T07, T09, and T10 were repo-visible `PASS`.
3. verification that T04 normalization, T05 chunking, T06 identity/hashing,
   T07 artifact lifecycle, T08 model policy, T09 lexical contract, and T10
   vector contract were already locked.
4. comparison of current contracts and tools against the T11 read-only
   retrieval scope.
5. materialization of this T11 execution result.
6. controller status update for T11 only.

No T12 MCP wrapper contract, T13 Windows gate, T14 rebuild gate, or later task
was executed.

## Retrieval Authority Spec

Canonical retrieval is a read-only query operation over an active, healthy,
manifest-bound index.

Retrieval authority is owned by `.repo_index/index_manifest.json` through:

- `retrieval_policy`.
- `ranking_policy`.
- `classification_policy`.
- `artifact_policy`.
- `model_policy`.
- `embedding_policy`.
- `verification_policy`.

T11 owns:

- query-mode read-only behavior.
- canonical retrieval stage order.
- query normalization requirements.
- lexical/vector candidate composition boundaries.
- query embedding ownership boundary.
- candidate union rules.
- optional rerank rules.
- final score and deterministic sort rules.
- canonical evidence object output.
- retrieval STOP conditions.

T11 does not own:

- corpus membership.
- text/path normalization for corpus files.
- chunk boundaries.
- `doc_id` formula.
- artifact write order.
- model or tokenizer locks.
- lexical index internals.
- Chroma/vector storage internals.
- MCP transport behavior.
- rebuild approval.

Retrieval may consume only active verified artifacts. Retrieval must never use
`search_manifest.txt`, `searchable_files.txt`, `rg --files`, source tree scans,
caches, Chroma metadata, lexical metadata, or MCP inputs as corpus, ranking,
model, or configuration authority.

## Pipeline Definition

The canonical query path is:

1. controller query-mode preflight.
2. active manifest and artifact health validation.
3. query normalization.
4. lexical candidate retrieval from persistent `lexical_index/`.
5. query embedding generation under manifest-owned T08 policy.
6. vector candidate retrieval from persistent `chroma_db/`.
7. candidate union by canonical `doc_id`.
8. optional bounded rerank if manifest `ranking_policy` enables it.
9. final scoring from manifest `ranking_policy`.
10. deterministic sort.
11. canonical evidence output.

No step may write artifacts, repair artifacts, rebuild artifacts, discover
corpus files, create Chroma collections, create lexical indexes, or alter the
manifest.

## Query-Mode Preflight Requirements

Retrieval must STOP before serving any query unless all of these are true:

- `.repo_index/index_manifest.json` exists.
- manifest state is `ACTIVE_VERIFIED`.
- manifest validates against the T02 schema.
- required active artifacts exist:
  - `.repo_index/chunk_manifest.jsonl`
  - `.repo_index/lexical_index/`
  - `.repo_index/chroma_db/`
- `chunk_manifest_hash` matches T06 canonical JSONL bytes.
- lexical artifact hash matches manifest `artifact_hashes.lexical_index`.
- vector artifact hash matches manifest `artifact_hashes.chroma_db`.
- lexical `doc_id` set equals chunk manifest `doc_id` set.
- vector `doc_id` set equals chunk manifest `doc_id` set.
- lexical and vector `doc_id` sets equal each other.
- `contract_version`, `corpus_manifest_hash`, and `chunk_manifest_hash` match
  across all active artifacts.
- model and tokenizer locks match the active manifest.
- retrieval runtime uses the canonical Windows interpreter defined by T03/T13
  when implementation reaches the Windows gate.

Missing `.repo_index` is STOP. Missing active artifacts are STOP or
`CORRUPT_INDEX` according to T03/T16 classification. Missing index must never
trigger build.

## Query Normalization Contract

Query normalization is manifest-owned and deterministic.

Required query normalization policy fields:

- `algorithm`.
- `unicode_normalization`: canonical value `NFC`.
- `line_ending_policy`: canonical value `LF`.
- `tab_policy`.
- `leading_trailing_whitespace_policy`.
- `internal_whitespace_policy`.
- `case_policy`.
- `empty_query_policy`: canonical value `STOP`.
- `query_prefix_source`: canonical value `embedding_policy.query_prefix`.

Minimum query normalization behavior:

1. input must be a string.
2. normalize Unicode to NFC.
3. normalize CRLF and CR to LF.
4. apply manifest-owned tab and whitespace policy.
5. reject empty normalized queries.

Lexical query tokenization must use the T09 manifest-owned lexical policy.
Embedding query input must use normalized query text plus the T08
manifest-owned `query_prefix`. No MCP, CLI, or script-local heuristic may alter
query text outside this policy.

## Stage Responsibilities

Lexical stage:

- owns candidate generation from persistent `lexical_index/` only.
- returns at most `retrieval_policy.lexical_candidate_k` candidates.
- returns canonical `doc_id` values.
- may return non-authoritative lexical diagnostic score if manifest permits it.
- must not define final ranking.
- must not scan source files.
- must not rebuild lexical statistics.
- must not write cache or memory artifacts.

Vector stage:

- owns similarity candidate generation from persistent `chroma_db/` only.
- receives query embedding from canonical retrieval, not from Chroma-owned
  model logic.
- returns at most `retrieval_policy.vector_candidate_k` candidates.
- returns canonical `doc_id` values.
- may return non-authoritative vector distance or similarity diagnostic if
  manifest permits it.
- must not define final ranking.
- must not create Chroma collections.
- must not repair or rebuild Chroma.
- must not write cache or memory artifacts.

Query embedding stage:

- is owned by canonical retrieval under T08 policy.
- uses manifest-owned model, tokenizer, prefix, dtype, dimension, and device
  policy.
- must use local-only locked model surfaces.
- must not download models.
- must not switch models.
- must not initialize models per request if runtime design supports a resident
  verified model surface.

Rerank stage:

- is optional.
- may run only if manifest `ranking_policy.rerank_enabled` is true.
- must operate only on the bounded union candidate set.
- must use manifest-owned model policy from T08.
- must not introduce new candidates.
- must not read source files outside approved chunk/evidence material.
- must not alter `doc_id`, file, layer, or source type.

Evidence stage:

- owns projection from final ranked candidates to canonical evidence objects.
- must emit exactly the evidence shape defined by `evidence_contract.md`.
- must not add transport fields, diagnostics, explanations, or prompts to the
  canonical evidence list.

## Candidate Merge Rules

Candidate identity is canonical `doc_id`.

Candidate union input:

- lexical candidates from T09.
- vector candidates from T10.

Union rules:

- merge by `doc_id`.
- each `doc_id` appears at most once.
- candidate metadata must be joined from `chunk_manifest.jsonl`, not inferred
  from source files.
- lexical and vector diagnostic scores remain diagnostics unless manifest
  `ranking_policy` explicitly uses them.
- if a `doc_id` appears in lexical and vector candidates, both diagnostic
  signals may be attached to the same internal candidate record.
- candidates absent from chunk manifest parity are corrupt and must STOP.

Bounding rules:

- lexical candidates must not exceed `lexical_candidate_k`.
- vector candidates must not exceed `vector_candidate_k`.
- union candidates must not exceed `candidate_union_limit`.
- if union count exceeds `candidate_union_limit`, truncation is allowed only
  through an explicit manifest-owned deterministic union policy.
- if no deterministic union policy exists, STOP.

## Ranking Rules

Final ranking is owned only by manifest `ranking_policy`.

Required ranking policy fields:

- `final_score_formula`.
- `score_components`.
- `rerank_enabled`.
- `boost_policy`.
- `hidden_boosts_allowed`: canonical value `false`.
- `tie_breakers`.
- `top_k`.
- `finite_score_required`: canonical value `true`.

Default final score contract:

```text
final_score(doc_id) = rerank_score(doc_id) + boost_score(doc_id)
```

If rerank is disabled, the manifest must explicitly define an alternate
deterministic final score formula. Retrieval must STOP if rerank is disabled
and no alternate formula exists.

Allowed score inputs:

- manifest-authorized rerank score.
- manifest-authorized lexical diagnostic score.
- manifest-authorized vector diagnostic score.
- manifest-authorized boost components.

Forbidden score inputs:

- hidden path boosts.
- runtime ordering.
- cache hit state.
- query memory state.
- Chroma internal ordering.
- filesystem metadata.
- timestamps.
- model/device fallback state.
- MCP wrapper behavior.

Final sort order:

1. descending finite `score`.
2. ascending normalized repo-root-relative `file` by UTF-8 byte order.
3. ascending canonical `doc_id` as the retrieval-contract final tie-breaker.

The T06 restriction on `doc_id` ordering applies to identity and chunk-manifest
hash ordering. T11 uses `doc_id` only as a final retrieval tie-breaker because
the active retrieval contract requires deterministic output order.

## Evidence Format

Retrieval output must be a list of canonical evidence objects with exactly this
shape:

```json
{
  "file": "string",
  "layer": "LAW | ROUTE | SERVICE | DB | POLICY | SCHEMA | MODEL | OTHER",
  "snippet": "string",
  "source_type": "chunk | ast | context",
  "score": 0.0
}
```

Rules:

- no extra canonical fields are allowed.
- `file` must be normalized repo-root-relative.
- `layer` must come from manifest `classification_policy`.
- `snippet` must be verbatim source-grounded text from the indexed candidate.
- `source_type` must be one of `chunk`, `ast`, or `context`.
- `score` must be finite.
- output length must be at most manifest `retrieval_policy.top_k`.
- evidence order must match final ranking order exactly.
- downstream prompt construction may project evidence but must not mutate
  canonical evidence fields.

Canonical evidence must not include:

- `doc_id`.
- lexical diagnostic score.
- vector distance.
- rerank raw score.
- model name.
- cache state.
- MCP envelope data.
- absolute paths.
- prompts.
- generated summaries.

Those fields may exist only in non-authoritative diagnostics if a later
manifest policy allows diagnostics outside canonical evidence.

## Read-Only Rules

Query mode must not create, modify, delete, repair, or rebuild:

- `.repo_index/index_manifest.json`.
- `.repo_index/chunk_manifest.jsonl`.
- `.repo_index/lexical_index/`.
- `.repo_index/chroma_db/`.
- `.repo_index/_staging/`.
- cache files.
- query memory files.
- lock files.
- diagnostic exports.
- source files.

Retrieval must not:

- run build mode.
- trigger rebuild approval.
- create `.repo_index`.
- create Chroma collections.
- build lexical index records.
- regenerate embeddings for indexed chunks.
- scan the repository.
- call `rg --files`.
- read `search_manifest.txt` or `searchable_files.txt` as authority.
- silently fallback to regex, ripgrep, source scan, MCP-local search, or an
  older index.

## Determinism Guarantees

For identical:

- normalized query.
- active `index_manifest.json`.
- active `chunk_manifest.jsonl`.
- active `lexical_index/`.
- active `chroma_db/`.
- manifest-owned retrieval, ranking, classification, model, embedding, and
  verification policies.

Retrieval must produce:

- identical lexical candidate set.
- identical vector candidate set within manifest-defined vector equivalence
  constraints.
- identical candidate union.
- identical final scores within declared score serialization policy.
- identical final order.
- byte-identical canonical evidence JSON when serialized under T06 canonical
  JSON rules.

Retrieval output must not vary by:

- filesystem ordering.
- Chroma internal ordering.
- Python dictionary insertion ordering.
- cache state.
- query memory state.
- current time.
- process ID.
- device auto-selection.
- model fallback.
- MCP wrapper behavior.

## Failure Conditions

Retrieval must STOP if any of these occur:

- selected mode is not `query`.
- `.repo_index` is missing.
- active manifest is missing.
- manifest state is not `ACTIVE_VERIFIED`.
- required active artifact is missing.
- artifact hash mismatches manifest.
- lexical/vector/chunk `doc_id` parity fails.
- artifact `contract_version` mismatches manifest.
- artifact `corpus_manifest_hash` mismatches manifest.
- artifact `chunk_manifest_hash` mismatches manifest.
- model or tokenizer lock mismatches manifest.
- query normalization policy is missing or ambiguous.
- normalized query is empty.
- lexical index cannot serve bounded candidates.
- vector index cannot serve bounded candidates.
- vector layer attempts to create or repair collection state.
- query path writes cache or query memory.
- query path scans source files.
- query path initializes or downloads models per request.
- rerank is enabled without a manifest-locked model.
- rerank is disabled without an alternate final score formula.
- union exceeds bounds without deterministic manifest union policy.
- final score is NaN or infinite.
- evidence object contains extra or missing canonical fields.
- evidence includes non-source-grounded snippets.
- retrieval falls back to another search path.

No fallback retrieval, partial result return, silent repair, cache authority,
or query-triggered build is allowed.

## Contract Drift Analysis

The current repository does not yet satisfy this T11 retrieval contract:

- `actual_truth/contracts/retrieval/ingestion_contract.md` still names
  `search_manifest.txt` as ingestion authority.
- `actual_truth/contracts/retrieval/index_structure_contract.md` still lists
  `.repo_index/searchable_files.txt` as authoritative and still defines legacy
  flat manifest fields.
- `tools/index/search_code.py` permits `.venv/bin/python` and
  `.repo_index/.search_venv/bin/python` instead of the Windows interpreter
  required by T03/T13.
- `tools/index/search_code.py` requires `search_manifest.txt` in
  `validate_canonical_index_health`.
- `tools/index/search_code.py` writes `query_memory.json` and `query_cache.json`
  during query execution.
- `tools/index/search_code.py` loads `SentenceTransformer` and `CrossEncoder`
  in runtime query state instead of a fully manifest-locked, preflight-verified
  model surface.
- `tools/index/search_code.py` uses runtime device resolution rather than
  manifest-only device policy.
- `tools/index/search_code.py` loads all lexical records and iterates every
  lexical record during lexical search, violating T09 bounded lexical query
  behavior.
- `tools/index/search_code.py` hardcodes BM25 constants, rerank batch sizes,
  query prefix behavior, and candidate fields outside the nested T02/T08/T09
  manifest policies.
- `tools/index/search_code.py` reads source files with `errors="ignore"` in
  context and rerank document construction, which violates query-time no-scan
  and T04 strict text handling.
- `tools/index/search_code.py` validates only partial vector metadata and does
  not verify full vector parity, model/tokenizer lock, embedding dimension, or
  vector artifact hash from T10.
- `tools/index/search_code.py` applies route override and path/layer boosts
  through legacy policy structure rather than the finalized nested T11 ranking
  policy.
- `tools/mcp/semantic_search_server.py` uses a Linux search interpreter path,
  owns independent embedding and semantic rerank behavior, hardcodes
  `intfloat/e5-large-v2`, and wraps a base search subprocess instead of a
  canonical retrieval API.

These are later correction targets. T11 does not patch them.

## Verification Result

T11 passed because:

- all required authority files existed and were inspected.
- `T01`, `T02`, `T03`, `T04`, `T05`, `T06`, `T07`, `T08`, `T09`, and `T10`
  were repo-visible `PASS`.
- `T11` was repo-visible `NOT_STARTED`.
- `DAG_SUMMARY.md` allowed only `T11` as the next executable task.
- T11 scope was limited to read-only retrieval contract design.
- T07 artifact structure and write order were treated as locked authority.
- T09 lexical contract was treated as locked authority.
- T10 vector contract was treated as locked authority.
- T04 normalization was treated as locked authority.
- T05 chunking was treated as locked authority.
- T06 identity and hashing were treated as locked authority.
- T08 model and embedding policy was treated as locked authority.
- canonical retrieval stage order is specified.
- candidate merge and bounding rules are specified.
- final ranking and tie-break rules are specified.
- exact evidence object shape is specified.
- query-mode read-only rules are specified.
- determinism and STOP conditions are specified.
- existing drift is identified for later controller tasks.
- no `.repo_index` directory was created.
- no retrieval query was run.
- no cache or memory artifact was created.
- no dependency was installed.
- no model was loaded or downloaded.
- CUDA was not executed.
- no index was built.
- T12 and later tasks were not executed.

## Next Transition

Only `T12` may execute next under the strict controller order.
