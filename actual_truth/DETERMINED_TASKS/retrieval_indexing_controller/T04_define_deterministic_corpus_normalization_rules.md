# T04 - Define Deterministic Corpus Normalization Rules

TYPE: design
OS_ROLE: OWNER
EXECUTION_STATUS: PASS
DEPENDS_ON: [T02, T03]

## Purpose

Define deterministic corpus path and text normalization rules for controller
governed indexing.

## Scope

Design only. Do not enumerate the current repo into a corpus. Do not create a
manifest. Do not write `.repo_index`.

## Authority References

- `actual_truth/contracts/retrieval/ingestion_contract.md`
- `actual_truth/contracts/retrieval/determinism_contract.md`
- T02 manifest schema
- T03 preflight contract

## Dependencies

- T02
- T03

## Expected Outcome

The rules define repo-root-relative path identity, slash normalization,
ascending byte-order sorting, uniqueness, no absolute paths, no `..` segments,
Windows case-collision detection, stable excludes for secrets/caches/generated
artifacts, UTF-8 decoding, Unicode NFC, LF line endings, tabs converted to
spaces, trailing whitespace stripped, deterministic terminal newline behavior,
and binary/null-byte/unreadable handling.

## Stop Conditions

- Any excluded path enters the corpus.
- Any path resolves outside repo root.
- Any path differs by Windows case only.
- Any unreadable or binary file is treated as indexed text.
- Working directory changes corpus bytes.

## Verification Requirements

- Repeating normalization for the same snapshot produces identical bytes.
- Corpus hash is stable across working directories.
- Exclusion rule failures stop before chunking.

## Mutation Rules

No runtime mutation is allowed during this design task. Controller execution may
update this task status and write `T04_execution_result.md` only.

## Output Artifacts

- `T04_execution_result.md`

## Next Transitions

- T05
