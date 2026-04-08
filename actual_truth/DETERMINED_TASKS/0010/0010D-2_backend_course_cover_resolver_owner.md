# 0010D-2

- TASK_ID: `0010D-2`
- TYPE: `OWNER`
- TITLE: `Create the canonical backend course cover resolver`
- DEPENDS_ON:
  - `0009A`
  - `0010D-1`

## problem_statement

The mounted backend has no active `resolve_course_cover()` owner and `attach_course_cover_read_contract()` is a no-op. Course reads therefore expose storage identity without a backend-authored resolved cover object.

## target_state

- Backend exposes one canonical course cover resolver.
- Resolver input is `cover_media_id` from `app.courses`.
- Resolver output is `null | { media_id, state, resolved_url }`.
- Resolver uses canonical backend media/storage primitives only.
- Resolver does not read legacy `cover_url`.
- Resolver does not require frontend signing or frontend media inference.

## verification_method

- `rg -n "def resolve_course_cover|attach_course_cover_read_contract" backend/app/services`
- Run a targeted backend import script that exercises:
  - `cover_media_id = null -> cover = null`
  - missing asset -> object with `resolved_url = null`
  - ready canonical asset -> object with deterministic `resolved_url`
- `rg -n "cover_url" backend/app/services/courses_service.py backend/app/services/courses_read_service.py`
