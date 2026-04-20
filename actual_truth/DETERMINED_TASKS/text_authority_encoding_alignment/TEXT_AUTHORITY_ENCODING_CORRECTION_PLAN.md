# Text Authority And Encoding Correction Plan

TYPE: AGGREGATE
DEPENDS_ON: []
MODE: generate
STATUS: GENERATED_PLAN_ONLY

## Scope

This plan covers user-facing text authority, encoding integrity, localization,
contract alignment, frontend rendering constraints, backend/API responses,
database-backed text, email templates, Stripe-related surfaces, and
Editor/Studio surfaces.

No source-code implementation is authorized by this artifact.

## Dependency Audit

The correction must execute as a DAG. No task may start until every declared
dependency has passed.

1. TXT-001 Canonical Text Authority Contract
   - TYPE: OWNER
   - DEPENDS_ON: []
   - Owns the system-wide text authority contract and text-surface inventory.

2. TXT-002 Encoding Gate Definition
   - TYPE: OWNER
   - DEPENDS_ON: [TXT-001]
   - Owns file, runtime, API, email, Stripe, and DB encoding enforcement rules.

3. TXT-003 Backend Text Catalog Authority
   - TYPE: OWNER
   - DEPENDS_ON: [TXT-001, TXT-002]
   - Owns backend runtime text catalog, error messages, email text, and surface
     text bundles derived from contract text IDs.

4. TXT-004 Database Text Classification
   - TYPE: OWNER
   - DEPENDS_ON: [TXT-001, TXT-002]
   - Owns classification of every DB-backed user-facing text field as domain
     content, user-authored content, or non-user-facing data.

5. TXT-005 API Text Envelope Alignment
   - TYPE: OWNER
   - DEPENDS_ON: [TXT-003, TXT-004]
   - Owns API response shapes that deliver backend-authored text bundles and
     Swedish canonical failure messages.

6. TXT-006 Frontend Renderer Constraint Cutover
   - TYPE: OWNER
   - DEPENDS_ON: [TXT-005]
   - Owns removal of frontend user-facing hardcoded strings, fallback text,
     error mapping, raw exception rendering, and English locale fallback.

7. TXT-007 Surface Migration
   - TYPE: OWNER
   - DEPENDS_ON: [TXT-006]
   - Owns complete migration of Profile, Auth, Onboarding, Checkout, Landing,
     Legal, Home, Studio, Editor, Media, Admin, Email, and Stripe surfaces to
     backend/contract text authority.

8. TXT-008 Contract Drift Prevention
   - TYPE: GATE
   - DEPENDS_ON: [TXT-001, TXT-003, TXT-005, TXT-006, TXT-007]
   - Blocks any rendered text that lacks contract ownership, backend delivery,
     or DB field classification.

9. TXT-009 Encoding And Localization Verification
   - TYPE: GATE
   - DEPENDS_ON: [TXT-002, TXT-003, TXT-004, TXT-005, TXT-006, TXT-007]
   - Blocks invalid UTF-8, double encoding, mojibake, English user-facing
     output, ASCII-degraded Swedish, and internal technical leakage.

10. TXT-010 Final System Confirmation
    - TYPE: AGGREGATE
    - DEPENDS_ON: [TXT-008, TXT-009]
    - Passes only when no encoding error, frontend authority, contract drift,
      frontend leak, or Swedish-language violation remains anywhere in scope.

## 1. System Model (Text Authority)

Canonical source layers:

1. Contracts under `actual_truth/contracts/`
   - Define every product UI surface, text ID, canonical Swedish value,
     placeholders, allowed interpolation variables, owning route/API surface,
     owning backend catalog namespace, and allowed DB content fields.
   - Define exact copy for contract-owned surfaces such as onboarding welcome,
     auth failures, membership checkout, legal links, email bodies, and
     payment-return states.
   - Define error-code to Swedish-message mapping for every covered failure
     envelope.

2. Backend text catalog
   - Is the only runtime authority for product UI copy, error messages,
     validation messages, email template text, Stripe product-facing copy,
     empty states, loading states, status messages, CTA text, headings,
     semantics labels, and accessibility labels.
   - Must be generated from or validated against contract text IDs.
   - Must fail startup or verification if a contract text ID is missing,
     duplicated, invalidly encoded, not Swedish, or contains forbidden
     technical leakage.

3. Database
   - May originate user-facing text only where a contract classifies a specific
     field as content authority.
   - Allowed DB-originated user-facing content includes only typed domain
     content fields such as profile display name/bio, course title,
     course public short description, lesson title, lesson markdown, and other
     explicitly contracted content fields.
   - DB must not own UI chrome, product copy, error messages, auth messages,
     routing text, fallback text, or payment-state text.
   - Every rendered DB text field must have a contract classification and an
     API field provenance.

4. Frontend
   - Is renderer only.
   - May contain stable non-user-facing identifiers, route names, enum values,
     schema keys, test IDs, and provider integration constants.
   - Must not contain or synthesize user-facing text.
   - Must render only backend-delivered text bundles, backend error messages,
     and contract-classified DB content fields.

Required system-wide text flow:

`contract text ID or DB content field -> backend catalog/composition -> API response -> frontend render model -> UI`

No alternate path is allowed.

## 2. Encoding Policy

Required standard:

- All source files, contracts, generated text catalogs, fixtures, snapshots,
  templates, JSON, ARB files while they exist, HTML, CSS, Dart, TypeScript,
  Python, SQL, Markdown, and task artifacts must be UTF-8.
- UTF-16, UTF-16LE, UTF-16BE, Latin-1, Windows-1252, mixed encodings, and
  invalid UTF-8 byte sequences are forbidden.
- UTF-8 with no BOM is the source-file standard.
- API JSON must be emitted as UTF-8 and must declare UTF-8 where content type
  supports a charset.
- HTML and email MIME bodies must declare UTF-8.
- PostgreSQL `server_encoding` and `client_encoding` must be UTF8.
- Stripe-facing product text and metadata supplied by Aveli must be UTF-8
  and must originate from backend contract text.

Invalid byte blocking:

- Every text file in the authority corpus and implementation corpus must be
  decoded with a strict UTF-8 decoder before merge.
- Any decode failure is a STOP condition.
- Any UTF-16 BOM or non-UTF-8 BOM is a STOP condition.
- Any file excluded from UTF-8 enforcement must be explicitly classified as
  binary; unclassified files block.

Double-encoding blocking:

- Every decoded text payload must be scanned for mojibake markers including
  `Ã`, `Â`, `â€`, `â€™`, and replacement character `�`.
- Swedish-specific canonical terms must be scanned for corrupted and
  ASCII-degraded variants, including password, continue, link, verify,
  required, access, teacher role, administrator, request, field, value,
  too many attempts, and try again.
- Runtime API responses, email bodies, Stripe text payloads, and rendered UI
  text must receive the same scan as source files.
- Any `latin1`, `cp1252`, `utf16`, implicit default-platform encoding,
  manual encode/decode bridge, or JavaScript text decoder without explicit
  UTF-8 justification is a STOP condition for user-facing text paths.

## 3. Migration Strategy

The migration is append-safe, ordered, and non-breaking only while old fields
remain non-rendered compatibility data.

Step 1: Establish the text authority contract.

- Create one system-wide text authority contract or contract addendum under
  `actual_truth/contracts/`.
- Inventory every user-facing surface: frontend pages, backend responses,
  schemas, errors, emails, Stripe checkout, landing/legal, Studio, Editor,
  media/admin surfaces, and DB-backed content fields.
- Assign each string one of these origins:
  - `contract_text`
  - `backend_error_text`
  - `backend_status_text`
  - `backend_email_text`
  - `backend_stripe_text`
  - `db_domain_content`
  - `db_user_content`
  - `non_user_facing_identifier`
- Any string that cannot be classified blocks the migration.

Step 2: Normalize contracts.

- Ensure all canonical contract copy is valid UTF-8.
- Add exact Swedish text IDs for every required heading, label, CTA,
  loading state, empty state, validation state, failure state, accessibility
  label, email phrase, and Stripe/payment state.
- Record allowed placeholders and formatting rules per text ID.
- Record forbidden technical terms per surface, including backend, webhook,
  session_id, order_id, FastAPI, Postgres, RLS, raw endpoint names, and raw
  exception details, unless the target surface is explicitly operator-only.

Step 3: Build backend text ownership.

- Move all product copy, email copy, auth failure messages, validation
  messages, Stripe text, and UI state text into the backend text catalog.
- The backend catalog must expose screen/surface text bundles needed by the
  frontend and must emit contract-owned Swedish messages in API failures.
- Existing route data fields remain available where needed, but frontend
  rendering must not consume old frontend literals.
- Backend must reject missing catalog keys and invalid interpolation variables.

Step 4: Classify and verify DB text.

- Enumerate every DB text column referenced by API responses or frontend
  rendering.
- For system/seed/product text stored in DB, require exact Swedish content and
  no mojibake.
- For user-authored or teacher-authored content, require explicit field
  classification, UTF-8 validity, no mojibake, no replacement characters, and
  Swedish content approval if the field is rendered as product-visible content.
- If a rendered DB text field lacks language metadata or contract
  classification, block until the owning contract or baseline task defines it.

Step 5: Align APIs.

- Covered auth/onboarding/profile failures must emit only the canonical error
  envelope with Swedish `message` and Swedish field messages.
- Product UI surfaces must include backend text bundles or typed text fields
  sufficient for frontend rendering without local copy.
- API responses must include no legacy `detail`, `error`, `description`, raw
  framework payloads, or English failure text on user-facing surfaces.
- Payment return and checkout surfaces must expose provider identifiers only
  as non-rendered correlation fields, never as user-facing copy.

Step 6: Cut over frontend to renderer-only.

- Remove all user-facing hardcoded literals from widgets, pages, components,
  route pages, snackbars, dialogs, forms, semantics labels, empty states,
  loading states, errors, and landing/legal pages.
- Remove English locale fallback and any English ARB/user-facing locale path.
- Remove frontend fallback message maps and raw exception rendering.
- Replace every user-facing text render with backend-delivered text or
  contract-classified DB content.
- If required text is missing, the frontend must fail closed and report a
  verification failure; it must not invent fallback text.

Step 7: Migrate all surfaces before final GO.

- Profile: profile labels, password action, save messages, logged-out prompt,
  and profile errors must come from backend text bundles; profile DB fields
  remain DB content only.
- Auth and onboarding: page copy, verification states, password reset states,
  welcome confirmation, errors, and field messages must come from backend or
  contract-owned failure envelopes.
- Checkout and Stripe: membership copy, trial/card text, CTA, loading,
  cancel, waiting, retry, post-confirmation, and payment errors must match the
  embedded checkout contract exactly.
- Landing/legal: all public copy and legal links must be Swedish and
  contract/backend-owned; implementation details must not render.
- Studio/Editor: labels, upload states, preview errors, unsupported states,
  and admin/teacher messages must be backend-owned Swedish text.
- Media/Admin/Home: all empty states, technical failures, and status messages
  must be backend-owned Swedish text or operator-only non-product text.
- Email templates: templates must consume backend catalog text and emit UTF-8
  Swedish.
- DB content: all rendered DB content must be classified and verified.

## 4. Enforcement Rules

Contract enforcement:

- No user-facing text may exist without a contract owner.
- No backend catalog entry may exist without a contract text ID.
- No frontend render path may display text without a backend/catalog/DB
  provenance marker.
- Contract text hash or version must be checked against backend catalog output.
- Contract drift is any mismatch among contract value, backend emitted value,
  API response, and rendered UI text.

Backend enforcement:

- Backend is the only runtime text authority.
- Backend must emit Swedish messages for all user-facing failures.
- Backend must not pass through framework exception text.
- Backend must not emit forbidden legacy error shapes on covered surfaces.
- Backend must not emit internal technical language to product UI surfaces.
- Backend must fail closed when required contract text is missing.

Frontend enforcement:

- No hardcoded user-facing strings.
- No frontend fallback messages.
- No `error.toString()` or raw exception text in UI.
- No English user-facing locale or English fallback.
- No direct rendering of `detail`, `error`, `description`, or raw response
  maps.
- No local translation, localization, capitalization, or text repair.
- No string concatenation for product messages unless the backend supplies
  both the template and validated interpolation values.
- No technical leakage: backend, webhook, session_id, order_id, internal route
  names, storage paths, SQL/database terms, provider identifiers, or framework
  names may render in product UI unless a contract explicitly classifies the
  surface as operator-only.

DB enforcement:

- DB must use UTF8 server/client encoding.
- DB text that renders to users must be classified by contract.
- System-seeded DB text must be Swedish and must pass mojibake detection.
- User/teacher content must pass encoding and corruption checks before write
  and before render.
- DB must not store or provide UI chrome, failure copy, or fallback copy.

## 5. Verification Flow

Verification must execute in this order and fail closed on the first blocking
violation.

1. Source encoding gate
   - Strict UTF-8 decode every in-scope text file.
   - Block invalid bytes, UTF-16 files, non-UTF-8 BOMs, mojibake markers, and
     replacement characters.

2. Contract inventory gate
   - Verify every user-facing surface has complete text IDs and owner mapping.
   - Verify every exact-copy contract value is Swedish UTF-8.
   - Verify placeholders and interpolation variables are declared.

3. Backend catalog gate
   - Verify backend catalog keys exactly match contract text IDs.
   - Verify backend failure messages are Swedish and use canonical envelopes.
   - Verify email and Stripe text are catalog-owned.

4. DB text gate
   - Verify DB encoding is UTF8.
   - Scan rendered DB text fields for mojibake and invalid characters.
   - Verify every rendered DB text field has contract classification and
     language status.

5. API response gate
   - Start only after required backend/MCP bootstrap passes in execute/confirm
     mode.
   - Capture raw response bytes for key surfaces and decode as UTF-8.
   - Verify content type, envelope shape, Swedish messages, no legacy error
     fields, no frontend-only text requirements, and no forbidden technical
     leakage.

6. Frontend static gate
   - Scan frontend source for user-facing literals in widgets/pages/components.
   - Scan for `error.toString()`, forbidden error fields, fallback maps,
     English locale fallback, ARB text drift, mojibake, and internal terms.
   - Block any string literal that reaches UI without backend/DB provenance.

7. Rendered UI gate
   - Render every route/surface after API gates pass.
   - Extract visible text and accessibility text.
   - Verify each text node maps to a contract text ID or classified DB field.
   - Verify Swedish-only product output, no mojibake, no English fallback, and
     no technical leakage.

8. Email and Stripe gate
   - Render email templates and payment states as UTF-8.
   - Verify exact Swedish catalog text and no corrupted characters.
   - Verify membership checkout copy matches the embedded checkout contract.

9. Final aggregate gate
   - Compare contract -> backend -> API -> frontend -> UI for every surface.
   - Pass only with zero `encoding_error`, zero `authority_violation`, zero
     `contract_violation`, and zero `frontend_leak`.

## 6. GO / BLOCKED Conditions

GO for execution of downstream correction tasks only when:

- TXT-001 through TXT-007 are complete in DAG order.
- TXT-008 and TXT-009 pass with zero findings.
- Every user-facing string has exactly one authority.
- Every rendered UI text node maps to contract/backend or classified DB
  content.
- Every source file and runtime text payload is valid UTF-8.
- Every product UI output is Swedish.
- Frontend contains no user-facing hardcoded strings, fallback messages,
  raw exception rendering, or English fallback.
- API responses contain no corrupted text, forbidden failure fields, or
  contract drift.

BLOCKED if any of the following are true:

- Any required authoritative file or contract is missing.
- Any text file is non-UTF-8 or invalid UTF-8.
- Any mojibake marker remains.
- Any ASCII-degraded Swedish product text remains.
- Any frontend user-facing literal remains.
- Any frontend fallback message remains.
- Any raw `error.toString()` or raw backend detail reaches UI.
- Any English product text remains outside generated operator prompts or
  explicitly operator-only surfaces.
- Any DB-rendered text field lacks contract classification.
- Any API response differs from its contract text or envelope.
- Any checkout, auth, onboarding, profile, email, Studio, Editor, landing,
  legal, or Stripe surface is not migrated.

## Final Plan Verification

If executed completely and gates pass, this plan eliminates:

- all known encoding errors,
- all frontend text authority,
- all contract drift,
- all frontend user-facing technical leakage,
- all English or ASCII-degraded product copy.

Until every task and gate above passes, the system status remains BLOCKED.
