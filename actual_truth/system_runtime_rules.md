# System Runtime Rules

## Definition Of Runtime Truth

Runtime truth is defined by actively mounted FastAPI routers in
[backend/app/main.py](/home/rodenhjalm/Aveli-editor/backend/app/main.py).

Repo code that is not mounted is implementation inventory, not active system
behavior.

## Active Router Rule

"Only routers mounted in main.py define active system behavior"

As of the current runtime entrypoint, the mounted routers are:

- `playback.router`
- `courses.router`
- `courses.api_router`
- `studio.course_lesson_router`
- `studio.lesson_media_router`

## Inert Route Rule

All non-mounted routes are inert.

If a route is declared in a route module but its router is not included in
`backend/app/main.py`, that route:

- is NOT part of system behavior
- MUST NOT be treated as runtime truth
- MUST NOT be used as audit authority
- MUST NOT block deterministic execution of scoped tasks

## Studio Route Interpretation

In [backend/app/routes/studio.py](/home/rodenhjalm/Aveli-editor/backend/app/routes/studio.py),
only endpoints attached to:

- `course_lesson_router`
- `lesson_media_router`

are active in the current app runtime.

Endpoints attached only to `router` are source-present but inert until
`backend/app/main.py` explicitly mounts `studio.router`.

## Execution Consequence

For verification and task execution:

- mounted routers define runtime truth
- non-mounted routes are excluded from active system behavior
- any future mount change requires this rule file to be re-audited

## Runtime Media Authority Rules

- runtime MUST use `runtime_media` only for all media surfaces
- runtime MUST reject invalid media state
- runtime MUST NOT infer media behavior
- runtime MUST NOT validate pipeline rules
- runtime MUST NOT fallback to ingest, storage identity, or legacy fields
- runtime MUST NOT inspect `media_assets` directly when constructing resolved media output
