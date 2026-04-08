# DETERMINISM CONTRACT

STATUS: ACTIVE

CLASSIFICATION: RETRIEVAL_STAGE_CONTRACT

This contract is a retrieval-stage contract.
It is not an execution contract and is not subject to the execution response-shape-only rule.

This contract defines the invariants that make indexing and retrieval
repeatable, auditable, and safe to diff against implementation.

## RULE 1 - SAME INPUTS, SAME ARTIFACTS, SAME ORDERED EVIDENCE

**RULE**

For the same repository snapshot, the same canonical configuration, the same
healthy index generation, and the same normalized query, the system MUST produce
the same authoritative artifact hashes and the same ordered evidence list.

**RATIONALE**

Diff audit is only meaningful if identical inputs produce identical indexing and
retrieval outputs.

**VIOLATION CONDITION**

- Repeating the same build changes authoritative artifact hashes without corpus
  or config changes.
- Repeating the same query changes ordered evidence without an index or config
  change.

**VERIFICATION METHOD**

- Run repeated fixed-corpus builds and compare authoritative artifact hashes.
- Run repeated fixed-query retrieval and compare ordered evidence objects
  byte-for-byte.

## RULE 2 - SINGLE CANONICAL CONFIGURATION AUTHORITY

**RULE**

Indexing and retrieval parameters MUST have one canonical authority:
`.repo_index/index_manifest.json`. Chunking parameters, model identifiers,
candidate limits, ranking policy, and output limits MUST NOT be redefined as
authority anywhere else.

**RATIONALE**

Duplicated configuration creates silent drift between ingestion, retrieval,
analysis, prompts, and validation.

**VIOLATION CONDITION**

- A stage uses a conflicting private value for a canonical parameter.
- A parameter change affects behavior without a corresponding manifest change.

**VERIFICATION METHOD**

- Compare runtime configuration reads to `index_manifest.json`.
- Fail if duplicated authoritative values diverge across stages.

## RULE 3 - STABLE TIE-BREAKERS AND IDENTIFIERS

**RULE**

When scores tie, result order MUST be resolved deterministically using the
canonical ordering contract. `doc_id` and `file` normalization MUST remain
stable across identical builds.

**RATIONALE**

Nondeterministic iteration order is enough to invalidate audit diffs and prompt
reproducibility.

**VIOLATION CONDITION**

- Tied results change order across repeated queries.
- Identical builds produce different canonical identifiers.

**VERIFICATION METHOD**

- Use tied-score fixtures and compare ordered output across repeated runs.
- Compare `doc_id` and normalized file values across repeated builds.

## RULE 4 - NO HIDDEN FALLBACKS

**RULE**

If a required interpreter, dependency set, canonical manifest, authoritative
index artifact, or model surface is not ready, the system MUST STOP explicitly.
It MUST NOT silently switch interpreter, corpus definition, ranking surface,
device policy, or retrieval mode.

**RATIONALE**

Hidden fallback converts readiness failures into silent behavioral drift.

**VIOLATION CONDITION**

- The system silently changes behavior after an environment or artifact failure.
- Tool availability changes corpus membership or ranking policy without an
  explicit contract change.

**VERIFICATION METHOD**

- Remove one required prerequisite at a time and assert an explicit stop.
- Compare retrieval outputs before and after tool unavailability simulation and
  fail on silent mode changes.

## RULE 5 - CACHE MUST BE CONTENT-DETERMINISTIC AND NON-LEAKING

**RULE**

If result caching exists, cache keys MUST include at least:

- normalized query
- contract version
- corpus manifest hash
- chunk manifest hash

Caches MUST NOT store prompts, secret-bearing source text, or authority-only
state not present in canonical evidence objects.

**RATIONALE**

Cache reuse is only deterministic when it is bound to the exact corpus and
contract generation. Cache safety is required to prevent leakage.

**VIOLATION CONDITION**

- A cache hit returns results built for a different corpus or contract version.
- Cache contents expose prompts or secret-bearing snippets.
- Cache hit and cache miss produce different authoritative evidence.

**VERIFICATION METHOD**

- Change the corpus hash and assert cache invalidation.
- Compare cache-hit and cache-miss evidence outputs for the same query.
- Inspect cache fixtures and fail on prompt or secret leakage.

## RULE 6 - LANGUAGE SURFACE CONTRACT

**RULE**

All user-facing text emitted by the indexing and retrieval toolchain MUST be in
Swedish. All generated prompts MUST be:

- in English
- plain text
- copy-paste-ready
- complete

Prompt templates MUST NOT contain truncation markers or mixed-language operator
wrappers.

**RATIONALE**

Language must be deterministic at the tool boundary: Swedish for user-facing
runtime/operator text, English for prompt payloads.

**VIOLATION CONDITION**

- Any user-facing status, warning, error, validation, or result text is emitted
  in a language other than Swedish.
- Any generated prompt is not English, not plain text, not complete, or not
  copy-paste-ready.

**VERIFICATION METHOD**

- Snapshot CLI and tool output and run a language-policy check.
- Generate prompts from fixed evidence fixtures and compare exact bytes.
- Fail on mixed-language prompt templates or truncation markers.

## RULE 7 - DETERMINISTIC FAILURE REPORTING

**RULE**

When the system stops because a contract precondition failed, the reported
failure MUST name the exact missing or invalid prerequisite. Failure reporting
MUST NOT guess causes or silently continue in degraded mode.

**RATIONALE**

Deterministic operators need deterministic failure surfaces.

**VIOLATION CONDITION**

- A stop condition reports a vague or guessed cause.
- The system continues after a known contract violation.

**VERIFICATION METHOD**

- Trigger each contract failure class with a fixture and compare the reported
  failure message to the expected prerequisite-specific error.

## RULE 8 - RETRIEVAL MUST BIND TO INDEX CONTRACT VERSION

**RULE**

Before serving any query, retrieval MUST verify that the loaded authoritative
index artifacts were produced under the same `contract_version` and
`chunk_manifest_hash` advertised by `.repo_index/index_manifest.json`.
Retrieval MUST STOP on any version or manifest mismatch.

**RATIONALE**

This creates an explicit handshake between the built index and the active
retrieval contract, which is required for a reliable diff audit.

**VIOLATION CONDITION**

- Retrieval serves results from an index built for a different contract
  generation.
- Retrieval accepts artifacts with the correct corpus but the wrong contract
  version.
- Retrieval continues when the loaded chunk manifest hash differs from the
  authoritative manifest.

**VERIFICATION METHOD**

- Change `contract_version` or `chunk_manifest_hash` in a fixture and assert
  that retrieval stops before serving results.
- Compare retrieval startup validation output to the authoritative manifest
  values.
