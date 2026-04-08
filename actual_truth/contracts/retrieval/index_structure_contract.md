# INDEX STRUCTURE CONTRACT

STATUS: ACTIVE

CLASSIFICATION: RETRIEVAL_STAGE_CONTRACT

This contract is a retrieval-stage contract.
It is not an execution contract and is not subject to the execution response-shape-only rule.

This contract defines the canonical persistent artifact structure for indexing.

## RULE 1 - PERSISTENT INDEX ROOT

**RULE**

All indexing artifacts MUST live under `.repo_index/`. The index root is a
persistent artifact boundary, not a transient scratch directory. If a healthy
index already exists, retrieval MUST use it and MUST NOT rebuild it implicitly.

**RATIONALE**

The operating system already treats the vector index as a persistent artifact.
The structure contract extends that requirement to the full indexing surface.

**VIOLATION CONDITION**

- Retrieval rebuilds or wipes index artifacts during a normal query path.
- Index artifacts are written outside `.repo_index/` without explicit system law.
- A healthy existing index is ignored in favor of an implicit rebuild.

**VERIFICATION METHOD**

- Run retrieval against an existing healthy index and assert no artifact writes.
- Scan produced paths and assert all authoritative artifacts are under
  `.repo_index/`.
- Fail if rebuild occurs without an explicit rebuild condition.

## RULE 2 - REQUIRED AUTHORITATIVE ARTIFACTS

**RULE**

The canonical index structure MUST contain these authoritative artifacts:

- `.repo_index/searchable_files.txt`
- `.repo_index/index_manifest.json`
- `.repo_index/chunk_manifest.jsonl`
- `.repo_index/chroma_db/`
- `.repo_index/lexical_index/`

Optional caches MAY exist, but they are non-authoritative and MUST be clearly
separated from the authoritative artifact set.

**RATIONALE**

The system needs one authoritative corpus manifest, one authoritative chunk
manifest, one authoritative vector store, and one authoritative lexical store.

**VIOLATION CONDITION**

- Any required authoritative artifact is missing from a healthy index.
- Retrieval depends on an artifact not declared here as authoritative.
- Optional caches are treated as authority for corpus membership or ranking.

**VERIFICATION METHOD**

- Validate presence and readability of every required artifact.
- Fail if the retrieval pipeline reads an undeclared authoritative artifact.
- Fail if cache deletion changes authoritative retrieval results.

## RULE 3 - SINGLE INDEX MANIFEST SCHEMA

**RULE**

`index_manifest.json` MUST be the single canonical configuration and versioning
surface for indexing and retrieval. At minimum it MUST define:

- `contract_version`
- `corpus_manifest_hash`
- `chunk_manifest_hash`
- `chunk_size`
- `chunk_overlap`
- `embedding_model`
- `rerank_model`
- `top_k`
- `vector_candidate_k`
- `lexical_candidate_k`

No other file MAY redefine these values as authority.

**RATIONALE**

Deterministic retrieval is not possible if chunking, models, or candidate limits
can drift across scripts.

**VIOLATION CONDITION**

- The same canonical value is duplicated with conflicting definitions elsewhere.
- Retrieval behavior changes without a corresponding manifest change.
- A stage ignores the manifest and uses a private authority value.

**VERIFICATION METHOD**

- Compare runtime parameters against `index_manifest.json`.
- Fail if conflicting definitions exist in other authoritative surfaces.
- Assert that changing the manifest changes the derived artifact hashes.

## RULE 4 - CANONICAL CHUNK RECORD

**RULE**

Every indexed chunk MUST have one canonical record in
`.repo_index/chunk_manifest.jsonl`. Each record MUST include:

- `doc_id`
- `file`
- `chunk_index`
- `layer`
- `source_type`
- `content_hash`

For canonical indexed chunks, `source_type` MUST be `chunk`.

**RATIONALE**

The chunk manifest is the deterministic bridge between ingestion, vector
storage, lexical storage, and downstream evidence.

**VIOLATION CONDITION**

- A stored vector or lexical document has no matching chunk record.
- `doc_id` is unstable across identical corpus builds.
- Indexed metadata omits required canonical fields.

**VERIFICATION METHOD**

- Join vector entries and lexical entries against `chunk_manifest.jsonl`.
- Rebuild the same corpus twice and compare ordered chunk records.
- Fail if any required field is missing or inconsistent.

## RULE 5 - STABLE DOCUMENT ID CONTRACT

**RULE**

`doc_id` MUST be stable for identical corpus content. It MUST be derived from
deterministic inputs only: normalized file path, chunk index, and chunk content
identity. Process counters, traversal order, and runtime timing MUST NOT define
`doc_id`.

**RATIONALE**

Stable IDs are necessary for cache correctness, vector/lexical parity, and
deterministic result ordering.

**VIOLATION CONDITION**

- Rebuilding the same corpus produces different `doc_id` values.
- `doc_id` depends on global counters or nondeterministic traversal order.

**VERIFICATION METHOD**

- Build the same fixed corpus twice and compare the ordered `doc_id` list.
- Mutate one chunk and confirm only the affected `doc_id` changes.

## RULE 6 - VECTOR AND LEXICAL PARITY

**RULE**

The vector store and lexical store MUST be built from the same
`chunk_manifest.jsonl` and MUST expose the same canonical `doc_id` set for a
healthy index generation.

**RATIONALE**

Hybrid retrieval is only meaningful when vector and lexical candidates refer to
the same canonical document universe.

**VIOLATION CONDITION**

- A `doc_id` exists only in one authoritative store.
- The vector store and lexical store reference different corpus hashes.
- Retrieval must map between mismatched document universes.

**VERIFICATION METHOD**

- Compare the `doc_id` set exported from both stores.
- Compare the stored corpus hash in each authoritative artifact to
  `index_manifest.json`.
- Fail on any set or hash mismatch.

## RULE 7 - CACHE IS NON-AUTHORITATIVE

**RULE**

Result caches and query-memory artifacts are optional accelerators only. They
MUST NOT define corpus membership, ranking policy, prompt content, or evidence
content.

**RATIONALE**

Caches may speed retrieval, but authority must stay with the canonical corpus
and index artifacts.

**VIOLATION CONDITION**

- Deleting a cache changes authoritative retrieval results for the same query
  and index generation.
- Cached prompt or snippet content becomes the only surviving source of
  evidence.

**VERIFICATION METHOD**

- Run the same query with and without caches and compare ordered evidence
  objects.
- Fail if cache artifacts contain authority-only fields not present in the
  canonical index artifacts.

## RULE 8 - MINIMAL LEXICAL INDEX DEFINITION

**RULE**

`.repo_index/lexical_index/` MUST be a persistent lexical retrieval artifact
built from the canonical `chunk_manifest.jsonl`. At minimum it MUST support:

- lookup by canonical `doc_id`
- lexical candidate retrieval over canonical chunk text
- deterministic top-N candidate emission
- export or validation of the indexed canonical `doc_id` set
- binding to the same `corpus_manifest_hash`, `chunk_manifest_hash`, and
  `contract_version` as `index_manifest.json`

The lexical index MAY use any implementation, but it MUST satisfy this minimal
contract.

**RATIONALE**

Hybrid retrieval needs a persistent lexical surface that is implementation-
agnostic but still auditable and parity-checked against the vector index.

**VIOLATION CONDITION**

- Lexical retrieval requires rebuilding corpus statistics during the query hot
  path.
- The lexical index cannot prove which canonical `doc_id` set it serves.
- The lexical index serves a different manifest or contract generation than the
  authoritative index manifest.

**VERIFICATION METHOD**

- Validate that the lexical index can emit its indexed `doc_id` set without
  rebuilding from source files.
- Compare lexical metadata binding to `index_manifest.json`.
- Fail if a warm query requires lexical index reconstruction.

## RULE 9 - CONTRACT-VERSION BINDING

**RULE**

Every authoritative index artifact MUST bind to the same `contract_version`
declared in `.repo_index/index_manifest.json`. Retrieval MUST refuse to operate
if any authoritative artifact advertises a missing or mismatched
`contract_version`.

**RATIONALE**

Diff audit requires explicit proof that ingestion, vector indexing, lexical
indexing, and retrieval all belong to the same contract generation.

**VIOLATION CONDITION**

- An authoritative artifact omits `contract_version`.
- Retrieval accepts an index whose artifact versions do not match.
- Retrieval mixes artifacts from different contract generations.

**VERIFICATION METHOD**

- Read metadata from all authoritative artifacts and compare their
  `contract_version` to `index_manifest.json`.
- Fail if any authoritative artifact has a missing or mismatched version.
