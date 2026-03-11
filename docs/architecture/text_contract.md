# Canonical Text Contract

This document defines the canonical contract for all persistent rich text in the application.

Scope:

- Database storage
- Backend services
- API request and response payloads
- Editor serialization and deserialization
- Frontend rendering

The intent is to eliminate formatting drift and make rich-text behavior deterministic, idempotent, and future-proof.

## System Overview

The current lesson content pipeline accepts and produces a hybrid format:

- Quill Delta in the editor
- Markdown in parts of the frontend and API
- Raw HTML media tags in stored content

This hybrid contract causes formatting drift because Markdown to Delta conversion does not safely support arbitrary HTML. When HTML is mixed with Markdown, the same content can be interpreted differently during save, load, and render. That creates non-deterministic behavior such as escaped HTML, duplicated markers, formatting loss, or representation changes after repeated saves.

The system must move to a single canonical text format.

The canonical contract defined here is:

- Persistent rich text is stored as canonical Markdown
- HTML is not stored in persistent content
- Media is represented by canonical Markdown-level tokens, not HTML
- The editor may use Delta internally, but Delta is never the persistent format

## Canonical Storage Format

All persistent rich text stored in the database must be canonical Markdown.

Canonical means:

- The database stores one text representation only
- The API exchanges the same canonical Markdown representation
- Frontend rendering consumes that same canonical Markdown representation
- No HTML is embedded in stored content
- No editor-native JSON is embedded in stored content

Example canonical text:

```md
## Lesson Title

This is *italic* and **bold**.

* bullet
* list

!image(media_id)

!audio(media_id)

!video(media_id)
```

## Forbidden Formats

The following must never be stored in the database:

- HTML tags such as `<em>`, `<strong>`, `<p>`, `<a>`, `<img>`, `<audio>`, and `<video>`
- Editor JSON structures such as `{ "ops": [...] }`
- Mixed HTML and Markdown in the same stored field
- Media URLs embedded directly in Markdown
- Backend-generated hybrid text that mixes plain text, Markdown, and HTML

If any of these formats are encountered, they are legacy content and must be handled by migration or rejected by contract validation. They are not valid canonical storage.

## Media Representation

Media must be represented using canonical tokens instead of HTML.

Canonical tokens:

- `!image(media_id)`
- `!audio(media_id)`
- `!video(media_id)`

Rules:

- `media_id` is the stable identifier for the media record
- Media URLs must never be stored directly in Markdown
- Signed URLs, public URLs, `/studio/media/...` paths, and `/media/stream/...` paths are transport details, not storage format
- Rendering layers may resolve tokens into display or playback URLs at runtime, but that resolution must not mutate stored text

## Editor Contract

The editor may internally use Quill Delta.

The storage pipeline must always be:

```text
Delta
-> Markdown adapter
-> Markdown normalization
-> database
```

The load pipeline must always be:

```text
Database Markdown
-> Markdown adapter
-> Delta
-> editor
```

Rules:

- Delta is an internal editor format only
- Persistent storage is canonical Markdown only
- The editor adapter must be deterministic in both directions
- Editor-only attributes that cannot be represented in canonical Markdown must not be persisted implicitly

## Normalization Rules

Canonical Markdown syntax must follow these rules:

- italic: `*text*`
- bold: `**text**`
- lists use standard Markdown bullets
- headings use standard Markdown heading syntax
- media uses canonical media tokens only

Normalization rules:

- `<em>text</em>` -> `*text*`
- `<strong>text</strong>` -> `**text**`
- `_text_` -> `*text*`
- `*text*` -> `*text*`
- unsupported HTML is removed or converted during migration into valid canonical Markdown

Additional normalization rules:

- Markdown output must use one canonical representation for equivalent formatting
- The normalization layer must not invent new semantics
- Text formatting normalization belongs to the Markdown pipeline only
- Runtime rendering must not rewrite persisted content

## Idempotence Requirement

The text pipeline must be idempotent.

Required invariant:

```text
save(load(text)) == text
```

Implications:

- Repeated save and load cycles must not change formatting markers
- Repeated save and load cycles must not introduce HTML
- Repeated save and load cycles must not change media representation
- Repeated save and load cycles must not change equivalent Markdown into a different canonical form after canonicalization has already been applied

Canonical text is valid only if it is stable under repeated round-trips.

## Rendering Rule

Frontend views must render rich text using a shared Markdown renderer.

Rules:

- Rendering must start from canonical Markdown
- Media tokens must be resolved by a shared token-aware Markdown rendering layer
- No direct HTML rendering is allowed
- No ad hoc per-screen rich-text parsing is allowed
- The editor view and the read-only lesson view must agree on the same canonical text semantics

## Backend Safety Rule

Backend services must never mutate text formatting as part of normal request handling.

Rules:

- Backend services may validate content
- Backend services may reject non-canonical content
- Backend services may route legacy content through an explicit migration path
- Backend services must not silently rewrite formatting during create, update, fetch, or render operations
- Text normalization belongs to the canonical Markdown pipeline, not to unrelated backend service logic

The backend is responsible for preserving canonical text exactly as received once it has passed contract validation.

## Migration Strategy

Legacy content may contain:

- HTML media tags
- HTML emphasis
- mixed Markdown and HTML
- editor-native JSON payloads

A migration script must convert legacy content into canonical Markdown.

Migration requirements:

- Convert HTML media tags into canonical media tokens
- Convert HTML emphasis into canonical Markdown emphasis
- Remove or transform unsupported HTML into valid Markdown
- Detect and convert legacy editor JSON into canonical Markdown
- Produce content that satisfies the idempotence requirement before it is considered migrated

Migration is the only place where legacy-to-canonical rewriting is allowed.

## Final Section

This document is the single source of truth for all persistent rich text in the system.

Any database schema, backend service, API contract, editor adapter, renderer, migration, or future rich-text feature must follow this contract. If implementation behavior conflicts with this document, the implementation is out of contract.
