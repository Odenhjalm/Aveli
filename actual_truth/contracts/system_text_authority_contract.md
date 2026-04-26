# System Text Authority Contract

## STATUS

ACTIVE.

This contract defines the system-wide authority model for user-facing product
text in Aveli. It composes with all active contracts under
`actual_truth/contracts/` and does not redefine their domain ownership rules.

This contract owns text authority, text provenance, frontend rendering
constraints, and downstream cutover preconditions for TXT-001 through TXT-010.

## 1. CONTRACT LAW

- All user-facing product text in Aveli MUST be Swedish.
- Generated operator prompts MUST be copy-paste-ready English.
- Contracts under `actual_truth/contracts/` are the only canonical contract
  source for product text ownership.
- The frontend is never a valid authority for user-facing product text.
- Frontend code may render text, but it MUST NOT originate, repair, translate,
  localize, map, fallback, or synthesize user-facing product text.
- Backend runtime text delivery is required for every product UI text value
  that is not explicitly classified as DB-rendered content.
- Database text may be rendered only when the exact field is classified by
  contract as rendered domain content or rendered user content.
- Missing text authority MUST fail closed. No layer may invent fallback text.

## 2. ALLOWED TEXT AUTHORITY CHAIN

The only allowed product text authority chain is:

```text
contract text ID or classified DB field
-> backend catalog or backend read composition
-> typed API response or backend-owned email/payment emission
-> frontend render model
-> UI
```

For DB-rendered content, the allowed chain is:

```text
contract-classified DB field
-> backend read composition
-> typed API response
-> frontend render model
-> UI
```

No other chain is valid.

## 3. AUTHORITY CLASSES

Every user-facing text value MUST have exactly one authority class.

### `contract_text`

Allowed:

- Static product UI copy.
- Headings.
- Labels.
- CTA text.
- Empty states.
- Loading states.
- Help text.
- Accessibility labels.
- Legal link labels.
- Onboarding confirmation text.

Origin:

- Contract text ID under `actual_truth/contracts/`.

Runtime delivery:

- Required through backend catalog or backend-composed surface text bundle.

DB rendering:

- Forbidden.

Frontend role:

- Render only.

Forbidden:

- Hardcoded frontend literals.
- ARB/localization fallback authority.
- Client-side copy maps.
- Client-side text repair.

### `backend_error_text`

Allowed:

- User-facing validation errors.
- Auth, onboarding, profile, checkout, media, studio, editor, landing, and
  route-level failure messages.
- Field error messages.

Origin:

- Contract-defined error code and Swedish message mapping.
- Backend text catalog or contract-owned backend failure map.

Runtime delivery:

- Required through canonical backend error envelope or typed backend response.

DB rendering:

- Forbidden.

Frontend role:

- Render only.

Forbidden:

- Raw framework payloads.
- `detail`, `error`, or `description` as frontend authority.
- `error.toString()` or exception text in UI.
- Frontend error-message maps.

### `backend_status_text`

Allowed:

- Backend-owned state text for app surfaces.
- Waiting, retry, cancellation, completion, unsupported, unavailable, and
  state-transition messages.
- Backend-owned snackbar/dialog/status text.

Origin:

- Contract text ID plus backend catalog.

Runtime delivery:

- Required.

DB rendering:

- Forbidden.

Frontend role:

- Render only.

Forbidden:

- Local frontend status strings.
- Client-side fallback status wording.
- Technical implementation language in product UI.

### `backend_email_text`

Allowed:

- Email subject lines.
- Email headings.
- Email body text.
- Email CTA text.
- Plain-text email alternatives.

Origin:

- Contract text ID plus backend email catalog/template composition.

Runtime delivery:

- Backend email service only.

DB rendering:

- Forbidden except for contract-classified interpolation values such as user
  email or referral URL.

Frontend role:

- None.

Forbidden:

- Frontend-authored email copy.
- Corrupted or ASCII-degraded Swedish.
- Unclassified interpolation text.

### `backend_stripe_text`

Allowed:

- Membership checkout product copy.
- Stripe embedded checkout shell copy.
- Payment waiting, cancel, retry, post-confirmation, and payment failure copy.
- Aveli-controlled product labels sent to Stripe when they may be user-visible.

Origin:

- Commerce and checkout contracts plus backend catalog.

Runtime delivery:

- Backend checkout/payment surface or backend-owned checkout shell text bundle.

DB rendering:

- Forbidden unless a contract explicitly classifies a sold item title as
  DB-rendered domain content.

Frontend role:

- Render only. Stripe is payment renderer and event emitter only.

Forbidden:

- Hosted/raw Stripe checkout as ordinary membership text fallback.
- Stripe success as membership or app-entry authority.
- Provider identifiers rendered as product copy.
- `session_id`, `order_id`, webhook, or backend implementation language in
  product UI.

### `db_domain_content`

Allowed:

- Contract-classified authored or domain content fields, including course
  titles, course public descriptions, lesson titles, lesson markdown, home
  player titles, course-linked home audio titles, and bundle titles.

Origin:

- Explicitly contracted DB field.

Runtime delivery:

- Required through backend read composition and typed API response.

DB rendering:

- Permitted only for the classified field.

Frontend role:

- Render only.

Forbidden:

- UI chrome stored in DB.
- Failure messages stored in DB.
- Fallback text stored in DB.
- Raw table access from frontend.
- Unclassified text fields rendered in UI.

### `db_user_content`

Allowed:

- Contract-classified user-authored profile or community text, including
  profile display name and bio.

Origin:

- Explicitly contracted DB field written through its canonical backend surface.

Runtime delivery:

- Required through backend read composition and typed API response.

DB rendering:

- Permitted only for the classified field.

Frontend role:

- Render only.

Forbidden:

- Using user content as routing, onboarding, role, membership, or access
  authority.
- Using user content as UI chrome.
- User content fallback for missing product copy.

### `non_user_facing_identifier`

Allowed:

- Route names.
- Error codes.
- Enum values.
- Schema keys.
- Text IDs.
- Provider correlation IDs.
- Telemetry keys.
- Test IDs.
- Internal debug labels when not rendered to product users.

Origin:

- Owning implementation or contract.

Runtime delivery:

- Forbidden as product UI text.

DB rendering:

- Forbidden as product UI text.

Frontend role:

- May carry identifiers for routing, telemetry, and typed rendering, but MUST
  NOT display them as product copy.

Forbidden:

- Rendering identifiers as product text.
- Treating identifiers as fallback text.
- Exposing provider IDs or backend implementation terms in ordinary UI.

## 4. REQUIRED PROVENANCE MODEL

Every rendered user-facing text value MUST have a provenance record with:

- `surface_id`
- `text_id` or `db_field`
- `authority_class`
- `canonical_owner`
- `source_contract`
- `backend_namespace`
- `api_surface` when delivered to frontend
- `db_table` and `db_column` when DB-rendered
- `render_surface`
- `language = sv`
- `interpolation_keys`
- `forbidden_render_fields`

Rules:

- `text_id` and `db_field` are mutually exclusive for a single text value.
- Every interpolation key MUST be contract-declared.
- Frontend MUST receive enough provenance to render without local text logic.
- Missing provenance is a blocking authority violation.

## 5. FORBIDDEN AUTHORITY PATTERNS

The following patterns are always forbidden for user-facing product text:

- Hardcoded frontend product strings.
- Frontend localization as canonical authority.
- English user-facing fallback.
- ASCII-degraded Swedish.
- Mojibake or replacement characters.
- `error.toString()` in UI.
- Rendering raw `detail`, `error`, `description`, raw maps, stack traces, or
  framework exception payloads.
- Frontend-side error-code message maps.
- Frontend-side fallback messages.
- Frontend-side copy repair or translation.
- UI text derived from token claims, route names, provider IDs, or local
  session state.
- Product UI text that exposes backend, webhook, session ID, order ID, raw
  endpoint names, storage paths, SQL/database terms, framework names, or
  provider internals unless the surface is explicitly operator-only.

## 6. SURFACE OWNERSHIP RULES

Profile:

- UI chrome is `contract_text`.
- Profile save/status/failure messages are `backend_status_text` or
  `backend_error_text`.
- `display_name` and `bio` are `db_user_content`.
- Profile media representation remains governed by media contracts and backend
  composition.

Auth and onboarding:

- Page copy is `contract_text`.
- Failure copy is `backend_error_text`.
- Welcome confirmation copy is `contract_text`.
- Post-auth routing text is not owned by frontend.

Checkout and Stripe:

- Ordinary membership checkout copy is `backend_stripe_text`.
- Payment state copy is `backend_stripe_text` or `backend_status_text`.
- Sold course or bundle names may be `db_domain_content` only when delivered
  by backend read composition.

Landing and legal:

- Static public product and legal UI copy is `contract_text`.
- Dynamic course, teacher, or service display data is `db_domain_content` or
  `db_user_content` only when contract-classified.

Home, course, lesson, Studio, and Editor:

- UI chrome, editor controls, upload states, preview states, and empty/error
  states are `contract_text`, `backend_status_text`, or `backend_error_text`.
- Course titles, short descriptions, lesson titles, lesson markdown, home
  player titles, and bundle titles are `db_domain_content`.
- Course Entry/Gateway CTA labels, disabled/blocked reason text, continuation
  labels, enrollment labels, purchase labels, and rendered price text are
  backend-owned payload text under `backend_status_text` or
  `backend_stripe_text` as appropriate.
- Frontend may render Course Entry/Gateway CTA and price text, but MUST NOT
  originate, translate, format, hide, or infer that text locally.

### Home Player Exact-Copy Failure Surfaces

The following Home Player surfaces are explicit text-authority surfaces:

- Studio Home Player library load failures
- Studio Home Player upload start failures
- Studio Home Player upload save/registration failures
- Studio Home Player upload status-refresh failures
- Studio Home Player upload auth failures
- Studio Home Player processing-terminal failures
- Studio Home Player course-link create/update/delete failures
- learner `/home/audio` load and access failures

Authority law for these surfaces:

- user-facing failure copy MUST be `backend_error_text`
- user-facing progress, waiting, and completion copy MUST be
  `backend_status_text`
- backend may expose stable English `snake_case` error codes only as
  `non_user_facing_identifier`
- backend must not use raw `detail`, raw framework exception text, storage
  errors, provider errors, or transport-library strings as product copy
- frontend must not render raw backend strings for these surfaces
- if a canonical backend error envelope is absent, frontend must render
  backend-owned catalog/status text rather than raw payload text

Auth failure law for Home Player surfaces:

- `401` and `403` on Home Player library, upload, upload-completion, status,
  source-mutation, and learner-feed surfaces are auth failures
- auth failures must resolve to Swedish backend-owned copy
- frontend must not repair auth copy from raw payload text

Media and Admin:

- Product-visible media/admin UI chrome and status text are `contract_text`,
  `backend_status_text`, or `backend_error_text`.
- Operator-only diagnostic identifiers may be `non_user_facing_identifier`
  only when not rendered to ordinary product users.

Email:

- Verification, reset, referral, membership, and notification email text is
  `backend_email_text`.

Backend failures:

- All product-visible backend failures are `backend_error_text`.
- Backend may emit stable English `snake_case` error codes only as
  `non_user_facing_identifier`.

## 7. CUTOVER PRECONDITIONS

TXT-002 Encoding Gate Definition MUST NOT begin until:

- Every in-scope surface is inventoried.
- Every inventoried surface has exactly one required authority class.
- Any unknown surface is recorded as BLOCKED.

TXT-003 Backend Text Catalog Authority MUST NOT begin until:

- All contract text classes are complete.
- Every non-DB product text surface has a canonical backend owner.
- Every exact-copy surface has a contract owner or an explicit BLOCKED status.

TXT-004 Database Text Classification MUST NOT begin until:

- Every DB-rendered field is classified as `db_domain_content`,
  `db_user_content`, or `non_user_facing_identifier`.
- No unclassified DB text field is listed as renderable.

TXT-005 through TXT-010 MUST remain blocked until TXT-002, TXT-003, and TXT-004
produce their required owner truth.

## 8. BLOCKING CONDITIONS

Downstream work is BLOCKED if any of the following remain true:

- A user-facing surface has no inventory row.
- A text value has more than one required authority class.
- Frontend is named as a canonical text authority.
- A DB text field is rendered without classification.
- Product text is allowed in any language other than Swedish.
- A generated operator prompt is not English, plain text, and copy-paste-ready.
- A fallback path can originate user-facing text.

## 9. FINAL ASSERTION

This contract makes backend/catalog or contract-classified DB content the only
valid runtime source for user-facing text. Frontend is renderer only. All
product text is Swedish. Any missing, ambiguous, or conflicting text authority
fails closed.
