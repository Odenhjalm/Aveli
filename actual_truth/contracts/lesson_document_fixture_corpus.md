# LESSON DOCUMENT FIXTURE CORPUS

## STATUS

ACTIVE_REBUILT_EDITOR_AUTHORITY

This corpus is the positive fixture authority for the rebuilt editor. It uses
`lesson_document_v1` only. It does not use Markdown round trips, Quill Delta,
newline counting, or legacy `content_markdown` as proof.

## Artifact

Canonical machine-readable corpus:

`actual_truth/contracts/lesson_document_fixture_corpus.json`

## Required Capability Coverage

- bold
- italic
- underline
- clear formatting
- heading
- bullet list
- ordered list
- image media node
- audio media node
- video media node
- document media node
- magic-link / CTA node
- persisted preview
- ETag concurrency

## Execution Binding

The corpus is executable evidence only when it is consumed by tests:

- backend validation tests load the JSON corpus and validate every positive
  document shape with backend-native `lesson_document_v1` validation
- frontend model tests parse the same JSON corpus through the Dart document
  model
- editor widget tests render corpus documents through the rebuilt authoring
  widget
- preview and learner tests render corpus documents through the shared document
  renderer
- ETag tests use corpus document variants to prove canonical JSON concurrency
  behavior

## Forbidden

The corpus must not contain:

- `canonical_markdown`
- `content_markdown`
- Markdown media tokens such as `!image(...)`
- raw storage paths
- frontend-authored resolved media URLs inside document nodes
- Quill Delta payloads

Resolved media URLs may appear only in read-side `media_rows` fixture data,
where they represent backend-authored projection objects rather than document
truth.
