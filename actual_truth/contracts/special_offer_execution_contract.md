# SPECIAL OFFER EXECUTION CONTRACT

## STATUS

ACTIVE

CONTRACT-ONLY AUTHORITY

NO RUNTIME IMPLEMENTATION AUTHORIZED

RUNTIME WORK REMAINS BLOCKED UNTIL FUTURE ACCEPTED SUBSTRATE AND
DETERMINED-TASK WORK

This contract defines execution-layer authority for the teacher-facing
`Skapa erbjudande` special-offer flow.

This contract does not authorize runtime code, SQL, routes, workers, storage
jobs, frontend UI, tests, migrations, baseline slots, or determined-task
artifacts.

This contract does not fix exact route names, mounted paths, request JSON,
response JSON, persistence schema, worker topology, or UI layout. Logical action
names in this contract are internal execution labels, not user-facing product
copy.

## 1. Authority References

This contract operates under these active authorities:

- `Aveli_System_Decisions.md`
  - owns semantic system direction, feature expansion through new canonical
    entities, Swedish product text law, and English operator-prompt law
- `aveli_system_manifest.json`
  - owns execution-rule policy, baseline V2 interpretation, media authority
    classification, and forbidden authority patterns
- `SYSTEM_LAWS.md`
  - owns one-canonical-location law, cross-domain media doctrine, determinism
    law, no-fallback doctrine, separation law, and execution-boundary law
- `special_offer_domain_contract.md`
  - owns special-offer domain state, selected courses, teacher owner, offer
    price, offer existence independent of image generation, and backend-owned
    current/needs-image semantic state
- `special_offer_composite_image_contract.md`
  - owns generated composite-image output, active image binding, persisted
    selected source inputs, overwrite semantics, generation attempt authority,
    governed-media output relation, and image failure preservation
- `media_unified_authority_contract.md`
  - owns governed-media source/read doctrine and frontend render-only media law
- `media_pipeline_contract.md`
  - owns canonical media ingest, placement boundaries, and media pipeline
    separation without granting this contract lesson-media authority
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
  - owns system-wide user-facing product text authority and Swedish-only product
    text law
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
- `CMTZ-008_PURCHASE_INTEGRATION.md`
  - clarifies order/payment-backed course and bundle purchase integration
    without granting special-offer commerce authority
- `CMT-008_BUNDLE_PRESERVATION.md`
  - clarifies bundle order/payment backing and membership separation during
    commerce repair

Authority ownership summary:

- Special-offer state: `special_offer_domain_contract.md`
- Special-offer execution coordination: this contract
- Generated composite-image output and active image binding:
  `special_offer_composite_image_contract.md`
- Cross-domain media doctrine: `SYSTEM_LAWS.md` and
  `media_unified_authority_contract.md`
- Media identity, readiness, lifecycle, runtime projection, and storage
  cleanup: active media and storage contracts
- Course and bundle pricing, sellability, checkout, orders, payments,
  fulfillment, and entitlement effects: monetization and commerce contracts
- Exact user-facing product text: text authority contracts

## 2. Execution Classification

This is an execution contract only.

It coordinates future backend execution surfaces between:

```text
special_offer_domain_contract.md
-> special_offer_composite_image_contract.md
-> governed media read/lifecycle authority
```

This contract does not own special-offer domain state. It may require execution
surfaces to validate and persist that state only through the future accepted
domain implementation.

This contract does not own composite-image output authority. It may require
execution surfaces to call or coordinate that authority only through future
accepted generation and binding implementation.

This contract does not own media identity, media readiness, media lifecycle,
storage lifecycle, text authority, commerce authority, checkout authority,
payment authority, order authority, fulfillment authority, or entitlement
authority.

Execution authority exists only to define how future backend surfaces:

- accept teacher intent
- validate intent through the owning authority
- order state transitions
- gate overwrite behavior
- expose side-effect-free execution-visible status
- preserve failure boundaries

## 3. Execution Surface Family

The canonical execution surface family contains these logical actions:

- create offer
- update offer
- generate image
- regenerate image
- read current offer execution-visible state

These are logical execution responsibilities, not canonical route names.

Future route names, request models, response models, transport metadata, and
backend service boundaries require separate accepted execution/substrate work.

No runtime implementation may treat this surface family as permission to add
mounted routes, SQL, workers, frontend UI, tests, baseline slots, or
determined-task artifacts.

## 4. Action Semantics

### Create Offer

Create offer is an explicit teacher-triggered backend action.

Create offer is atomic at the special-offer state boundary.

Create offer must validate submitted teacher intent through
`special_offer_domain_contract.md`, including:

- teacher owner
- selected course count within `1..5`
- no duplicate selected courses
- same-teacher selected course set in MVP
- valid offer price

Successful create offer persists backend-validated special-offer state only.

Successful create offer must not:

- generate an image
- regenerate an image
- create an active composite-image binding
- create governed media output
- create media lifecycle cleanup work
- activate commerce
- mark sellability
- initiate checkout
- create an order or payment
- grant entitlements

Create offer does not require overwrite confirmation because it must not replace
an active image binding.

Any implementation that tries to create an offer and generate an image in the
same implicit action is contract-invalid.

### Update Offer

Update offer is an explicit teacher-triggered backend action.

Update offer is atomic at the special-offer state boundary.

Update offer must validate submitted teacher intent through
`special_offer_domain_contract.md`, including selected courses, teacher owner,
same-teacher MVP invariants, duplicate-course rejection, and offer price.

Successful update offer persists backend-validated special-offer state only.

Successful update offer may change backend-owned image-current / image-required
semantics when the persisted offer state no longer matches the currently active
composite image.

Successful update offer must preserve any existing active composite-image
binding until an explicit generation or regeneration action succeeds.

Update offer must not automatically generate or regenerate an image.

Update offer does not require overwrite confirmation if it only updates
special-offer state and preserves the active image binding.

Any update action that would replace an active image binding must use regenerate
semantics and must be overwrite-confirmation-gated.

### Generate Image

Generate image is an explicit teacher-triggered backend action.

Generate image is valid only when the target special offer has no active
composite-image binding.

Generate image coordinates with
`special_offer_composite_image_contract.md` for source eligibility, persisted
selected source inputs, generation attempt authority, governed-media output,
and output binding.

Generate image is asynchronous-capable. Future implementation may complete the
generated output during the request or through backend-owned asynchronous work,
but the execution contract requires the same authority boundary in both cases.

Generate image does not require overwrite confirmation when no active image
binding exists.

If an active image binding exists, generate image must fail closed or require
the caller to use explicit regenerate semantics. Hidden conversion from
generate to regenerate is forbidden.

Successful generate image may bind the first active composite image only after
the generated output is accepted under composite-image and governed-media
authority.

Failed generate image must preserve the special offer and leave active image
state absent.

### Regenerate Image

Regenerate image is an explicit teacher-triggered backend action.

Regenerate image is the only canonical action that may replace an active
special-offer composite-image binding.

Regenerate image is overwrite-confirmation-gated. Backend execution must verify
explicit confirmation before generation work starts.

Regenerate image coordinates with
`special_offer_composite_image_contract.md` for source eligibility, persisted
selected source inputs, overwrite semantics, generation attempt authority,
governed-media output, and replacement binding.

Regenerate image is asynchronous-capable. Future implementation may complete
the generated output during the request or through backend-owned asynchronous
work, but the previous active image must remain active until a replacement
output has succeeded and binding replacement is accepted.

Failed regeneration must preserve the previous active composite-image binding.

Regenerate image must not synchronously delete old media assets or physical
storage objects. Old output media may become eligible for media lifecycle and
storage cleanup only after reference removal and only under existing
media/storage doctrine.

### Read Current Offer Execution-Visible State

Read current offer execution-visible state is a side-effect-free backend read.

Read state may compose execution-visible facts from:

- backend-validated persisted special-offer state
- active composite-image presence or absence
- backend-owned image-current / image-required semantics
- backend-owned generation status
- backend-owned failure-preservation status
- backend/catalog-owned text identifiers or status identifiers, when future
  text authority defines them

Read state must not:

- generate images
- regenerate images
- repair image bindings
- create fallback images
- trigger media cleanup
- trigger storage cleanup
- activate commerce
- initiate checkout
- create orders or payments
- grant entitlements
- repair status from frontend state

Read state must expose no raw storage paths, raw URLs, signed URLs, preview
files, local files, internal stack traces, framework errors, or ungoverned media
truth.

## 5. Status / State Model

The minimal execution-visible backend state is:

- persisted offer state
- active composite-image presence or absence
- image-current / image-required semantics
- generation status
- failure-preservation semantics

Persisted offer state is owned by `special_offer_domain_contract.md`.

Active composite-image binding is owned by
`special_offer_composite_image_contract.md`.

Image-current / image-required semantics are domain-owned and may be exposed by
execution reads only as backend-owned state.

Generation status is execution-visible, but not frontend-owned. Future accepted
implementation must decide whether generation status is persisted, derived from
backend job state, or represented through another backend-owned substrate.

Allowed logical generation-status classes are limited to:

- no active generation attempt
- generation accepted but not complete
- generation succeeded
- generation failed

These logical classes are not final enum names and do not authorize schema.

Failure-preservation semantics:

- if initial generation fails, the offer remains and active image remains absent
- if regeneration fails, the previous active image remains active
- partial output must not become active image truth
- stale active image after offer update is a valid execution-visible state
- frontend must not repair, hide, or reinterpret stale or failed states

Execution-visible state must not leak raw internal errors as canonical
user-facing truth. Product-visible copy must be delivered only through text
authority.

## 6. Failure Model

### Initial Generation Failure

If initial image generation fails:

- the special offer remains persisted if create or update already succeeded
- no active composite-image binding is created
- no fallback image is generated
- no frontend-composed image becomes truth
- no placeholder image becomes truth
- no raw storage URL or raw collage becomes truth
- failure status may be exposed only through backend-owned execution state and
  future text authority

### Regeneration Failure

If regeneration fails:

- the previous active composite-image binding remains active
- the failed output must not replace the active binding
- partial media must not become active output truth
- old media assets and storage objects must not be synchronously deleted by the
  regenerate request
- failure status may be exposed only through backend-owned execution state and
  future text authority

### Stale Image After Offer Update

If offer state changes after a successful image generation:

- the offer update may mark the current image as requiring generation or
  regeneration
- the existing active image may remain visible as stale backend-owned output
  until explicit generation or regeneration succeeds, if future execution
  response law chooses to expose that state
- the update action must not automatically regenerate
- frontend must not decide current/stale status

### Confirmation Missing

If overwrite confirmation is missing for an action that would replace an active
image binding:

- backend execution must reject the action before generation starts
- no generation attempt may be created
- no worker job may be scheduled
- no media asset may be created for that replacement attempt
- no active binding may change
- no lifecycle or storage cleanup may be requested from that rejected action

### Invalid Teacher, Course, Or Price Input

If submitted teacher, course, or price input is invalid:

- backend execution must reject the action before mutation
- no partial offer state may be persisted
- no image generation may start
- no active image binding may change
- no commerce activation may occur
- no frontend fallback authority may be created

Raw internal errors, exception strings, framework messages, SQL errors, storage
errors, provider identifiers, stack traces, route names, and worker internals
must not become canonical user-facing truth.

## 7. Confirmation Model

Overwrite confirmation is required for regenerate image.

Overwrite confirmation is required for any future action that would replace an
active composite-image binding.

Overwrite confirmation is not required for:

- create offer when it does not replace an active image binding
- update offer when it preserves the active image binding
- generate image when no active image binding exists
- read current offer execution-visible state

Overwrite confirmation must be enforced by the backend execution layer before
generation work starts.

Frontend confirmation UI may collect teacher intent only. Frontend confirmation
state is not overwrite authority until backend execution validates it.

Exact warning copy belongs to `system_text_authority_contract.md` and
`backend_text_catalog_contract.md`, not this contract.

Any exact future user-facing warning, status, validation, or failure copy must
be Swedish and must flow through text authority.

This contract does not hardcode exact warning copy.

## 8. Frontend Execution Boundary

Frontend may:

- submit teacher intent to future canonical backend execution surfaces
- trigger backend create, update, generate, and regenerate actions when those
  actions are available through accepted implementation
- submit overwrite-confirmation intent when backend execution requires it
- render backend-owned offer state
- render backend-composed governed media output
- render backend/catalog-owned Swedish product text

Frontend must not own:

- local selected-course authority
- local price authority
- local teacher ownership authority
- local image-current authority
- local generation status authority
- local overwrite truth
- local media authority
- local commerce authority
- local text authority

Frontend must not:

- compose special-offer images
- crop, merge, grid, or draw source images as canonical output
- render price onto the image as canonical output
- call OpenAI or any image model for selection, layout, composition, or
  fallback truth
- generate fallback images
- use placeholder images as canonical truth
- repair failed generation
- repair stale status
- construct storage URLs
- resolve media from buckets, object paths, signed URLs, public URLs, filenames,
  preview files, or local files
- treat route state, local form state, cache state, optimistic state, or
  browser storage as persisted special-offer truth

Frontend validation may support user guidance only. Backend validation remains
the authority boundary.

## 9. Domain Alignment

This contract does not duplicate special-offer domain authority.

`special_offer_domain_contract.md` owns:

- special-offer identity
- teacher owner
- selected course set
- selected course count `1..5`
- duplicate-course rejection
- same-teacher MVP invariant
- offer price
- offer existence independent of image generation
- domain-owned current/needs-image semantics

This contract does not duplicate composite-image authority.

`special_offer_composite_image_contract.md` owns:

- generated composite-image output
- active special-offer composite-image binding
- persisted selected source inputs
- overwrite semantics
- generation attempt authority
- governed-media output relation
- source image eligibility
- generated-output failure preservation

This contract does not duplicate media lifecycle or storage authority.

Existing media and storage contracts own:

- media identity
- media readiness
- media runtime projection
- backend media read composition
- media orphan verification
- asset deletion
- physical storage cleanup

This contract does not duplicate commerce authority.

Course monetization and commerce contracts own:

- course pricing
- bundle pricing
- bundle composition
- sellability
- checkout
- Stripe mapping
- orders
- payments
- webhook settlement
- course entitlement fulfillment
- membership state

Special-offer price remains domain truth. The generated image may represent
price, but price must never be derived from image pixels, image metadata,
frontend overlay, storage object metadata, or generated-output text.

The composite image remains derivative output. It must never become selected
course truth, teacher ownership truth, price truth, sellability truth, checkout
truth, order truth, payment truth, or entitlement truth.

## 10. Forbidden Patterns

The following patterns are contract-invalid:

- automatic image generation
- automatic image regeneration
- read-time image generation
- read-time image regeneration
- render-time image generation
- render-time image regeneration
- page-load image generation
- update-triggered image generation
- update-triggered image regeneration
- course-edit-triggered image generation
- cover-edit-triggered image generation
- checkout-triggered image generation
- worker-sweep generation that was not created by explicit backend action
- hidden conversion of generate into regenerate
- replacing an active image binding without overwrite confirmation
- overwrite confirmation enforced only by frontend
- create offer that implicitly generates an image
- update offer that implicitly regenerates an image
- read state that mutates offer, image, media, storage, commerce, or status
  truth
- frontend composition
- frontend price overlay as canonical image truth
- frontend image-model calls for selection, layout, composition, or fallback
  truth
- frontend fallback image behavior
- frontend fallback offer-state behavior
- frontend status repair
- frontend overwrite truth
- frontend media resolution
- frontend URL construction
- raw storage truth
- raw URL truth
- signed URL truth
- public URL truth
- preview-file truth
- local-file truth
- direct `app.media_assets` control as special-offer placement truth
- `app.media_assets` alone as active image binding truth
- direct `app.runtime_media` writes
- media lifecycle deletion inside a regenerate request
- storage object deletion inside a regenerate request
- commerce activation from create, update, generate, regenerate, or read
- sellability inference from offer existence or generated image presence
- checkout initiation from image generation success
- route names treated as canonical before accepted execution review
- mounted paths treated as canonical from this contract alone
- request JSON treated as final from this contract alone
- response JSON treated as final from this contract alone
- baseline substrate inferred from this contract without accepted baseline work

## 11. Future Work Required Before Implementation

Runtime implementation remains blocked until future accepted work defines all
of the following:

- baseline substrate for special-offer domain relations
- baseline substrate for composite-image output/source relations
- accepted media purpose, readiness, runtime projection, and read-composition
  changes required by generated composite output
- determined-task tree with dependency audit
- exact backend execution owners for create, update, generate, regenerate, and
  read state
- transaction boundaries for offer state persistence and image binding
- asynchronous job model or synchronous completion model for generation
- backend generation owner and worker alignment
- media worker/read-composition alignment for generated image output
- media lifecycle reference-surface audit for special-offer output relations
- storage lifecycle cleanup alignment after reference removal
- final route names and transport contracts
- final request and response shapes
- backend-owned failure/status model
- Swedish text catalog entries for create, update, generate, regenerate,
  overwrite confirmation, status, validation, and failure copy
- frontend trigger-only and render-only alignment gates
- future commerce integration audit if special offers become sellable,
  checkoutable, order-backed, payment-backed, or entitlement-granting

No runtime work may proceed from this contract alone.

If future implementation review discovers that required substrate is missing,
runtime implementation must stop until accepted baseline work creates the
required substrate and updates baseline authority.

If future implementation review discovers authority conflict with special-offer
domain, composite-image, media, storage, text, commerce, course-cover, or bundle
authority, implementation must stop until contract authority is reconciled.

## 12. Final Assertion

This contract is the canonical execution-layer coordinator for the
teacher-facing `Skapa erbjudande` special-offer flow.

The only valid future execution layering is:

```text
teacher intent
-> backend execution surface
-> special-offer domain validation/persistence
-> optional explicit backend image generation/regeneration
-> composite-image output/source authority
-> governed media identity and lifecycle
-> runtime media projection
-> backend read composition
-> frontend trigger-only and render-only behavior
```

Create and update persist backend-validated special-offer state only.

Generate and regenerate are explicit.

Regenerate and any active-image replacement are overwrite-confirmation-gated.

Previous active image output remains active when regeneration fails.

Read state is side-effect-free.

Frontend is trigger-only and render-only.

No implementation may proceed until future accepted substrate, execution
transport, backend owner, text, media-alignment, frontend-alignment,
commerce-integration, and determined-task authorities required by this contract
are accepted.
