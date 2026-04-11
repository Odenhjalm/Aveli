# Onboarding Entry Authority Contract

## STATUS

ACTIVE

This contract defines the canonical cross-domain law for auth entry,
onboarding completion gating, global app-entry authority, and invite/referral
interaction with entry authority.

This contract operates under `SYSTEM_LAWS.md`.

This contract composes with:

- `auth_onboarding_contract.md`
- `commerce_membership_contract.md`
- `referral_membership_grant_contract.md`
- `profile_projection_contract.md`
- `course_access_contract.md`

Contract truth and runtime drift are separate. The completed no-code audit is
the source for current runtime drift named in this contract.

## 1. DOMAIN DEFINITION

- Auth entry means identity creation, credential validation, token issuance,
  token refresh, and token validation.
- Onboarding means the explicit user-state transition stored on
  `app.auth_subjects.onboarding_state`.
- Global app-entry means backend-owned permission for an authenticated user to
  enter authenticated app surfaces beyond public, auth, payment-return, and
  webhook surfaces.
- Protected course access means permission to read protected lesson/content
  surfaces governed by `app.course_enrollments`.
- Invite flow means signed invite-token transport used for identity bootstrap
  plus time-bounded non-purchase membership grant.
- Referral flow means teacher-issued referral-code transport and post-identity
  redemption that may create a non-purchase membership grant.
- Auth entry is not global app-entry.
- Onboarding is not membership authority.
- Membership is not protected course-access authority.
- Invite flow is not referral flow.
- Referral flow is not auth registration.

## PHASE A ROUTE SURFACE CLASSIFICATION

This classification is a Phase A snapshot. Classification is not authority.
No listed route may use its classification as proof of app-entry.

Backend mounted route classes:

- Public/static: `/assets/*`.
- Mounted empty router: `playback.router` exposes no active route surface.
- Diagnostic: `/healthz`, `/readyz`, `/metrics`,
  `/mcp/logs`, `/mcp/media-control-plane`, `/mcp/domain-observability`,
  `/mcp/verification`.
- Auth entry: `POST /auth/register`, `POST /auth/login`,
  `POST /auth/forgot-password`, `POST /auth/reset-password`,
  `POST /auth/refresh`, `POST /auth/send-verification`,
  `GET /auth/verify-email`, `GET /auth/validate-invite`.
- Pre-entry onboarding/referral/profile projection:
  `POST /auth/onboarding/complete`, `GET /profiles/me`, `PATCH /profiles/me`,
  `POST /referrals/redeem`.
- Public course/catalog/payment-information:
  `GET /courses`, `GET /courses/`, `GET /courses/{slug}/pricing`,
  `GET /api/courses/{slug}/pricing`, `GET /courses/by-slug/{slug}`,
  `GET /courses/{course_id}/public`, `GET /courses/{course_id}`,
  `GET /api/course-bundles/{bundle_id}`.
- Payment-initiation pre-entry:
  `POST /api/billing/create-subscription`,
  `POST /api/billing/cancel-subscription-intent`,
  `POST /api/checkout/create`,
  `POST /api/course-bundles/{bundle_id}/checkout-session`.
- Webhook: `POST /api/stripe/webhook`.
- Protected course access:
  `GET /courses/lessons/{lesson_id}`, `GET /courses/me`,
  `GET /courses/{course_id}/enrollment`, `GET /courses/{course_id}/access`,
  `POST /courses/{course_id}/enroll`.
- Global app-entry with secondary admin permission:
  `GET /admin/settings`, `POST /admin/users/{user_id}/grant-teacher-role`,
  `POST /admin/users/{user_id}/revoke-teacher-role`.
- Global app-entry with secondary teacher permission:
  `/studio/*`, `/api/lesson-media/*`, `/api/*` media-pipeline routes owned by
  `studio.media_pipeline_router`, `POST /api/notifications`,
  `POST /api/teachers/course-bundles`,
  `GET /api/teachers/course-bundles`,
  `POST /api/teachers/course-bundles/{bundle_id}/courses`.
- Global app-entry with route-local feature checks:
  `GET /home/audio`, all mounted `/api/events*` routes.

Frontend route classes:

- Public: `landingRoot`, `boot`, `landing`, `login`, `signup`, `verifyEmail`,
  `forgotPassword`, `resetPassword`, `invite`, `courseIntro`,
  `courseIntroRedirect`, `courseCatalog`, `course`, `serviceDetail`,
  `profileView`, `teacherProfile`, `privacy`, `terms`, `checkoutSuccess`,
  `checkoutCancel`.
- Pre-entry onboarding/payment: `welcome`, `createProfile`,
  `profileSubscription`, `checkout`, `subscribe`.
- Protected course access: `lesson`.
- Global app-entry: `home`, `sfuDemo`, `messages`, `directMessage`, `profile`,
  `tarot`, `booking`, `settings`, `community`, `seminarDiscover`,
  `seminarJoin`.
- Global app-entry with secondary admin metadata: `admin`, `adminMedia`,
  `adminSettings`.
- Global app-entry with secondary teacher metadata: `studio`, `teacherHome`,
  `teacherBundles`, `teacherEditor`, `studioProfile`, `seminarStudio`,
  `seminarDetail`, `seminarPreJoin`, `seminarBroadcast`.

## 2. CANONICAL AUTHORITIES

| Concept | Canonical authority | Backend responsibility boundary | Current drift state |
|---|---|---|---|
| Identity and credentials | `auth.users` | `/auth/register`, `/auth/login`, password reset, email verification, token subject identity | No drift found for identity ownership. |
| Token transport | Backend auth layer and `app.refresh_tokens` for refresh-token persistence | Access-token issuance/validation, refresh-token rotation and revocation | Supabase JWT bearer validation exists as an implicit token-entry path; it must not become app-entry authority. |
| Onboarding state | `app.auth_subjects.onboarding_state` | `POST /auth/onboarding/complete` only | Runtime stores and mutates state, but does not enforce completed onboarding before app-entry. |
| Role and admin authority | `app.auth_subjects.role_v2`, `app.auth_subjects.role`, `app.auth_subjects.is_admin` | Admin role routes and canonical permission dependencies | Frontend route metadata declares teacher/admin levels but does not enforce them as authority. |
| Global app-entry membership | `app.memberships` | Backend membership reads and app-entry gate decisions | Runtime does not enforce active membership globally before authenticated app access. |
| Purchase substrate | `app.orders`, `app.payments` | Billing and Stripe webhook settlement before purchase-backed membership or course access is applied | Membership purchase flow is order-backed in runtime; some refund/payment resolution fallback exists and is non-authoritative. |
| Profile projection | `app.profiles` plus `auth.users.email` for projected email | `GET /profiles/me` and `PATCH /profiles/me` projection only | Profile hydration is used by frontend as effective app gate; that is invalid. |
| Protected course access | `app.course_enrollments` | Course access, lesson content, and protected course-content read decisions | Active protected lesson access uses enrollment authority; legacy entitlement service code exists and must not be authority. |
| Referral authority | `app.referral_codes` | Teacher-issued referral creation and authenticated `POST /referrals/redeem` after identity exists | Baseline audit did not find `app.referral_codes`; runtime read helpers also catch missing table. This is invalid drift. |
| Invite authority | Signed invite email token plus `app.memberships` grant with `source = 'invite'` and non-null `expires_at` | `/auth/validate-invite`, optional `invite_token` validation during `/auth/register`, and canonical non-purchase membership-grant boundary | Runtime currently validates invite token but does not create invite membership. That is invalid drift from the corrected invite law. |

## 3. ENTRY LAW

A user is allowed to enter the authenticated app only when all conditions are
true:

- The request has a valid authenticated identity.
- The identity resolves to a canonical `app.auth_subjects` row.
- `app.auth_subjects.onboarding_state = 'completed'`.
- A single canonical current-state membership row exists in `app.memberships`.
- Membership access evaluates as active under the membership law in this
  contract.

If any condition is missing, invalid, ambiguous, or unavailable, global app-entry
must be denied.

Authentication alone must not grant global app-entry.
Profile hydration alone must not grant global app-entry.
Frontend route state must not grant global app-entry.
Stripe checkout success must not grant global app-entry.
Referral link presence must not grant global app-entry.
Invite-token presence must not grant global app-entry.
Invite membership grant must not grant global app-entry without completed
onboarding.

The audit found that current runtime does not enforce this law. That behavior is
invalid runtime drift.

## 4. ONBOARDING LAW

The only canonical onboarding states proven by audit are:

- `incomplete`
- `completed`

Onboarding state is stored only in `app.auth_subjects.onboarding_state`.

Onboarding completion means that `POST /auth/onboarding/complete` explicitly
persists `app.auth_subjects.onboarding_state = 'completed'` for the authenticated
user. Completion is idempotent when the stored state is already `completed`.

Onboarding completion is required for global app-entry.

The following events must not implicitly complete onboarding:

- registration
- login
- token refresh
- profile read
- profile update
- email verification
- invite validation
- invite membership grant
- referral redemption
- membership grant
- Stripe webhook processing

The audit found that users with `onboarding_state = 'incomplete'` can reach
authenticated app surfaces. That behavior is invalid runtime drift.

## 5. MEMBERSHIP LAW

`app.memberships` is the only canonical authority for global app-entry
membership state.

Global app-entry is active only when:

- `status = 'active'`
- OR `status = 'canceled' AND current_time < expires_at`

All other membership states deny global app-entry, including:

- missing row
- `inactive`
- `past_due`
- `expired`
- `canceled` without a future `expires_at`
- unknown status values

No route may treat authentication alone as sufficient global app-entry.
No frontend state may treat authentication alone as sufficient global app-entry.
No course enrollment may grant global app-entry.
No role, admin flag, teacher flag, or event participation state may grant global
app-entry.
No local route-level membership check may redefine global app-entry authority.

The audit found localized membership checks for members-only event visibility.
Those checks are not global app-entry authority and must not be relied upon as a
substitute for the global app-entry law.

## 6. COURSE ACCESS LAW

Global app-entry authority and protected course-access authority are separate.

Global app-entry is governed by `app.memberships` and completed onboarding.
Protected course access is governed by `app.course_enrollments`.

Protected lesson/content access must require canonical course enrollment state
and the canonical lesson unlock rule from `course_access_contract.md`.

Membership alone never grants protected lesson/content access.
Course enrollment never grants global app-entry.
Course purchase, bundle purchase, and intro enrollment must not mutate
`app.memberships` unless a separate membership authority explicitly applies.

## 7. INVITE AND REFERRAL LAW

Invite flow currently validates a signed invite token and may pass
`invite_token` into `/auth/register`.

Canonical invite flow is identity bootstrap plus non-purchase membership grant.
Accepted invite membership must be written through canonical membership
authority with:

- `source = 'invite'`
- non-null `expires_at`

Invite flow must not:

- redeem referral
- complete onboarding
- bypass global app-entry law
- share referral parameter handling

Invite may bypass payment capture only through its canonical time-bounded
membership grant. Invite token validation alone is not membership authority.
Invite membership grant alone is not app-entry authority.

Referral flow currently uses teacher-issued referral codes and authenticated
`POST /referrals/redeem` after identity exists. A valid referral redemption may
create a non-purchase membership grant through membership authority. Referral
redemption must not create `app.orders` or `app.payments`.

Referral may bypass payment only as a canonical non-purchase membership grant
after valid referral redemption. Referral must not bypass onboarding completion.
Referral must not bypass global app-entry law.

The audit found referral drift:

- Backend referral email generation emits `/signup?referral_code=...`.
- Frontend signup reads `invite_token`, not `referral_code`.
- Backend `/auth/register` rejects `referral_code`.
- Authenticated `/referrals/redeem` is the actual redemption surface.
- `app.referral_codes` was not found in the audited baseline slots.
- Runtime referral reads contain missing-table handling.

These mismatches are invalid drift. They must not be normalized into canonical
behavior.

## FORBIDDEN PATHS

- Authenticated app entry without active membership is forbidden.
- Authenticated app entry without completed onboarding is forbidden.
- Treating `/profiles/me` success or profile hydration as app-entry authority is
  forbidden.
- Treating frontend `gate.allow()` or route session state as app-entry authority
  is forbidden.
- Treating local JWT claims, Supabase JWT claims, role claims, or admin claims as
  membership authority is forbidden.
- Treating invite-token presence or invite validation without a canonical
  invite membership row as membership authority is forbidden.
- Creating invite membership without `source = 'invite'` is forbidden.
- Creating invite membership without non-null `expires_at` is forbidden.
- Treating referral-code presence in a signup URL as referral redemption is
  forbidden.
- Accepting `referral_code` on `/auth/register` is forbidden.
- Treating `/signup?referral_code=...` as equivalent to `/referrals/redeem` is
  forbidden.
- Reading, redeeming, or relying on referral authority when the canonical
  `app.referral_codes` substrate is missing is forbidden.
- Catching missing referral authority tables as a normal no-result flow is
  forbidden.
- Using legacy `app.entitlements` or entitlement-service logic as app-entry or
  protected course-access authority is forbidden.
- Treating members-only event route checks as global app-entry authority is
  forbidden.
- Treating public course discovery, course detail, payment-return, auth, or
  webhook surfaces as evidence of authenticated app-entry authority is forbidden.
- Treating course enrollment, intro enrollment, course purchase, or bundle
  purchase as global app-entry authority is forbidden.
- Treating Stripe checkout success, Stripe runtime subscription state, frontend
  checkout result state, or payment-return deep links as membership authority is
  forbidden.
- Letting frontend teacher/admin route metadata override backend
  `app.auth_subjects` authority is forbidden.
- Any duplicated or conflicting ownership of identity, onboarding, membership,
  profile projection, course access, referral, or invite authority is forbidden.
- Any fallback authority that compensates for missing canonical authority is
  forbidden.

## CURRENT DRIFT SURFACES

- Manifest and system decisions require membership-gated app entry, but runtime
  authenticated routes commonly require only `CurrentUser`, `TeacherUser`, or
  `AdminUser`.
- Auth runtime validates canonical `app.auth_subjects`, but does not require
  `onboarding_state = 'completed'` before authenticated app access.
- Frontend auth state treats profile hydration as authenticated entry and calls
  its gate after login, register, session hydration, and welcome completion.
- Frontend profile model does not carry onboarding state or membership state.
- Frontend router redirects only on public-vs-authenticated state and does not
  enforce completed onboarding or active membership.
- Frontend route metadata includes teacher/admin access levels, but the redirect
  layer does not enforce those levels.
- Referral creation emits signup links with `referral_code`, while frontend
  signup accepts only `invite_token` and backend register rejects
  `referral_code`.
- Referral runtime references `app.referral_codes`, while the audited baseline
  slots did not contain the referral authority table.
- Referral repository read helpers catch `UndefinedTable` and return `None`.
- Runtime invite validation/register currently does not create invite
  membership with `source = 'invite'` and non-null `expires_at`; this is drift
  from the corrected canonical invite law.
- Legacy entitlement-service code references `app.entitlements`; it was not
  found as an active mounted authority path in the audit, but the authority-like
  code remains present.
- Event routes contain membership checks for members-only event visibility; that
  is a local feature gate and not global app-entry enforcement.
- Stripe Connect onboarding code and frontend calls exist outside the mounted
  backend router set; this is teacher payout onboarding, not auth onboarding.
- Supabase JWT validation exists as bearer-token validation substrate; it must
  remain token transport and must not become membership or onboarding authority.

## FINAL SYSTEM LAW

Canonical auth entry is identity and token transport only.
Canonical onboarding authority is `app.auth_subjects.onboarding_state`.
Canonical global app-entry authority is completed onboarding plus active
membership in `app.memberships`.
Canonical profile projection is `app.profiles` and must remain non-authoritative.
Canonical protected course access is `app.course_enrollments`.
Canonical referral authority is `app.referral_codes`; if that authority is
missing, referral-dependent behavior must fail closed.
Canonical invite authority is signed invite-token validation plus a
time-bounded membership grant with `source = 'invite'`. Invite token validation
alone is not app-entry.

Non-canonical runtime drift, frontend gates, route-level exceptions, legacy
entitlement logic, missing-table fallback, checkout-return state, and token
claims must never be relied upon in future implementation.

Future task trees must treat drift, fallback removal, or drift isolation as
required work before new entry/onboarding behavior relies on these surfaces.
