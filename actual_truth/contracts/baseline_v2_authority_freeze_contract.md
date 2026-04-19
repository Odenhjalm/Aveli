# BASELINE V2 AUTHORITY FREEZE CONTRACT

## STATUS

ACCEPTED BASELINE V2 PLANNING AUTHORITY.

Concrete database baseline authority is now owned by
`actual_truth/AVELI_DATABASE_BASELINE_MANIFEST.md` and
`backend/supabase/baseline_v2_slots.lock.json`.

This contract was created by the approved Batch 1 authority-freeze execution for
Baseline V2. It remains the controlling Baseline V2 planning authority, but it
does not supersede the canonical V2 lock or database baseline manifest.

This contract cross-references and must be reconciled with:

- `actual_truth/Aveli_System_Decisions.md`
- `actual_truth/aveli_system_manifest.json`
- `actual_truth/AVELI_DATABASE_BASELINE_MANIFEST.md`
- `actual_truth/NEW_BASELINE_DESIGN_PLAN.md`
- `actual_truth/contracts/SYSTEM_LAWS.md`
- `actual_truth/contracts/livekit_runtime_contract.md`
- `actual_truth/contracts/production_deployment_contract.md`
- `actual_truth/contracts/profile_community_media_contract.md`
- `actual_truth/contracts/home_audio_aggregation_contract.md`
- `actual_truth/contracts/home_audio_runtime_contract.md`
- `actual_truth/contracts/media_unified_authority_contract.md`
- `actual_truth/contracts/commerce_membership_contract.md`
- `actual_truth/contracts/embedded_checkout_activation_decision.md`
- `actual_truth/contracts/aveli_embedded_checkout_spec.md`
- `README.md`
- `backend/README.md`

## 1. PURPOSE AND CONTROL

This contract freezes the approved Baseline V2 authority model before any
implementation planning, SQL generation, baseline slot materialization, runtime
code editing, database mutation, or deployment execution begins.

Baseline V2 is a clean conceptual rebaseline. The implementation target is full
cutover, not append-only extension of the current authority model.

Concrete Baseline V2 replay ownership is app-owned schema only. Hosted Supabase
owns the physical `auth` and `storage` schemas; Baseline V2 verifies their
required interfaces but does not replay-create them. Local development may
provision locked minimal compatibility substrate before app-owned slot replay.

This contract controls Baseline V2 planning only after acceptance. Until all
later authority-freeze alignment batches are reviewed and accepted, existing
repo files may still contain stale or conflicting statements. Those statements
do not override the approved input truth frozen here.

## 2. APPROVED BASELINE V2 INPUT TRUTH

The following decisions are frozen as approved Baseline V2 input truth:

- Baseline V2 is a clean conceptual rebaseline.
- The implementation target is full cutover.
- `welcome_pending` is canonical onboarding state.
- `home_player_course_links` is canonical source truth for course-linked home
  audio inclusion.
- Backend composition is read authority for course-linked home audio output.
- `runtime_media` remains read-only projection authority where in scope, but is
  not the source table for `home_player_course_links`.
- Profile/community media is canonical Baseline V2 scope.
- `profile_media_placements` owns authored-placement truth.
- `profiles` remains projection-only.
- `orders`, `payments`, and `memberships` are the canonical commerce trail.
- `subscription` may remain provider/order modality, but is not Aveli domain
  authority.
- Service/session/Connect-like order fields are inert unless explicitly
  activated by a later accepted authority.
- LiveKit runtime is paused/inert.
- `actual_truth/contracts/livekit_runtime_contract.md` remains the accepted
  tracked authority for the LiveKit runtime surface.
- Production deployment authority must be updated before implementation
  planning.
- Runtime code, baseline slots, lockfiles, SQL, database state, and runtime
  state remain out of scope for authority-freeze Batch 1.
- User-facing product text must be Swedish.
- Generated operator prompts must be copy-paste-ready English.

## 3. SUPERSESSION RULE

After this contract is accepted, stale Baseline V2 planning authority must lose
control in favor of this contract.

`actual_truth/NEW_BASELINE_DESIGN_PLAN.md` becomes historical comparison input
only for Baseline V2. It must not control V2 implementation planning after the
freeze is accepted. In particular, any statement in that file that treats
profile/community media as non-core or above Baseline V2 scope is superseded.

Any authority statement that makes `runtime_media` the source table for
`home_player_course_links` is superseded for Baseline V2. `runtime_media`
remains read-only projection authority where in scope, but source truth for
course-linked home audio inclusion is `home_player_course_links`.

Any authority statement that treats `subscription` as Aveli domain authority is
superseded for Baseline V2. `subscription` may remain a provider/order modality
only.

Any authority statement that treats service/session/Connect-like order fields as
active Baseline V2 commerce scope is superseded unless later explicitly
activated by accepted authority.

Any authority statement that treats LiveKit as active runtime scope is
superseded by `actual_truth/contracts/livekit_runtime_contract.md`.

## 4. AUTHORITY MATRIX

Baseline V2 authority is separated into five classes:

| Class | Meaning | Rule |
| --- | --- | --- |
| Canonical write authority | Tables or surfaces that own durable domain truth | May create or change domain truth only within accepted authority |
| Projection and read authority | Derived views, read models, or backend composition outputs | May expose or derive truth; must not become source truth |
| Inert support structure | Retained support shape with no active domain authority | May exist only as support until activated by later authority |
| Excluded legacy structure | Retired or non-foundational authority | Must not control Baseline V2 |
| Runtime integration surface | External/provider/runtime boundary | May correlate or transport state; must not redefine Aveli domain truth |

No file, route, worker, UI surface, provider event, or legacy document may move a
surface between these classes without later accepted authority.

## 5. CANONICAL WRITE AUTHORITY

Canonical write authority for Baseline V2 includes:

- Identity and auth-subject authority:
  - `auth.users` as external provider-owned identity/credential substrate only.
  - `app.auth_subjects` as Aveli auth subject, onboarding state, role, and
    app-entry subject authority.
  - `app.refresh_tokens`, `app.auth_events`, and `app.admin_bootstrap_state`
    for their accepted auth/operator purposes.
- Onboarding and app-entry authority:
  - `app.auth_subjects.onboarding_state`.
  - `welcome_pending` as the canonical post-create-profile onboarding state.
  - `app.memberships` as canonical app-entry membership authority.
- Course and content authority:
  - `app.courses`.
  - `app.course_public_content`.
  - `app.lessons`.
  - `app.lesson_contents`.
  - `app.lesson_media`.
  - `app.course_enrollments`.
  - `app.course_bundles`.
  - `app.course_bundle_courses`.
- Media source authority:
  - `app.media_assets` for media identity and lifecycle.
  - `app.lesson_media` for lesson media placement/inclusion.
  - `app.home_player_uploads` for direct home-player upload source truth.
  - `app.home_player_course_links` for course-linked home audio inclusion
    source truth.
  - `app.profile_media_placements` for profile/community authored-placement
    truth.
- Commerce and membership authority:
  - `app.orders`.
  - `app.payments`.
  - `app.memberships`.
  - `app.referral_codes`.

## 6. PROJECTION AND READ AUTHORITY

Projection and read authority for Baseline V2 includes:

- `app.profiles` as projection-only profile persistence.
- Course discovery, course detail, lesson structure, and lesson content read
  projections.
- `app.runtime_media` as read-only runtime media projection where in scope.
- Backend read composition for final API-facing media output.
- `GET /entry-state` as routing/read composition from canonical onboarding and
  membership truth.
- Profile/avatar read composition from profile projection plus media authority.
- Home audio read composition from direct upload sources, course-link sources,
  canonical course/lesson access, media readiness, and backend composition.

Projection and read authority must not create independent domain truth. Read
composition may expose resolved output, but it must not replace canonical source
tables.

## 7. INERT SUPPORT STRUCTURE

The following structures are inert or support-only unless later explicitly
activated by accepted authority:

- `app.livekit_webhook_jobs`, governed by
  `actual_truth/contracts/livekit_runtime_contract.md`.
- LiveKit webhook route, handler, queue, worker, retry, and processing concepts.
- `app.payment_events` as webhook idempotency/logging support.
- `app.billing_logs` as support/observability structure.
- `app.stripe_customers` as provider-correlation support substrate.
- Stripe checkout/session/subscription/payment identifiers as provider
  correlation, not Aveli domain truth.
- Service/session/Connect-like order fields, including `service_id`,
  `session_id`, `session_slot_id`, and `connected_account_id`.

Inert support structure may be carried to preserve shape or correlation, but it
must not be treated as active Baseline V2 domain authority.

## 8. EXCLUDED LEGACY STRUCTURE

The following are excluded from the Baseline V2 foundation unless later
explicitly activated by accepted authority:

- `subscription` as Aveli domain authority.
- Legacy subscription tables or transaction tables that have been removed from
  accepted baseline authority.
- Service/session/Connect commerce as active foundational scope.
- `invite` as membership source vocabulary.
- Frontend checkout success, provider session state, provider subscription
  state, or provider payment state as standalone Aveli authority.
- Direct writes to `runtime_media`.
- Direct storage delivery or client-side fallback as media truth.
- Active LiveKit runtime behavior.
- Any legacy migration, historical baseline plan, or README/operator text that
  conflicts with this contract.

## 9. RUNTIME INTEGRATION SURFACE

Runtime integrations are boundary surfaces, not independent Aveli domain truth.

Stripe may provide checkout, subscription-mode provider behavior, payment
events, and provider identifiers. Aveli commerce truth remains in `orders`,
`payments`, and `memberships`.

LiveKit is paused/inert. The accepted authority is
`actual_truth/contracts/livekit_runtime_contract.md`. No LiveKit worker startup,
webhook ingestion, enqueueing, queue processing, retry, deletion, or domain
mutation is authorized by Baseline V2 authority freeze.

Supabase Auth and Storage are external-compatible substrates. They do not own
Aveli onboarding, profile, membership, course, media, or app-entry truth.
Hosted Supabase physical `auth` and `storage` schemas are provider-owned and
must not be recreated by Baseline V2 replay. The V2 lock owns only their
required interface expectations.

Backend composition may resolve and present read output, but it must remain
subordinate to canonical write authority and projection/read authority.

## 10. REQUIRED CONTRACT ALIGNMENTS

Later authority-freeze alignment must reconcile the following files with this
contract before implementation planning begins:

- `actual_truth/Aveli_System_Decisions.md`
- `actual_truth/aveli_system_manifest.json`
- `actual_truth/AVELI_DATABASE_BASELINE_MANIFEST.md`
- `actual_truth/NEW_BASELINE_DESIGN_PLAN.md`
- `actual_truth/contracts/SYSTEM_LAWS.md`
- `actual_truth/contracts/production_deployment_contract.md`
- `actual_truth/contracts/profile_community_media_contract.md`
- `actual_truth/contracts/home_audio_aggregation_contract.md`
- `actual_truth/contracts/home_audio_runtime_contract.md`
- `actual_truth/contracts/media_unified_authority_contract.md`
- `actual_truth/contracts/commerce_membership_contract.md`
- `actual_truth/contracts/embedded_checkout_activation_decision.md`
- `actual_truth/contracts/aveli_embedded_checkout_spec.md`
- `README.md`
- `backend/README.md`

The LiveKit contract remains accepted unchanged authority unless a later
explicit LiveKit activation contract is approved.

## 11. CONCEPTUAL BASELINE V2 SLOT GROUPS

Baseline V2 must be explainable through these conceptual slot groups:

1. Identity, Auth Subject, and Operator Bootstrap.
2. Onboarding State and App Entry Authority.
3. Profile Projection and Profile/Community Media.
4. Course and Public Content Core.
5. Lesson Content, Access, Enrollment, and Drip.
6. Unified Media Identity, Placement, Inclusion, and Runtime Reads.
7. Home Audio Source Truth and Backend Composition.
8. Commerce, Orders, Payments, and Membership.
9. Referral Identity, Redemption, and Membership Grants.
10. Runtime Support and Paused/Inert Integrations.
11. Read Projections and API Enforcement.
12. Replay, Cutover Proof, Locking, and Deployment Gate.

These are conceptual authority groups only. They are not SQL slot definitions
and do not authorize baseline slot creation.

## 12. PRODUCTION DEPLOYMENT GATE

`actual_truth/contracts/production_deployment_contract.md` must be updated
before implementation planning begins.

The production deployment gate must align with:

- Baseline V2 clean rebaseline and full cutover target.
- Accepted baseline scope and later V2 authority materialization.
- `welcome_pending` onboarding authority.
- Profile/community media as canonical Baseline V2 scope.
- `home_player_course_links` source truth and backend composition read
  authority.
- Orders/payments/memberships as canonical commerce trail.
- `subscription` as provider/order modality only.
- Service/session/Connect-like order fields as inert unless activated later.
- LiveKit paused/inert authority.
- Swedish user-facing product text.
- English copy-paste-ready generated operator prompts.

No production deployment planning is valid while the production deployment
contract conflicts with this authority freeze.

## 13. SWEDISH COPY AND ENGLISH PROMPT LAW

User-facing product text must be Swedish.

Generated operator prompts must be copy-paste-ready English.

Known runtime copy drift may be recorded by authority docs, but runtime code
correction is not part of this contract and is not authorized by Batch 1.

## 14. NON-IMPLEMENTATION BOUNDARY

This contract does not authorize:

- Runtime implementation.
- Runtime code edits.
- SQL generation.
- Baseline slot generation.
- Baseline lockfile edits.
- Database mutation.
- Runtime mutation.
- DAG planning or artifact creation.
- Tasktree planning or artifact creation.
- Production deployment.
- LiveKit activation.
- Stripe or provider behavior changes.
- Frontend implementation.

This contract defines authority freeze only.

## 15. ACCEPTANCE GATES

Implementation planning may not begin until all of the following are true:

- This contract is reviewed and accepted.
- Stale Baseline V2 planning authority is explicitly superseded.
- Decisions, manifest, baseline manifest, system laws, domain contracts, and
  README/operator docs are aligned to this contract.
- Production deployment authority is updated and reviewed.
- LiveKit remains governed by the accepted paused/inert contract.
- Orders fields are classified as canonical, inert, or excluded.
- Profile/community media is frozen as canonical Baseline V2 scope.
- Home-player course-linked audio authority is frozen as source truth plus
  backend read composition.
- Swedish user-facing copy compliance is documented as a gate.
- Generated operator prompt compliance is documented as a gate.
- Database state, replay, deploy, and runtime state remain untouched during
  authority-freeze alignment unless a later task
  explicitly authorizes a different scope.
