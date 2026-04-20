# SPECIAL OFFER COMPOSITE IMAGE CONTRACT

## STATUS

ACTIVE

CONTRACT-ONLY AUTHORITY

NO RUNTIME IMPLEMENTATION AUTHORIZED

RUNTIME WORK REMAINS BLOCKED UNTIL FUTURE ACCEPTED EXECUTION AND SUBSTRATE WORK

This contract defines the canonical domain authority for backend-generated
special-offer composite images.

This contract does not authorize runtime code, SQL, routes, workers, storage
jobs, frontend UI, tests, migrations, baseline slots, or determined-task
artifacts.

## 1. Authority References

This contract operates under these active authorities:

- `SYSTEM_LAWS.md`
  - owns cross-domain determinism law, no-fallback doctrine, media separation
    doctrine, source-table placement doctrine, backend read-composition
    authority, and frontend render-only law
- `media_unified_authority_contract.md`
  - owns cross-domain governed-media doctrine:
    `app.media_assets -> app.runtime_media -> backend read composition -> API -> frontend`
- `media_pipeline_contract.md`
  - owns existing lesson-media ingest and placement law and does not grant this
    contract lesson-media authority
- `media_lifecycle_contract.md`
  - owns media-asset orphan verification and deletion authority
- `storage_lifecycle_contract.md`
  - owns physical storage cleanup and storage readiness constraints
- `course_lesson_editor_contract.md`
  - owns course structure, lesson structure, lesson content, and course-cover
    assignment through `app.courses.cover_media_id`
- `COURSE_COVER_READ_CONTRACT.md`
  - owns course-cover response-shape law and ready course-cover output rules
- `course_monetization_contract.md`
  - owns bundle pricing, sellability, teacher bundle composition intent, and
    backend monetization validation
- `commerce_membership_contract.md`
  - owns commerce membership separation, course-bundle purchase separation, and
    order/payment authority
- `course_public_surface_contract.md`
  - owns public course and lesson read surface semantics and public course-cover
    rendering constraints
- `system_text_authority_contract.md`
  - owns system-wide user-facing product text authority and Swedish-only product
    text law
- `backend_text_catalog_contract.md`
  - owns backend text catalog structure, text ID rules, and runtime text
    provenance requirements
- `AVELI_DATABASE_BASELINE_MANIFEST.md`
  - owns baseline substrate truth, enum authority, schema-change requirements,
    and the rule that new app-owned schema requires accepted Baseline V2 work
- `CCL_course_cover_lesson_content_authority_task_tree.md`
  - clarifies course-cover and lesson-content authority boundaries for future
    execution planning
- `0011B_course_cover_media_authority_unification.md`
  - clarifies that course cover is a media usage under unified media authority,
    not a separate resolver system
- `BCP-040_resolve_unified_runtime_media_expansion.md`
  - clarifies that `runtime_media` is runtime truth only and does not own
    authored placement or final frontend representation
- `CMTZ-004_BUNDLE_COMPOSITION.md`
  - clarifies same-teacher bundle composition invariants and membership
    separation for bundle composition

Authority ownership summary:

- Cross-domain media doctrine: `SYSTEM_LAWS.md` and
  `media_unified_authority_contract.md`
- Determinism law: `SYSTEM_LAWS.md`
- Media identity and lifecycle: `app.media_assets` under media pipeline and
  lifecycle contracts
- Storage cleanup: `storage_lifecycle_contract.md`
- Bundle pricing, composition, and sellability: `course_monetization_contract.md`
  plus commerce contracts
- User-facing text authority: `system_text_authority_contract.md` and
  `backend_text_catalog_contract.md`

## 2. Domain Classification

Special-offer composite images are canonically classified as:

```text
special-offer domain attachment
+ governed-media output
```

This is not course-cover authority.

This is not lesson-media authority.

This is not bundle pricing, bundle composition, sellability, checkout,
membership, course access, or public course-surface authority.

The special-offer domain owns whether a generated composite image is attached
to a target special offer. Governed media contracts own the generated media
asset identity, runtime readiness, backend delivery resolution, and eventual
media/storage lifecycle after reference removal.

Existing course-cover authority may be used only as source eligibility evidence
when a selected source image is a course cover.

Bundle composition and pricing remain outside this contract. A future execution
or substrate task may decide whether the target special offer maps to existing
bundle substrate or a separate special-offer substrate, but that decision must
not rewrite bundle pricing, sellability, checkout, access, or membership law.

## 3. Canonical Entity Model

Future substrate is required before implementation.

Required future substrate concepts:

- A future special-offer output owner relation is required before any runtime
  generation or rendering implementation.
- A future persisted source-selection relation, or equivalent persisted selected
  input set, is required before any runtime generation or rendering
  implementation.
- A future media purpose value named `special_offer_composite_image` is proposed
  unless future review chooses a different exact value before baseline work.

The future special-offer output owner relation must own:

- active special-offer composite image binding
- persisted selected source inputs for the generated output
- overwrite semantics for regeneration
- generation attempt authority and final generation result binding

The future special-offer output owner relation must enforce:

- exactly one active composite image binding may exist per special offer
- zero active binding is valid when no generation has succeeded
- the active binding must reference governed media output
- the active binding must not be represented by `app.media_assets` alone
- `app.media_assets` owns media identity and lifecycle only
- `app.courses.cover_media_id` must never be reused as the special-offer output
  pointer

No current baseline relation is promoted by this contract into special-offer
image placement truth.

## 4. Source Image Eligibility

Canonical source image count:

- minimum: 1
- maximum: 5

Zero source images is invalid.

More than five source images is invalid.

Source image eligibility rules:

- Source images must be backend-validated governed image media.
- Source images must resolve through canonical media identity and readiness
  authority before participation in generation.
- Raw URLs, storage paths, signed URLs, preview files, local files, client file
  names, buckets, object paths, public URLs, and ungoverned media are forbidden
  as source truth.
- Source courses must belong to the target special offer.
- Source courses must belong to the same teacher in MVP.
- Cross-teacher source images are forbidden in MVP.
- This contract owns whether a validated governed image may participate in
  special-offer generation.

Course-cover source rule:

- If a source image is a course cover, `course_lesson_editor_contract.md` and
  `COURSE_COVER_READ_CONTRACT.md` still own course-cover identity, assignment,
  validity, readiness, and read shape.
- Course-cover validity does not become special-offer authority.
- Course-cover authority may prove only that the course-cover source image is a
  valid governed image candidate.
- This contract owns the separate decision that the validated course-cover
  source may be selected for a special-offer composite image.

Lesson-media source rule:

- This contract does not create lesson-media source eligibility.
- Lesson-media images may not become source truth unless a future accepted
  contract explicitly allows that eligibility while preserving lesson-media
  placement authority.

## 5. Generation And Regeneration

Generation is backend-owned.

Regeneration is allowed only through an explicit user-triggered
generate/regenerate action routed to a future canonical backend execution
surface.

Automatic generation or regeneration is forbidden on:

- read
- render
- page load
- course edit
- special-offer edit
- cover edit
- checkout
- worker sweep
- lifecycle cleanup
- runtime projection
- backend read composition

Random source choice is permitted only as an internal backend selection
mechanism inside an explicit generate/regenerate transaction.

Randomness is not canonical truth.

The canonical truth for a generated output is the persisted selected source
input set associated with that output.

Forbidden randomness patterns:

- hidden randomness
- recomputed randomness
- read-time randomness
- render-time randomness
- worker-sweep randomness
- state-dependent re-selection
- candidate-set re-evaluation after generation as if it were original selection

A seed alone is insufficient unless it is paired with:

- the candidate snapshot used for the transaction
- the selection algorithm version
- the persisted selected source input set
- the generated output binding

## 6. Overwrite Semantics

Overwrite is approved.

Regeneration replaces the active special-offer composite image binding.

No versioned public history is part of this model.

The regenerate request must not synchronously delete media assets or physical
storage objects.

Previous output media may become eligible for lifecycle and orphan handling only
after the previous active binding is removed or replaced and existing
media/storage doctrine proves that no canonical usage surface still references
the asset.

Reference replacement and asset cleanup are separate authority layers:

```text
explicit regenerate action
-> backend generation transaction
-> new governed output media identity and readiness flow
-> replacement of active special-offer binding after success
-> old reference removal signal may request lifecycle evaluation
-> media lifecycle verifies orphan status
-> storage cleanup runs only after safe asset deletion authority
```

## 7. Failure Model

If generation fails, preserve the previous active special-offer composite image
binding.

If no previous active image exists, the special-offer composite image output
remains null.

Failure must not create:

- frontend fallback authority
- sellability authority
- checkout authority
- course-access authority
- media readiness authority
- storage truth authority
- course-cover assignment authority
- lesson-media authority

Forbidden fallback outputs:

- frontend-composed fallback
- OpenAI-generated fallback
- external image-model-generated fallback
- placeholder fallback
- raw collage fallback
- storage-URL fallback
- signed-URL fallback
- course-cover pointer fallback
- bundle-title or pricing fallback

Generation failure may produce backend-owned failure status or error text only
through future accepted execution and text authority. Missing generated output
must fail closed.

## 8. Confirmation Warning And Text Authority

This contract owns the rule that overwrite requires explicit confirmation before
backend generation starts.

Exact user-facing warning copy belongs to text authority, not this contract.

Allowed future text authority pattern:

```text
contract text ID
-> backend text catalog
-> backend execution/read surface
-> frontend render
```

Potential text IDs may be ASCII internal identifiers such as:

- `studio_editor.special_offer_image.overwrite_confirmation`
- `studio_editor.special_offer_image.generation_failed`
- `studio_editor.special_offer_image.generation_status`

These IDs are non-user-facing identifiers and must never be rendered as product
copy.

Any exact user-facing copy for confirmation, status, failure, or recovery must
be Swedish and must be owned by `system_text_authority_contract.md` and
`backend_text_catalog_contract.md`.

This contract does not hardcode exact warning copy.

## 9. Frontend Boundary

Frontend may only trigger future canonical backend execution surfaces for
generate/regenerate actions.

Frontend may only render backend-composed governed media output.

Frontend must treat the special-offer composite image output as read-only
backend truth.

Frontend must not:

- select source inputs as authority
- compose images
- crop images
- merge images
- generate output
- call OpenAI or any image model for layout/composition truth
- resolve storage
- construct URLs
- inspect buckets, object paths, signed URLs, upload URLs, or local files as
  media truth
- repair failed generation
- synthesize fallback images
- replace backend confirmation logic
- treat UI state as active binding truth

Frontend guidance checks may exist only after future execution work defines
them, and such checks are never authority.

## 10. Forbidden Patterns

The following patterns are contract-invalid:

- reusing `app.courses.cover_media_id` as the special-offer output pointer
- treating course-cover authority as special-offer authority
- treating lesson-media authority as special-offer authority
- treating `app.media_assets` alone as active special-offer placement truth
- treating `app.runtime_media` as authored placement truth
- frontend source-selection authority
- frontend image composition authority
- frontend crop, merge, or collage authority
- frontend URL construction
- frontend storage resolution
- frontend generation repair
- OpenAI or any image model as selection authority
- OpenAI or any image model as layout authority
- OpenAI or any image model as composition authority
- OpenAI or any image model as fallback authority
- hidden randomness
- recomputed randomness
- read-time randomness
- render-time randomness
- state-dependent re-selection
- overwrite without explicit confirmation
- immediate media-asset deletion inside the regenerate request
- immediate storage-object deletion inside the regenerate request
- raw storage truth
- raw URL truth
- signed URL truth
- public URL truth
- preview-file truth
- local-file truth
- automatic regeneration
- regeneration on read, render, page load, edit, checkout, or worker sweep
- cross-teacher source images in MVP
- public version-history behavior unless future accepted authority replaces
  overwrite semantics
- changing bundle pricing, composition, sellability, checkout, access, or
  membership law from this contract
- changing course-cover assignment or course-cover read shape from this
  contract
- changing media lifecycle, storage lifecycle, or runtime projection authority
  from this contract
- adding exact user-facing product copy outside text authority

## 11. Future Work Required Before Implementation

Runtime implementation remains blocked until future accepted work defines all of
the following:

- execution contract for generate/regenerate surfaces and response shape
- baseline substrate task for special-offer output/source relations
- baseline substrate task for the proposed media purpose/readiness/runtime
  projection changes, or an accepted replacement media-purpose decision
- determined-task tree with dependency audit
- backend generation owner and transaction semantics
- media worker and readiness alignment for generated composite output
- backend read-composition alignment for special-offer composite image output
- media lifecycle reference-surface audit for the new output owner relation
- storage lifecycle cleanup alignment after reference removal
- text catalog entries for Swedish confirmation, status, and failure copy
- frontend render-only alignment and gates
- verification that no course-cover, lesson-media, bundle-pricing, checkout, or
  membership authority has been collapsed into this domain

Future execution work must preserve this contract's owner boundaries. If future
baseline or execution review discovers a conflict with existing active
contracts, implementation must stop until contract authority is reconciled.

## 12. Final Assertion

Special-offer composite images are a special-offer domain attachment with
governed-media output.

This contract does not make special-offer composite images a course-cover
concern, lesson-media concern, media-assets-only concern, bundle-pricing
concern, checkout concern, or frontend concern.

The only valid future runtime path is:

```text
explicit user-triggered backend generate/regenerate action
-> backend-validated governed image sources
-> persisted selected source input set
-> governed generated media output
-> special-offer output owner binding
-> runtime media projection
-> backend read composition
-> frontend render-only output
```

No implementation may proceed until the future execution, substrate, text, and
determined-task authorities required by this contract are accepted.
