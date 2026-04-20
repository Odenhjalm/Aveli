# Backend Text Catalog Contract

TYPE: OWNER
DEPENDS_ON: [TXT-001]
MODE: execute
STATUS: ACTIVE

This contract defines the canonical backend-owned product text catalog structure
for Aveli. It composes with `system_text_authority_contract.md` and does not
change frontend, backend, API, DB, email, Stripe, or runtime behavior by
itself.

This contract owns the catalog model, text ID rules, domain structure,
provenance requirements, DB-content exclusions, and deterministic cutover
rules for later implementation tasks.

## 1. Authority Inputs

Authoritative inputs for this contract are:

- `actual_truth/contracts/system_text_authority_contract.md`
- `actual_truth/DETERMINED_TASKS/text_authority_encoding_alignment/TXT-001_TEXT_SURFACE_INVENTORY.md`
- `actual_truth/Aveli_System_Decisions.md`
- `actual_truth/aveli_system_manifest.json`
- Active domain contracts under `actual_truth/contracts/`

The generated artifact
`actual_truth/DETERMINED_TASKS/text_authority_encoding_alignment/TEXT_AUTHORITY_ENCODING_CORRECTION_PLAN.md`
is planning context only. It does not override active contracts or the current
task input.

## 2. Catalog Scope

The backend text catalog is the only valid runtime owner for user-facing
product text that is not a contract-classified DB content field.

The catalog owns structure and runtime delivery targets for:

- `contract_text`
- `backend_error_text`
- `backend_status_text`
- `backend_email_text`
- `backend_stripe_text`

The catalog does not own rendered DB content values. These remain classified as:

- `db_domain_content`
- `db_user_content`

The catalog does not own non-rendered identifiers. These remain classified as:

- `non_user_facing_identifier`

## 3. Canonical Entry Model

Every catalog-owned text entry MUST have this logical shape:

```text
text_id: stable ASCII dotted identifier
domain: catalog domain
authority_class: one of the allowed backend-owned classes
canonical_owner: backend_text_catalog
source_contract: active contract path
surface_ids: TXT-001 inventory IDs
language: sv-SE
value_status: contract_defined | pending_txt003_value | blocked_missing_contract
interpolation_keys: declared list, empty when not needed
forbidden_render_fields: declared list, empty when not needed
delivery_surface: API route, email template, Stripe payload, or backend bundle
render_surface: frontend/email/payment surface or none
```

Every DB-owned rendered content entry MUST have this logical shape:

```text
db_field: schema.table.column or contracted field family
authority_class: db_domain_content | db_user_content
canonical_owner: source table contract plus backend read composition
source_contract: active contract path
surface_ids: TXT-001 inventory IDs
language_policy: value must be UTF-8; product-visible DB content must pass later language gate
value_status: pending_txt004_db_value_verification
delivery_surface: typed backend read composition only
render_surface: frontend renderer surface
```

Every non-user-facing identifier entry MUST have this logical shape:

```text
identifier_scope: route | enum | code | provider_id | telemetry | operator_tool | test_id
authority_class: non_user_facing_identifier
canonical_owner: owning implementation or contract
surface_ids: TXT-001 inventory IDs
render_rule: MUST NOT render as ordinary product copy
```

## 4. Text ID Rules

Text IDs are internal identifiers. They are never product copy.

Rules:

- Text IDs MUST be ASCII.
- Text IDs MUST use lowercase dotted segments.
- Text IDs MUST start with a catalog domain.
- Text IDs MUST be stable across frontend and backend cutover.
- Text IDs MUST NOT contain Swedish product wording.
- Text IDs MUST NOT be rendered to ordinary users.
- Text IDs MAY be logged or tested only as non-user-facing identifiers.

Allowed pattern:

```text
<domain>.<surface>.<element>[.<state_or_variant>]
```

Examples:

```text
profile.password.change_action
auth.login.title
checkout.membership.headline
landing_legal.footer.privacy_label
studio_editor.course.save_success
media_system.preview.loading
```

## 5. Domain Structure

The canonical catalog domains are:

| Domain | Scope | Justification |
|---|---|---|
| `auth` | Login, signup, password reset, email verification, auth settings, auth failures | TXT-SURF-007 through TXT-SURF-015, TXT-SURF-101, TXT-SURF-124 |
| `onboarding` | Create-profile, welcome, onboarding status and failures | TXT-SURF-001, TXT-SURF-020, TXT-SURF-021 |
| `profile` | Profile UI chrome, profile save/failure/status, password action, logout/profile projection labels | TXT-SURF-004 through TXT-SURF-006, TXT-SURF-052, TXT-SURF-056, TXT-SURF-102, TXT-SURF-116 |
| `checkout` | Membership checkout start, embedded shell, cancel, return, course/bundle checkout product states | TXT-SURF-003, TXT-SURF-023 through TXT-SURF-036, TXT-SURF-097, TXT-SURF-121 |
| `payments` | Payment result, post-confirmation, waiting, retry, provider-status-facing copy | TXT-SURF-029 through TXT-SURF-036, TXT-SURF-098 |
| `landing_legal` | Landing, public legal pages, legal footer links, data deletion link label | TXT-SURF-037 through TXT-SURF-048, TXT-SURF-122 |
| `home` | Home dashboard, feed, home player, certification gate, home shell | TXT-SURF-049, TXT-SURF-057, TXT-SURF-075, TXT-SURF-080, TXT-SURF-128 |
| `community` | Community home, teacher/service/profile public surfaces, service cards, feed/service route copy | TXT-SURF-050 through TXT-SURF-055, TXT-SURF-115, TXT-SURF-119, TXT-SURF-127 |
| `course_lesson` | Course catalog, course detail, lesson view, access gates, course and lesson route failures | TXT-SURF-058 through TXT-SURF-065, TXT-SURF-100, TXT-SURF-114, TXT-SURF-120, TXT-SURF-139 |
| `studio_editor` | Studio entry, teacher home, course editor, media controls, editor upload/preview/dialog states, studio sessions | TXT-SURF-066 through TXT-SURF-080 |
| `admin` | Admin teacher-role, admin settings, permission failures | TXT-SURF-081, TXT-SURF-082, TXT-SURF-084, TXT-SURF-085 |
| `media_system` | Media UI, media failures, media control plane product-visible states, upload/media route failures | TXT-SURF-083, TXT-SURF-086 through TXT-SURF-094, TXT-SURF-125, TXT-SURF-126 |
| `email` | Verification, reset, referral, and backend-emitted user email text | TXT-SURF-016 through TXT-SURF-019, TXT-SURF-123, TXT-SURF-124 |
| `mvp_shared` | MVP shell and shared widgets that remain product-visible during migration | TXT-SURF-099 through TXT-SURF-118 |
| `global_system` | Global not-found, boot, snackbar, app chrome, logo/brand text, global backend error handling | TXT-SURF-103 through TXT-SURF-112, TXT-SURF-117, TXT-SURF-118 |
| `future_blocked` | Future-facing messages, notifications, events, seminars, session slots | TXT-SURF-095, TXT-SURF-096, TXT-SURF-129 through TXT-SURF-132 |

No new domain may be added without:

- one or more TXT-001 inventory IDs,
- an active source contract,
- a canonical backend owner,
- a Swedish-only product text language policy,
- and explicit DB/content exclusion rules.

## 6. Domain Namespace Ownership

| Authority class | Catalog ownership rule | Backend delivery required | DB rendering permitted |
|---|---|---|---|
| `contract_text` | Catalog entry MUST reference active contract text owner | Yes | No |
| `backend_error_text` | Catalog entry MUST reference error code and failure contract | Yes | No |
| `backend_status_text` | Catalog entry MUST reference state/status owner | Yes | No |
| `backend_email_text` | Catalog entry MUST reference email namespace and template part | Backend email service only | No, except declared interpolation values |
| `backend_stripe_text` | Catalog entry MUST reference checkout/payment contract | Yes, or backend-owned Stripe payload | No, except sold item title fields classified as DB content |
| `db_domain_content` | Not catalog-owned; source table contract and backend read composition own value | Yes, through read composition | Yes, only for classified field |
| `db_user_content` | Not catalog-owned; source table contract and backend read composition own value | Yes, through read composition | Yes, only for classified field |
| `non_user_facing_identifier` | Not catalog-owned as product copy | No product delivery | No product rendering |

## 7. Provenance Requirements

Every catalog mapping MUST record:

- `surface_ids`
- `text_id` or `db_field` or `identifier_scope`
- `domain`
- `authority_class`
- `source_contract`
- `canonical_owner`
- `current_origin`
- `required_cutover_target`
- `compliance_state`
- `violation_type` when non-compliant

Rules:

- A single rendered text value MUST map to exactly one authority class.
- A file-level inventory row MAY map to multiple entries only when the file
  contains multiple independent rendered values with different authorities.
- `text_id` and `db_field` are mutually exclusive for the same rendered value.
- DB-owned fields MUST NOT be reassigned into catalog text IDs.
- Non-user-facing identifiers MUST NOT become fallback product text.
- Missing provenance is a STOP condition.

## 8. Canonical Cutover Order

This contract authorizes artifact creation only. Runtime cutover remains
blocked until later implementation tasks.

The deterministic cutover order is:

1. TXT-002 creates this catalog structure and the inventory-to-catalog mapping.
2. The next catalog-value task populates exact Swedish values for every
   catalog-owned text ID and records allowed interpolation keys.
3. The encoding gate verifies all source artifacts, catalog values, templates,
   and runtime text payloads as valid UTF-8.
4. The DB text gate verifies DB server/client encoding and rendered DB field
   values without moving DB-owned content into the catalog.
5. Backend implementation exposes catalog-owned text bundles, email text,
   Stripe text, errors, and status messages.
6. API envelope alignment carries text provenance and blocks forbidden raw
   fields.
7. Frontend cutover removes local product text authority and renders only
   backend/catalog or classified DB content.
8. Rendered UI, email, and Stripe gates prove Swedish-only, uncorrupted output.

No step may treat a later task as already complete.

## 9. Forbidden Patterns

This contract forbids:

- frontend text authority,
- frontend fallback product messages,
- frontend error-message maps,
- raw `error.toString()` rendering,
- rendering `detail`, `error`, or `description` as product copy,
- English user-facing product copy,
- ASCII-degraded Swedish,
- mojibake,
- storing UI chrome, failure messages, or fallback copy in DB content fields,
- recoding DB-owned content fields as catalog text,
- rendering provider IDs, route names, webhook terms, session IDs, order IDs,
  storage paths, stack traces, SQL terms, or framework exceptions as ordinary
  product copy.

## 10. Stop Conditions

Downstream implementation MUST stop if any of the following is true:

- a TXT-001 surface lacks a catalog mapping, DB mapping, identifier mapping,
  or explicit blocked classification,
- a catalog-owned text surface has no text ID,
- a DB-owned field is assigned to a catalog text ID,
- a non-user-facing identifier is renderable as product copy,
- a source contract is missing or inactive,
- a product text value is not defined as Swedish-only,
- an operator prompt is not English and copy-paste-ready,
- a source artifact is encoding-unsafe,
- a future-facing surface lacks an active product text contract,
- legal text ownership remains unresolved,
- frontend is named as a valid product text authority,
- a fallback path can originate user-facing product text.

## 11. Final Assertion

The backend text catalog is the canonical runtime authority for all
non-DB-owned Aveli product text. The frontend is renderer only. DB-owned
domain and user content remains DB-owned and must flow only through backend
read composition. All user-facing product text values governed by this model
are Swedish-only. This contract does not claim runtime compliance and does not
authorize partial cutover.
