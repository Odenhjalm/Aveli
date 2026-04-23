# LESSON EDITOR REBUILD CONTRACT ALIGNMENT AUDIT

## STATUS

CONTRACT ALIGNMENT AUDIT

## 1. AUDIT VERDICT

The rebuild manifest intentionally conflicts with the current Markdown-centered
content law.

That conflict is not accidental. It is the core decision required by the
reported editor failure. The current editor contract stack encodes Markdown as
the canonical content format. The new rebuild contract encodes a versioned
document model as target truth.

The conflict must be resolved by task execution before runtime code can be
declared aligned. The existing Markdown laws must not be allowed to pull the
new editor back into the failing architecture.

## 2. PRESERVED CONTRACTS AND LAWS

The rebuild preserves these existing contract decisions:

- structure and content remain separate concerns
- content write surfaces remain content-only
- structure write surfaces must not accept content fields
- governed media remains under cross-domain media law
- frontend must not construct governed media URLs
- preview remains persisted-only and read-only
- ETag / If-Match content concurrency remains mandatory
- learner read surfaces remain distinct from editor write surfaces

Primary preserved sources:

- `actual_truth/contracts/SYSTEM_LAWS.md:65` separates structure, content,
  media lifecycle, public-surface, and execution transport law
- `actual_truth/contracts/SYSTEM_LAWS.md:67` keeps editor write surfaces and
  learner read surfaces distinct
- `actual_truth/contracts/SYSTEM_LAWS.md:35-51` defines cross-domain media law
- `actual_truth/contracts/course_lesson_editor_contract.md:683-690` locks
  content read ETag behavior
- `actual_truth/contracts/course_lesson_editor_contract.md:731-738` locks
  content write If-Match and response behavior
- `actual_truth/contracts/course_lesson_editor_contract.md:815-833` locks
  Preview Mode as persisted-only and read-only

## 3. DIRECT CONFLICTS WITH CURRENT CONTRACTS

### CONFLICT-001: Markdown canonical content law

Current contract law:

- `actual_truth/contracts/course_lesson_editor_contract.md:18` says Markdown is
  the canonical lesson-content format
- `actual_truth/contracts/course_lesson_editor_contract.md:841` repeats that
  Markdown is canonical
- `actual_truth/contracts/AVELI_COURSE_DOMAIN_SPEC.md:293-294` says lesson text
  content is canonical Markdown stored in `app.lesson_contents.content_markdown`

Rebuild decision:

- `lesson_document_v1` canonical JSON is the editor content authority
- `content_markdown` is legacy compatibility, not new editor truth

Required resolution:

- amend the current Markdown laws so `content_document` is canonical for the
  rebuilt editor
- reclassify Markdown as legacy compatibility/import/export only

### CONFLICT-002: `content_markdown` field authority

Current contract law:

- `actual_truth/contracts/course_lesson_editor_contract.md:46` declares
  `app.lesson_contents.content_markdown` as markdown/text authority
- `actual_truth/contracts/course_lesson_editor_contract.md:672` returns
  `content_markdown` from editor content read
- `actual_truth/contracts/course_lesson_editor_contract.md:708` accepts
  `content_markdown` in editor content write
- `actual_truth/contracts/course_public_surface_contract.md:140` exposes
  learner lesson `content_markdown`

Rebuild decision:

- editor content read/write authority is `content_document`
- learner rendering must move to document rendering
- `content_markdown` must not be the new editor save or render authority

Required resolution:

- update editor content read/write contracts
- update learner content read contract or add a document-aware learner content
  contract
- quarantine or remove Markdown response fields from the new editor path

### CONFLICT-003: backend Markdown normalization authority

Current contract law:

- `actual_truth/contracts/course_lesson_editor_contract.md:736` requires backend
  Markdown normalization before persistence
- `actual_truth/contracts/course_lesson_editor_contract.md:880-882` requires
  backend Markdown normalization or rejection

Rebuild decision:

- backend validation must validate `lesson_document_v1`
- backend validation must not perform Markdown round-trip validation
- canonical JSON normalization replaces Markdown normalization

Required resolution:

- replace Markdown normalization law with canonical JSON validation and
  canonical-byte ETag law

### CONFLICT-004: supported Markdown fixture corpus authority

Current contract law:

- `actual_truth/contracts/lesson_supported_content_fixture_corpus.md:6`
  describes the Markdown-canonical Aveli editor pipeline
- `actual_truth/contracts/lesson_supported_content_fixture_corpus.md:31`
  locks `app.lesson_contents.content_markdown` as stored truth
- `actual_truth/contracts/lesson_supported_content_fixture_corpus.md:70-75`
  locks supported canonical Markdown fixtures

Rebuild decision:

- supported editor content must be a document-model fixture corpus
- Markdown fixtures may remain as legacy compatibility tests only

Required resolution:

- create a document fixture corpus
- mark Markdown fixture corpus as legacy or compatibility-only for the rebuild

## 4. NON-CONFLICTING ADJACENT CONTRACTS

The media contracts remain compatible if media references move from Markdown
tokens to document media nodes.

Reason:

- media node references still use governed lesson media identity
- frontend still does not resolve URLs
- backend still composes media read representations

The course and lesson structure contracts remain compatible if the content
payload field changes from `content_markdown` to `content_document`.

Reason:

- lesson title and position are still structure
- lesson content remains content
- content writes remain separate from structure writes

## 5. REQUIRED CONTRACT AMENDMENT ORDER

The first execution task must align the contract layer before runtime code work:

1. amend `course_lesson_editor_contract.md` for document content read/write
2. amend `AVELI_COURSE_DOMAIN_SPEC.md` content model
3. amend `course_public_surface_contract.md` learner content shape
4. reclassify `lesson_supported_content_fixture_corpus.*` as legacy
   compatibility or replace it with a document fixture corpus
5. add explicit forbidden patterns for new editor paths

## 6. STOP CONDITION

Stop implementation if both of these remain true after contract-alignment work:

- Markdown is still declared canonical for the rebuilt editor
- `lesson_document_v1` is also declared canonical for the rebuilt editor

Two simultaneous content authorities would recreate the current editor failure
mode at the contract layer.
