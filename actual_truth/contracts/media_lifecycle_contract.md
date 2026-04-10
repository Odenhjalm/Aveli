# MEDIA LIFECYCLE CONTRACT

## STATUS

ACTIVE

This contract defines the canonical media lifecycle / cleanup authority layer.
It operates under `SYSTEM_LAWS.md`, `media_pipeline_contract.md`, and the lesson-delete boundary defined in `course_lesson_editor_contract.md`.

This contract does not redefine ingest, placement, runtime projection, backend read composition, or lesson delete authority.

## 1. AUTHORITY

Media lifecycle is the only authority allowed to delete `app.media_assets`.

Media lifecycle is separate from:

- lesson delete
- lesson-media placement delete
- lesson-media placement reorder
- media ingest
- runtime projection
- backend read composition

Layer ownership:

- `app.media_assets` remains canonical media identity.
- `app.lesson_media` remains authored placement.
- `app.runtime_media` remains runtime truth for governed media state and resolution eligibility.
- media lifecycle owns orphan verification and safe cleanup after canonical references are removed.

Media lifecycle must not create lesson-media placements, delete lesson-owned rows, reorder placements, or write runtime truth.

## 2. ORPHAN DEFINITION

A media asset is an orphan only when all of the following are true:

- the asset has zero referencing `app.lesson_media` rows
- the asset is not referenced by any other canonical media usage surface
- every canonical reference surface in scope can be checked deterministically
- no reference ambiguity exists

Canonical media usage surfaces include any active contract-governed surface that references `app.media_assets`, including but not limited to:

- lesson-media placement references through `app.lesson_media.media_asset_id`
- course-cover references through `app.courses.cover_media_id`
- home-player references where the canonical home-player substrate references `app.media_assets`
- profile/community media references where an active contract defines them as canonical
- future canonical media usage surfaces declared in `actual_truth/contracts/`

If a possible canonical reference surface cannot be checked, orphan status is unknown and cleanup must not delete the asset.

Absence from `app.runtime_media` is not sufficient orphan proof.
Storage-object state is not sufficient orphan proof.
Frontend visibility is not sufficient orphan proof.
Control-plane classification is not sufficient orphan proof unless it is backed by canonical reference checks.

## 3. CLEANUP RULES

Media lifecycle may delete an `app.media_assets` row only after orphan verification passes.

Media lifecycle must not delete `app.media_assets` rows that are still referenced by any canonical usage surface.

Media lifecycle may delete storage objects only after the corresponding asset deletion is confirmed safe.

Storage cleanup must be treated as physical cleanup of dependency objects, not canonical media authority.

If storage cleanup fails after asset deletion, the cleanup result must remain auditable and retryable.

Media lifecycle must not delete storage objects first as a substitute for orphan verification.

Media lifecycle must not use raw storage paths, signed URLs, download URLs, preview URLs, playback URLs, or frontend fields as orphan authority.

## 4. EXECUTION MODEL

Cleanup is asynchronous.

Cleanup may be triggered by:

- an explicit media lifecycle cleanup job
- periodic garbage collection
- a post-placement-delete signal
- a post-lesson-delete signal
- another canonical post-reference-removal signal declared by contract

A signal is not cleanup authority by itself.
A signal may only request lifecycle evaluation.

Media lifecycle execution must be idempotent.
Repeated execution over the same asset must not produce conflicting canonical state.

Media lifecycle execution must re-check orphan status at the deletion boundary.

## 5. SAFETY GUARANTEES

No deletion is allowed if reference ambiguity exists.

Media lifecycle must double-check references before deleting `app.media_assets`.

Media lifecycle must be safe under concurrent placement creation, placement deletion, lesson deletion, home-player mutation, profile/community media mutation, and future canonical media usage mutation.

Media lifecycle must fail closed when:

- a reference check cannot run
- a canonical usage surface is unknown
- reference data is inconsistent
- storage state and canonical reference state disagree
- the asset is referenced by a canonical usage surface

Media lifecycle must not turn cleanup failure into frontend fallback behavior.

## 6. SEPARATION CONSTRAINTS

Lesson delete must not create, update, or delete `app.media_assets`.

Placement delete must not create, update, or delete `app.media_assets`.

Runtime projection must not trigger cleanup and must not delete `app.media_assets`.

`app.runtime_media` must not be used as the sole source for orphan status.

Backend read composition must not trigger cleanup.

Frontend rendering must not trigger cleanup and must not decide orphan status.

Control-plane observability may classify lifecycle state, but it must not delete assets unless routed through the media lifecycle authority.

Worker execution may transform media and perform canonical state transitions only under its existing worker authority. Worker authority does not bypass this lifecycle cleanup contract for asset deletion.

## 7. OBSERVABILITY

Media lifecycle operations must be traceable.

Every cleanup decision must be auditable after execution.

Audit evidence for a cleanup decision must include:

- target `media_asset_id`
- trigger source
- reference checks performed
- orphan status result
- deletion decision
- asset deletion result
- storage cleanup result, when storage cleanup runs
- failure reason when cleanup is skipped or fails

Skipped cleanup is a valid lifecycle result when orphan status is false, unknown, or ambiguous.

Lifecycle observability must not introduce new media authority, alternate runtime truth, or frontend representation authority.

## 8. CONTRACT COMPATIBILITY

This contract preserves the media pipeline split:

- ingest may create `app.media_assets`
- placement may create or delete `app.lesson_media`
- runtime projection may expose governed runtime truth
- media lifecycle alone may delete orphan `app.media_assets`

This contract preserves the lesson delete split:

- lesson delete may remove lesson-owned `app.lesson_contents`, `app.lesson_media`, and `app.lessons` rows
- lesson delete success does not mean asset cleanup has completed
- asset cleanup after lesson delete remains media lifecycle authority

This contract preserves `SYSTEM_LAWS.md`:

- no alternate media identity authority exists
- no alternate runtime-media authority exists
- no frontend media construction or cleanup authority exists
- storage remains dependency detail, not business truth
