# LESSON EDITOR REBUILD MANIFEST CONTRACT

## STATUS

ACTIVE TARGET-TRUTH REBUILD CONTRACT

NO RUNTIME CODE CHANGE

This contract defines the target truth for rebuilding the Aveli lesson editor.
It does not claim that current runtime code already satisfies this truth.

## 1. PURPOSE

The purpose of this contract is to make the editor rebuild deterministic before
implementation begins.

The current editor is not sufficient. The current Quill-to-Markdown pipeline
can collapse authored block boundaries, can reject otherwise valid italic text
through round-trip guard behavior, and depends on patch layers instead of a
stable content authority. These failures are not local formatting bugs. They
are evidence that the current editor architecture is legacy for the rebuild.

The rebuild target is a stable, future-proof editor that supports:

- bold, italic, underline, and clear formatting
- headings and lists
- image, audio, video, and document content
- magic-link / CTA content
- preview against persisted saved content
- ETag-based concurrency
- paragraph blocks, bullet-list blocks, and ordered-list blocks

No legacy data migration is a goal of this work. Existing legacy Markdown may
remain as historical or compatibility input only until explicitly removed or
quarantined by task execution.

## 2. DETERMINED DECISION

The new editor SHALL use a versioned document model as lesson-content
authority.

Markdown SHALL NOT be the new editor authority.

Quill Delta SHALL NOT be the new editor authority.

The current Markdown round-trip validator SHALL NOT be the new editor save
gate.

The backend Flutter round-trip harness SHALL NOT be the new editor validation
authority.

The new editor content authority is:

```text
app.lesson_contents.content_document
```

The persisted document shape is:

```text
lesson_document_v1 canonical JSON
```

The existing `app.lesson_contents.content_markdown` field is legacy for this
rebuild. It may be kept temporarily as compatibility data, export cache, or
legacy read input, but it must not drive the new editor save path, preview
truth, learner rendering truth, or validation truth.

## 3. CONTRACT PACKET

This rebuild packet is governed by:

- `actual_truth/contracts/lesson_editor_rebuild_manifest_contract.md`
- `actual_truth/analysis/lesson_editor_rebuild_foundation/AUDIT_FOR_CONTRACT.md`
- `actual_truth/analysis/lesson_editor_rebuild_foundation/CONTRACT_ALIGNMENT_AUDIT.md`
- `actual_truth/analysis/lesson_editor_rebuild_foundation/CODE_DECISION_DIFF.md`
- `actual_truth/DETERMINED_TASKS/lesson_editor_rebuild/`

Existing contracts that still declare Markdown as canonical are treated as
current legacy authority and must be amended by the task tree before runtime
implementation can claim completion.

## 4. DOCUMENT MODEL LAW

`lesson_document_v1` is a canonical JSON document with explicit nodes.

The root document MUST contain:

- `schema_version = "lesson_document_v1"`
- `blocks`

Allowed block nodes:

- `paragraph`
- `heading`
- `bullet_list`
- `ordered_list`
- `media`
- `cta`

Allowed inline content:

- `text`

Allowed inline marks:

- `bold`
- `italic`
- `underline`
- `link`

Block semantics:

- paragraph boundaries are explicit nodes, not inferred newline counts
- headings carry an explicit level
- bullet lists carry explicit list-item structure
- ordered lists carry explicit list-item structure and optional start value
- media blocks carry `lesson_media_id` and `media_type`
- CTA blocks carry label and target URL

Clear formatting MUST remove inline marks from the selected text without
deleting text or collapsing block boundaries.

The document model MUST reject unknown node types, unknown mark types, invalid
mark overlap, malformed list structure, invalid media references, invalid CTA
shape, and invalid schema versions.

## 4A. AUTHORING SURFACE LAW

The editor authoring UI MUST present one continuous writing surface.

Users must experience writing as one flowing document, not as a stack of
separate block containers.

The UI may keep deterministic internal focus targets when required for
editing, toolbar operations, media nodes, CTA nodes, and validation, but those
targets must remain implementation details. They must not reintroduce visible
per-block card editors, isolated block boxes, Markdown textareas, Quill
editors, or legacy conversion surfaces as the authoring experience.

The continuous authoring surface MUST still map deterministically to
`lesson_document_v1` blocks and nodes:

- paragraph text maps to `paragraph` blocks
- heading text maps to `heading` blocks
- bullet-list text maps to `bullet_list` items
- ordered-list text maps to `ordered_list` items
- media placements map to `media` blocks with `lesson_media_id`
- magic-link / CTA authoring maps to `cta` blocks

Formatting commands MUST be selection-based.

Bold, italic, underline, clear-formatting, heading conversion, paragraph
conversion, bullet-list conversion, and ordered-list conversion must apply to
the current selected text range only.

Collapsed cursor state or active-block focus MUST NOT be treated as implicit
permission to format the entire block or document. A formatting command may
affect an entire block only when that block's text range is explicitly
selected.

When a structural command such as heading or list conversion is applied to a
partial selection, the editor must split the surrounding text into deterministic
`lesson_document_v1` blocks/nodes so the selected range alone receives the new
structure.

This law changes presentation only. It does not weaken document authority,
backend validation, persisted preview authority, learner rendering authority,
or ETag / If-Match concurrency.

## 4B. READING UX PRESENTATION LAW

The rebuilt editor authoring shell MUST use a clean white writing surface.

The rebuilt editor, persisted preview, and learner reading UI MUST NOT render
internal model labels, schema labels, Markdown/Quill authority text, or debug
strings to users.

Persisted preview and learner lesson rendering MUST provide local selectable
reading modes:

- Glass mode preserves the existing translucent presentation style
- Paper mode renders the same document content on a white surface with subtle
  visual-only horizontal lines and high-contrast text

Reading mode is presentation-only local UI state. It MUST NOT be serialized
into `lesson_document_v1`, sent to backend APIs, used as validation authority,
or treated as content persistence.

## 5. CONTENT WRITE LAW

The new canonical content write surface remains content-only.

The target write request is:

```json
{
  "content_document": {
    "schema_version": "lesson_document_v1",
    "blocks": []
  }
}
```

Required request transport metadata:

- `If-Match`

Rules:

- writes without a matching `If-Match` token must fail without persistence
- successful writes must emit a replacement `ETag`
- ETag calculation must use canonical JSON bytes for `content_document`
- backend validation must happen against `lesson_document_v1`
- backend validation must not shell out to Flutter
- backend validation must not use Markdown round-trip equivalence
- response must return the persisted canonical document
- structure fields remain forbidden on the content write surface

## 6. CONTENT READ LAW

The new canonical editor content read surface returns persisted document truth:

```json
{
  "lesson_id": "uuid",
  "content_document": {
    "schema_version": "lesson_document_v1",
    "blocks": []
  },
  "media": []
}
```

Response transport metadata:

- `ETag`

Rules:

- read output must be persisted content, not draft editor state
- read output must not contain lesson structure mutation authority
- `media` remains read-only backend-authored media representation
- read output must not expose storage paths, signed URLs, preview URLs, or
  frontend-resolved URLs

## 7. MEDIA LAW

Media nodes in `lesson_document_v1` MUST reference governed lesson media by
`lesson_media_id`.

Allowed media node types:

- `image`
- `audio`
- `video`
- `document`

Media nodes MUST NOT reference:

- storage paths
- signed URLs
- public URLs
- preview URLs
- playback URLs
- `runtime_media`
- `media_asset_id` as editor document truth

Backend media validation must prove that referenced lesson media belongs to the
same lesson content boundary before persistence.

## 8. MAGIC-LINK / CTA LAW

Magic-link / CTA is first-class editor content.

The new editor MUST NOT encode CTA authority as incidental Markdown link text.

The CTA node must preserve:

- label
- target URL
- stable node identity if required by the editor runtime

The CTA validator must reject empty labels, malformed target values, and
unsupported CTA shape.

## 9. PREVIEW LAW

Editor Preview Mode must render persisted saved content only.

Preview Mode must use the same `lesson_document_v1` renderer path as learner
lesson content rendering, with presentation differences only where explicitly
allowed by the editor surface.

Preview Mode MUST NOT use:

- unsaved editor controller state
- local draft Markdown
- local draft document state
- preview cache entries as content authority
- frontend-constructed media URLs
- a mutation API

## 10. LEGACY REMOVAL LAW

The implementation bias is to remove more legacy editor code rather than less.

The following are legacy for this rebuild:

- Quill Delta as editor state authority
- `flutter_quill` as the long-term lesson editor authority
- `markdown_quill` conversion as save authority
- `markdown_widget` as the editor/learner content truth renderer
- frontend Markdown canonicalization as content authority
- frontend Markdown integrity guard as save authority
- backend Flutter round-trip markdown validator
- Markdown media-token rewriting as editor document authority
- regex-based paragraph/newline canonicalization as semantic authority

Legacy code may survive only when explicitly quarantined as import/export or
read-only compatibility. Quarantined legacy code must not be reachable from the
new editor save path, preview path, learner rendering path, or validation path.

## 11. CONTRACT RELATIONSHIP LAW

Preserved existing laws:

- course structure remains separate from lesson content
- lesson structure remains separate from lesson content
- governed media remains under cross-domain media law
- frontend must not construct governed media URLs
- content writes require ETag / If-Match concurrency
- Preview Mode remains persisted-only and read-only

Superseded target laws:

- Markdown as canonical lesson-content format
- `content_markdown` as new editor content authority
- backend Markdown normalization as new write-boundary authority
- Markdown fixture corpus as new supported-content authority

These supersessions must be materialized by the task tree. Until then, the old
Markdown contract text is known contract drift against this rebuild target.

## 12. STOP CONDITIONS

Implementation must stop if:

- a task attempts to make Markdown the new editor authority
- a task attempts to make Quill Delta the persisted authority
- a task depends on migrating legacy content as a precondition
- a task keeps the Markdown round-trip guard in the new save path
- a task keeps the Flutter backend validator in the new validation path
- a task makes Preview Mode render unsaved draft content
- a task weakens ETag / If-Match concurrency
- a task bypasses governed media authority
- a task cannot reconcile old Markdown contracts without an explicit contract
  amendment

## 13. FINAL ASSERTION

The target editor is a document-model editor.

Current Quill/Markdown behavior is not adequate and is not the rebuild target.

The rebuild is successful only when authoring, persistence, validation, preview,
learner rendering, media handling, CTA handling, and tests all operate from
`lesson_document_v1` rather than from Markdown round trips.
