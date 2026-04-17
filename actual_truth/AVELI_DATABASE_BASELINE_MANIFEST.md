# AVELI Database Baseline Manifest

STATUS: CANONICAL

This manifest is the canonical database baseline authority for Aveli.

It defines the intended database truth. Observed database state is evidence
only. If observed database state differs from this manifest, this manifest wins
and the system is blocked until the baseline is repaired through the execution
policy in this file.

## 1. Purpose

This manifest exists to make database authority deterministic.

It is sufficient to:

- reconstruct database intent from canonical baseline authority
- classify every known database relation by write safety and domain role
- define enum authority and critical invariants
- detect and block drift between baseline intent and observed database state
- prevent runtime, projection, or substrate objects from becoming business truth

This manifest overrides observed DB state.

Observed DB state may identify violations, but it must not redefine canonical
schema intent, table ownership, enum values, domain authority, or write safety.

## 2. Baseline Authority Model

Canonical schema authority is:

- `backend/supabase/baseline_slots/`
- `backend/supabase/baseline_slots.lock.json`

These are the only schema source for database baseline truth.

Rules:

- Baseline slots define accepted schema objects and append-only evolution.
- The lock file defines the accepted baseline slot set and slot hashes.
- `backend/supabase/migrations/` is not local baseline authority.
- Legacy migrations, observed runtime schema, local DB drift, remote DB drift,
  tests, generated docs, and implementation code do not redefine baseline truth.
- A clean replay of locked baseline slots is the only valid proof of baseline
  correctness.
- Any schema change requires a new append-only baseline slot and a lock update.
- Accepted baseline slots must not be edited in place.

If clean baseline replay and this manifest disagree:

- classification: `MANIFEST_BASELINE_DRIFT`
- result: `SYSTEM BLOCKED`

If observed DB state and this manifest disagree:

- classification: `OBSERVED_DB_DRIFT`
- result: `SYSTEM BLOCKED`

## 2A. Baseline V2 Authority Freeze Overlay

Baseline V2 planning is controlled by
`actual_truth/contracts/baseline_v2_authority_freeze_contract.md`.

Baseline V2 is a clean conceptual rebaseline with full cutover as the
implementation target. The current accepted baseline slot evidence remains
`backend/supabase/baseline_slots/` plus
`backend/supabase/baseline_slots.lock.json`, currently accepted through slot
`0038`, unless later accepted V2 slot authority replaces that scope.

This overlay does not edit accepted slots in place and does not authorize SQL,
baseline slot generation, lockfile edits, runtime code edits, DB mutation, or
runtime mutation.

Baseline V2 authority interpretation:

- `welcome_pending` is accepted baseline onboarding truth.
- `home_player_course_links` is source truth for course-linked home audio
  inclusion; backend composition is read authority.
- `runtime_media` is read-only projection authority where in scope, not the
  source table for `home_player_course_links`.
- Profile/community media is canonical Baseline V2 scope.
- `profile_media_placements` owns profile/community authored-placement truth.
- `profiles` remains projection-only.
- `orders`, `payments`, and `memberships` are the canonical commerce trail.
- `subscription` may remain provider/order modality, but not Aveli domain
  authority.
- Service/session/Connect-like order fields are inert unless later activated by
  explicit accepted authority.
- LiveKit remains paused/inert under
  `actual_truth/contracts/livekit_runtime_contract.md`.

## 3. Domain Classification

Every relation is classified into exactly one baseline authority class:

- `CANONICAL`: source truth or canonical authority substrate owned by Aveli
- `RUNTIME`: operational support state, queue state, audit/log/idempotency state,
  or runtime-only support
- `PROJECTION`: derived/read-composed surface, view, or non-authoritative
  projection table
- `SUBSTRATE`: external-compatible physical/auth/storage substrate required for
  local replay or integration, but not Aveli business truth

### 3.1 CANONICAL

The following tables are allowed canonical write targets only through their
owning backend/operator authority:

| Relation                       | Canonical role                                                                           | Write authority                                                                      |
| ------------------------------ | ---------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| `app.auth_subjects`            | application subject authority: onboarding state, role, admin state                       | auth/onboarding/admin backend authority                                              |
| `app.admin_bootstrap_state`    | first-admin operator bootstrap state                                                     | operator-controlled bootstrap only                                                   |
| `app.refresh_tokens`           | refresh-token persistence, rotation lineage, revocation state                            | backend auth authority                                                               |
| `app.auth_events`              | canonical auth/onboarding audit-event persistence                                        | backend/operator mutation surfaces only                                              |
| `app.courses`                  | course identity, structure, pricing fields, grouping, drip configuration, cover identity | studio/course backend authority                                                      |
| `app.course_public_content`    | sibling public course content such as `short_description`                                | dedicated public-content backend authority                                           |
| `app.lessons`                  | lesson identity and structure                                                            | studio lesson-structure backend authority                                            |
| `app.lesson_contents`          | lesson markdown content                                                                  | studio lesson-content backend authority                                              |
| `app.lesson_media`             | authored lesson-media placement identity and ordering                                    | media placement backend authority                                                    |
| `app.media_assets`             | sole governed media identity and lifecycle source                                        | media ingest plus canonical worker authority                                         |
| `app.course_enrollments`       | protected course-content access state                                                    | `app.canonical_create_course_enrollment(...)` and canonical backend fulfillment only |
| `app.memberships`              | global current membership state                                                          | commerce/referral membership backend authority only                                  |
| `app.orders`                   | purchase identity and purchase lifecycle                                                 | commerce backend authority                                                           |
| `app.payments`                 | payment-provider settlement tied to orders                                               | Stripe webhook/backend settlement authority                                          |
| `app.course_bundles`           | canonical bundle identity, ownership, composition pricing surface                        | teacher bundle backend authority                                                     |
| `app.course_bundle_courses`    | canonical bundle composition                                                             | teacher bundle backend authority                                                     |
| `app.home_player_uploads`      | direct home-player upload inclusion source                                               | home-audio/media backend authority                                                   |
| `app.home_player_course_links` | course-linked home-audio inclusion source                                                | home-audio/backend authority                                                         |
| `app.profile_media_placements` | profile/community media authored-placement source                                        | profile/community media backend authority                                            |
| `app.referral_codes`           | referral identity, recipient binding, duration, redemption lifecycle                     | referral backend authority                                                           |

Canonical tables are not automatically public write targets. Canonical means the
table owns source truth for its domain. Writes must still use the canonical
backend/operator path for that domain.

### 3.2 RUNTIME

Runtime tables exist for operational behavior, support, queueing,
observability, idempotency, or external integration support. They must not
become business authority.

| Relation                   | Runtime role                                                 | State          | Constraints                                                                                      |
| -------------------------- | ------------------------------------------------------------ | -------------- | ------------------------------------------------------------------------------------------------ |
| `app.payment_events`       | Stripe webhook idempotency and webhook observability support | ACTIVE SUPPORT | append-only; not purchase, payment, membership, pricing, or access authority                     |
| `app.billing_logs`         | billing observability/logging support                        | ACTIVE SUPPORT | backend-only writes; no business authority                                                       |
| `app.stripe_customers`     | retained Stripe customer support substrate                   | ACTIVE SUPPORT | not purchase, pricing, ownership, sellability, membership, or access authority                   |
| `app.livekit_webhook_jobs` | inert LiveKit webhook queue structure                        | PAUSED         | no worker execution allowed; no canonical mutation allowed; queue exists only as inert structure |

`app.livekit_webhook_jobs` is intentionally retained as runtime structure but
is governed by the accepted paused/inert authority in
`actual_truth/contracts/livekit_runtime_contract.md`. It must remain paused
until a later active contract assigns its domain owner, mutation surface, worker
behavior, and replay requirements.

`app.livekit_webhook_jobs`

STATE: PAUSED

CONSTRAINTS:

- no worker execution allowed
- no canonical mutation allowed
- queue exists only as inert structure

### 3.3 PROJECTION

Projection relations are read/composition surfaces or non-authoritative
projection storage. Projection writes are forbidden unless a named contract
explicitly allows projection maintenance without transferring authority.

| Relation                       | Projection role                                         | Source authority                                                                            |
| ------------------------------ | ------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| `app.profiles`                 | projection-only current-user profile persistence        | derived from auth subject, identity, and media-owned avatar binding                         |
| `app.course_discovery_surface` | course discovery read surface                           | `app.courses`                                                                               |
| `app.lesson_structure_surface` | lesson structure read surface                           | `app.lessons`                                                                               |
| `app.course_detail_surface`    | composed course detail structure/public-content surface | `app.course_discovery_surface`, `app.course_public_content`, `app.lesson_structure_surface` |
| `app.lesson_content_surface`   | protected lesson content read projection                | `app.lessons`, `app.lesson_contents`, `app.lesson_media`, `app.course_enrollments`          |
| `app.runtime_media`            | canonical runtime media truth projection                | `app.media_assets` plus placement/inclusion source tables                                   |

Projection rules:

- Projections must not be written as source truth.
- Projection availability does not create authority.
- Projection output must remain downstream of canonical source tables.
- If projection state and source authority disagree, source authority wins.
- If projection dependencies are missing or ambiguous, runtime must fail closed.

### 3.4 SUBSTRATE

Substrate objects are required compatibility or physical persistence surfaces.
They are not Aveli business-domain truth.

| Relation          | Substrate role                                                    | Authority boundary                                                                                |
| ----------------- | ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `auth.users`      | identity, credential, email-verification, token subject substrate | identity/auth only; not onboarding, profile, membership, role, admin, media, or routing authority |
| `storage.buckets` | physical storage bucket substrate                                 | storage only; not media, access, or frontend delivery authority                                   |
| `storage.objects` | physical storage object substrate                                 | storage only; not media, access, or frontend delivery authority                                   |

Substrate rules:

- `auth.users.id` may be referenced by application `user_id` fields only as a
  soft external reference unless a later contract explicitly changes this.
  auth.users MUST NOT:
- define onboarding_state
- define role
- define membership
- define routing or access decisions
- `storage.objects` and `storage.buckets` are physical storage substrate only.
- Storage paths, signed URLs, object URLs, buckets, and object names must not
  become business truth or governed media truth.

## 4. Enum Authority

Enum authority includes both physical PostgreSQL enum types and logical enum
sets enforced by text/check constraints.

### 4.1 Logical Enum: `app.onboarding_state`

`app.onboarding_state` is the canonical logical enum for
`app.auth_subjects.onboarding_state`.

Allowed values, in canonical progression order:

1. `incomplete`
2. `welcome_pending`
3. `completed`

Constraints:

- DB must match exactly.
- Missing value -> BLOCK.
- Extra value -> BLOCK.
- Different spelling, casing, or alias -> BLOCK.
- `welcome_pending` is required baseline truth.

### 4.2 Physical Enum: `app.course_step`

Allowed values:

- `intro`
- `step1`
- `step2`
- `step3`

### 4.3 Physical Enum: `app.course_enrollment_source`

Allowed values:

- `purchase`
- `intro_enrollment`

### 4.4 Physical Enum: `app.media_type`

Allowed values:

- `audio`
- `image`
- `video`
- `document`

### 4.5 Physical Enum: `app.media_purpose`

Allowed values:

- `course_cover`
- `lesson_media`
- `home_player_audio`
- `profile_media`

### 4.6 Physical Enum: `app.media_state`

Allowed values:

- `pending_upload`
- `uploaded`
- `processing`
- `ready`
- `failed`

### 4.7 Physical Enum: `app.order_type`

Allowed values:

- `one_off`
- `subscription`
- `bundle`

`subscription` is an order/provider modality value only. It is not Aveli
domain authority.

### 4.8 Physical Enum: `app.order_status`

Allowed values:

- `pending`
- `requires_action`
- `processing`
- `paid`
- `canceled`
- `failed`
- `refunded`

### 4.9 Physical Enum: `app.payment_status`

Allowed values:

- `pending`
- `processing`
- `paid`
- `failed`
- `refunded`

### 4.10 Logical Enum: `app.membership_status`

Allowed values:

- `inactive`
- `active`
- `past_due`
- `canceled`
- `expired`

### 4.11 Logical Enum: `app.membership_source`

Allowed values:

- `purchase`
- `coupon`
- `referral`

### 4.12 Logical Enum: `app.auth_subject_role`

Allowed values:

- `learner`
- `teacher`

`app.auth_subjects.role_v2` is canonical role truth.
`app.auth_subjects.role` is a compatibility mirror and must equal `role_v2`.

## 5. Critical Invariants

### 5.1 Onboarding Flow

Canonical onboarding progression is:

```text
incomplete -> welcome_pending -> completed
```

Rules:

- No skipping is allowed.
- `incomplete -> completed` is forbidden.
- `completed -> incomplete` is forbidden.
- `completed -> welcome_pending` is forbidden.
- Create-profile moves `incomplete -> welcome_pending`.
- Welcome confirmation moves `welcome_pending -> completed`.
- Payment, checkout success, registration, login, profile writes, referral
  transport, referral redemption, and email verification must not complete
  onboarding.

### 5.2 Memberships

Rules:

- `app.memberships` is the single canonical current-state membership authority.
- Exactly one current authority row may exist per `user_id`.
- Multiple active membership authorities for one user are forbidden.
- Membership current state must not be derived by aggregating multiple rows.
- Membership source is required and must be explicit.
- Membership alone does not grant protected course content access.
- Membership state is an input to entry composition, not a replacement for
  onboarding or routing authority.

### 5.3 Media

Rules:

- `app.media_assets` is the sole governed media identity authority.
- `app.lesson_media` is authored lesson-media placement authority.
- `app.profile_media_placements` is profile/community media authored-placement
  authority.
- `app.home_player_uploads` and `app.home_player_course_links` are home-audio
  inclusion source tables.
- `app.runtime_media` is read-only runtime projection.
- No direct write path may target `app.runtime_media`.
- Storage paths, object names, signed URLs, object URLs, preview URLs, and
  download URLs are not canonical media truth.
- `ready` media requires canonical worker-owned readiness.
- Audio `ready` requires `playback_format = 'mp3'`.
- Direct audio `ready` writes are forbidden.

### 5.4 Enrollments

Rules:

- `app.course_enrollments` is the only protected course-content access source.
- Enrollment rows must be created through the canonical enrollment function
  only.
- Direct inserts into `app.course_enrollments` are forbidden.
- `drip_started_at` must equal `granted_at`.
- `current_unlock_position` must never decrease.
- Drip progression is worker-owned stored state.
- Membership, orders, payments, frontend state, and visibility rules must not
  replace course-enrollment authority.

### 5.5 Course And Lesson Structure

Rules:

- `app.courses` owns course identity and course structure.
- `app.lessons` owns lesson identity and lesson structure.
- `app.lesson_contents` owns lesson content only.
- Lesson structure must not contain `content_markdown`.
- Lesson content writes must not mutate lesson title, position, or course
  structure.
- `lesson_title` is canonical.
- Runtime lesson alias `title` is forbidden.
- Module-like runtime grouping is forbidden.

### 5.6 Commerce

Rules:

- `app.orders` owns purchase identity and purchase lifecycle.
- `app.payments` owns payment settlement tied to orders.
- `app.memberships` owns resulting current membership state only.
- Canonical order fields own purchase identity, user binding, applicable
  course/bundle binding, amount, currency, lifecycle status, purchase modality,
  and provider settlement correlation.
- `service_id`, `session_id`, `session_slot_id`, `connected_account_id`, and
  other service/session/Connect-like order fields are inert unless later
  activated by explicit accepted authority.
- Stripe checkout, payment, customer, and subscription identifiers are provider
  correlation only.
- Course/bundle purchases must create order-backed and payment-backed truth
  before course access fulfillment.
- Stripe is payment infrastructure only.
- Stripe runtime state, checkout success, session state, subscription state, and
  customer portal state are not authority by themselves.

### 5.7 Referral

Rules:

- `app.referral_codes` is the sole referral identity authority.
- Referral redemption is post-auth only.
- Referral grants membership through `app.memberships` with source `referral`.
- Referral must not create orders or payments.
- Referral must not complete onboarding.
- Referral link presence must not grant app entry.

### 5.8 Projections

Rules:

- `app.profiles` is projection-only and non-authoritative.
- `/profiles/me` must not become onboarding, routing, bootstrap, role, admin,
  membership, billing, or access authority.
- Views are read surfaces only.
- Projection state must fail closed when source authority is missing or
  ambiguous.

## 6. Forbidden Patterns

The following patterns are forbidden:

- projection writes as source truth
- direct writes to `app.runtime_media`
- frontend -> Supabase direct writes
- frontend database/storage/auth clients used as runtime authority
- multiple authority sources for the same concept
- fallback logic that grants authority when canonical truth is missing
- observed DB drift treated as canonical truth
- legacy migrations treated as baseline authority
- runtime schema introspection as a replacement for baseline truth
- direct storage playback or storage URL delivery as governed media authority
- profile-derived onboarding completion
- checkout-success-derived membership or onboarding authority
- membership-derived protected course-content access
- course-enrollment-derived global app entry
- Stripe-derived membership state without backend webhook confirmation
- direct `app.course_enrollments` insert outside the canonical function
- direct media `ready` transition outside the canonical worker function
- direct `app.media_assets` playback metadata writes outside canonical worker
  authority
- keeping a runtime queue active without an active contract owner

## 7. Drift Policy

Drift policy is fail-closed.

If DB != manifest:

```text
SYSTEM BLOCKED
```

Required handling:

1. classify the mismatch
2. stop downstream implementation
3. do not normalize around the mismatch
4. do not add fallback behavior
5. repair only through append-only baseline evolution
6. update `backend/supabase/baseline_slots.lock.json`
7. prove correctness by clean baseline replay

Drift classes:

| Drift class           | Meaning                                                              | Result                                         |
| --------------------- | -------------------------------------------------------------------- | ---------------------------------------------- |
| `OBSERVED_DB_DRIFT`   | observed DB differs from this manifest                               | `SYSTEM BLOCKED`                               |
| `BASELINE_SLOT_DRIFT` | baseline slots differ from this manifest                             | `SYSTEM BLOCKED`                               |
| `LOCK_DRIFT`          | lock file does not describe accepted baseline slots exactly          | `SYSTEM BLOCKED`                               |
| `CONTRACT_DRIFT`      | active contracts conflict with this manifest                         | `SYSTEM BLOCKED` until authority is reconciled |
| `PROJECTION_DRIFT`    | projection exposes or stores authority outside source truth          | `SYSTEM BLOCKED`                               |
| `RUNTIME_DRIFT`       | runtime/support table becomes authority or executes without contract | `SYSTEM BLOCKED`                               |
| `SUBSTRATE_DRIFT`     | auth/storage substrate becomes business truth                        | `SYSTEM BLOCKED`                               |

No downstream schema-dependent implementation, verification, worker repair, API
repair, frontend authority alignment, or baseline-dependent task may proceed
while a blocking drift is unresolved.

## 8. Known Violations

### V001: `app.auth_subjects.onboarding_state` Missing `welcome_pending`

STATE: ACCEPTED BASELINE REPAIR IN SLOT `0038`; RUNTIME CONFIRMATION REMAINS
SEPARATE

Expected manifest truth:

- `incomplete`
- `welcome_pending`
- `completed`

Accepted baseline evidence:

- slot `0038_auth_subjects_welcome_pending_onboarding_state.sql` repairs the
  accepted baseline constraint to include `welcome_pending`
- `backend/supabase/baseline_slots.lock.json` includes slot `0038`

Runtime interpretation:

- clean replay through the accepted slot set is required before downstream
  implementation planning
- observed DB state remains separate evidence and must not override accepted
  baseline authority

### V002: `app.livekit_webhook_jobs` Is Paused/Inert Runtime Structure

STATE: PAUSED RUNTIME CLASSIFICATION

Expected manifest truth:

- `app.livekit_webhook_jobs` exists only as inert runtime structure
- no worker execution allowed
- no canonical mutation allowed
- queue exists only as inert structure
- accepted authority is `actual_truth/contracts/livekit_runtime_contract.md`

Observed audit evidence:

- table exists in current DB
- table exists in baseline slot `0021`
- accepted paused/inert contract authority is tracked

Impact:

- queue execution would violate paused/inert runtime authority
- queue mutation would be non-canonical

Required outcome:

- keep table classified as `RUNTIME`
- keep state `PAUSED`
- do not execute workers
- do not mutate queue rows as canonical truth
- activate only after an active contract defines owner, lifecycle, worker
  behavior, mutation authority, and baseline replay requirements

## 9. Execution Policy

No schema change is allowed without:

1. an append-only baseline slot in `backend/supabase/baseline_slots/`
2. an updated `backend/supabase/baseline_slots.lock.json`
3. an explicit authority classification in this manifest or a manifest update
4. clean baseline replay proof
5. verification that observed DB schema matches this manifest

Forbidden execution paths:

- editing accepted baseline slots in place
- modifying observed DB to make tests pass without baseline authority
- generating migrations without baseline slot ownership
- treating production or local DB state as baseline truth
- changing runtime behavior to tolerate schema drift
- enabling workers against paused runtime tables

Valid execution order for any future schema repair:

1. identify manifest mismatch
2. classify drift
3. create append-only baseline slot
4. update lock file
5. replay baseline from scratch
6. verify schema, constraints, enums, functions, triggers, views, and policies
7. verify runtime readiness only after baseline replay is valid

## 10. Verification Gates

This manifest is valid only if all of the following hold:

- `actual_truth/AVELI_DATABASE_BASELINE_MANIFEST.md` exists
- `backend/supabase/baseline_slots/` exists
- `backend/supabase/baseline_slots.lock.json` exists
- `app.livekit_webhook_jobs` is explicitly marked `STATE: PAUSED`
- `app.onboarding_state` includes `welcome_pending`
- projection relations are not classified as canonical write authority
- substrate relations are not classified as Aveli business truth
- drift policy states `DB != manifest -> SYSTEM BLOCKED`
- schema changes require baseline slot plus lock update

If any verification gate fails:

```text
STOP
```
