# 0010D-5

- TASK_ID: `0010D-5`
- TYPE: `OWNER`
- TITLE: `Align landing course cards to the canonical cover read contract`
- DEPENDS_ON:
  - `0010D-2`
  - `0010D-4`

## problem_statement

Landing course cards still expose a separate cover shape based on `resolved_cover_url` and optional `cover_media_id`, which leaves a second backend/frontend course-cover contract alive after the core course read surfaces move to backend-authored `cover`.

## target_state

- Landing course cards use the canonical backend-authored course cover shape.
- Landing backend queries no longer emit `NULL::text AS resolved_cover_url` as a separate contract field.
- Landing frontend course-card parsing/rendering does not carry a parallel course-cover contract.

## verification_method

- `rg -n "resolved_cover_url|cover_media_id" backend/app/models.py backend/app/schemas/__init__.py frontend/lib/features/landing`
- Run landing route serialization checks after the contract change.
