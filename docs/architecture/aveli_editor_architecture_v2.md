# Aveli Editor Architecture V2

## Implementation Plan (Path B)

## Purpose

The current editor implementation relies on `flutter_quill` as both the UI editor and the primary mutation surface. This creates instability due to:

- internal Quill mutation paths bypassing page-level guards
- async race conditions during uploads and lesson loading
- controller replacement destroying composing and selection state
- lack of a stable editor identity across async flows

The goal of this migration is to introduce a session-based editor architecture where:

- canonical markdown is the single source of truth
- Quill becomes a UI adapter
- editor mutations are managed through an explicit operation pipeline
- async flows are revision-guarded
- preview rendering uses the same contract as the student view

No database schema or stored lesson content format will be changed.

## Core Architectural Principles

### 1. Canonical Content Ownership

The canonical representation of lesson content remains:

```text
lesson_content_markdown
```

stored in the database.

The editor must never store or persist Quill delta as authoritative data.

Conversion must always follow:

```text
canonical markdown
      ↓
editor adapter
      ↓
quill delta
```

and

```text
quill delta
      ↓
editor adapter
      ↓
canonical markdown
```

### 2. Editor Session Model

The editor must operate inside a stable session object.

Conceptual model:

```text
EditorSession
    sessionId
    lessonId
    revision
    controller
    focusNode
    scrollController
    canonicalMarkdown
```

Responsibilities:

- represent the active editing context
- gate all async operations
- maintain document revision consistency
- prevent stale operations from mutating the wrong editor

### 3. Mutation Pipeline

All app-initiated editor mutations must be represented as operations.

Conceptual model:

```text
EditorOperation
    type
    baseRevision
    sessionId
    origin
    payloadFiles changed: ￼course_editor_page.dart and ￼course_editor_screen_test.dart. No module files were added.

Exact page-level hardening added: page-local session/revision state plus _EditorRevisionToken and fingerprint helpers at ￼course_editor_page.dart (line 345) and ￼course_editor_page.dart (line 608); revision tracking now lives in the existing controller listener and only bumps when the document delta fingerprint changes, so selection-only movement does not increment revision at ￼course_editor_page.dart (line 645). A fresh editor session is seeded on document replacement at ￼course_editor_page.dart (line 1702). Stale-token guards were added to _saveLessonContent() at ￼course_editor_page.dart (line 2164), _uploadImageFromToolbar() at ￼course_editor_page.dart (line 3661), _afterUploadSuccess() at ￼course_editor_page.dart (line 4444), and _replaceAudioMedia() at ￼course_editor_page.dart (line 5171). I also added a tiny @visibleForTesting web image-picker hook at ￼course_editor_page.dart (line 352) so the toolbar upload regression could be tested without a real browser file dialog.

Exact donor lineage concepts used: the March 17-18 line’s sessionId + lessonId + revision token semantics and “capture before await, revalidate before applying state” pattern from 8d14471, 91a9647, and the dirty /home/rodenhjalm/aveli-editor-session page/session work. This is the architecture-aligned Phase 1/Phase 3 salvage: page-local session identity, revision integrity, and stale-async blocking.

Exact donor lineage pieces left out: frontend/lib/editor/session/*, editor_mutation_pipeline.dart, editor_operation_payloads.dart, the dirty EditorSessionController, the dirty domain/session modules, the whole dirty course_editor_page.dart rewrite, preview shell changes, preview hydration changes, LessonMediaPreview changes, and March 16 embed helper rewrites. This stayed as controlled salvage, not a second editor architecture import.

Test/analyze results: flutter analyze lib/features/studio/presentation/course_editor_page.dart test/widgets/course_editor_screen_test.dart reported only 4 pre-existing experimental warnings in ￼course_editor_page.dart (line 2367) and ￼course_editor_page.dart (line 2415). These passed: flutter test --platform chrome test/widgets/course_editor_screen_test.dart --plain-name 'toolbar image upload result is ignored after lesson switch', flutter test --platform chrome test/widgets/course_editor_screen_test.dart --plain-name 'queued upload success for previous lesson does not insert into current lesson', flutter test --platform chrome test/widgets/course_edi
```

Operation types include:

```text
insertText
deleteRange
replaceRange
applyFormat
insertEmbed
removeEmbed
replaceMediaReference
setSelection
loadDocument
resetDocument
```

Operations must increment the editor revision.

### 4. Async Safety

Every async operation touching the editor must verify:

```text
sessionId
lessonId
revision
```

before mutating state.

Example guard pattern:

```text
if (!session.isActive) return
if (session.lessonId != originalLessonId) return
if (session.sessionId != capturedSessionId) return
```

This prevents:

- upload results mutating wrong lessons
- stale preview updates
- delayed operations overwriting newer edits

### 5. Controller Stability

Controller replacement must be minimized.

Controller swaps are allowed only for:

```text
initial editor mount
lesson change
catastrophic recovery
```

All other updates must occur through operations applied to the existing controller.

### 6. Representation Separation

The system must maintain three representations:

```text
Canonical Representation
    lesson_content_markdown

Editor Representation
    lightweight Quill delta

Preview Representation
    full student rendering
```

Editor mode prioritizes performance and stability.

Preview mode must match the student rendering pipeline.

## Implementation Phases

### Phase 1 - EditorSession Infrastructure

Goal: introduce a stable editor identity and revision system.

Tasks:

- Create new module `frontend/lib/editor/session/`
- Add `editor_session.dart`
- Add `editor_operation.dart`
- Add `editor_mutation_pipeline.dart`
- Update `course_editor_page.dart` to reference the session object instead of directly managing controller state
- Add revision increment after each operation

Responsibilities:

```text
EditorSession
    sessionId
    lessonId
    revision
    controller
    focusNode
    scrollController
```

Acceptance criteria:

- editor has stable `sessionId`
- async flows capture `sessionId`
- revision increments on mutation
- no functional regression in editing

### Phase 2 - Canonical Adapter Layer

Goal: decouple editor representation from canonical storage.

Tasks:

- Create module `frontend/lib/editor/adapter/`
- Add `markdown_to_editor.dart`
- Add `editor_to_markdown.dart`
- Move editor-facing conversion logic from `prepareLessonMarkdownForRendering` and `convertLessonMarkdownToDelta` into this layer

Responsibilities:

```text
canonical markdown
    ↓
editor delta
```

```text
editor delta
    ↓
canonical markdown
```

Acceptance criteria:

- adapter handles all conversions
- course editor no longer calls conversion logic directly
- canonical markdown roundtrip produces identical content

### Phase 3 - Async Hardening

Goal: eliminate race conditions.

Targets:

```text
lesson load
lesson reset
image upload
audio upload
video insertion
media replacement
preview hydration
```

Every async flow must:

1. capture session identity
2. verify identity after `await`
3. abort if session mismatch

Acceptance criteria:

- stale async results cannot mutate editor
- switching lessons mid-upload cannot corrupt editor
- no crashes from disposed controllers

### Phase 4 - Controller Swap Reduction

Goal: stop unnecessary controller replacement.

Current problem:

Frequent calls to `_replaceLessonDocument()` destroy selection and composing state.

Tasks:

- Replace full controller rebuilds with operations such as `replaceRange`, `insertEmbed`, `deleteRange`, and `applyFormat`
- Keep controller swaps only for `initial mount`, `lesson change`, `explicit reset`, and catastrophic recovery when needed

Acceptance criteria:

- cursor position remains stable during edits
- IME composing state is preserved
- editor focus remains stable

### Phase 5 - Preview Mode Separation

Goal: ensure preview uses the student rendering contract.

Editor mode:

```text
placeholders
thumbnails
light rendering
```

Preview mode:

```text
full media players
runtime playback URLs
student layout
```

Preview rendering must derive from canonical markdown, not from Quill internal state.

Acceptance criteria:

- preview matches student view
- switching modes does not mutate editor state
- editor performance improves

## Non-Goals

The following will not change during this migration:

```text
database schema
lesson_content_markdown format
media token format
media control plane architecture
```

This ensures existing teacher content remains valid.

## Migration Risk Assessment

Risk level: Low

Reasons:

- canonical markdown unchanged
- media tokens unchanged
- database schema unchanged

The refactor affects only:

```text
editor UI architecture
state management
mutation handling
```

## Success Criteria

The migration is considered successful when:

- editor session identity prevents async corruption
- controller swaps are rare
- canonical markdown roundtrip is stable
- preview matches student rendering
- editor remains responsive with large lessons

## Recommended Branch Strategy

Create branch:

```text
feature/editor-session-architecture
```

Phase commits:

```text
editor-session-core
editor-adapter-layer
editor-async-guards
editor-controller-stability
editor-preview-mode
```

Each phase should pass Flutter build and editor smoke tests.

## Final Objective

Transform the editor architecture from:

```text
quill-driven editor
```

to:

```text
canonical-document editor
with quill as UI adapter
```

This ensures long-term stability for:

- large lessons
- heavy media usage
- concurrent async operations
