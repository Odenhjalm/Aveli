# T04 Execution Result - Deterministic Corpus Normalization Rules

TASK_ID: T04
EXECUTION_STATUS: PASS
MODE: execute
CONTROLLER_SCOPE: retrieval_indexing_controller

## Authority Load

- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/task_manifest.json`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/DAG_SUMMARY.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T04_define_deterministic_corpus_normalization_rules.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T01_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T02_execution_result.md`
- `actual_truth/DETERMINED_TASKS/retrieval_indexing_controller/T03_execution_result.md`
- `codex/AVELI_OPERATING_SYSTEM.md`
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

## Controller State Before T04

- `T01` was repo-visible `PASS`.
- `T02` was repo-visible `PASS`.
- `T03` was repo-visible `PASS`.
- `T04` was repo-visible `NOT_STARTED`.
- `DAG_SUMMARY.md` allowed only `T04` as the next executable task.
- `.repo_index` was absent and was not created.

## Executive Verdict

PASS with CONTRACT_DRIFT identified for later correction.

T04 defines deterministic corpus normalization rules for path identity, file
admissibility, text bytes, stable ordering, corpus serialization, corpus hash
input, and Windows edge-case rejection. It does not enumerate the current repo
as a corpus, does not create a manifest, does not create `.repo_index`, does
not build an index, does not download models, does not run CUDA, and does not
execute retrieval.

## Corpus Normalization Authority

Corpus membership is owned only by `.repo_index/index_manifest.json` through the
manifest `corpus.files` list defined by T02.

T04 owns the canonical normalization rules that must be applied to those
manifest-declared paths before chunking, hashing, embedding, lexical indexing,
vector indexing, or retrieval verification.

The normalization layer must never discover corpus membership. It may validate,
normalize, reject, sort, and serialize only the manifest-declared corpus. It may
not accept `search_manifest.txt`, `searchable_files.txt`, `rg --files`,
filesystem traversal, Chroma metadata, lexical metadata, cache state, or MCP
input as corpus authority.

## File Inclusion And Exclusion Rules

Allowed corpus input:

- each file must be explicitly listed in `index_manifest.json` under
  `corpus.files`.
- each file must pass the path rules in this T04 result.
- each file must be readable as strict UTF-8 text after binary/null-byte
  rejection.
- each file must produce non-empty normalized text.
- each file must represent canonical code or text content, not cache,
  generated output, secret material, or runtime state.

Mandatory exclusions:

- `.git/**`
- `.repo_index/**`
- `.venv/**`
- `node_modules/**`
- `build/**`
- `dist/**`
- `coverage/**`
- `target/**`
- `__pycache__/**`
- `.mypy_cache/**`
- `.pytest_cache/**`
- `.ruff_cache/**`
- `.next/**`
- `.turbo/**`
- `.env`
- `.env.*`
- `*.log`
- `*.pyc`
- files containing a null byte before UTF-8 decoding
- files that cannot be read through the approved runtime path
- files that fail strict UTF-8 decoding
- files whose normalized content is empty

If any mandatory exclusion is present in manifest `corpus.files`, the
controller must STOP before chunking. It must not silently remove the file,
repair the manifest, or substitute a different corpus.

Optional project-specific exclusions may exist only as explicit manifest-owned
policy values. They must be sorted, deterministic, and validated by the
controller. Tool-local exclude constants are not authority.

## Path Normalization Rules

Path identity rules:

1. Input path strings must come from manifest `corpus.files` only.
2. Paths are interpreted relative to the repository root declared by the
   manifest.
3. Stored path identity is repo-root-relative.
4. Stored path separators are `/`.
5. Absolute paths are forbidden.
6. Drive-letter paths are forbidden.
7. UNC paths are forbidden.
8. Backslashes are forbidden in manifest corpus paths.
9. Empty paths are forbidden.
10. `.` and `..` segments are forbidden.
11. Paths that resolve outside the repository root are forbidden.
12. Trailing slash paths are forbidden.
13. Duplicate normalized paths are forbidden.
14. Paths are Unicode NFC normalized before identity checks.
15. Final corpus ordering is ascending by the UTF-8 byte sequence of the
    normalized path string.

Windows case-collision rules:

- the exact normalized path string is the preserved identity.
- a second collision key is computed from the NFC-normalized path using
  Unicode `casefold`.
- if two different preserved paths share the same collision key, STOP.
- path segments whose visible identity differs only by Windows case semantics
  are not allowed in the same corpus.

Windows path safety rules:

- reserved device names are forbidden as path segments, with or without an
  extension: `CON`, `PRN`, `AUX`, `NUL`, `COM1` through `COM9`, and `LPT1`
  through `LPT9`.
- path segments ending in space or `.` are forbidden.
- `:` is forbidden in any path segment.
- control characters are forbidden in path strings.
- filesystem case mismatch between the manifest path and the actual file path
  is STOP on Windows.

These checks must be independent of current working directory and filesystem
enumeration order.

## Text Normalization Rules

Read and decode rules:

1. Read file bytes exactly from the manifest-declared path under the repo root.
2. Reject files containing byte `0x00` before decoding.
3. Decode using strict UTF-8 only.
4. Do not use encoding fallback.
5. Do not use `errors="ignore"` or equivalent replacement behavior.
6. If a UTF-8 BOM appears at the beginning of the file, remove that BOM before
   Unicode normalization.
7. A BOM anywhere else is treated as ordinary content.

Canonical text transform order:

1. Decode strict UTF-8 bytes to text.
2. Remove one leading UTF-8 BOM if present.
3. Normalize Unicode to NFC.
4. Convert CRLF and lone CR line endings to LF.
5. Convert each tab character to exactly four ASCII spaces.
6. Split on LF.
7. Remove trailing ASCII space `U+0020` from each line.
8. Preserve internal spaces and blank lines.
9. Do not collapse repeated whitespace.
10. Join lines with LF.
11. For non-empty normalized text, ensure exactly one terminal LF.
12. If normalized text is empty, STOP for manifest-listed files.

Normalization must not add embedding prefixes, model-specific formatting,
ranking data, timestamps, file metadata, or runtime-dependent content.

## Corpus Serialization Spec

Corpus serialization is the only byte input to `corpus_manifest_hash`.

Serialization rules:

1. Sort normalized corpus records by UTF-8 byte order of normalized path.
2. Encode all control labels as ASCII.
3. Encode paths and normalized text as UTF-8 without BOM.
4. Use decimal byte lengths with no leading zeroes except the value `0`.
5. Use LF for every structural newline.
6. Include every manifest-declared, validated, normalized file exactly once.
7. Do not include timestamps, filesystem metadata, absolute paths, device
   choice, model policy, chunking policy, or runtime environment values.

Canonical byte layout:

```text
AVELI_CORPUS_NORMALIZATION_V1\n
FILE_COUNT <decimal_count>\n
PATH_LEN <decimal_path_byte_length>\n
<path_utf8_bytes>\n
CONTENT_LEN <decimal_normalized_text_byte_length>\n
<normalized_text_utf8_bytes>
PATH_LEN <decimal_path_byte_length>\n
<path_utf8_bytes>\n
CONTENT_LEN <decimal_normalized_text_byte_length>\n
<normalized_text_utf8_bytes>
...
```

`normalized_text_utf8_bytes` already ends in exactly one LF for non-empty text.
No extra delimiter is inserted after content bytes beyond the next structural
`PATH_LEN` line. Length prefixes are the boundary authority.

An empty corpus is invalid and must STOP before hashing.

## Corpus Hash Definition

`corpus_manifest_hash` is:

```text
sha256(canonical_corpus_serialization_bytes)
```

The hash depends only on:

- sorted normalized path list
- normalized UTF-8 text bytes for each file
- T04 serialization labels and byte lengths

The hash must not depend on:

- manifest file formatting
- original manifest path order
- filesystem traversal order
- current working directory
- absolute repo path
- timestamps
- file permissions
- Python version
- operating system
- CPU/GPU device selection
- model or tokenizer identity
- embedding prefixes
- chunking output

The manifest must store the resulting hash, but the manifest is not part of
the corpus hash input.

## Stability And Rejection Rules

Identical repository snapshot plus identical manifest corpus policy must
produce identical normalized corpus bytes and identical `corpus_manifest_hash`.

The controller must STOP before chunking if any of these occur:

- manifest `corpus.files` is missing.
- manifest `corpus.files` is empty.
- a listed path is not a string.
- a listed path is absolute.
- a listed path contains `..`.
- a listed path uses backslashes.
- a listed path resolves outside repo root.
- a listed path matches a mandatory exclusion.
- two paths duplicate after normalization.
- two paths collide under Windows casefold rules.
- a listed file is missing.
- a listed file is unreadable.
- a listed file contains a null byte.
- a listed file fails strict UTF-8 decoding.
- normalized text is empty.
- normalized ordering is not byte-sort stable.
- the same snapshot produces different corpus serialization bytes.

No fallback file discovery, best-effort decoding, skipped file, or partial
corpus is allowed.

## Windows Edge Case Handling

Windows compatibility requirements:

- all manifest corpus paths must be slash-normalized repo-relative strings.
- drive letters are rejected, including paths like `C:/x`.
- UNC paths are rejected, including `//server/share`.
- backslash-separated paths are rejected before any filesystem lookup.
- case-only path collisions are STOP.
- reserved device names are STOP.
- alternate data stream syntax using `:` is STOP.
- trailing space or trailing dot in path segments is STOP.
- cwd changes must not affect path resolution, content bytes, or hash output.

The canonical interpreter rule from T03 still applies to future execution:
`.repo_index/.search_venv/Scripts/python.exe`. T04 does not create that
interpreter and does not run normalization code.

## Contract Drift Analysis

The current repository does not yet satisfy this T04 normalization contract:

- `actual_truth/contracts/retrieval/ingestion_contract.md` still names
  `.repo_index/search_manifest.txt` as an ingestion authority.
- `actual_truth/contracts/retrieval/index_structure_contract.md` still lists
  `.repo_index/searchable_files.txt` as an artifact surface.
- `tools/index/build_repo_index.sh` uses `rg --files`, `LC_ALL=C sort -u`,
  bash, Linux paths, and writes `search_manifest.txt`.
- `tools/index/build_vector_index.py` reads `search_manifest.txt`, computes
  `corpus_manifest_hash` from raw `search_manifest.txt` bytes, defines
  tool-local searchable suffix and exclude rules, permits absolute path
  normalization through runtime resolution, and strips whitespace through
  Python runtime behavior rather than a manifest-bound T04 byte contract.
- `tools/index/search_code.py` still requires `search_manifest.txt`, defines
  tool-local searchable suffix and exclude rules, reads source snippets with
  `errors="ignore"`, and can scan source files during query-time result
  construction.
- `tools/index/ast_extract.py` and `tools/index/run_codex_auto.py` read text
  using `errors="ignore"`.
- `tools/mcp/semantic_search_server.py` calls retrieval-adjacent logic through
  a Linux `.repo_index/.search_venv/bin/python` path and must later become a
  thin wrapper over canonical retrieval.

These are later correction targets. T04 does not patch them.

## Verification Result

T04 passed because:

- all required authority files existed and were inspected.
- `T01`, `T02`, and `T03` were repo-visible `PASS`.
- `T04` was repo-visible `NOT_STARTED`.
- `DAG_SUMMARY.md` allowed only `T04` as the next executable task.
- T04 scope was limited to deterministic normalization design.
- path normalization is fully specified.
- file inclusion and exclusion behavior is fail-closed.
- text normalization is byte-for-byte specified.
- corpus serialization and `corpus_manifest_hash` input are specified.
- Windows case-collision and path edge cases are specified.
- existing drift is identified for later controller tasks.
- no index was built.
- `.repo_index` was not created.
- no model was downloaded or executed.
- CUDA was not used.
- no retrieval query was executed.
- T05 and later tasks were not executed.

## Next Transition

Only `T05` may execute next under the strict controller order.
