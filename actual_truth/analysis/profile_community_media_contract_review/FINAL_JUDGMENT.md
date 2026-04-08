## Explicit Unresolved Decisions

The current source set still requires real canonical decisions on all of the following before the document can become active truth:

1. What is the exact profile/community source entity name or names?
2. Is the source model shared across profile and community, or split into separate models?
3. What is the exact authored subject-binding model?
4. What are the exact publication-state fields and invariants?
5. What profile/community-specific `media_purpose` value or values, if any, become canonical?
6. What exact append-only baseline or above-baseline authority path feeds profile/community rows into `runtime_media`?

## Final Judgment

The current document is best treated as:

`DECISION_SCAFFOLD`

## Why This Is The Strongest Judgment

It is not best treated as `CANDIDATE_CONTRACT`, because the document currently lives inside the authoritative contract set while still hard-coding source-shape decisions that are not declared elsewhere.

It is not best treated as `PARTIAL_CANONICAL_DOCTRINE`, because the document does not yet cleanly separate:

- doctrine that is already declared elsewhere
- unresolved choices that still need real decisions

It is not best treated as `NONCANONICAL_AND_SHOULD_BE_REPLACED`, because a substantial part of the document is already correct and useful:

- unified media chain
- backend read composition boundary
- forbidden legacy payload truth
- non-core versus baseline-core boundary

`DECISION_SCAFFOLD` is therefore the best fit:

- it preserves the strong canonical core
- it prevents speculative source-shape choices from pretending to be active truth
- it gives future task generation a safer foundation once the unresolved decisions are explicitly declared

## Does The Proposed Direction Better Represent The Declared Aveli Target Model?

Yes.

The proposed direction better supports the declared target model because it keeps profile/community media from distorting the already-declared authorities that matter to core product behavior:

- teacher login and teacher-rights authority stay governed by `auth_subjects` and teacher-rights rules
- editor/studio flows stay free from accidental media-domain shortcuts
- teacher course upload and selling flows stay attached to the existing canonical media and course authority layers
- learner login, membership, course purchase, and lesson-access flows stay free from profile/community media side effects
- the system keeps one media doctrine instead of adding another one

## Overall Recommendation

Do not activate the current document as contract truth.

Instead:

1. keep the already-declared doctrine
2. downgrade unsupported source-shape choices into explicit unresolved decisions
3. use the document as a decision scaffold until the missing decisions are actually declared elsewhere in the canonical source set
