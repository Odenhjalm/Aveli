# Aveli Text Contract Implementation Plan

## Phase 0 – No‑Code Audit

### Objective

Evaluate the current system state to understand how text content is stored, parsed, rendered and edited. This audit will inform later work and ensure that all changes are grounded in existing reality rather than assumptions, in line with the “no guessing” principle.

### Phase 0 Execution Checklist

- [ ] Confirm access and context
  - [ ] AVELI OS env booted (backend + DB + frontend tooling)
  - [ ] Supabase access and migrations folder confirmed
  - [ ] CI config and lint/test config location identified
- [ ] Catalog all content storage fields
  - [ ] Enumerate DB columns touching lesson/content text
  - [ ] Confirm canonical vs legacy candidates (`content_markdown`, `content_html`, `delta`, etc.)
  - [ ] Map each field to owner (model/table/API contract)
- [ ] Trace parser/rendering paths
  - [ ] Identify backend parser/render pipeline
  - [ ] Identify frontend parser/render pipeline
  - [ ] Record versions/extensions and any fallback behavior
- [ ] Audit editor surface
  - [ ] Identify active editor(s) for teachers
  - [ ] Verify whether markdown is ever exposed directly
  - [ ] Record formatting controls and mappings for bold/italic/underline/font-size
- [ ] Scan for legacy syntax patterns
  - [ ] Search for `<u>`, `<b>`, `<strong>`, `<i>`, `<em>`, `<span>` in rendering/saving paths
  - [ ] Search for delta/editor-state serialization/legacy payloads
  - [ ] Capture sample files/lines with representative findings
- [ ] Review CI/validation safeguards
  - [ ] Find lint/type/lint-like checks touching content formatting
  - [ ] Find tests that assert formatting correctness or sanitization
  - [ ] Identify where enforcement can be expanded in future phases
- [ ] Produce Phase 0 audit artifacts
  - [ ] Storage field inventory (comprehensive)
  - [ ] Parser/version matrix (backend vs frontend)
  - [ ] Legacy usage list with prevalence indicators
  - [ ] Open risks and blockers
  - [ ] Assumption confirmations and unresolved unknowns

### Systems / Files Likely Affected

- Backend schemas (e.g. database migrations, models for lesson content).
- Content storage fields (identify whether `content_markdown`, `content_html`, `delta`, or other fields exist).
- Parser and renderer implementations in backend (Python/FastAPI) and frontend (Flutter/Dart).
- Existing editors (WYSIWYG or markdown) and their adapter code.
- CI rules and validation scripts relating to text formatting.

### Concrete Task Groups

1. Catalog Storage Fields
   - Inspect database schema and models to list all fields storing text content.
   - Verify existence of `content_markdown` and any legacy HTML or editor-state fields.
   - Cross-reference with Supabase migrations and code to confirm actual storage truth.

2. Review Parser / Renderer
   - Identify where markdown and HTML are parsed and rendered in both backend and frontend.
   - Note versions of CommonMark and custom extensions currently in use.
   - Determine whether separate parsers exist for backend and frontend.

3. Audit Editor Interfaces
   - Enumerate rich-text editors used by teachers.
   - Determine whether a markdown-exposing interface exists and how formatting options map to syntax.
   - Record any custom formatting for underline or font-size.

4. Examine Legacy Formatting
   - Search repository for `<u>`, `<b>`, `<strong>`, `<i>`, `<em>`, `<span>`, and delta-state usage to quantify legacy syntax prevalence.
   - Identify migration scripts or normalizers, if any.

5. CI / Validation Rules
   - Review existing CI scripts, lint rules, and tests that enforce text formatting standards.
   - Document current invariants and compare with the new contract.

6. Prepare Audit Report
   - Summarize findings including storage truth, discrepancies between expected and actual state, areas requiring normalization, and preliminary risks.

### Dependencies

- Requires access to database schemas, code repository, and CI configuration. Should not modify any data.
- Dependent on environment bootstrap according to AVELI OS (env load, backend ready) for inspection.

### Risks / Failure Modes

- Incomplete inspection might overlook hidden content fields or custom formatting. Mitigate by searching both code and migrations, and verifying with MCP observability where available.
- Misinterpreting UI behavior as truth; mitigate by prioritizing code and database as authoritative sources.

### Verification Targets

- Confirm that all existing storage fields are documented.
- Verify parser versions and any divergence between frontend and backend.
- Identify whether legacy syntax is present in stored data.

### Decisions Satisfied

- Supports Decision 1 by establishing whether `content_markdown` exists and whether other fields violate the “sole canonical truth”.
- Sets baseline for Decisions 2–9 by discovering current editor features, syntax support, and validation rules.

### Phase 0 Acceptance Criteria

| Phase | Owner | Date | Status |
| --- | --- | --- | --- |
| Phase 0 | | | [ ] Done [ ] Not done |
| Phase 1 | | | [ ] Done [ ] Not done |
| Phase 2 | | | [ ] Done [ ] Not done |
| Phase 3 | | | [ ] Done [ ] Not done |
| Phase 4 | | | [ ] Done [ ] Not done |
| Phase 5 | | | [ ] Done [ ] Not done |
| Phase 6 | | | [ ] Done [ ] Not done |
| Phase 7 | | | [ ] Done [ ] Not done |

## Phase 1 – Contract & Canonical Grammar Definition

### Objective

Define the updated text contract based on the approved decisions. Document canonical markdown syntax, Aveli extensions for underline and font-size, and semantic normalization rules. This specification becomes the single source of truth for developers and tests.

### Systems / Files Likely Affected

- Project documentation (e.g. `/docs/text_contract.md` or similar location).
- API contracts and types that reference content fields.
- Developer guidelines for contributing new extensions.

### Concrete Task Groups

1. Draft Contract Document
   - Create or update a markdown document defining `content_markdown` as the sole persisted format.
   - Describe permitted CommonMark features and disallowed HTML tags.

2. Define Canonical Extensions
   - Specify `[u]…[/u]` for underline and `[size=…]…[/size]` for font size.
   - Include rules for allowed values and fallback behavior.

3. Semantic Normalization Rules
   - List conversions such as `_italic_` → `*italic*`, `__bold__` → `**bold**`, `<b>/<strong>` → `**…`, `<i>/<em>` → `*…`, and forbid `<u>` and span-based formatting.
   - Explain that normalization is based on meaning rather than original symbols.

4. Round‑Trip Stability Guarantees
   - Define what constitutes semantic round-trip stability between markdown → editor → markdown.
   - Specify that syntax may be normalized but meaning must remain identical.

5. Versioning Strategy
   - Introduce explicit version tags for the text contract to allow backward compatibility and future extensions.
   - Document process for bumping the version.

6. Formal Extension Process
   - Outline requirements for introducing new formatting options: canonical syntax, parser support, renderer support, editor support, round-trip tests, and contract version increment.

7. Review and Stakeholder Approval
   - Circulate the draft among engineers, product owners, and QA for feedback.
   - Revise until approved.

### Dependencies

- Phase 0 report to ensure contract addresses all identified legacy patterns.
- Requires consensus from domain experts and maintainers.

### Risks / Failure Modes

- Ambiguities in grammar may lead to divergent interpretations. Mitigate through examples and explicit normative language.
- Lack of versioning can cause future changes to break existing content.

### Verification Targets

- Contract document merged into repository and referenced in API documentation.
- Explicit mapping of every approved decision to a clause in the contract.

### Decisions Satisfied

- Decision 1 (markdown as canonical truth).
- Decision 3 (support underline and font size via Aveli extensions).
- Decision 4 (normalize literal formatting syntax).
- Decision 5 (semantic round-trip stability).
- Decision 6 (unified parser contract via versioning).
- Decision 8 (formal extension process).
- Decision 9 (immutable system rules).

## Phase 2 – Parser and Normalizer Design

### Objective

Implement a unified parsing and normalization layer that adheres to the contract, supports Aveli extensions, and ensures round-trip stability across frontend and backend. Provide normalization functions to enforce canonical syntax on read/write.

### Systems / Files Likely Affected

- Backend parsing modules (e.g. Python/Markdown library wrappers).
- Frontend markdown parser (Flutter packages or custom implementations).
- Normalizer utilities and unit tests.
- API endpoint validations.

### Concrete Task Groups

1. Select Base Library
   - Confirm CommonMark implementation used across both environments.
   - Evaluate existing libraries for extension support; choose one that allows custom extensions or build wrappers.

2. Implement Aveli Extensions
   - Extend parser to recognize `[u]` and `[size=…]` syntax and produce appropriate AST nodes.
   - Ensure these extensions are treated as inline formatting with defined attributes.

3. Normalize Legacy Syntax
   - Build normalizer functions that transform `_…_`, `__…__`, `<b>`, `<strong>`, `<i>`, `<em>`, `<u>`, and span-based tags into canonical `*`, `**`, `[u]`, `[size=…]` forms.
   - Provide optional modes: one for migration and one for write-time enforcement.

4. Unify Parser Across Backend and Frontend
   - Establish a shared specification or generate code from a single source so both environments interpret text identically.
   - If needed, expose parser logic via WebAssembly or a shared library.

5. Define AST Model
   - Agree on a common abstract syntax tree representation for the contract, including versioning metadata.
   - Document how extension nodes map to runtime rendering properties.

6. Implement Round-Trip Tests
   - Create a test suite that converts sample markdown into an AST, into editor state and back, verifying semantic stability.
   - Include cases with legacy syntax, underline, size, nested formatting, and edge cases like empty tags.

### Dependencies

- Approved contract specification from Phase 1.
- Tooling environment must be bootstrapped per AVELI OS (backend/frontend running) to test parsers.

### Risks / Failure Modes

- Parser divergence if backend and frontend rely on different libraries. Mitigate by sharing code or thoroughly documenting the spec.
- Normalization may inadvertently change meaning (e.g. underscores used for emphasis vs underscores in identifiers). Mitigate with context-aware rules and tests.

### Verification Targets

- All approved formatting forms parse into expected AST nodes.
- Legacy syntax normalizes to canonical forms.
- Round-trip tests pass across multiple scenarios.

### Decisions Satisfied

- Decision 3 (extensions implementation).
- Decision 4 (semantic normalization).
- Decision 5 (round-trip stability).
- Decision 6 (unified parser and renderer logic).
- Decision 9 (one canonical parser contract).

## Phase 3 – Editor and Frontend Adaptation

### Objective

Provide teachers with a full WYSIWYG editor that uses the canonical markdown format internally but does not expose raw markdown syntax. Add support for underline and font-size formatting and ensure that the editor state converts to and from canonical markdown without loss of meaning.

### Systems / Files Likely Affected

- Frontend editor component (Flutter or web).
- Editor adapter converting markdown ↔ delta/editor state.
- UI controls for underline and font size.
- Documentation and onboarding materials for teachers.

### Concrete Task Groups

1. Design Editor Experience
   - Specify how underline and font-size options appear in the toolbar.
   - Determine font-size presets and their allowed values corresponding to `[size=…]` tag values.

2. Adapt Editor Adapter
   - Implement conversion functions between editor state and canonical markdown using the parser/normalizer from Phase 2.
   - Ensure when a user applies bold, italic, underline, or size formatting, the editor state reflects canonical syntax on save.

3. Hide Raw Markdown
   - Ensure the WYSIWYG editor does not display markdown syntax by default.
   - Provide an optional “view source” for developers if necessary but keep it disabled for teachers.

4. Normalize Legacy Edits
   - When loading existing content, normalize any legacy formatting into canonical forms before rendering in the editor.
   - Provide warnings or logs if unsupported syntax is encountered.

5. Accessibility and UX Testing
   - Validate that the editor controls are intuitive, and converted content renders as expected across different devices.
   - Ensure keyboard shortcuts map to canonical formatting.

6. Internationalization
   - Confirm that the editor still supports other languages and special characters; normalization should not break multi-byte characters.

### Dependencies

- Parser/normalizer from Phase 2.
- Backend endpoints for saving and retrieving content must use canonical markdown.

### Risks / Failure Modes

- Editor state might diverge from canonical markdown if conversion fails; mitigate with robust testing and fallback normalization.
- Teachers may copy-paste content with HTML or unsupported syntax; ensure sanitization and normalization before save.

### Verification Targets

- Creating and editing content via WYSIWYG yields canonical markdown on save.
- Underline and font-size formatting persist across reloads and appear correctly in the editor and rendered view.
- No raw markdown syntax is displayed to teachers.

### Decisions Satisfied

- Decision 2 (full WYSIWYG without exposing markdown syntax).
- Decision 3 (support underline and font size via canonical extensions).
- Decision 4 (normalize literal formatting syntax in the editor adapter).
- Decision 5 (round-trip stability through editor integration).
- Decision 6 (frontend uses unified parser/renderer).
- Decision 9 (no editor state as persistent truth).

## Phase 4 – Backend Enforcement and Persistence

### Objective

Ensure that the backend treats `content_markdown` as the sole canonical truth, enforces canonical syntax on write, and disallows legacy HTML or delta storage. Provide validation and normalization pipelines at API boundaries.

### Systems / Files Likely Affected

- API endpoints handling lesson or content creation/update.
- Data models and database schema (ensuring only `content_markdown` remains).
- Validation and normalizer middleware.
- Logging and ledger to capture mutations.

### Concrete Task Groups

1. Schema Enforcement
   - Remove or deprecate legacy fields (`content_html`, `delta`, etc.) from models and database.
   - Ensure new content is stored exclusively in `content_markdown`.

2. Write-Time Validation
   - Integrate the normalizer into API endpoints so that incoming content is parsed and normalized.
   - Reject or transform payloads containing HTML or non-canonical syntax.

3. Read-Time Transformation
   - If necessary for backward compatibility, transform legacy records into canonical markdown on retrieval until migration is complete.

4. Integrate Version Metadata
   - Store contract version information alongside `content_markdown` to facilitate future migrations.

5. Logging and Ledger
   - Update logging to include mutations of content and ensure before/after states are recorded, as mandated by AVELI OS logging rules.
   - Persist session IDs and timestamps.

6. Validation Errors
   - Provide descriptive error responses when users attempt to store disallowed syntax or bypass the normalizer.

### Dependencies

- Parser and normalizer from Phase 2.
- Contract specification from Phase 1.
- Audit results to know which legacy fields exist.

### Risks / Failure Modes

- Removing legacy fields without migration may break existing features. Mitigate by gating removal behind migration completion.
- Overly strict validation could reject valid content; mitigate by thorough test coverage and fallback normalization.

### Verification Targets

- Database contains only `content_markdown` with canonical syntax after writes.
- API responses include normalized markdown and version metadata.
- Audit logs show normalized before/after states with no legacy syntax.

### Decisions Satisfied

- Decision 1 (content_markdown as sole canonical truth).
- Decision 4 (enforce canonical syntax at write time).
- Decision 6 (unified parser used server-side).
- Decision 7 (write-time enforcement eliminates legacy syntax).
- Decision 9 (no HTML or editor state as persisted truth).

## Phase 5 – Legacy Migration and Data Audit

### Objective

Eliminate legacy syntax and fields in existing data through a controlled migration. Ensure all stored content conforms to the new contract and record all changes for auditability.

### Systems / Files Likely Affected

- Database migration scripts.
- Backfill scripts or jobs for converting existing content.
- Supabase migrations and data audit reports.
- CI checks to block reintroduction of legacy syntax.

### Concrete Task Groups

1. Migration Plan
   - Design a phased migration strategy.
   - Determine whether to run a one-off script or incremental background jobs.
   - Plan for a read-only window if needed.

2. Implement Migration Scripts
   - Write scripts that read existing `content_html`, `delta`, or non-canonical markdown entries, parse and normalize them into canonical `content_markdown`, and update records.
   - Capture before/after states in logs.

3. Data Audit
   - After migration, run queries to verify no legacy fields remain and that all markdown conforms to canonical syntax.
   - Use MCP observability to cross-check counts.

4. Deprecate Legacy Fields
   - After verification, remove legacy columns from the schema and codebase.
   - Update ORMs and API responses accordingly.

5. CI Enforcement
   - Update CI checks to fail if any future migrations reintroduce legacy fields or accept HTML/delta.
   - Add tests scanning for `<u>`, `<span>`, `<b>`, `<i>`, and non-canonical underscores.

6. Communication Plan
   - Inform stakeholders about migration schedule and potential downtime.
   - Provide guidance for content owners to review changes if necessary.

### Dependencies

- Backend enforcement (Phase 4) to prevent new legacy entries during migration.
- Completed parser and normalizer from Phase 2.

### Risks / Failure Modes

- Data corruption if normalization fails on complex legacy documents. Mitigate by backing up data and running migration in staging first.
- Long-running jobs may impact performance; schedule during low-usage periods.

### Verification Targets

- All content records after migration contain only canonical markdown.
- Legacy fields are removed and no longer referenced in code or schema.
- CI tests pass and block reintroduction of legacy syntax.

### Decisions Satisfied

- Decision 1 (sole canonical truth after migration).
- Decision 4 (normalize legacy syntax).
- Decision 7 (phased migration and ongoing audit).
- Decision 9 (no legacy HTML or delta stored).

## Phase 6 – Test Strategy and Continuous Integration Enforcement

### Objective

Establish comprehensive tests across layers and CI pipelines to guarantee semantic stability, enforce canonical syntax, and prevent regression. Integrate these tests into automated verification per AVELI OS.

### Systems / Files Likely Affected

- Unit and integration test suites (backend and frontend).
- CI configuration (e.g. GitHub Actions).
- Playwright or similar E2E test scripts.

### Concrete Task Groups

1. Parser/Normalizer Unit Tests
   - Create tests for each rule in the contract, verifying that input strings normalize as expected and unsupported syntax is rejected.

2. Round-Trip Tests
   - Extend tests created in Phase 2 to run automatically in CI.
   - Include scenarios covering editor interactions, API boundaries, and storage persistence.

3. Integration Tests
   - Use Playwright to simulate user interactions: create, edit, and publish content through the UI.
   - Verify saved content matches canonical markdown and rendered view matches expected styling (underline, font size, bold, italic).

4. CI Linting
   - Implement linters/static analysis tools that scan code for prohibited patterns, such as hard-coded HTML formatting or storage of editor state.
   - Fail build on violation.

5. MCP and API Verification
   - Incorporate calls to MCP endpoints to verify domain state before and after content mutations.
   - Ensure ledger logs conform to OS rules.

6. Regression Guardrails
   - Require new extensions to include test cases demonstrating parser support, renderer behavior, editor integration, and version bumps before merging.

### Dependencies

- Parser and normalizer implementation (Phase 2).
- Editor adaptation (Phase 3) and backend enforcement (Phase 4).

### Risks / Failure Modes

- Tests might be brittle if reliant on UI; mitigate by prioritizing AST and API-level checks.
- Without strict CI gating, future contributors may bypass rules; mitigate by making tests mandatory and blocking merges on failure.

### Verification Targets

- CI passes only when canonical rules are respected.
- Playwright tests confirm round-trip stability.
- Ledger and logs captured during tests meet OS logging requirements.

### Decisions Satisfied

- Decision 5 (round-trip stability tested continuously).
- Decision 6 (parser and renderer unified across layers tested).
- Decision 7 (ongoing audit via CI validation).
- Decision 8 (extension process requires tests and verification).
- Decision 9 (immutable system rules enforced through tests).

## Phase 7 – Rollout, Gating, and Governance

### Objective

Deploy the new contract in a controlled manner, manage gating between phases, and define governance for future extensions to ensure ongoing compliance with the canonical rules.

### Systems / Files Likely Affected

- Feature flags or configuration toggles.
- Release notes and migration announcements.
- Governance documentation and checklists for proposing new extensions.

### Concrete Task Groups

1. Rollout Plan
   - Decide deployment strategy (e.g., enable new editor and validation for a subset of users first, then widen gradually).
   - Coordinate backend and frontend releases to avoid mismatches.

2. Feature Gating
   - Implement flags to toggle enforcement of canonical syntax and WYSIWYG editor.
   - Use environment configuration to allow rollback if unforeseen issues arise.

3. Monitoring and Feedback
   - Monitor errors, user feedback, and logs during rollout.
   - Use MCP observability to track migration progress and identify anomalies.

4. Governance Process
   - Finalize a formal process for proposing new text-format extensions.
   - Require canonical syntax specification, parser and renderer implementation, editor support, round-trip tests, and version bump.
   - Document roles and approval steps.

5. Training and Support
   - Update documentation and training materials for teachers and developers.
   - Offer guidance on new formatting options and contract expectations.

6. Post-Rollout Review
   - After full rollout, conduct a retrospective to assess compliance, user satisfaction, and unexpected issues.
   - Use findings to improve future migrations.

### Dependencies

- Completion of earlier phases including migration and testing.
- Infrastructure for feature flags and monitoring.

### Risks / Failure Modes

- Incomplete gating could expose untested features to all users; mitigate by thorough testing before enabling flags.
- Delayed feedback could allow regressions to propagate; mitigate by real-time monitoring and quick rollback options.

### Verification Targets

- Successful staged rollout with no data loss.
- Governance process adopted for any future text-format extensions.
- All decisions remain enforced after full deployment.

### Decisions Satisfied

- Decision 7 (phased migration and audit is part of rollout).
- Decision 8 (governance for future extensions implemented).
- Decision 9 (immutable system rules reinforced through gating and rollback).

## Assumptions Requiring Confirmation

- Existing Data Fields: It is assumed that `content_markdown` exists and that legacy fields (`content_html`, `delta`) are present. Confirmation required from Phase 0 audit.
- Parser Library Choice: Assumes that a CommonMark implementation is already in use and can be extended. Verify during Phase 2.
- Editor Framework: Assumes current frontend uses a rich-text editor that can be extended. Audit must confirm if replacement is needed.
- Versioning Mechanism: Assumes infrastructure exists to store contract version metadata alongside content.

## Ordering Constraints and Blockers

- Contract Definition First: Phases 2–7 depend on contract from Phase 1; thus Phase 1 must complete and be approved before proceeding.
- Parser Before Editor/Backend Changes: Unified parser and normalizer (Phase 2) must exist before adapting the editor (Phase 3) and enforcing backend rules (Phase 4).
- Migration After Enforcement: Legacy migration (Phase 5) should occur only after backend enforcement (Phase 4) to prevent re-introduction of legacy syntax.
- Testing Setup Precedes Rollout: CI and test suites (Phase 6) must be established before rollout (Phase 7) to ensure stability during deployment.

## Decision Coverage Confirmation

This plan explicitly addresses all approved decisions:

- Decision
  - 1: `content_markdown` is the sole canonical truth - Phase 0, 1, 4, 5
  - 2: Teachers must use a full WYSIWYG editor without exposing markdown - Phase 3
  - 3: Underline and font-size via canonical extensions - Phases 1–3
  - 4: Normalize literal formatting syntax - Phases 1, 2, 3, 4, 5
  - 5: Semantic round-trip stability - Phases 1–3, 2, 6
  - 6: Unified parser and renderer with versioning - Phases 1, 2
  - 7: Legacy syntax elimination through migration and validation - Phases 0, 4, 5, 6
  - 8: Formal extension process for future features - Phases 1, 7
  - 9: Immutable system rules - across all phases enforcing markdown as sole persisted truth, single parser contract, disallowing legacy syntax and HTML, and not persisting editor state.
