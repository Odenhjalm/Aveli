# Aveli Markdown Contract v1

## 1. Truth model
- Editor truth is Delta.
- Persisted `content_markdown` is the canonical interchange format.
- UI is not truth.
- The read path is a strict consumer, not a healing layer.

## 2. Priority order
Use this exact evaluation order:

P0. Opaque spans
- fenced code
- inline code
- links
- images
- media tokens / embeds

P1. Block structure
- headings
- lists
- block quotes
- paragraphs
- blank lines

P2. Escapes / literal text

P3. Strong emphasis
- `**bold**`

P4. Emphasis
- `*italic*`

P5. Plain text

## 3. Supported canonical syntax
Allowed:
- plain text
- `*italic*`
- `**bold**`
- links
- inline code
- fenced code
- media tokens
- normal block markdown used by Aveli

Not canonical in v1:
- `__bold__`
- `_italic_`
- raw HTML emphasis tags
- overlapping emphasis
- free-form mixed emphasis not explicitly round-trip tested
- intraword emphasis forms that depend on parser ambiguity

## 4. Canonical inline rules
- No whitespace directly inside emphasis delimiters.
- Label punctuation belongs inside the bold span.
  - canonical: `**Tips:** text`
  - not canonical: `**Tips**: text`
- After a closing emphasis delimiter, the canonical boundary is:
  - whitespace
  - newline
  - end-of-block
- Therefore these are non-canonical and must normalize or be flagged:
  - `**Tips:**Om`
  - `**Energi**Ljus`
  - `**OBS!**Giftig`
  - `**guidebyte**i`

## 5. Normalization order
Use this exact order:
1. Protect opaque spans
2. Normalize basic whitespace / line endings
3. Convert legacy bold forms
4. Fix delimiter whitespace
5. Move label punctuation inside bold span
6. Enforce post-close boundary
7. Re-run normalization and require idempotence
8. Restore protected spans
9. Validate against contract

## 6. Validation and apply gate
- Canonical markdown must round-trip through the current `markdown_to_editor` path deterministically.
- Non-canonical persisted markdown is a data-quality defect.
- The read path may log violations but must not invent semantics.
- Apply is only allowed when:
  - false positives = 0
  - risky cases = 0
  - remaining out-of-contract rows are explicitly classified and intentionally out of scope

## 7. Decision rule for new patterns
- A new pattern must become either:
  - supported canonical syntax, or
  - migration-only legacy input
- Do not add runtime healing without contract + test + migration rule
