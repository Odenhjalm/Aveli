# SPECIAL OFFER DOMAIN CONTRACT

## STATUS

ACTIVE

CONTRACT-ONLY AUTHORITY

NO RUNTIME IMPLEMENTATION AUTHORIZED

RUNTIME WORK REMAINS BLOCKED UNTIL FUTURE ACCEPTED EXECUTION, SUBSTRATE, AND
DETERMINED-TASK WORK

This contract defines the canonical domain authority for the teacher-facing
`Skapa erbjudande` special-offer state.

This contract does not authorize runtime code, SQL, routes, workers, storage
jobs, frontend UI, tests, migrations, baseline slots, or determined-task
artifacts.

## 1. Authority References

This contract operates under these active authorities:

- `Aveli_System_Decisions.md`
  - owns semantic system direction, feature expansion through new canonical
    entities, Swedish product text law, and English operator-prompt law
- `aveli_system_manifest.json`
  - owns execution-rule policy, media authority classification, baseline V2
    interpretation, and forbidden authority patterns
- `SYSTEM_LAWS.md`
  - owns one-canonical-location law, cross-domain media doctrine,
    determinism law, no-fallback doctrine, separation law, and
    execution-boundary law
- `special_offer_composite_image_contract.md`
  - owns generated special-offer composite-image output, active image binding,
    persisted selected source inputs, overwrite semantics, generation attempt
    authority, and governed-media output relation
- `media_unified_authority_contract.md`
  - owns cross-domain governed-media source/read doctrine and frontend
    render-only media law
- `media_pipeline_contract.md`
  - owns lesson-media ingest and placement law and does not grant this contract
    lesson-media authority
- `media_lifecycle_contract.md`
  - owns media-asset orphan verification and deletion authority
- `storage_lifecycle_contract.md`
  - owns physical storage lifecycle and the rule that storage is never media
    identity, access truth, or frontend truth
- `course_monetization_contract.md`
  - owns course and bundle monetization, pricing validation, sellability,
    Stripe mapping, and teacher selling authority
- `commerce_membership_contract.md`
  - owns order, payment, membership, bundle-commerce separation, checkout, and
    course-entitlement fulfillment boundaries
- `course_public_surface_contract.md`
  - owns public course and lesson read-surface semantics and backend-provided
    course-cover rendering constraints
- `system_text_authority_contract.md`
  - owns system-wide product text authority and Swedish-only user-facing text
    law
- `backend_text_catalog_contract.md`
  - owns backend text catalog structure, text ID rules, and runtime text
    provenance requirements
- `AVELI_DATABASE_BASELINE_MANIFEST.md`
  - owns accepted baseline substrate truth and the rule that new app-owned
    schema requires accepted Baseline V2 work
- `CCL_course_cover_lesson_content_authority_task_tree.md`
  - clarifies course-cover identity, assignment, readiness, and frontend
    render-only boundaries
- `0011B_course_cover_media_authority_unification.md`
  - clarifies that course cover is a media usage under unified media authority,
    not a special resolver system
- `BCP-040_resolve_unified_runtime_media_expansion.md`
  - clarifies that `runtime_media` is runtime truth only and does not own
    authored identity or final frontend representation
- `CMTZ-004_BUNDLE_COMPOSITION.md`
  - clarifies same-teacher bundle composition invariants and membership
    separation for bundle composition
- `CMTZ-005_BUNDLE_PRICING_AUTHORITY.md`
  - clarifies backend-owned bundle pricing authority and frontend
    non-authority
- `CMT-008_BUNDLE_PRESERVATION.md`
  - clarifies bundle order/payment backing and membership separation during
    commerce repair

Authority ownership summary:

- Special-offer state: this contract
- Generated composite image output: `special_offer_composite_image_contract.md`
- Cross-domain media doctrine: `SYSTEM_LAWS.md` and
  `media_unified_authority_contract.md`
- Media identity, readiness, lifecycle, runtime projection, and storage
  cleanup: active media and storage contracts
- Course and bundle pricing, sellability, Stripe mapping, checkout, orders,
  payments, fulfillment, and entitlement effects: monetization and commerce
  contracts
- Exact user-facing product text: text authority contracts

## 2. Domain Classification

The teacher-facing `Skapa erbjudande` feature is canonically classified as:

```text
standalone special-offer domain
+ downstream governed-media integration
+ downstream commerce integration
```

This is not course-cover authority.

This is not lesson-media authority.

This is not generic media authority.

This is not checkout, payment, Stripe, order, membership, bundle-pricing,
bundle-sellability, or course-entitlement authority.

The one-course case and the two-to-five-course case remain one unified
special-offer domain. A one-course special offer must not be forced into
ordinary course-pricing authority merely because it contains one course. A
multi-course special offer must not be forced into existing bundle authority
unless a later accepted integration contract explicitly maps the special-offer
state into commerce/bundle behavior.

The special-offer domain owns the offer state that downstream media generation
and future commerce integration may consume.

The generated composite image is derivative output and is never offer-state
authority.

## 3. Canonical Domain Model

Future substrate is required before implementation.

Required future substrate concepts:

- special-offer identity
- teacher owner
- selected course set
- deterministic selected-course ordering or an accepted canonical sort rule
- offer price
- backend-owned image-current / image-required semantic state
- relation to active composite-image authority owned outside this contract

The future special-offer domain relation must own:

- the existence of a special offer
- the teacher owner for the special offer
- the selected course set for the special offer
- validation that the selected course count is within the canonical range
- validation that selected courses are not duplicated
- validation that selected courses belong to the same teacher in MVP
- the offer price as domain truth
- whether the current offer state requires image generation or regeneration

The future special-offer domain relation must not own:

- generated image media identity
- active generated-image binding
- persisted selected image-source inputs
- media readiness
- media lifecycle cleanup
- physical storage lifecycle
- checkout
- Stripe mapping
- order creation
- payment recording
- entitlement fulfillment
- exact user-facing text copy

Exactly zero active generated images is valid for an existing special offer.
Offer existence is independent of image generation.

The active composite image relation must not be represented by
`app.media_assets` alone. `app.media_assets` owns media identity and lifecycle
only. Active special-offer image binding remains owned by the future output
relation governed by `special_offer_composite_image_contract.md`.

`app.courses.cover_media_id` must never be reused as the special-offer image
pointer or offer-state pointer.

No current baseline relation is promoted by this contract into special-offer
domain truth.

## 4. Core Invariants

Course selection invariants:

- A special offer must contain at least one selected course.
- A special offer must contain no more than five selected courses.
- The selected course count is canonically `1..5`.
- Zero selected courses is invalid.
- More than five selected courses is invalid.
- Duplicate selected courses are invalid.
- Each selected course must be backend-validated.
- Each selected course must belong to the special-offer teacher in MVP.
- Cross-teacher selected course sets are forbidden in MVP.

Teacher ownership invariants:

- Every special offer must have exactly one teacher owner.
- Teacher ownership must be backend-validated before submitted intent becomes
  canonical special-offer truth.
- Frontend teacher identity, route state, token display state, or local form
  state must not become teacher ownership authority.

Price invariants:

- Offer price is special-offer domain truth.
- Teacher price input is intent only until backend validates and persists it
  through future accepted implementation.
- Price must be present and valid under future accepted price validation law.
- Missing price is invalid.
- Invalid price is invalid.
- The generated image may represent price but must not define, correct,
  override, or reconstruct price truth.
- Frontend price display or local form state must not become price authority.

Image-current invariants:

- Special-offer state may exist before any composite image has been generated.
- No active composite image is valid when generation has not yet succeeded.
- Current/needs-image state must be backend-owned.
- Current/needs-image state must be derived only from canonical special-offer
  state and accepted composite-image generation/binding evidence.
- Frontend must not decide image-current state.
- Image failure must not invalidate special-offer existence.

## 5. Relation To Composite Image Contract

`special_offer_composite_image_contract.md` owns:

- generated composite-image output
- active special-offer composite-image binding
- persisted selected source inputs for the generated image
- overwrite semantics
- generation attempt authority
- governed-media output relation
- frontend render-only image boundary
- failure behavior for image generation

This contract owns:

- selected courses as offer-state truth
- offer price as offer-state truth
- teacher owner as offer-state truth
- offer existence independent of image generation
- whether current offer state requires image generation or regeneration

The composite image is a deterministic representation of special-offer state.
It is not the source of truth for selected courses, price, teacher ownership,
sellability, checkout, or entitlement.

A future execution contract must define how create, update, generate, and
regenerate actions coordinate these two authority layers without collapsing
them.

A future substrate task must define the exact relation between:

```text
special-offer state
-> image-required/current state
-> composite-image output/source relation
-> governed media identity
-> runtime media projection
-> backend read composition
-> frontend render
```

## 6. Separation From Commerce And Bundle Authority

This contract does not redefine:

- course pricing
- bundle pricing
- bundle composition
- bundle sellability
- course sellability
- checkout initiation
- Stripe product or price mapping
- Stripe checkout behavior
- order creation
- payment recording
- webhook settlement
- course entitlement fulfillment
- membership state
- refund, withdrawal, cancellation, or remedy authority

Future commerce systems may consume special-offer state only through a later
accepted integration authority.

Special-offer price may be consumed by future commerce, but this contract does
not make a special offer sellable, checkout-ready, order-backed, payment-backed,
or entitlement-granting.

Existing bundle substrate and bundle contracts remain separate. This contract
must not be used to reinterpret `app.course_bundles`,
`app.course_bundle_courses`, bundle Stripe mappings, bundle checkout, or bundle
fulfillment as special-offer domain truth.

If a future accepted task maps special offers into bundle or commerce
substrate, that task must preserve:

- special-offer state ownership in this contract
- composite image ownership in `special_offer_composite_image_contract.md`
- checkout/order/payment/entitlement ownership in commerce contracts

## 7. Frontend Boundary

Frontend may:

- submit teacher intent to future canonical backend execution surfaces
- trigger future canonical backend create, update, generate, or regenerate
  actions where execution contracts allow those actions
- render backend-owned special-offer state
- render backend-composed governed media output for the active composite image
- display backend/catalog-owned Swedish product text

Frontend must not own:

- selected-course authority
- selected-course validation authority
- teacher ownership authority
- price authority
- image-current authority
- image-required authority
- overwrite authority
- generated image binding authority
- media identity, readiness, lifecycle, projection, or delivery authority
- commerce, checkout, payment, order, fulfillment, or entitlement authority
- product text authority

Frontend must not:

- compose special-offer images
- draw or overlay price as canonical image truth
- repair missing or failed image generation
- synthesize fallback offer state
- synthesize fallback images
- construct storage URLs
- resolve media from buckets, object paths, signed URLs, public URLs, filenames,
  preview files, or local files
- treat local form state as persisted offer truth

## 8. Text Authority

This contract names `Skapa erbjudande` only as the accepted Swedish feature
label for the teacher-facing special-offer feature.

Exact user-facing copy for create, update, generate, regenerate, overwrite
confirmation, status, validation, and failure states belongs to text authority,
not this contract.

Future exact user-facing copy must be Swedish and must flow through:

```text
contract text ID
-> backend text catalog
-> backend execution/read surface
-> frontend render
```

Text IDs are internal non-user-facing identifiers and must not be rendered as
product copy.

This contract does not hardcode exact confirmation, status, validation, or
failure copy.

## 9. Invalid States

The following states are contract-invalid:

- special offer without a teacher owner
- selected course set with zero courses
- selected course set with more than five courses
- selected course set containing duplicate courses
- selected course set containing courses not owned by the special-offer teacher
  in MVP
- cross-teacher selected course set in MVP
- missing offer price
- invalid offer price
- frontend-authored selected-course truth
- frontend-authored price truth
- frontend-authored teacher ownership truth
- frontend-authored image-current truth
- image-derived price truth
- image-derived selected-course truth
- image-derived teacher ownership truth
- media-assets-only offer truth
- runtime-media-only offer truth
- course-cover authority reused as special-offer truth
- `app.courses.cover_media_id` reused as special-offer state or image pointer
- checkout, payment, order, membership, or entitlement authority duplicated
  inside special-offer state
- existing bundle authority treated as special-offer authority without future
  accepted integration authority

## 10. Forbidden Patterns

The following patterns are forbidden:

- splitting `Skapa erbjudande` into separate single-course and multi-course
  domain authorities
- treating the one-course case as ordinary course-pricing authority
- treating the two-to-five-course case as existing bundle authority by default
- treating selected courses as frontend truth
- treating price as frontend truth
- treating generated image pixels as price truth
- treating generated image pixels as course-set truth
- treating generated image presence as offer existence truth
- making image generation required for special-offer existence
- using `app.media_assets` alone as special-offer placement truth
- using `app.runtime_media` as special-offer source truth
- using `app.courses.cover_media_id` as special-offer output pointer
- using course-cover assignment authority as special-offer authority
- using lesson-media placement authority as special-offer authority
- using bundle pricing, bundle sellability, checkout, Stripe, order, payment,
  membership, or entitlement authority as special-offer state authority
- automatic commerce activation from special-offer state
- frontend image composition
- frontend price overlay as canonical image truth
- frontend fallback image behavior
- frontend fallback offer-state behavior
- frontend product text authority
- raw URL truth
- raw storage truth
- signed URL truth
- public URL truth
- local file truth
- storage path truth
- hidden fallback authority when image generation, commerce integration, or
  substrate ownership is missing

## 11. Future Work Required Before Implementation

Runtime implementation remains blocked until future accepted work defines all
of the following:

- execution contract for create, update, generate, and regenerate surfaces
- execution contract response-shape and failure-shape law
- baseline substrate task for special-offer domain relations
- baseline substrate task for composite-image output/source relations if not
  already covered by accepted work
- baseline substrate task for any media purpose, readiness, runtime projection,
  or backend read-composition changes required by generated output
- determined-task tree with dependency audit
- backend owner alignment for special-offer state persistence and validation
- backend owner alignment for image generation coordination
- composite-image read alignment
- media lifecycle reference-surface audit for the new domain and output
  relations
- storage lifecycle cleanup alignment after reference removal
- Swedish text catalog entries for create, update, generate, regenerate,
  overwrite confirmation, status, validation, and failure copy
- frontend render-only and trigger-only alignment gates
- commerce integration audit if special offers become sellable, checkoutable,
  order-backed, payment-backed, or entitlement-granting

No runtime work may proceed from this contract alone.

## 12. Final Assertion

`Skapa erbjudande` is a standalone special-offer domain with downstream media
and commerce integrations.

This contract owns special-offer state only.

This contract does not make special offers a course-cover concern, lesson-media
concern, generic media concern, bundle-pricing concern, checkout concern,
payment concern, membership concern, entitlement concern, or frontend concern.

The only valid future authority layering is:

```text
teacher intent
-> backend-validated special-offer state
-> optional explicit backend image generation/regeneration
-> composite-image output/source authority
-> governed media identity and lifecycle
-> runtime media projection
-> backend read composition
-> frontend render-only output
```

No implementation may proceed until the future execution, substrate, text,
commerce-integration, media-alignment, frontend-alignment, and determined-task
authorities required by this contract are accepted.
