# Application Domain Map Contract

## STATUS

DRAFT
NO-CODE DOMAIN-TOPOLOGY CONTRACT

## PURPOSE

This contract defines the canonical application domain map for the
identity-to-entry chain and adjacent authorities that touch it.

This contract separates:

- verified current-state domain topology
- target canonical domain topology
- domain drift that must be resolved

For this document, verified current-state topology means the repo state proven by
the active contracts in `actual_truth/contracts/`, canonical Baseline V2
authority in `backend/supabase/baseline_v2_slots/` and
`backend/supabase/baseline_v2_slots.lock.json`, and mounted backend/runtime repo
evidence only where needed to describe current drift. It is not a claim about
remote runtime state outside inspected repo evidence.

This contract does not merge current-state truth and target-state truth into one
undifferentiated map.

## AUTHORITY HIERARCHY

1. Locked target-truth decisions in
   `actual_truth/contracts/onboarding_target_truth_decision.md` define target
   canonical topology wherever they speak explicitly.
2. Active contracts in `actual_truth/contracts/` define active contract law for
   domain ownership unless a locked target decision overrides them for target
   topology.
3. `backend/supabase/baseline_v2_slots/` and
   `backend/supabase/baseline_v2_slots.lock.json` are the canonical app-owned
   schema authority and substrate-interface authority. They outrank legacy
   migrations for app-owned table existence, app-owned field existence,
   baseline-backed constraints, and required external substrate interfaces.
4. Mounted backend routes, backend auth logic, and backend services define the
   current runtime execution surfaces used to identify drift in repo current
   state.
5. Frontend assumptions, manifests, readiness docs, task trees, notes, and
   analysis artifacts are derived artifacts only and must not redefine domain
   ownership.
6. If these layers disagree, the disagreement must be classified as drift or
   unresolved ownership rather than normalized into implied truth.

## VERIFIED CURRENT-STATE DOMAIN MAP

- Authentication Identity: current contract and runtime repo evidence use
  `auth.users` as external provider-owned identity and credential substrate.
- Application Subject: current contract, baseline, and runtime repo evidence use
  `app.auth_subjects` for `onboarding_state` and `role`.
- Onboarding: current completion authority is `POST /auth/onboarding/complete`
  writing `app.auth_subjects.onboarding_state`, but current runtime completion
  is still coupled to profile `display_name` presence.
- Profile Projection: `/profiles/me` currently behaves as projection-only, and
  current runtime writes only `display_name` and `bio`.
- Global App Membership: `app.memberships` is the current membership-state
  authority consumed by entry composition, including current non-purchase grant
  handoff.
- Purchase / Payment: `app.orders` and `app.payments` remain active contract
  truth for purchase/payment authority.
- Protected Course Access: `app.course_enrollments` remains active contract
  truth for protected course access.
- Post-Auth Entry Composition: `GET /entry-state` exists as a routing/output
  surface and currently computes post-auth outputs from onboarding state and
  membership state, but backend also contains separate entry-evaluation and
  guard logic outside `/entry-state`.
- Referral: current repo truth includes email-delivered referral transport,
  authenticated `POST /referrals/redeem`, and membership handoff into
  `app.memberships`.
- Invite: current repo truth still includes invite-token validation during auth
  registration and invite-shaped membership grants with source bucket
  `invite`.
- Admin / Rights: current role and admin semantics live on
  `app.auth_subjects`, and backend permissions enforce teacher/admin checks on
  top of app-entry guards.
- Media: current contract truth keeps media lifecycle and runtime media outside
  identity, onboarding-state, membership, and routing authority; profile
  `photo_url` remains read composition only.
- Runtime Projections: current runtime builds derived current-user context,
  compatibility token claims, profile projections, and entry-state outputs from
  source domains.
- Baseline / Schema Evolution: `backend/supabase/baseline_v2_slots/` and
  `backend/supabase/baseline_v2_slots.lock.json` are the canonical app-owned
  schema and substrate-interface authority; `backend/supabase/migrations/` is
  legacy reference only.
- Tasks / Readiness / Derived Documentation: task lists, manifests, readiness
  docs, and analysis notes exist only as non-authoritative derived artifacts.

## TARGET CANONICAL DOMAIN MAP

- Authentication Identity: `auth.users` is authentication identity only.
- Application Subject: `app.auth_subjects` is the canonical application subject
  authority.
- Onboarding: onboarding state belongs only to `app.auth_subjects`;
  create-profile and welcome are onboarding steps and not profile-projection,
  checkout, or frontend-local authority.
- Profile Projection: `/profiles/me` is projection only.
- Global App Membership: `app.memberships` is the sole current-state authority
  for global app membership.
- Purchase / Payment: `app.orders` and `app.payments` own purchase/payment
  truth only.
- Protected Course Access: `app.course_enrollments` owns protected course
  access truth only.
- Post-Auth Entry Composition: `GET /entry-state` owns the canonical post-auth
  decision model, post-auth routing precedence, and the sole authority for
  post-auth routing outputs.
- Referral: referral must converge into one canonical grant path into
  `app.memberships`, grants time-bounded global paid-access-equivalent
  membership state, does not create purchase or payment truth, occurs via email
  link, and must bring the user into onboarding at the create-profile step
  before the shared welcome completion gate.
- Invite: invite must be removed from active runtime domain topology.
- Admin / Rights: app-level role/admin subject fields remain on
  `app.auth_subjects` and must not create separate entry semantics.
- Media: media remains separate from identity, onboarding state, membership,
  and routing authority; optional create-profile image input may exist, but it
  must remain mediated by media authority rather than redefine onboarding or
  profile projection as media truth.
- Runtime Projections: projections, compositions, and compatibility artifacts
  may expose derived views only and must never become fallback authority.
- Baseline / Schema Evolution: `backend/supabase/baseline_v2_slots/` and
  `backend/supabase/baseline_v2_slots.lock.json` remain the only canonical
  app-owned baseline and substrate-interface authority; legacy migrations
  remain historical residue only.
- Tasks / Readiness / Derived Documentation: derived docs may summarize the
  topology but must never own it.

## DOMAIN DEFINITIONS

### Authentication Identity

Classification: `source authority`.

Owns identity semantics through external provider-owned `auth.users`, credential
truth, canonical email identity, authentication, and auth-token verification
substrate.

Must not own onboarding state, application-subject role fields, admin fields,
membership state, protected course access, profile projection semantics, or
post-auth routing outputs.

Relations: Application Subject may share the same `user_id`. Profile Projection
may expose email read-only. No downstream domain may redefine identity truth.

### Application Subject

Classification: `source authority`.

Owns `app.auth_subjects` as the canonical application subject substrate for
`onboarding_state` and `role`.

Must not own purchase truth, payment truth, referral identity, invite-token
transport, protected course access, or post-auth routing outputs.

Relations: Onboarding state and app-level rights are subject-state concerns.
`GET /entry-state` may compose from this domain, but it does not replace it.

### Onboarding

Classification: `source authority`.

Owns onboarding-step meaning and onboarding completion semantics. Persisted
onboarding state belongs only to `app.auth_subjects`.

Must not be profile-derived, purchase-derived, payment-derived, referral-owned,
invite-owned, or route-local fallback logic.

Relations: `POST /auth/onboarding/complete` is the current explicit completion
surface. In target topology, create-profile belongs to this domain. Profile and
media domains may supply projection or asset inputs, but they must not own
onboarding truth.

Resolved ownership: `auth_onboarding_contract.md` defines
`POST /auth/onboarding/create-profile` as the canonical create-profile
execution surface for required name plus optional bio, while media remains
separate for optional image handling.

Welcome-step ownership: welcome is an onboarding-owned step. The canonical
intermediate state after create-profile is `welcome_pending`, persisted on
`app.auth_subjects.onboarding_state`. Onboarding is completed only after the
explicit welcome confirmation `Jag förstår hur Aveli fungerar`.

### Profile Projection

Classification: `projection`.

Owns projection-only current-user profile read/write semantics through
`app.profiles` and `/profiles/me`.

Must not own onboarding completion, create-profile step authority, role/admin
authority, membership truth, purchase/payment truth, referral identity, invite
truth, or post-auth routing outputs.

Relations: Profile Projection may expose `display_name`, `bio`,
`avatar_media_id`, and derived `photo_url`. It may depend on identity or media
domains for read composition, but it remains non-authoritative.

### Global App Membership

Classification: `source authority`.

Owns `app.memberships` as the single canonical current-state authority for
global app membership.

Must not own purchase identity, payment settlement, referral-code identity,
invite-token identity, protected course access, or post-auth routing outputs.

Relations: Purchase / Payment may result in membership through canonical backend
mutation. Referral may also result in membership through one canonical
non-purchase grant path. Post-Auth Entry Composition may derive
`membership_active` from this domain, but it must not redefine membership
truth.

Resolved vocabulary: the canonical non-purchase membership source label for
referral-derived grants is `referral`.

### Purchase / Payment

Classification: `source authority`.

Owns `app.orders` and `app.payments` as purchase and payment truth only.

Must not own current membership state, referral identity, onboarding state,
profile projection, protected course access state, or post-auth routing
outputs.

Relations: Paid membership and paid course access may depend on this domain for
purchase settlement, but resulting current-state membership and course access
remain separate downstream authorities.

### Protected Course Access

Classification: `source authority`.

Owns `app.course_enrollments` as protected course-access truth only.

Must not own purchase/payment truth, global app membership, onboarding state,
profile projection, or post-auth routing outputs.

Relations: Purchase / Payment may produce protected course access through
canonical backend fulfillment. Membership must not be used as a substitute for
course-access authority.

### Post-Auth Entry Composition

Classification: `composition`.

Owns the canonical post-auth decision model and routing outputs through
`GET /entry-state`. Routing precedence is domain authority, not frontend
implementation detail.

Must not own identity truth, subject truth, raw membership truth,
purchase/payment truth, profile projection truth, or protected course-access
truth.

Relations: This domain may compose only from canonical upstream sources. Backend
guards may enforce the canonical decision model technically, but they must not
define, derive, extend, or invent a separate app-entry model.

Routing precedence:

1. If `can_enter_app` is `true`, route to the authenticated app.
2. Else if explicit referral context is present and
   `onboarding_state = "incomplete"`, route to create-profile.
3. Else if `needs_payment` is `true`, route to the checkout/subscribe
   pre-entry payment-initiation surface.
4. Else if `needs_onboarding` is `true` and
   `onboarding_state = "incomplete"`, route to create-profile.
5. Else if `needs_onboarding` is `true` and
   `onboarding_state = "welcome_pending"`, route to welcome.
6. Else fail closed.

For ordinary self-signup, checkout takes precedence over create-profile. For
referral flow, explicit `referral_code` context is the exception and routes to
create-profile before referral redemption. These rules select pre-entry route
order only and do not move authority into frontend route state.

### Referral

Classification: `source authority`.

Owns referral identity and lifecycle, recipient binding, redemption
eligibility, and the rule that a valid referral may initiate one canonical
non-purchase membership grant path into `app.memberships`.

Must not own purchase truth, payment truth, onboarding state, a separate
onboarding state machine, profile-projection authority, or final post-auth
routing outputs.

Relations: Referral occurs via email link and must land the user in onboarding
at create-profile in target topology. Referral may transport pre-redemption
context used by Post-Auth Entry Composition's routing precedence, but
redemption alone never grants purchase/payment truth, onboarding completion, or
app-entry. Referral and Invite must not coexist as overlapping active grant
doctrines in target topology.

### Invite

Classification: `source authority`, `derived artifact`.

In verified current state, Invite still owns signed invite-token validation and
invite-shaped time-bounded non-purchase membership grants using source bucket
`invite`.

In target canonical topology, Invite must own nothing. It survives only as a
historical derived artifact during drift analysis and migration planning.

Relations: Invite currently overlaps Referral as a second non-purchase
membership-grant concept. That overlap is drift. No target-canonical coexistence
is allowed.

### Admin / Rights

Classification: `source authority`.

Owns app-level role/admin subject fields and their mutation law through
`app.auth_subjects`, admin bootstrap, and admin-only teacher-role mutation
surfaces.

Must not own onboarding completion, membership truth, purchase/payment truth,
profile projection truth, or post-auth routing outputs.

Relations: Post-Auth Entry Composition may expose `role`, but exposure does not
move authority out of this domain.

### Media

Classification: `source authority`.

Owns media-asset identity, placement identity, media lifecycle, and runtime
media truth under the media contracts.

Must not own identity, onboarding state, create-profile authority, membership,
purchase/payment, or post-auth routing outputs.

Relations: Profile Projection may derive `photo_url` from media authority. In
target topology, optional create-profile image input may hand off to Media, but
the current contract set does not yet define the canonical target write path
for that handoff. That gap is unresolved and must not be guessed.

### Runtime Projections

Classification: `projection`, `composition`, `derived artifact`.

Owns derived runtime read surfaces and compatibility artifacts such as
`/profiles/me`, `GET /entry-state` responses, `CurrentUser` hydration, and
compatibility token claims.

Must not become fallback authority for identity, onboarding, rights,
membership, purchase/payment, referral, invite, or course access.

Relations: Every runtime projection must derive from canonical source domains.
If a projection and a source authority disagree, the source authority wins and
the projection is drift.

### Baseline / Schema Evolution

Classification: `source authority`, `derived artifact`.

Owns canonical app-owned schema shape and substrate-interface expectations only through
`backend/supabase/baseline_v2_slots/` and
`backend/supabase/baseline_v2_slots.lock.json`.

Must not let legacy migrations, stale columns, or non-baseline schema residue
redefine domain ownership.

Relations: Baseline constrains what source domains may legally persist in local
verification state. `backend/supabase/migrations/` is historical residue only.

### Tasks / Readiness / Derived Documentation

Classification: `derived artifact`.

Owns no runtime domain truth, no baseline truth, and no contract truth.

Must not define or repair ownership for identity, subject, onboarding, profile,
membership, purchase/payment, course access, referral, invite, media, or entry
composition.

Relations: These artifacts may summarize, plan, or diff canonical truth only
after canonical truth has been defined elsewhere.

## CROSS-DOMAIN RELATION RULES

- Authentication Identity and Application Subject are adjacent but separate.
  Identity does not become application-subject authority.
- Onboarding state belongs to Application Subject and may be surfaced through
  Onboarding and Post-Auth Entry Composition, but it must not be inferred from
  Profile Projection.
- Admin / Rights belongs to Application Subject and must not be derived from
  token claims, profile fields, or route metadata.
- Global App Membership is separate from Purchase / Payment. Paid flows may
  create membership state only through canonical backend mutation after
  purchase/payment truth is established.
- Protected Course Access is separate from Global App Membership. Course access
  must not be inferred from membership, and membership must not be inferred from
  course access.
- Post-Auth Entry Composition may compose only from Application Subject and
  Global App Membership for the identity-to-entry chain named in this contract.
- Post-Auth Entry Composition owns routing precedence as domain authority;
  frontend routing may implement that order but must not own or redefine it.
- Ordinary self-signup target flow is:
  register -> checkout -> create-profile -> welcome -> onboarding-complete -> app.
- Referral target flow remains the checkout-first exception and continues
  through the shared welcome gate:
  register -> create-profile -> redeem -> welcome -> onboarding-complete -> app.
- `/profiles/me` may expose projection data only after or independently of
  routing decisions, but it must never repair, replace, or bypass
  `GET /entry-state`.
- Referral may authorize a time-bounded non-purchase membership grant, but it
  must not create purchase truth, payment truth, or a separate onboarding state
  machine.
- Invite currently overlaps Referral, but target topology forbids that overlap.
  The canonical target is one active non-purchase grant doctrine into
  `app.memberships`, not two.
- Media may support optional user image flows, but media truth must remain
  separate from onboarding truth and profile projection truth.
- Runtime Projections must remain downstream of source authorities and must fail
  closed on missing or ambiguous upstream truth.
- Baseline / Schema Evolution may constrain source-domain storage shape, but it
  must not override target canonical domain meaning by itself.
- Tasks / Readiness / Derived Documentation may describe the topology, but they
  must never own or amend it.

## FORBIDDEN AUTHORITY PATTERNS

- Treating `auth.users` as owner of onboarding state, role/admin state,
  membership, or routing outputs.
- Treating `app.auth_subjects` as purchase/payment authority, referral-code
  identity, invite-token identity, or course-access authority.
- Treating `/profiles/me` or profile hydration as onboarding authority, routing
  authority, bootstrap authority, or entry authority.
- Treating profile-name presence as canonical onboarding-completion authority.
- Letting backend guards define a second app-entry model outside
  `GET /entry-state`.
- Letting `GET /entry-state` expose raw purchase, payment, profile, or course
  access fields as routing truth.
- Letting `app.memberships` become purchase/payment truth or protected
  course-access truth.
- Letting `app.orders` or `app.payments` become current membership truth or
  post-auth routing authority.
- Letting `app.course_enrollments` grant global app entry.
- Letting Referral or Invite create purchase truth or payment truth.
- Allowing both Referral and Invite to remain active overlapping authorities for
  the same temporary paid-access-equivalent membership meaning.
- Letting Runtime Projections, compatibility token claims, route metadata, task
  docs, or readiness docs become fallback authority.
- Letting legacy migrations redefine baseline-backed domain ownership.

## DOMAIN DRIFT REGISTER

- Duplicate post-auth entry authority:
  current runtime defines `GET /entry-state` and also separate app-entry
  evaluation/guard logic in `backend/app/auth.py` and `backend/app/permissions.py`.
  Classification: `runtime drift`.
- Profile-derived onboarding completion:
  current runtime blocks `POST /auth/onboarding/complete` when
  `display_name` is absent.
  Classification: `runtime drift`.
- Referral transport mismatch:
  current referral email transport resolves to `/login`, not onboarding
  create-profile.
  Classification: `runtime drift`.
- Referral membership vocabulary mismatch:
  current referral-derived membership handoff still uses source bucket
  `invite`.
  Classification: `contract drift`, `baseline drift`, `runtime drift`.
- Dual non-purchase grant topology:
  current repo carries both invite-token grants and referral redemption grants
  into `app.memberships`.
  Classification: `domain overlap drift`.
- Invite still active:
  current auth/runtime/contracts still keep Invite semantics live even though
  target topology requires removal.
  Classification: `contract drift`, `runtime drift`.
- Create-profile target-surface gap:
  target truth assigns create-profile to Onboarding, but the current contract
  set does not yet define the canonical target execution surface or persistence
  split for required name and optional image/bio.
  Classification: `unresolved`.
- Replacement referral-grant source label gap:
  target truth removes Invite, but the replacement non-purchase membership
  source vocabulary for referral-derived grants is not yet locked in the
  current contract set or target decision file.
  Classification: `unresolved`.
- Projection separation gap:
  `/profiles/me` is correctly projection-only in current contract/runtime, but
  current repo truth does not yet express create-profile as a distinct
  onboarding step separate from profile-projection authority.
  Classification: `contract drift`, `runtime drift`.
- Application-subject naming gap:
  current contracts name field ownership on `app.auth_subjects`, but not every
  active contract names it explicitly as the canonical application subject
  authority.
  Classification: `contract drift`.

## MIGRATION RULE

Future implementation must migrate from verified current-state topology to
target canonical topology by removing overlapping ownership one domain at a
time.

Migration must obey all of the following:

- no migration may move authority into a projection, composition, or derived
  artifact
- no migration may preserve overlapping Invite and Referral grant ownership
- `GET /entry-state` must become the sole post-auth routing authority before
  backend guards may claim enforcement-only status
- profile-derived onboarding completion must be removed rather than renamed
- create-profile must be implemented as an onboarding-owned step and must not
  be collapsed into `/profiles/me`
- routing precedence must remain owned by Post-Auth Entry Composition, not
  frontend implementation convenience
- referral must converge into one canonical grant path into `app.memberships`
- the replacement non-purchase membership source vocabulary that survives invite
  removal must be explicitly locked before baseline or runtime mutation is
  treated as canonical
- optional create-profile image handling must be assigned explicitly to the
  correct media/projection boundary before implementation; this contract does
  not guess that write path
- after the canonical map is locked, downstream task trees and readiness docs
  must be regenerated from this contract instead of redefining it

## FINAL ASSERTION

This contract separates verified current-state topology from target canonical
topology and does not merge them.

The canonical source-authority domains for the identity-to-entry chain are:

- Authentication Identity
- Application Subject
- Onboarding
- Global App Membership
- Purchase / Payment
- Protected Course Access
- Referral
- Admin / Rights
- Media
- Baseline / Schema Evolution

The canonical non-source domains are:

- Profile Projection
- Post-Auth Entry Composition
- Runtime Projections
- Tasks / Readiness / Derived Documentation

If a future implementation, contract, baseline change, or runtime surface
creates overlapping ownership across those domains, that change is drift unless
this contract is explicitly revised first.
