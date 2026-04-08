# Aveli Markdown Contract v1

## 1. Truth model
- Editor truth is Delta.
- Persisted `content_markdown` is the canonical interchange format.
- UI is not truth.
- The read path is a strict consumer, not a healing layer.
- Persisted markdown states are classified as `canonical`, `valid_legacy`, or `invalid`.

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

## 3. Persisted states
### A. Canonical
Preferred persisted form going forward.

Canonical in v1 includes:
- plain text
- `*italic*`
- `**bold**`
- links
- inline code
- fenced code
- media tokens
- normal block markdown used by Aveli
- punctuation-inside-label form: `**Tips:** text`

### B. Valid legacy
Allowed persisted forms that are not preferred, but are deterministic in the current
`markdown_to_editor -> Quill` runtime and therefore do not block apply by themselves.

Valid legacy in v1 includes:
- `_italic_`
- post-close punctuation or dash adjacency such as:
  - `**ALFA**–`
  - `**text**,`
  - `**text**.`
- label punctuation outside bold when deterministic, such as `**Morrigan**:`

Rules:
- valid legacy may be normalized later
- valid legacy is not a blocking defect
- the read path may consume valid legacy
- the write path should still prefer canonical output

### C. Invalid
Blocking contract violations.

Invalid in v1 includes:
- escaped emphasis that shows literal markers
- whitespace directly inside emphasis delimiters
- unbalanced emphasis
- post-close alphanumeric adjacency such as:
  - `**Tips:**Om`
  - `**Energi**Ljus`
  - `**guidebyte**i`
- mixed-formatting boundary cases that produce ambiguous or non-deterministic import/render behavior
- raw HTML emphasis tags if present

## 4. Inline rules
- No whitespace directly inside emphasis delimiters in canonical output.
- Label punctuation belongs inside the bold span in canonical output.
  - canonical: `**Tips:** text`
  - valid legacy if deterministic: `**Morrigan**: text`
- After a closing emphasis delimiter, canonical output uses:
  - whitespace
  - newline
  - end-of-block
- Post-close punctuation or dash adjacency may remain `valid_legacy` if deterministic.
- Post-close alphanumeric adjacency is `invalid`.

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
- `valid_legacy` persisted markdown is allowed when deterministic, but is still not the preferred write form.
- `invalid` persisted markdown is a blocking data-quality defect.
- The read path may log violations but must not invent semantics.
- Apply is only allowed when:
  - false positives = 0
  - risky cases = 0
  - invalid rows remaining = 0

## 7. Decision rule for new patterns
- A new pattern must become either:
  - supported canonical syntax, or
  - migration-only legacy input
- Do not add runtime healing without contract + test + migration rule
