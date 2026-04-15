# Onboarding Entry Authority Contract

## STATUS

ACTIVE

This contract defines the canonical cross-domain law for auth entry,
application-subject onboarding state, onboarding completion gating, global
app-entry authority, and referral interaction with entry authority.

This contract operates under `SYSTEM_LAWS.md`.

This contract composes with:

- `auth_onboarding_contract.md`
- `commerce_membership_contract.md`
- `referral_membership_grant_contract.md`
- `profile_projection_contract.md`
- `course_access_contract.md`

Contract truth and runtime drift are separate.

## 1. DOMAIN DEFINITION

- Auth entry means identity creation, credential validation, token issuance,
  token refresh, and token validation.
- `app.auth_subjects` is the canonical application subject authority for:
  - onboarding subject state
  - app-level role subject fields
  - app-level admin subject fields
- Onboarding means the canonical create-profile step plus the explicit
  completion transition stored on `app.auth_subjects.onboarding_state`.
- Global app-entry means backend-owned permission for an authenticated user to
  enter authenticated app surfaces beyond public, auth, payment-return, and
  webhook surfaces.
- Protected course access means permission to read protected lesson/content
  surfaces governed by `app.course_enrollments`.
- Referral flow means teacher-issued referral-code transport via email link,
  onboarding landing at create-profile, and post-identity redemption that may
  create a non-purchase membership grant with source `referral`.
- Auth entry is not global app-entry.
- Onboarding is not membership authority.
- Membership is not protected course-access authority.
- Referral flow is not auth registration.
- Invite is not an active canonical doctrine in this contract corpus.

## 2. ROUTE SURFACE CLASSIFICATION

This classification is a current contract snapshot. Classification is not
authority. No listed route may use its classification as proof of app-entry.

Backend mounted route classes:

- Public/static: `/assets/*`
- Mounted empty router: `playback.router` exposes no active route surface
- Diagnostic: `/healthz`, `/readyz`, `/metrics`, `/mcp/logs`,
  `/mcp/media-control-plane`, `/mcp/domain-observability`,
  `/mcp/verification`
- Auth entry: `POST /auth/register`, `POST /auth/login`,
  `POST /auth/forgot-password`, `POST /auth/reset-password`,
  `POST /auth/refresh`, `POST /auth/send-verification`,
  `GET /auth/verify-email`
- Pre-entry onboarding/referral/profile projection:
  `POST /auth/onboarding/create-profile`,
  `POST /auth/onboarding/complete`, `GET /profiles/me`,
  `PATCH /profiles/me`, `POST /referrals/redeem`
- Public course/catalog/payment-information:
  `GET /courses`, `GET /courses/`, `GET /courses/{slug}/pricing`,
  `GET /api/courses/{slug}/pricing`, `GET /courses/by-slug/{slug}`,
  `GET /courses/{course_id}/public`, `GET /courses/{course_id}`,
  `GET /api/course-bundles/{bundle_id}`
- Payment-initiation pre-entry:
  `POST /api/billing/create-subscription`,
  `POST /api/billing/cancel-subscription-intent`,
  `POST /api/checkout/create`,
  `POST /api/course-bundles/{bundle_id}/checkout-session`
- Webhook: `POST /api/stripe/webhook`
- Protected course access:
  `GET /courses/lessons/{lesson_id}`, `GET /courses/me`,
  `GET /courses/{course_id}/enrollment`, `GET /courses/{course_id}/access`,
  `POST /courses/{course_id}/enroll`
- Global app-entry with secondary admin permission:
  `GET /admin/settings`, `POST /admin/users/{user_id}/grant-teacher-role`,
  `POST /admin/users/{user_id}/revoke-teacher-role`
- Global app-entry with secondary teacher permission:
  `/studio/*`, `/api/lesson-media/*`, `/api/*` media-pipeline routes owned by
  `studio.media_pipeline_router`, `POST /api/notifications`,
  `POST /api/teachers/course-bundles`,
  `GET /api/teachers/course-bundles`,
  `POST /api/teachers/course-bundles/{bundle_id}/courses`
- Global app-entry with route-local feature checks:
  `GET /home/audio`, all mounted `/api/events*` routes

Frontend route classes:

- Public: `landingRoot`, `boot`, `landing`, `login`, `signup`,
  `verifyEmail`, `forgotPassword`, `resetPassword`, `courseIntro`,
  `courseIntroRedirect`, `courseCatalog`, `course`, `serviceDetail`,
  `profileView`, `teacherProfile`, `privacy`, `terms`, `checkoutSuccess`,
  `checkoutCancel`
- Pre-entry onboarding/payment: `welcome`, `createProfile`,
  `profileSubscription`, `checkout`, `subscribe`
- Protected course access: `lesson`
- Global app-entry: `home`, `sfuDemo`, `messages`, `directMessage`, `profile`,
  `tarot`, `booking`, `settings`, `community`, `seminarDiscover`,
  `seminarJoin`
- Global app-entry with secondary admin metadata: `admin`, `adminMedia`,
  `adminSettings`
- Global app-entry with secondary teacher metadata: `studio`, `teacherHome`,
  `teacherBundles`, `teacherEditor`, `studioProfile`, `seminarStudio`,
  `seminarDetail`, `seminarPreJoin`, `seminarBroadcast`

## 3. CANONICAL AUTHORITIES

| Concept | Canonical authority | Backend responsibility boundary | Current drift state |
|---|---|---|---|
| Identity and credentials | `auth.users` | `/auth/register`, `/auth/login`, password reset, email verification, token subject identity | No drift found for identity ownership. |
| Application subject authority | `app.auth_subjects` | canonical subject-state storage for onboarding subject state, app-level role subject fields, and app-level admin subject fields | Earlier contracts used field-only naming instead of the locked canonical phrase. |
| Onboarding step surfaces | `POST /auth/onboarding/create-profile` and `POST /auth/onboarding/complete` under `auth_onboarding_contract.md` | create-profile step execution plus completion transition | Runtime still uses `/profiles/me` writes and profile-name coupling instead of the canonical create-profile model. |
| Global app-entry membership | `app.memberships` | Backend membership reads and app-entry gate decisions | Runtime does not enforce active membership globally before authenticated app access. |
| Purchase substrate | `app.orders`, `app.payments` | Billing and Stripe webhook settlement before purchase-backed membership or course access is applied | Membership purchase flow is order-backed in runtime; some refund/payment resolution fallback exists and is non-authoritative. |
| Profile projection | `app.profiles` plus `auth.users.email` for projected email | `GET /profiles/me` and `PATCH /profiles/me` projection only | Profile hydration is used by frontend as effective app gate; that is invalid. |
| Protected course access | `app.course_enrollments` | Course access, lesson content, and protected course-content read decisions | Active protected lesson access uses enrollment authority; legacy entitlement service code exists and must not be authority. |
| Referral authority | `app.referral_codes` | Teacher-issued referral creation, referral email transport to create-profile, and authenticated `POST /referrals/redeem` after identity exists | Current runtime email transport still lands `/login`, and current membership handoff still uses source `invite`. |

## 4. POST-AUTH ENTRY-STATE SURFACE

`GET /entry-state` is the only canonical post-auth routing authority surface.
After authenticated identity is established, `GET /entry-state` is the only
allowed source for:

- app-entry decision
- onboarding gating
- payment gating

No other surface may determine post-auth routing. This includes `/profiles/me`,
frontend route state, token claims, local session state, Stripe checkout
success, payment-return state, membership reads outside entry composition,
teacher/admin metadata, course enrollment, referral-link presence, or any
public/auth/payment/webhook/read surface.

### Response Ownership

The allowed `GET /entry-state` response fields are exactly:

- `can_enter_app`
- `onboarding_state`
- `onboarding_completed`
- `membership_active`
- `needs_onboarding`
- `needs_payment`
- `role_v2`
- `role`
- `is_admin`

No other response field is allowed.

Field ownership:

- `onboarding_state`, `role_v2`, `role`, and `is_admin` are sourced from
  `app.auth_subjects` as the canonical application subject authority.
- `membership_active` is derived from the canonical current membership state
  defined by `commerce_membership_contract.md`.
- `can_enter_app`, `onboarding_completed`, `needs_onboarding`, and
  `needs_payment` are entry-composition fields owned by this contract and
  exposed only through `GET /entry-state`.

### Derivation Rules

- `onboarding_completed = onboarding_state == "completed"`
- `membership_active` is defined by `commerce_membership_contract.md`
- `can_enter_app = onboarding_completed && membership_active`
- `needs_onboarding = !onboarding_completed`
- `needs_payment = !membership_active`

### Relation To `/profiles/me`

`/profiles/me` is projection-only. It must not be used for routing,
bootstrap, create-profile authority, or entry decision. `/profiles/me` must
not be required before post-auth routing decisions, and a successful
`/profiles/me` response must not repair, replace, or infer `GET /entry-state`
truth.

### Frontend Routing Rule

Frontend must call `GET /entry-state` before post-auth routing. Frontend must
not depend on `/profiles/me` before routing, and must not route from profile
hydration, token claims, local session state, membership-only reads, checkout
success, or role/admin metadata.

## 5. ENTRY LAW

A user is allowed to enter the authenticated app only when all conditions are
true:

- The request has a valid authenticated identity
- The identity resolves to a canonical `app.auth_subjects` row
- `app.auth_subjects.onboarding_state = 'completed'`
- A single canonical current-state membership row exists in `app.memberships`
- `membership_active = true` under `commerce_membership_contract.md`

These conditions are exposed for post-auth routing only through
`GET /entry-state`.

If any condition is missing, invalid, ambiguous, or unavailable, global
app-entry must be denied.

Authentication alone must not grant global app-entry.
Profile hydration alone must not grant global app-entry.
Frontend route state must not grant global app-entry.
Stripe checkout success must not grant global app-entry.
Referral link presence must not grant global app-entry.

## 6. ONBOARDING LAW

Canonical onboarding surfaces are:

- `POST /auth/onboarding/create-profile`
- `POST /auth/onboarding/complete`

Rules:

- Onboarding state is stored only in `app.auth_subjects.onboarding_state`
- Create-profile is an onboarding-owned step and is not profile-projection
  authority
- Required name belongs at create-profile and is not registration-derived
- Optional bio is onboarding-collected but profile-persisted
- Optional image is media-mediated and must not move media authority into
  onboarding or profile projection
- Onboarding completion means that `POST /auth/onboarding/complete` explicitly
  persists `app.auth_subjects.onboarding_state = 'completed'` for the
  authenticated user
- Create-profile alone does not complete onboarding
- Profile-name presence is not onboarding-completion authority
- The following events must not implicitly complete onboarding:
  - registration
  - login
  - payment
  - referral transport
  - referral redemption
  - profile projection writes
  - email verification

## 7. REFERRAL GRANT LAW

- Referral is the sole canonical non-purchase grant doctrine relevant to this
  onboarding path
- Referral email transport must bring the user into onboarding at the
  create-profile step
- Referral redemption remains post-auth through `POST /referrals/redeem`
- A valid referral redemption may create a non-purchase membership grant
  through membership authority using source `referral`
- Referral must not create `app.orders` or `app.payments`
- Referral must not complete onboarding
- Referral must not bypass global app-entry law
- Referral transport or redemption does not become routing authority

## 8. FORBIDDEN PATTERNS

- Authenticated app entry without active membership
- Authenticated app entry without completed onboarding
- Treating `/profiles/me` success or profile hydration as app-entry authority
- Treating frontend `gate.allow()` or route session state as app-entry
  authority
- Treating local JWT claims, Supabase JWT claims, role claims, or admin claims
  as membership authority
- Treating `POST /auth/register` as create-profile authority
- Treating profile-name presence as canonical onboarding-completion authority
- Accepting `referral_code` on `/auth/register`
- Treating `/signup?referral_code=...` as equivalent to `/referrals/redeem`
- Letting backend guards define a second app-entry model outside
  `GET /entry-state`
- Letting frontend teacher/admin route metadata override backend
  `app.auth_subjects` authority
- Any duplicated or conflicting ownership of identity, application subject,
  onboarding, membership, profile projection, course access, or referral
  authority

## 9. CURRENT DRIFT SURFACES

- Manifest and system decisions require membership-gated app entry, but runtime
  authenticated routes commonly require only `CurrentUser`, `TeacherUser`, or
  `AdminUser`
- Auth runtime validates canonical `app.auth_subjects`, but does not require
  `onboarding_state = 'completed'` before authenticated app access
- Frontend auth state treats profile hydration as authenticated entry and calls
  its gate after login, register, session hydration, and welcome completion
- Frontend profile model does not carry onboarding state or membership state
- Frontend router redirects only on public-vs-authenticated state and does not
  yet treat `GET /entry-state` as the sole post-auth routing output authority
- Runtime currently uses `/profiles/me` writes instead of the canonical
  `POST /auth/onboarding/create-profile` surface
- Runtime currently blocks onboarding completion on profile-name presence
- Current referral email transport resolves to `/login` instead of the
  canonical create-profile onboarding step
- Current referral membership handoff still uses source `invite`
- Legacy invite validation and invite-shaped membership grant surfaces remain
  runtime drift only and are not canonical law

## 10. FINAL SYSTEM LAW

Canonical auth entry is identity and token transport only.
Canonical application subject authority is `app.auth_subjects`.
Canonical onboarding surfaces are `POST /auth/onboarding/create-profile` and
`POST /auth/onboarding/complete`.
Canonical post-auth routing authority is `GET /entry-state` in this contract.
Canonical global app-entry authority is `GET /entry-state` composition from
completed onboarding plus `membership_active`.
Canonical profile projection is `app.profiles` and must remain
non-authoritative.
Canonical protected course access is `app.course_enrollments`.
Canonical referral authority is `app.referral_codes`, and referral-derived
membership grants use source `referral`.
Invite is removed as an active canonical doctrine.
