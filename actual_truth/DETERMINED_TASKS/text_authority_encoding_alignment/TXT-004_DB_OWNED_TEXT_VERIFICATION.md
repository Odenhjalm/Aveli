# TXT-004 DB-Owned Text Verification

TYPE: GATE
DEPENDS_ON: [TXT-001, TXT-002, TXT-002A, TXT-003]
MODE: execute
STATUS: COMPLETE_WITH_LANGUAGE_WARNING

This artifact records read-only verification of DB-owned user-facing text fields
against the established text authority model. It does not change runtime
behavior, frontend rendering, backend response envelopes, DB schema, DB values,
email templates, Stripe behavior, or catalog ownership.

## 1. Authority Load

Loaded authority inputs:

- `codex/AVELI_OPERATING_SYSTEM.md`
- `codex/AVELI_EXECUTION_WORKFLOW.md`
- `actual_truth/contracts/system_text_authority_contract.md`
- `actual_truth/contracts/backend_text_catalog_contract.md`
- `actual_truth/DETERMINED_TASKS/text_authority_encoding_alignment/TXT-001_TEXT_SURFACE_INVENTORY.md`
- `actual_truth/DETERMINED_TASKS/text_authority_encoding_alignment/TXT-002_TEXT_CATALOG_MAPPING.md`
- `actual_truth/DETERMINED_TASKS/text_authority_encoding_alignment/TXT-002A_CONCRETE_TEXT_CATALOG_MAPPING_REMEDIATION.md`
- `actual_truth/DETERMINED_TASKS/text_authority_encoding_alignment/TXT-003_NON_LEGAL_BACKEND_TEXT_CATALOG_VALUES.md`
- `actual_truth/Aveli_System_Decisions.md`
- `actual_truth/aveli_system_manifest.json`
- active contracts under `actual_truth/contracts/`

Index binding:

- Existing `.repo_index/index_manifest.json` was present.
- Canonical search interpreter `.repo_index/.search_venv/Scripts/python.exe` was present.
- Initial index query was blocked until the D01 dependency result authority was
  bound.
- Query was then executed with
  `actual_truth/DETERMINED_TASKS/retrieval_index_environment_dependencies/D01_environment_dependency_result_c78b8e68c25d1484475bf3f07b25facc97ddcf89278cc36f02b3d480509fa8e3.json`.

## 2. TXT-004 Precheck

Precheck result: PASS.

- TXT-001, TXT-002, TXT-002A, and TXT-003 exist.
- TXT-001 and TXT-002 classify DB-rendered fields as `db_domain_content` or
  `db_user_content`.
- TXT-002A preserves DB-owned fields as DB-owned concrete fields.
- TXT-003 explicitly leaves DB-owned fields unpopulated as catalog values.
- No DB-owned field was reassigned to canonical backend catalog text.

Runtime and environment gate:

- `backend/.env.local` supplied the local DB target.
- Verified database target: `aveli_local`.
- Verified host: `127.0.0.1`.
- Verified port: `5432`.
- Verified `MCP_MODE=local`.
- Cloud environment variables were not used for DB inspection.
- `ops/mcp_bootstrap_gate.ps1` returned `MCP_BOOTSTRAP_GATE_OK`.
- PostgreSQL reported `server_encoding=UTF8` and `client_encoding=UTF8`.

## 3. DB Verification Scope

Only authority-classified DB-owned rendered fields were inspected.

| DB field | Authority class | Canonical owner | TXT authority basis |
|---|---|---|---|
| `app.profiles.display_name` | `db_user_content` | Profile projection backend read composition | TXT-001, TXT-002, TXT-002A |
| `app.profiles.bio` | `db_user_content` | Profile projection backend read composition | TXT-001, TXT-002, TXT-002A |
| `auth.users.email` | `db_user_content` | Auth/profile projection only | TXT-001, TXT-002A |
| `app.auth_subjects.email` | `db_user_content` | Auth/profile projection only | contract-authorized projection substrate |
| `app.courses.title` | `db_domain_content` | Course contracts and backend read composition | TXT-001, TXT-002, TXT-002A |
| `app.course_public_content.short_description` | `db_domain_content` | Course public surface backend read composition | TXT-001, TXT-002, TXT-002A |
| `app.lessons.lesson_title` | `db_domain_content` | Course/lesson contracts and backend read composition | TXT-001, TXT-002, TXT-002A |
| `app.lesson_contents.content_markdown` | `db_domain_content` | Course/lesson content backend read composition | TXT-001, TXT-002, TXT-002A |
| `app.home_player_uploads.title` | `db_domain_content` | Home audio backend read composition | TXT-001, TXT-002, TXT-002A |
| `app.home_player_course_links.title` | `db_domain_content` | Home audio backend read composition | TXT-001, TXT-002, TXT-002A |
| `app.course_bundles.title` | `db_domain_content` | Commerce/course bundle backend read composition | TXT-001, TXT-002, TXT-002A |

Excluded from TXT-004 value inspection:

- Catalog-owned product text IDs from TXT-003.
- Non-user-facing identifiers.
- Media diagnostic fields classified as non-user-facing identifiers.
- Legal copy blocked by TXT-002A/TXT-003.
- Future-facing blocked domains.

## 4. Inspection Method

Inspection was read-only.

SQL operations:

- `SHOW server_encoding`
- `SHOW client_encoding`
- `SELECT` from `information_schema.columns`
- `SELECT` aggregate value checks from in-scope DB-owned fields
- `SELECT` redacted or bounded sample evidence from in-scope DB-owned fields

No SQL mutation was executed.

Encoding checks:

- PostgreSQL server/client encoding must be UTF-8.
- Mojibake marker checks used ASCII-only SQL with `chr(...)` code-point
  detection to avoid introducing command-line encoding ambiguity.
- Checked marker families:
  - `chr(195)` broad U+00C3 marker family
  - `chr(194)` broad U+00C2 marker family
  - `chr(65533)` replacement character
  - `chr(239)||chr(191)||chr(189)` degraded replacement sequence
- Checked ASCII-degraded Swedish patterns:
  - `losenord`
  - `aterstall`
  - `forsok`
  - `atkomst`
  - `larare`
  - `behorighet`
  - `bekraft`
  - `overblick`
  - `installning`

Language checks:

- `db_user_content` profile fields are user-generated and are not falsely forced
  into Swedish-only policy when empty or user-authored.
- Email identity fields are DB-owned identity text and are not language-copy.
- `db_domain_content` is product-visible domain content and must be classified
  for Swedish-only readiness before render compliance can be claimed.
- English marker checks were heuristic and evidence-based, not a replacement
  for later rendered-output language gates.

## 5. Field / Value Classification Summary

| DB field | Rows | Nonempty | Mojibake rows | Replacement rows | ASCII-degraded Swedish rows | English marker rows | Language status | Classification |
|---|---:|---:|---:|---:|---:|---:|---|---|
| `app.profiles.display_name` | 8 | 0 | 0 | 0 | 0 | 0 | user-generated; no nonempty local values | `PASS_DB_OWNED_USER_GENERATED` |
| `app.profiles.bio` | 8 | 0 | 0 | 0 | 0 | 0 | user-generated; no nonempty local values | `PASS_DB_OWNED_USER_GENERATED` |
| `auth.users.email` | 4 | 4 | 0 | 0 | 0 | 0 | identity value; not language-copy | `PASS_DB_OWNED_SAFE` |
| `app.auth_subjects.email` | 8 | 8 | 0 | 0 | 0 | 0 | identity value; not language-copy | `PASS_DB_OWNED_SAFE` |
| `app.courses.title` | 6 | 6 | 0 | 0 | 0 | 6 | English DB-domain content present | `WARNING_LANGUAGE_MIXED` |
| `app.course_public_content.short_description` | 0 | 0 | 0 | 0 | 0 | 0 | no local values | `PASS_DB_OWNED_SAFE` |
| `app.lessons.lesson_title` | 0 | 0 | 0 | 0 | 0 | 0 | no local values | `PASS_DB_OWNED_SAFE` |
| `app.lesson_contents.content_markdown` | 0 | 0 | 0 | 0 | 0 | 0 | no local values | `PASS_DB_OWNED_SAFE` |
| `app.home_player_uploads.title` | 0 | 0 | 0 | 0 | 0 | 0 | no local values | `PASS_DB_OWNED_SAFE` |
| `app.home_player_course_links.title` | 0 | 0 | 0 | 0 | 0 | 0 | no local values | `PASS_DB_OWNED_SAFE` |
| `app.course_bundles.title` | 2 | 2 | 0 | 0 | 0 | 0 | Swedish domain title values: `Paket A`, `Paket B` | `PASS_DB_OWNED_SAFE` |

Sample evidence:

| DB field | Evidence |
|---|---|
| `app.courses.title` | 6 values matched English marker checks; bounded samples include `Course bundle-course-418e99`, `Course bundle-course-6799f9`, `Course bundle-stripe-fail-one-874a16`, `Course bundle-stripe-fail-two-7c24c9`, `Course bundle-course-d33c77`, `Course bundle-course-bad-e37dec`. |
| `app.course_bundles.title` | 2 values inspected: `Paket A`, `Paket B`. |
| `auth.users.email` | 4 values inspected as redacted identity values; raw email values were not copied into this artifact. |
| `app.auth_subjects.email` | 8 values inspected as redacted identity values; raw email values were not copied into this artifact. |

## 6. Failures / Warnings

Warnings:

| Classification | Field | Evidence | Effect |
|---|---|---|---|
| `WARNING_LANGUAGE_MIXED` | `app.courses.title` | 6 of 6 nonempty values contain English marker evidence and bounded samples begin with `Course`. | Swedish-only DB-domain render compliance is not confirmed for this field. |

Failures:

- No `FAIL_ENCODING_UNSAFE` field was found.
- No `FAIL_AUTHORITY_MISCLASSIFIED` field was found.

Authority preservation:

- DB-owned content remains DB-owned.
- DB-owned content was not moved into TXT-003 catalog values.
- Empty DB-owned fields were not treated as catalog gaps.
- User-generated profile content was not forced into Swedish-only policy beyond
  encoding and authority validation.

## 7. Blockers / Stop Conditions

TXT-004 does not block because of DB access; local DB inspection completed.

Downstream Swedish-only render compliance is blocked until the
`app.courses.title` English DB-domain values are addressed by a later
DB-content remediation task or excluded from product-visible verification by an
explicit contract-backed fixture policy.

STOP conditions for downstream tasks:

- Do not claim all user-facing DB-owned domain content is Swedish while
  `app.courses.title` contains the inspected English values.
- Do not reassign `app.courses.title` into catalog ownership to hide DB-content
  language drift.
- Do not mutate DB values under TXT-004.
- Do not treat redacted email identity values as Swedish product copy.
- Do not claim rendered UI compliance until backend/API/frontend render gates
  verify delivery and rendering.

## 8. Ready / Blocked For Next Task

TXT-004 DB inspection itself is complete.

Readiness:

- READY for a downstream task that consumes the TXT-004 classification evidence.
- BLOCKED for any downstream task that requires the claim "all user-facing
  DB-owned product/domain content is Swedish" before DB-content language drift
  is remediated or explicitly scoped out by contract.

Final TXT-004 assertion:

- DB-owned text authority is preserved.
- DB-owned values were classified for encoding and language safety.
- No encoding-unsafe DB-owned values were found.
- English DB-domain content remains present in `app.courses.title`.
- No runtime compliance is claimed.
