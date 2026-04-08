# EVIDENCE CONTRACT

STATUS: ACTIVE

CLASSIFICATION: RETRIEVAL_STAGE_CONTRACT

This contract is a retrieval-stage contract.
It is not an execution contract and is not subject to the execution response-shape-only rule.

This contract defines the canonical evidence object and its invariants.

## CANONICAL EVIDENCE OBJECT

```json
{
  "file": "string",
  "layer": "LAW | ROUTE | SERVICE | DB | POLICY | SCHEMA | MODEL | OTHER",
  "snippet": "string",
  "source_type": "chunk | ast | context",
  "score": 0.0
}
```

## RULE 1 - EXACT EVIDENCE SHAPE

**RULE**

The canonical evidence object MUST contain exactly these fields:

- `file`
- `layer`
- `snippet`
- `source_type`
- `score`

Canonical downstream consumers MUST treat this object shape as stable system
law.

**RATIONALE**

A single stable evidence shape is required to keep retrieval, analysis, prompt
construction, validation, and diff audit aligned.

**VIOLATION CONDITION**

- A downstream stage requires undeclared canonical fields.
- A stage changes the meaning of one of the canonical fields.
- Canonical evidence cannot be serialized into the exact object shape above.

**VERIFICATION METHOD**

- Validate emitted evidence against the canonical schema.
- Fail if any canonical stage rejects or mutates the schema.

## RULE 2 - `file` FIELD INVARIANT

**RULE**

`file` MUST be a normalized repo-root-relative path that identifies the exact
source file from which `snippet` was derived.

**RATIONALE**

The evidence object must always point back to one exact local authority file.

**VIOLATION CONDITION**

- `file` is absolute, missing, or non-normalized.
- `file` does not resolve to the source of `snippet`.
- A downstream stage rewrites `file` into a display alias.

**VERIFICATION METHOD**

- Resolve every `file` against the repo root and assert existence.
- Confirm that `snippet` is derivable from the referenced file.

## RULE 3 - `layer` ENUM INVARIANT

**RULE**

`layer` MUST be one of:

- `LAW`
- `ROUTE`
- `SERVICE`
- `DB`
- `POLICY`
- `SCHEMA`
- `MODEL`
- `OTHER`

The layer mapping policy MUST be declared once and reused by indexing,
retrieval, analysis, prompting, and validation.

**RATIONALE**

If layer semantics drift across stages, evidence grouping and ranking become
non-auditable.

**VIOLATION CONDITION**

- A stage invents a new canonical layer.
- Different stages classify the same file under different canonical layers
  without a declared exception.

**VERIFICATION METHOD**

- Run one canonical layer-classification fixture across all stages and compare
  output.
- Fail on any undeclared layer or stage-specific remapping.

## RULE 4 - `snippet` INVARIANT

**RULE**

`snippet` MUST be a verbatim, local, source-grounded excerpt from `file`. It
MUST NOT be a generated summary. It MUST remain bounded by the canonical
evidence snippet limit and MUST NOT contain secret-bearing content that was
forbidden at ingestion time.

**RATIONALE**

Evidence is only auditable if it stays anchored to local source text rather than
generated paraphrase.

**VIOLATION CONDITION**

- `snippet` cannot be matched back to the referenced file.
- `snippet` is a generated summary rather than source text.
- `snippet` includes content from excluded secret-bearing files.

**VERIFICATION METHOD**

- Confirm that each snippet appears in the referenced file or is reproducibly
  derived from it by the declared source type rule.
- Scan snippet fixtures for excluded secret patterns and fail on any match.

## RULE 5 - `source_type` ENUM INVARIANT

**RULE**

`source_type` MUST be one of:

- `chunk`
- `ast`
- `context`

The meanings are fixed:

- `chunk` = canonical indexed chunk text
- `ast` = deterministic AST-derived source excerpt from the same file
- `context` = deterministic local text window from the same file

`ast` and `context` MUST NOT introduce a new file that was absent from canonical
retrieval evidence.

**RATIONALE**

Source type explains how the snippet was derived while keeping provenance tied
to the same local authority file.

**VIOLATION CONDITION**

- A snippet labeled `ast` or `context` comes from a different file than the
  retrieved file.
- A stage uses a private or undeclared source type.

**VERIFICATION METHOD**

- Re-derive the snippet from the source file using the declared source type
  logic.
- Fail if derivation cannot be reproduced.

## RULE 6 - `score` INVARIANT

**RULE**

`score` MUST be a finite float where higher values rank ahead of lower values.
`score` is comparable only within the same query, contract version, and index
manifest hash.

**RATIONALE**

Scores need a stable ordering role without pretending to be globally comparable
across different corpora or contract generations.

**VIOLATION CONDITION**

- `score` is NaN, infinite, or missing.
- A downstream stage overwrites `score` with a private value.
- A stage treats scores from different manifest hashes as directly comparable.

**VERIFICATION METHOD**

- Validate score finiteness for every emitted evidence object.
- Run repeated same-query tests and compare ordered score lists.
- Fail if downstream consumers replace canonical scores.

## RULE 7 - EVIDENCE IMMUTABILITY

**RULE**

Once retrieval emits a canonical evidence object, downstream stages MAY filter
or format the evidence list, but they MUST NOT rewrite `file`, `layer`,
`snippet`, `source_type`, or `score` in place.

**RATIONALE**

Immutability keeps the retrieval result auditable through analysis, prompting,
and validation.

**VIOLATION CONDITION**

- Analysis or validation edits canonical evidence fields in place.
- Prompt construction changes evidence content rather than selecting from it.

**VERIFICATION METHOD**

- Snapshot the evidence list at retrieval output and compare it with each
  downstream handoff.
- Fail on any in-place canonical field mutation.

## RULE 8 - CANONICAL CLASSIFICATION AUTHORITY

**RULE**

Canonical layer classification authority MUST live in
`.repo_index/index_manifest.json` as the retrieval contract's single
classification authority. That authority MUST define deterministic mapping rules
from normalized repo-relative file paths to exactly one canonical `layer` value.
All stages MUST reuse that same classification authority unchanged.

**RATIONALE**

Layer drift across ingestion, retrieval, analysis, prompting, and validation
prevents diff-auditable evidence grouping.

**VIOLATION CONDITION**

- A stage classifies files without consulting the canonical classification
  authority.
- Different stages assign different canonical layers to the same normalized
  file.
- The classification authority allows more than one canonical layer for the
  same file without an explicit precedence rule.

**VERIFICATION METHOD**

- Evaluate a fixed file-classification fixture against every stage and compare
  the resulting `layer` values.
- Fail if any stage diverges from the canonical classification authority.
