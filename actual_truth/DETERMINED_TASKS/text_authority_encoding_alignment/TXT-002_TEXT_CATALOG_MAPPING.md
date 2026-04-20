# TXT-002 Text Catalog Mapping

TYPE: OWNER
DEPENDS_ON: [TXT-001]
MODE: execute
STATUS: COMPLETE_FOR_TXT_002_STRUCTURE

This artifact maps the TXT-001 text-surface inventory to canonical backend text
catalog targets, DB-owned content fields, non-user-facing identifiers, or
explicit blocked future-facing classifications.

This artifact does not change runtime behavior. It does not move strings,
rewrite frontend rendering, modify backend routes, change API envelopes, change
DB schema, or fix encoding.

## 1. Authority Load

Loaded authorities:

- `codex/AVELI_OPERATING_SYSTEM.md`
- `actual_truth/Aveli_System_Decisions.md`
- `actual_truth/aveli_system_manifest.json`
- `actual_truth/contracts/system_text_authority_contract.md`
- `actual_truth/contracts/backend_text_catalog_contract.md`
- `actual_truth/DETERMINED_TASKS/text_authority_encoding_alignment/TXT-001_TEXT_SURFACE_INVENTORY.md`
- Active contracts under `actual_truth/contracts/`

TXT-001 preconditions satisfied:

- `system_text_authority_contract.md` exists and is active.
- `TXT-001_TEXT_SURFACE_INVENTORY.md` exists and is marked
  `COMPLETE_FOR_TXT_001`.
- TXT-001 class list contains exactly the allowed eight authority classes.
- Frontend is not an authority class.
- TXT-001 recorded no unclassified current product surface in inspected roots.

Runtime verification not performed in TXT-002:

- no MCP bootstrap,
- no backend startup,
- no DB query,
- no API call,
- no UI render,
- no email render,
- no Stripe runtime call.

Reason: TXT-002 is an artifact-only owner task.

## 2. Canonical Catalog Model

Backend-owned product text maps to stable text IDs. Text IDs are internal
ASCII identifiers and are never rendered as product copy.

Catalog-owned authority classes:

- `contract_text`
- `backend_error_text`
- `backend_status_text`
- `backend_email_text`
- `backend_stripe_text`

Non-catalog rendered content classes:

- `db_domain_content`
- `db_user_content`

Non-rendered class:

- `non_user_facing_identifier`

Every user-facing product text value governed by the catalog model is
Swedish-only (`sv-SE`). Exact Swedish values are intentionally not populated by
this TXT-002 artifact unless already owned by an active contract. Population
and runtime delivery are downstream tasks.

## 3. Domain Registry

| Domain | Backend namespace target | Surface coverage |
|---|---|---|
| `auth` | `backend_text_catalog.auth` | Login, signup, password reset, email verification, auth settings, auth failures |
| `onboarding` | `backend_text_catalog.onboarding` | Create-profile, welcome, onboarding confirmation, onboarding failures |
| `profile` | `backend_text_catalog.profile` | Profile page, password action, profile save/status/failure, logout/profile projection labels |
| `checkout` | `backend_text_catalog.checkout` | Membership checkout, embedded shell, checkout cancel/return, course/bundle checkout surface text |
| `payments` | `backend_text_catalog.payments` | Payment result, waiting, retry, post-confirmation, provider-facing state copy |
| `landing_legal` | `backend_text_catalog.landing_legal` | Landing, legal pages, footer legal links, data deletion link label |
| `home` | `backend_text_catalog.home` | Home dashboard, feed states, certification gate, home-player states |
| `community` | `backend_text_catalog.community` | Community, teacher/service/profile public surfaces |
| `course_lesson` | `backend_text_catalog.course_lesson` | Course catalog, course detail, lesson view, access gate, route failures |
| `studio_editor` | `backend_text_catalog.studio_editor` | Studio entry, teacher home, course editor, upload, preview, dialog, session states |
| `admin` | `backend_text_catalog.admin` | Admin role/settings UI and admin failures |
| `media_system` | `backend_text_catalog.media_system` | Media UI, media failures, media control plane product-visible text |
| `email` | `backend_text_catalog.email` | Verification, reset, referral, and backend-emitted email text |
| `mvp_shared` | `backend_text_catalog.mvp_shared` | MVP shell and shared widgets still product-visible during migration |
| `global_system` | `backend_text_catalog.global_system` | Not-found, boot, snackbar, nav chrome, brand, global backend failures |
| `future_blocked` | none until contract exists | Messages, notifications, events, seminars, session slots |

## 4. Inventory To Catalog Mapping

The following groups cover every TXT-001 inventory ID exactly once. A group row
may contain multiple authority classes because TXT-001 file rows can contain
multiple independent rendered values. Each individual rendered value still
maps to exactly one class.

### Auth, Onboarding, And Email

Surface IDs:

`TXT-SURF-001`, `TXT-SURF-002`, `TXT-SURF-007`, `TXT-SURF-008`,
`TXT-SURF-009`, `TXT-SURF-010`, `TXT-SURF-011`, `TXT-SURF-012`,
`TXT-SURF-013`, `TXT-SURF-014`, `TXT-SURF-015`, `TXT-SURF-016`,
`TXT-SURF-017`, `TXT-SURF-018`, `TXT-SURF-019`, `TXT-SURF-020`,
`TXT-SURF-021`, `TXT-SURF-022`, `TXT-SURF-123`, `TXT-SURF-124`

Mapping targets:

| Current surface | Target classification | Canonical target |
|---|---|---|
| Onboarding welcome confirmation | canonical backend text ID target | `onboarding.welcome.confirmation_action` |
| Auth login/signup page chrome | canonical backend text ID target | `auth.login.*`, `auth.signup.*` |
| Forgot/reset password UI | canonical backend text ID target | `auth.password.forgot.*`, `auth.password.reset.*` |
| Verify-email UI and resend states | canonical backend text ID target | `auth.email_verification.*` |
| Auth settings UI | canonical backend text ID target | `auth.settings.*` |
| Auth/onboarding failures | canonical backend text ID target | `auth.error.*`, `onboarding.error.*` |
| Auth/onboarding error codes | non-user-facing identifier | `auth.error_code.*`, `onboarding.error_code.*`; never rendered as copy |
| Email verification template | canonical backend text ID target | `email.verify.subject`, `email.verify.heading`, `email.verify.body`, `email.verify.cta` |
| Reset-password email template | canonical backend text ID target | `email.password_reset.subject`, `email.password_reset.heading`, `email.password_reset.body`, `email.password_reset.cta` |
| Referral email text | canonical backend text ID target | `email.referral.subject`, `email.referral.body`, `email.referral.cta` |
| Create-profile onboarding form chrome | canonical backend text ID target plus DB user fields | `onboarding.create_profile.*`; `app.profiles.display_name`; `app.profiles.bio` |
| Entry-state route identifiers | non-user-facing identifier | `entry_state.*`; may route, must not render as product copy |

Known problem coverage:

- Auth/onboarding failure text must move to backend-owned catalog IDs and
  canonical envelopes.
- Error codes remain stable English identifiers only.
- Email copy is backend email catalog owned.
- Welcome confirmation copy is contract-owned and delivered by backend catalog.

### Profile

Surface IDs:

`TXT-SURF-004`, `TXT-SURF-005`, `TXT-SURF-006`, `TXT-SURF-052`,
`TXT-SURF-056`, `TXT-SURF-102`, `TXT-SURF-116`

Mapping targets:

| Current surface | Target classification | Canonical target |
|---|---|---|
| Profile page title and form labels | canonical backend text ID target | `profile.page.title`, `profile.form.display_name.label`, `profile.form.bio.label` |
| Profile password section | canonical backend text ID target | `profile.password.change_action`, `profile.password.change_title`, `profile.password.reset_status.*` |
| Profile save/status/failure copy | canonical backend text ID target | `profile.save.success`, `profile.save.failure`, `profile.error.*` |
| Profile API failure `profile_not_found` | canonical backend text ID target | `profile.error.profile_not_found` |
| Profile display name | DB-owned content field | `app.profiles.display_name` |
| Profile bio | DB-owned content field | `app.profiles.bio` |
| Account email when projected | DB-owned user content field | `auth.users.email` or `app.auth_subjects.email` projection only |
| Public profile labels | canonical backend text ID target | `profile.public.*`, `community.profile.*` |
| Logout section | canonical backend text ID target | `profile.logout.*` |
| Teacher card display name | DB-owned user content field | profile projection through backend read composition |

Known problem coverage:

- `Byt lösenord`/password change text maps to
  `profile.password.change_action`.
- The text ID is ASCII and internal; the downstream catalog value must be
  Swedish UTF-8 and must not originate in frontend code.
- Profile DB fields remain DB-owned and are not recoded as catalog text.

### Checkout, Payments, And Commerce

Surface IDs:

`TXT-SURF-003`, `TXT-SURF-023`, `TXT-SURF-024`, `TXT-SURF-025`,
`TXT-SURF-026`, `TXT-SURF-027`, `TXT-SURF-028`, `TXT-SURF-029`,
`TXT-SURF-030`, `TXT-SURF-031`, `TXT-SURF-032`, `TXT-SURF-033`,
`TXT-SURF-034`, `TXT-SURF-035`, `TXT-SURF-036`, `TXT-SURF-097`,
`TXT-SURF-098`, `TXT-SURF-121`

Mapping targets:

| Current surface | Target classification | Canonical target |
|---|---|---|
| Membership checkout headline | canonical backend text ID target | `checkout.membership.headline` |
| Trial/card line | canonical backend text ID target | `checkout.membership.trial_card_line` |
| Membership contents list | canonical backend text ID target | `checkout.membership.contents.*` |
| Trust copy | canonical backend text ID target | `checkout.membership.trust_line` |
| Payment CTA | canonical backend text ID target | `checkout.membership.primary_action` |
| Embedded checkout loading | canonical backend text ID target | `checkout.embedded.loading` |
| Embedded checkout unsupported state | canonical backend text ID target | `checkout.embedded.unsupported` |
| Checkout waiting/retry/cancel/post-confirmation | canonical backend text ID target | `checkout.return.waiting`, `checkout.return.retry_action`, `checkout.cancel.body`, `checkout.return.confirmed` |
| Landing checkout return page title/status | canonical backend text ID target | `checkout.return.title`, `payments.status.waiting`, `payments.status.failed`, `payments.status.confirmed` |
| Paywall and booking prompt copy | canonical backend text ID target | `checkout.paywall.*`, `checkout.booking.*` |
| Billing/subscription/checkout failures | canonical backend text ID target | `checkout.error.*`, `payments.error.*` |
| Course/bundle checkout copy and failures | canonical backend text ID target plus DB field | `checkout.course.*`, `checkout.bundle.*`; `app.course_bundles.title` |
| Provider session/order/payment identifiers | non-user-facing identifier | `session_id`, `order_id`, provider payment references; never rendered as copy |
| Order/payment event metadata | non-user-facing identifier | `app.orders.*`, `app.payments.*`, `app.payment_events.*`, `app.billing_logs.*` |

Known problem coverage:

- Checkout membership UI maps to backend Stripe/payment catalog IDs.
- Landing checkout return/status copy maps to backend-owned checkout/payment
  IDs.
- `session_id`, `order_id`, backend, and webhook terms are identifiers only
  and must not render as product text.
- Bundle title stays `db_domain_content`.

### Landing And Legal

Surface IDs:

`TXT-SURF-037`, `TXT-SURF-038`, `TXT-SURF-039`, `TXT-SURF-040`,
`TXT-SURF-041`, `TXT-SURF-042`, `TXT-SURF-043`, `TXT-SURF-044`,
`TXT-SURF-045`, `TXT-SURF-046`, `TXT-SURF-047`, `TXT-SURF-048`,
`TXT-SURF-122`

Mapping targets:

| Current surface | Target classification | Canonical target |
|---|---|---|
| Landing hero, sections, CTA, product cards | canonical backend text ID target | `landing_legal.landing.*` |
| Public legal page copy | canonical backend text ID target | `landing_legal.privacy.*`, `landing_legal.terms.*`, `landing_legal.gdpr.*` |
| Static HTML fallback legal/landing copy | canonical backend text ID target | same IDs as typed landing/legal surfaces; fallback authority forbidden |
| Shared legal footer links | canonical backend text ID target | `landing_legal.footer.terms_label`, `landing_legal.footer.privacy_label`, `landing_legal.footer.data_deletion_label` |
| Landing dynamic course/service/teacher data | DB-owned content field | course/service/profile fields through typed backend landing API |
| Landing route product copy | canonical backend text ID target | `landing_legal.api.*` |

Known problem coverage:

- Legal/footer link labels are contract text and backend catalog delivered.
- English legal labels are non-compliant until cutover.
- Landing technical implementation copy is forbidden as ordinary product UI.

### Home And Community

Surface IDs:

`TXT-SURF-049`, `TXT-SURF-050`, `TXT-SURF-051`, `TXT-SURF-053`,
`TXT-SURF-054`, `TXT-SURF-055`, `TXT-SURF-057`, `TXT-SURF-115`,
`TXT-SURF-119`, `TXT-SURF-127`, `TXT-SURF-128`

Mapping targets:

| Current surface | Target classification | Canonical target |
|---|---|---|
| Home dashboard chrome, empty states, feed/service states | canonical backend text ID target | `home.dashboard.*`, `home.feed.*`, `home.services.*` |
| Certification gate text | canonical backend text ID target | `home.certification.*` |
| Community navigation/chrome | canonical backend text ID target | `community.home.*`, `community.navigation.*` |
| Teacher/service/profile labels | canonical backend text ID target | `community.teacher.*`, `community.service.*`, `community.profile.*` |
| Tarot and service detail states | canonical backend text ID target | `community.tarot.*`, `community.service_detail.*` |
| Community route failures | canonical backend text ID target | `community.error.*` |
| Feed route failures | canonical backend text ID target | `home.feed.error.*` |
| Service/teacher/profile display content | DB-owned content field | service, course, and profile fields through backend read composition |

### Course And Lesson

Surface IDs:

`TXT-SURF-058`, `TXT-SURF-059`, `TXT-SURF-060`, `TXT-SURF-061`,
`TXT-SURF-062`, `TXT-SURF-063`, `TXT-SURF-064`, `TXT-SURF-065`,
`TXT-SURF-100`, `TXT-SURF-114`, `TXT-SURF-120`, `TXT-SURF-139`

Mapping targets:

| Current surface | Target classification | Canonical target |
|---|---|---|
| Course catalog chrome, empty, error states | canonical backend text ID target | `course_lesson.catalog.*`, `course_lesson.error.*` |
| Course intro and detail chrome | canonical backend text ID target | `course_lesson.intro.*`, `course_lesson.detail.*` |
| Intro redirect/loading/error | canonical backend text ID target | `course_lesson.redirect.*` |
| Course access gate states | canonical backend text ID target | `course_lesson.access_gate.*` |
| Lesson view labels, errors, media states | canonical backend text ID target | `course_lesson.lesson.*` |
| Course route failures | canonical backend text ID target | `course_lesson.error.*` |
| Course title | DB-owned content field | `app.courses.title` |
| Course short description | DB-owned content field | `app.course_public_content.short_description` |
| Lesson title | DB-owned content field | `app.lessons.lesson_title` |
| Lesson markdown/content | DB-owned content field | `app.lesson_contents.content_markdown` |
| Course card labels | canonical backend text ID target plus DB fields | `course_lesson.card.*`; course/profile DB fields |
| Read projection fields | DB-owned content field | projection of source table fields only |

### Studio, Editor, And Home Player

Surface IDs:

`TXT-SURF-066`, `TXT-SURF-067`, `TXT-SURF-068`, `TXT-SURF-069`,
`TXT-SURF-070`, `TXT-SURF-071`, `TXT-SURF-072`, `TXT-SURF-073`,
`TXT-SURF-074`, `TXT-SURF-075`, `TXT-SURF-076`, `TXT-SURF-077`,
`TXT-SURF-078`, `TXT-SURF-079`, `TXT-SURF-080`

Mapping targets:

| Current surface | Target classification | Canonical target |
|---|---|---|
| Studio entry/title/role errors | canonical backend text ID target | `studio_editor.entry.*`, `studio_editor.error.*` |
| Teacher home and dashboard labels | canonical backend text ID target | `studio_editor.teacher_home.*` |
| Course editor labels, validation, preview, save states | canonical backend text ID target | `studio_editor.course_editor.*`, `studio_editor.validation.*`, `studio_editor.save.*` |
| Editor media controls | canonical backend text ID target | `studio_editor.media_controls.*` |
| Lesson media preview states | canonical backend text ID target | `studio_editor.lesson_media_preview.*` |
| Profile media page copy | canonical backend text ID target | `studio_editor.profile_media.*` |
| Cover upload card | canonical backend text ID target | `studio_editor.cover_upload.*` |
| WAV upload and replace dialog | canonical backend text ID target | `studio_editor.audio_upload.*`, `studio_editor.audio_replace.*` |
| Home-player upload dialog | canonical backend text ID target plus DB field | `home.player_upload.*`; `app.home_player_uploads.title` |
| Studio calendar/session UI | blocked until active session text contract for future-facing session copy; DB fields remain DB-owned if contract exists | `future_blocked.session.*` until accepted contract |
| Studio session title/description model fields | DB-owned content field | session title/description only after explicit studio session contract |
| Studio route/editor failures | canonical backend text ID target | `studio_editor.error.*`, `studio_editor.status.*` |
| Home-player course link title | DB-owned content field | `app.home_player_course_links.title` |

Known problem coverage:

- Studio/admin technical copy must not render raw backend, endpoint, or storage
  language.
- Backend route/service failures map to catalog error/status IDs.
- DB content such as lesson content and home-player titles stays DB-owned.

### Admin And Media System

Surface IDs:

`TXT-SURF-081`, `TXT-SURF-082`, `TXT-SURF-083`, `TXT-SURF-084`,
`TXT-SURF-085`, `TXT-SURF-086`, `TXT-SURF-087`, `TXT-SURF-088`,
`TXT-SURF-089`, `TXT-SURF-090`, `TXT-SURF-091`, `TXT-SURF-092`,
`TXT-SURF-093`, `TXT-SURF-094`, `TXT-SURF-125`, `TXT-SURF-126`,
`TXT-SURF-133`, `TXT-SURF-134`, `TXT-SURF-135`, `TXT-SURF-136`,
`TXT-SURF-137`, `TXT-SURF-138`, `TXT-SURF-140`

Mapping targets:

| Current surface | Target classification | Canonical target |
|---|---|---|
| Admin teacher-role UI | canonical backend text ID target | `admin.teacher_role.*` |
| Admin settings/bootstrap UI | canonical backend text ID target | `admin.settings.*`, `admin.bootstrap.*` |
| Admin route/permission failures | canonical backend text ID target | `admin.error.admin_required`, `admin.error.forbidden`, `admin.error.*` |
| Media control plane product-visible admin UI | canonical backend text ID target | `media_system.control_plane.*` |
| Controller video block/media player/preview labels | canonical backend text ID target | `media_system.video.*`, `media_system.audio.*`, `media_system.preview.*` |
| Network image/media repository/media service failures | canonical backend text ID target | `media_system.error.*` |
| Media upload/API route failures | canonical backend text ID target | `media_system.upload.error.*`, `media_system.api.error.*` |
| Media resolver failure details | split target | product-visible failure uses `media_system.error.*`; diagnostics stay non-user-facing |
| Media asset error message and resolution failure reason | non-user-facing identifier | `app.media_assets.error_message`, `app.media_resolution_failures.reason`; must not render as ordinary product copy |
| MCP tool descriptions and observability metadata | non-user-facing identifier | operator-only MCP/diagnostic identifiers |
| Runtime support inert metadata | non-user-facing identifier | `app.payment_events.*`, `app.billing_logs.*`, `app.media_events.*`, `app.auth_events.*` |

Known problem coverage:

- Admin technical copy maps to backend catalog IDs if product-visible.
- Control-plane and MCP diagnostics are identifiers only unless a separate
  operator UI contract classifies them.

### Future-Facing Blocked Surfaces

Surface IDs:

`TXT-SURF-095`, `TXT-SURF-096`, `TXT-SURF-129`, `TXT-SURF-130`,
`TXT-SURF-131`, `TXT-SURF-132`

Mapping targets:

| Current surface | Target classification | Canonical target |
|---|---|---|
| Messages list | blocked / missing contract authority | `future_blocked.messages.*`; no catalog values until explicit messages contract exists |
| Chat UI | blocked / missing contract authority | `future_blocked.chat.*`; DB user message content remains unconfirmed until contract exists |
| Notifications route text | blocked / missing contract authority | `future_blocked.notifications.*` |
| Events route text | blocked / missing contract authority | `future_blocked.events.*` |
| Seminar route text | blocked / missing contract authority | `future_blocked.seminars.*` |
| Session slots route text | blocked / missing contract authority | `future_blocked.session_slots.*` |

Rules:

- These surfaces are inventoried and classified, but catalog value population
  is blocked until active product text contracts exist.
- DB fields for these surfaces may not be rendered as product copy until their
  contract-owned render rules exist.

### MVP, Shared Widgets, And Global System Text

Surface IDs:

`TXT-SURF-099`, `TXT-SURF-101`, `TXT-SURF-103`, `TXT-SURF-104`,
`TXT-SURF-105`, `TXT-SURF-106`, `TXT-SURF-107`, `TXT-SURF-108`,
`TXT-SURF-109`, `TXT-SURF-110`, `TXT-SURF-111`, `TXT-SURF-112`,
`TXT-SURF-113`, `TXT-SURF-117`, `TXT-SURF-118`

Mapping targets:

| Current surface | Target classification | Canonical target |
|---|---|---|
| MVP shell UI labels | canonical backend text ID target | `mvp_shared.shell.*` |
| MVP login/register labels and errors | canonical backend text ID target | `mvp_shared.auth.*`, `auth.error.*` |
| Not-found page | canonical backend text ID target | `global_system.not_found.*` |
| Auth boot/loading state | canonical backend text ID target | `global_system.auth_boot.*` |
| Global snackbar text | inherited from caller text class | `global_system.snackbar.*` only for backend-owned global statuses |
| Localization fallback | blocked violation until removed | no English fallback catalog authority |
| Frontend error fallback map | canonical backend text ID target for replacement; current frontend map invalid | `global_system.error.*` and domain-specific error IDs |
| Raw `error.toString()` helpers | canonical backend error text only; raw exception text forbidden | no frontend text ID authority |
| Shared scaffold/nav chrome | canonical backend text ID target | `global_system.navigation.*` |
| Brand wordmark/text | canonical backend text ID target if rendered as copy | `global_system.brand.name` |
| Card text renderer | inherited DB/catalog provenance | no local text authority |
| AI helper default action | canonical backend text ID target if product-visible | `global_system.action.ok` |
| Global backend error handler | canonical backend text ID target | `global_system.error.internal`, `global_system.error.unavailable` |

Rules:

- Shared render helpers do not own text.
- Caller provenance must decide whether a rendered value is catalog-owned,
  DB-owned, or blocked.
- Frontend fallback labels remain violations until cutover.

## 5. DB-Owned Content Field Registry

The following fields are not catalog text IDs. They remain DB-owned content
only when delivered through backend read composition.

| Field | Authority class | Canonical owner | TXT-001 coverage |
|---|---|---|---|
| `app.profiles.display_name` | `db_user_content` | Profile projection contract | TXT-SURF-006, TXT-SURF-020, TXT-SURF-052, TXT-SURF-102, TXT-SURF-116 |
| `app.profiles.bio` | `db_user_content` | Profile projection contract | TXT-SURF-006, TXT-SURF-020, TXT-SURF-052, TXT-SURF-102 |
| projected account email | `db_user_content` | Auth/profile projection contracts | TXT-SURF-006 |
| `app.courses.title` | `db_domain_content` | Course contracts | TXT-SURF-064, TXT-SURF-114, TXT-SURF-139 |
| `app.course_public_content.short_description` | `db_domain_content` | Course public surface contract | TXT-SURF-064, TXT-SURF-139 |
| `app.lessons.lesson_title` | `db_domain_content` | Course/lesson contracts | TXT-SURF-065, TXT-SURF-139 |
| `app.lesson_contents.content_markdown` | `db_domain_content` | Course/lesson editor contract | TXT-SURF-065, TXT-SURF-068, TXT-SURF-139 |
| `app.home_player_uploads.title` | `db_domain_content` | Home audio contracts | TXT-SURF-080 |
| `app.home_player_course_links.title` | `db_domain_content` | Home audio contracts | TXT-SURF-080 |
| `app.course_bundles.title` | `db_domain_content` | Commerce/course bundle contracts | TXT-SURF-097, TXT-SURF-098, TXT-SURF-121 |

DB verification status:

- `pending_txt004_db_value_verification`

Rules:

- These fields must not be moved into catalog values.
- These fields must pass later UTF-8 and rendered-language gates.
- Frontend may render these only after backend read composition supplies typed
  fields with provenance.

## 6. Non-User-Facing Identifier Registry

The following are identifiers, not product text:

| Identifier family | Coverage | Render rule |
|---|---|---|
| Auth/onboarding error codes | TXT-SURF-002, TXT-SURF-013 through TXT-SURF-015 | May drive backend envelope, must not render as message copy |
| Entry-state values | TXT-SURF-022 | May route, must not render as product copy |
| Stripe/provider correlation IDs | TXT-SURF-024, TXT-SURF-029, TXT-SURF-031, TXT-SURF-098 | Must not render as product copy |
| Order/payment IDs and event metadata | TXT-SURF-098, TXT-SURF-140 | Must not render as product copy |
| Media diagnostic fields | TXT-SURF-093, TXT-SURF-094, TXT-SURF-140 | Operator/control-plane only unless separately contracted |
| MCP tool descriptions/diagnostics | TXT-SURF-133 through TXT-SURF-138 | Operator-only; not ordinary product UI copy |
| Route names, enum values, test IDs, telemetry keys | inherited across inventory | Internal only |

## 7. Cutover Rules

Later implementation tasks MUST follow these rules:

- Frontend is renderer only.
- Frontend must never originate, translate, repair, synthesize, or fallback
  user-facing product text.
- No frontend hardcoded product strings may remain after renderer cutover.
- No frontend fallback messages may remain after renderer cutover.
- No `error.toString()` or raw exception rendering is allowed.
- No English product copy is allowed outside operator-only surfaces and
  generated English prompts.
- Backend-owned catalog text values must be Swedish UTF-8.
- Contract text must remain contract-governed.
- DB-owned content must stay DB-owned and must not be recoded as catalog text.
- Provider, route, webhook, backend, storage, SQL, and framework identifiers
  must not render as ordinary product copy.
- Runtime implementation must not claim compliance until source, DB, API,
  rendered UI, email, and Stripe gates pass.

## 8. Stop Conditions

STOP downstream implementation if any of these occur:

- a TXT-001 surface is missing from this mapping,
- a text ID is missing for a catalog-owned rendered value,
- a DB field is assigned to catalog text authority,
- a non-user-facing identifier is rendered as ordinary product copy,
- an exact-copy legal or product text value lacks active contract ownership,
- a future-facing surface is populated without an active product text contract,
- canonical catalog values are not Swedish,
- source artifacts or runtime payloads are encoding-unsafe,
- frontend is named as a valid authority,
- an English fallback or frontend fallback path remains,
- `detail`, `error`, `description`, stack traces, provider IDs, or raw
  exception strings can reach ordinary UI.

## 9. Coverage Verification

All TXT-001 inventory rows are covered by the groups above:

- TXT-SURF-001 through TXT-SURF-140 are represented.
- DB-owned rendered fields are retained as DB-owned.
- Non-user-facing identifiers are not treated as catalog text.
- Future-facing surfaces are blocked rather than silently inferred.
- Frontend is not established as a valid text authority.
- Product text governed by catalog authority is Swedish-only.
- Operator execution text and generated prompts remain English.

## 10. Ready Status

TXT-002 catalog structure and mapping coverage are complete for the inspected
TXT-001 baseline.

Ready for the next task only under these constraints:

- exact Swedish catalog values must still be populated and verified by a later
  task,
- encoding gates must still verify contracts, catalog values, source files,
  runtime responses, email, Stripe payloads, and rendered UI,
- DB values must still be verified by TXT-004 or equivalent DB text gate,
- future-facing blocked surfaces must not receive catalog values until their
  active product text contracts exist.
