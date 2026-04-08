# 0010D-1

- TASK_ID: `0010D-1`
- TYPE: `OWNER`
- TITLE: `Align course cover contract shape across canonical read-model contracts`
- DEPENDS_ON:
  - `0010A`

## problem_statement

`COURSE_COVER_READ_CONTRACT.md` defines the canonical cover read shape as `null | { media_id, state, resolved_url }`, but active learner/public contract definitions still describe `source` as part of the cover object. That leaves the cover read shape ambiguous before backend and frontend execution work begins.

## target_state

- Canonical course cover read shape is identical everywhere it is defined for learner/public read surfaces.
- `CourseCoverResolved` is defined only as:
  - `media_id`
  - `state`
  - `resolved_url`
- Canonical contract text states that frontend does not resolve course cover URLs from `cover_media_id`.

## verification_method

- `rg -n "CourseCoverResolved|source" actual_truth/contracts`
- Confirm learner/public contract files no longer define `source` on the course cover read object.
- Confirm canonical contract text names backend read layer as the sole authority for read-time cover resolution.
