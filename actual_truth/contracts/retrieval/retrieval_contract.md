# RETRIEVAL CONTRACT

STATUS: ACTIVE

CLASSIFICATION: RETRIEVAL_STAGE_CONTRACT

This contract is a retrieval-stage contract.
It is not an execution contract and is not subject to the execution response-shape-only rule.

This contract defines the canonical retrieval behavior for indexed repository
search.

## RULE 1 - HEALTHY INDEX IS A PRECONDITION

**RULE**

Retrieval MUST operate only against a healthy canonical index. If the required
index artifacts are missing, unreadable, or corrupt, retrieval MUST STOP. It
MUST NOT rebuild indexes implicitly inside the query path.

**RATIONALE**

The operating system treats index rebuild as expensive and explicit. Retrieval
must therefore be query-only, not query-plus-rebuild.

**VIOLATION CONDITION**

- A normal query triggers index rebuild or index deletion.
- Retrieval substitutes an alternate corpus when the canonical index is invalid.

**VERIFICATION METHOD**

- Run retrieval with a missing or corrupt required artifact and assert a hard
  stop.
- Assert that no authoritative artifact changes during a failing query.

## RULE 2 - CANONICAL RETRIEVAL PIPELINE

**RULE**

The canonical retrieval order MUST be:

1. normalize query
2. lexical candidate retrieval from the persistent lexical index
3. vector candidate retrieval from the persistent vector index
4. candidate union by canonical `doc_id`
5. bounded local rerank
6. ordered evidence emission

Downstream analysis, prompt construction, and validation MUST consume the same
ordered evidence list produced by this pipeline.

**RATIONALE**

Canonical stage order removes hidden ranking drift between search, analysis,
prompting, and validation.

**VIOLATION CONDITION**

- A downstream stage adds new files not present in retrieval evidence.
- A downstream stage reclassifies or reorders evidence using a private policy.
- Retrieval skips lexical, vector, or rerank stages without an explicit contract
  change.

**VERIFICATION METHOD**

- Trace one query end-to-end and compare ordered evidence across all stages.
- Fail if analysis/prompt/validation input differs from retrieval output.

## RULE 3 - NO FULL-CORPUS WORK IN THE QUERY HOT PATH

**RULE**

Per-query work MUST be bounded by candidate limits, not by total corpus size,
except for reading already-materialized evidence for the bounded candidate set.
The hot path MUST NOT:

- load the full corpus into memory
- rebuild a lexical index
- perform BM25 construction over the full corpus
- load embedding or rerank models per query

**RATIONALE**

Hot-path work that scales with the full corpus makes query latency unstable and
prevents the system from acting as a persistent search toolchain.

**VIOLATION CONDITION**

- Query latency includes full-corpus scan or rebuild work.
- Models are initialized for every query.
- Lexical scoring requires rebuilding corpus statistics on each query.

**VERIFICATION METHOD**

- Instrument the query path and fail on full-corpus materialization or index
  rebuild calls.
- Assert that a warm query does not initialize models.
- Measure warm-query behavior as corpus size grows and fail on full-corpus
  scaling.

## RULE 4 - SINGLE-SOURCE RANKING POLICY

**RULE**

Ranking policy MUST be explicit and governed by the canonical index manifest.
Candidate limits, fusion behavior, rerank usage, and any allowed boost policy
MUST be declared once. Hidden path-specific boosts are forbidden unless they are
declared by system law.

**RATIONALE**

Undeclared ranking heuristics create silent retrieval drift and make results
impossible to audit.

**VIOLATION CONDITION**

- Ranking depends on undeclared hardcoded file-name boosts.
- Candidate limits differ across stages without manifest authority.
- Retrieval output cannot be explained from the canonical ranking policy.

**VERIFICATION METHOD**

- Compare runtime ranking parameters to `index_manifest.json`.
- Run an audit query and explain each score contribution from declared policy.
- Fail if any score contribution has no declared authority.

## RULE 5 - BOUNDED, DETERMINISTIC OUTPUT ORDER

**RULE**

Retrieval MUST emit at most `top_k` evidence objects, where `top_k` is defined
by the canonical index manifest. Output order MUST be deterministic:

1. descending score
2. ascending normalized file path
3. ascending `doc_id`

**RATIONALE**

Stable output order is required for reproducible prompts, validation, and audit
diffs.

**VIOLATION CONDITION**

- Equivalent queries produce different result ordering without a corpus change.
- `top_k` differs between retrieval and downstream consumers.
- Tie ordering depends on runtime iteration order.

**VERIFICATION METHOD**

- Run the same query repeatedly against an unchanged healthy index and compare
  ordered evidence.
- Inject tied-score fixtures and assert deterministic tie-break behavior.

## RULE 6 - PROMPT HANDOFF CONTRACT

**RULE**

If retrieval output is turned into a prompt, the prompt MUST be constructed only
from canonical evidence objects. Prompt text MUST be:

- plain text
- copy-paste-ready
- complete
- in English

Prompts MUST NOT include truncation markers, conversational wrappers, or
undeclared analysis not grounded in evidence.

**RATIONALE**

Prompt construction is part of the retrieval consumer chain and must remain
auditable, deterministic, and operator-safe.

**VIOLATION CONDITION**

- Prompt text includes evidence not present in the canonical evidence list.
- Prompt text is mixed-language when the contract requires English.
- Prompt text includes `...`, summaries, or injected commentary instead of
  evidence-grounded content.

**VERIFICATION METHOD**

- Generate a prompt from a fixed evidence fixture and compare exact bytes.
- Assert every prompt evidence reference maps back to a canonical evidence
  object.
- Fail if the prompt contains truncation markers or non-English template text.

## RULE 7 - SCORE FUSION CONTRACT

**RULE**

For each retrieved candidate `doc_id`, the canonical final retrieval score MUST
be defined as:

`final_score(doc_id) = rerank_score(doc_id) + boost_score(doc_id)`

Where:

- `rerank_score(doc_id)` is the canonical bounded rerank output for that
  candidate within the current query
- `boost_score(doc_id)` is the sum of all declared, contract-authorized boost
  contributions for that candidate

If no rerank stage is declared for a contract generation, the contract MUST
explicitly redefine `final_score` in `index_manifest.json`; otherwise this
formula is mandatory.

**RATIONALE**

The score formula must be explicit so that each ordered retrieval result can be
reconstructed during diff audit.

**VIOLATION CONDITION**

- Final ranking uses undeclared score terms.
- A stage combines lexical, vector, rerank, or boost signals through a private
  formula.
- Ordered results cannot be explained from the declared fusion formula.

**VERIFICATION METHOD**

- For a fixed query fixture, reconstruct `final_score` for every emitted result
  from declared terms only.
- Fail if any ordered result depends on an undeclared score contribution.

## RULE 8 - STRICT EVIDENCE-TO-PROMPT MAPPING

**RULE**

Prompt construction MUST be a deterministic projection of the ordered canonical
evidence list. For every prompt evidence block:

- one block MUST map to exactly one canonical evidence object
- block order MUST match evidence order exactly
- `file`, `layer`, `source_type`, and `snippet` MUST be preserved verbatim
- no new file, layer, snippet text, or score interpretation MAY be introduced

Prompt construction MAY add fixed English labels and fixed separators only if
those wrappers are defined by contract and do not alter evidence content.

**RATIONALE**

Diff audit is only possible if prompt evidence is a strict, lossless projection
of retrieval evidence rather than a rewritten narrative.

**VIOLATION CONDITION**

- One prompt block merges multiple evidence objects.
- Prompt order differs from canonical evidence order.
- Prompt text rewrites snippets, omits provenance fields, or inserts undeclared
  evidence.

**VERIFICATION METHOD**

- Build a prompt from a fixed evidence fixture and map each prompt block back to
  exactly one evidence object.
- Fail if prompt order, provenance fields, or snippet bytes differ from the
  source evidence list.
