# INDEX INGESTION CONTRACT

STATUS: ACTIVE

CLASSIFICATION: RETRIEVAL_STAGE_CONTRACT

This contract is a retrieval-stage contract.
It is not an execution contract and is not subject to the execution response-shape-only rule.

This contract defines the canonical rules for repository ingestion before any
index is built.

## RULE 1 - SINGLE MANIFEST AUTHORITY

**RULE**

The searchable corpus MUST be defined by one canonical ingestion manifest:

.repo_index/search_manifest.txt

Vector indexing, lexical indexing, retrieval, analysis, prompt construction,
and validation MUST all consume this manifest. A non-search inventory MAY exist,
but it MUST NOT be treated as search authority.

**RATIONALE**

One authority removes drift between file discovery, chunk ingestion, retrieval
corpus membership, and downstream evidence.

**VIOLATION CONDITION**

- Any indexed or retrieved document originates from a path not present in the
  canonical ingestion manifest.
- Different stages consume different file lists.
- A fallback inventory is used as search authority when the canonical manifest
  exists.

**VERIFICATION METHOD**

- Compare the canonical manifest to the set of indexed document paths.
- Assert that all downstream stages reference the same manifest hash.
- Fail if any search-stage path is absent from the canonical manifest.

---

## RULE 2 - NORMALIZED, REPO-RELATIVE, STABLE PATHS

**RULE**

Every manifest entry MUST be a normalized repo-root-relative path. The manifest
MUST be:

- unique
- sorted in ascending byte order
- free from absolute paths
- free from duplicate entries
- independent of working directory

**RATIONALE**

Deterministic paths are required for stable chunk IDs, stable evidence, and
portable verification across machines.

**VIOLATION CONDITION**

- Any manifest line is absolute.
- Any manifest line contains duplicate or unresolved path segments.
- Re-running ingestion from a different working directory changes manifest bytes.

**VERIFICATION METHOD**

- Generate manifest from multiple working directories and compare byte-for-byte.
- Assert uniqueness and sorted order.
- Assert all paths resolve inside repo root.

---

## RULE 3 - TEXT NORMALIZATION CONTRACT

**RULE**

All ingested text MUST be normalized using:

- UTF-8 decoding
- Unicode normalization (NFC)
- LF line endings
- tabs converted to spaces
- no trailing whitespace
- deterministic newline handling

Only admissible text files MAY enter the corpus. Files containing:

- binary data
- null bytes
- unreadable text

MUST be excluded.

**RATIONALE**

Text normalization ensures stable chunking, hashing, and deterministic indexing.

**VIOLATION CONDITION**

- Same file content produces different normalized output across runs.
- Binary or unreadable files enter ingestion.
- Normalization differs between ingestion runs.

**VERIFICATION METHOD**

- Normalize same file twice and compare byte output.
- Scan corpus for null bytes or binary markers.
- Compare normalized corpus hashes across runs.

---

## RULE 4 - SECRET, CACHE, AND GENERATED ARTIFACT EXCLUSION

**RULE**

The searchable corpus MUST exclude:

- `.git/**`
- `.venv/**`
- `.repo_index/**`
- `node_modules/**`
- `build/**`
- `dist/**`
- `coverage/**`
- `target/**`
- `__pycache__/**`
- `*.log`
- `.env*`

If any file matching these patterns is detected in ingestion input,
the system MUST STOP.

**RATIONALE**

Secrets and generated artifacts must never enter the searchable corpus.

**VIOLATION CONDITION**

- A secret-bearing file appears in the manifest.
- Generated artifacts are ingested.
- Ingestion continues after detecting excluded files.

**VERIFICATION METHOD**

- Inject fixture files (.env, logs, caches) and assert system STOP.
- Scan manifest against exclusion patterns.
- Fail if any excluded file is present.

---

## RULE 5 - DETERMINISTIC CHUNK EMISSION

**RULE**

Chunk emission MUST be deterministic for a given:

- normalized file content
- chunk size
- chunk overlap

Chunks MUST:

- preserve source order
- NOT be empty
- NOT cross file boundaries

**RATIONALE**

Stable chunk boundaries are required for deterministic indexing and retrieval.

**VIOLATION CONDITION**

- Same file produces different chunk sequences.
- Empty chunks are emitted.
- Chunk order depends on runtime factors.

**VERIFICATION METHOD**

- Re-run chunking on fixed corpus and compare chunk hashes.
- Assert chunk boundaries match expected positions.
- Fail if chunk order changes.

---

## RULE 6 - NO SILENT CORPUS FALLBACK

**RULE**

If the canonical ingestion manifest is:

- missing
- unreadable
- invalid

the system MUST STOP.

No fallback corpus definition is allowed.

**RATIONALE**

Silent fallback creates hidden corpus drift and breaks determinism.

**VIOLATION CONDITION**

- Indexing continues after manifest failure.
- Alternative file lists are used without explicit contract.

**VERIFICATION METHOD**

- Corrupt manifest and assert hard STOP.
- Verify no artifacts are updated after failure.

---

## RULE 7 - DETERMINISTIC CHUNK ORDERING

**RULE**

Canonical chunk order MUST be defined as:

1. ascending normalized `file`
2. ascending `chunk_index`

Constraints:

- first chunk index = 0
- increments by exactly 1 per file
- no gaps or duplicates

No runtime factor MAY affect chunk ordering.

**RATIONALE**

Deterministic ordering is required for diff audit and reproducible indexing.

**VIOLATION CONDITION**

- Same corpus produces different chunk ordering.
- chunk_index is non-monotonic.
- ordering depends on traversal timing or tool behavior.

**VERIFICATION METHOD**

- Compare `(file, chunk_index, content_hash)` across builds.
- Assert monotonic progression.
- Fail if re-sorting changes order.
