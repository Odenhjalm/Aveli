# Backend

FastAPI API backed by Supabase-compatible Postgres and storage integrations.
This README is operator orientation only. It is subordinate to the accepted
authority files under `../actual_truth/`, especially
`../actual_truth/contracts/baseline_v2_authority_freeze_contract.md` and
`../actual_truth/contracts/production_deployment_contract.md`.

Unless stated otherwise, commands and paths in this README are relative to the
repository root.

Authority summary:

- Backend startup authority is `backend.bootstrap.run_server`.
- Local baseline authority is `backend/supabase/baseline_v2_slots/` plus
  `backend/supabase/baseline_v2_slots.lock.json`.
- Root or legacy migrations are reference/tooling inputs only unless a later
  accepted authority explicitly promotes them.
- Stripe is a provider integration. Checkout, session, subscription, and
  payment identifiers are provider correlation only.
- Aveli commerce authority remains in `orders`, `payments`, and `memberships`.
- `subscription` may remain provider/order modality, but not Aveli domain
  authority.
- Service/session/Connect-like order fields are inert unless later activated by
  accepted authority.
- LiveKit route, worker, webhook, and queue surfaces are present only as
  paused/inert runtime support under the accepted LiveKit contract.
- User-facing product text must be Swedish.
- Generated operator prompts must be copy-paste-ready English.

## Environment

Load local environment values from `backend/.env.local` or `backend/.env` when
needed for local development. Environment files are not authority and must not
override accepted contracts.

Common local variables:

- Supabase: `SUPABASE_URL`, `SUPABASE_SECRET_API_KEY`,
  `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_PUBLISHABLE_API_KEY`,
  `SUPABASE_ANON_KEY`, `SUPABASE_DB_URL`.
- Stripe: `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY`,
  `STRIPE_WEBHOOK_SECRET`, `STRIPE_BILLING_WEBHOOK_SECRET`,
  `STRIPE_PRICE_MONTHLY`, `STRIPE_PRICE_YEARLY`, `STRIPE_PRICE_SERVICE_*`.
- LiveKit: `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `LIVEKIT_WS_URL`,
  `LIVEKIT_API_URL`, `LIVEKIT_WEBHOOK_SECRET`. These variables may exist, but
  LiveKit remains paused/inert unless later accepted authority activates it.
- Auth/media: `JWT_SECRET`, `MEDIA_SIGNING_SECRET`,
  `MEDIA_SIGNING_TTL_SECONDS`, `LESSON_MEDIA_MAX_BYTES`.
- Checkout redirects: `FRONTEND_BASE_URL`, `CHECKOUT_SUCCESS_URL`,
  `CHECKOUT_CANCEL_URL`.

Default backend port: `8080`.

## Run Locally

From the repository root, use the explicit interpreter entrypoint:

```bash
# Windows
.\.venv\Scripts\python.exe -m backend.bootstrap.run_server

# Linux/macOS
./.venv/bin/python -m backend.bootstrap.run_server
```

- `/healthz` checks process responsiveness.
- `/readyz` checks database readiness.
- `/metrics` is available when `prometheus_client` is installed.
- Do not use `poetry run uvicorn`, direct `uvicorn`, shell activation, or bare
  `python` as startup authority.

## Local DB Authority

- Authoritative local DB source:
  `backend/supabase/baseline_v2_slots/`.
- Canonical baseline lock:
  `backend/supabase/baseline_v2_slots.lock.json`.
- Canonical native local target:
  `postgresql://postgres:postgres@127.0.0.1:5432/aveli_local`.
- Ensure the native local database exists with `backend/scripts/ensure_db.sh`.
- Materialize the accepted local baseline with
  `backend/scripts/replay_v2.sh`.

Cloud clones, legacy database state, root migrations, archived migrations, and
interactive SQL output are reference or tooling inputs only. They do not
override baseline slots, the lockfile, or accepted contracts.

## Production Database And Deployment

Production deployment authority lives in
`../actual_truth/contracts/production_deployment_contract.md`.

This README does not authorize production migration execution, production DB
mutation, baseline slot edits, or lockfile edits. Production planning must
follow the accepted production deployment contract, the Baseline V2 freeze
contract, and the baseline manifest.

## Tests

```bash
make backend.test
make backend.lint
```

Smoke:

```bash
make qa.teacher
```

Smoke tests require a running backend and the local secrets required for the
surface under test.

## Runtime Authority Notes

- Auth and onboarding authority is governed by the accepted auth/onboarding
  contracts and decisions. `welcome_pending` is canonical onboarding state.
- App entry is composed from onboarding and membership authority.
- Media source tables own governed inclusion and placement truth.
- `runtime_media` remains read-only projection authority where in scope.
- `home_player_course_links` is source truth for course-linked home-audio
  inclusion, with backend composition as read authority.
- Profile/community media is canonical Baseline V2 scope.
- `profile_media_placements` owns authored-placement truth.
- `profiles` remains projection-only.
- Stripe provider events may correlate payment state, but Aveli domain truth is
  settled through backend order, payment, membership, and course-access
  authority.
- LiveKit must not be treated as active launch runtime without later accepted
  activation authority.

## Key Modules

- `app/main.py` - app wiring, routers, CORS, health, and metrics.
- `app/config.py` - runtime settings for Supabase, Stripe, LiveKit, auth, and
  media integrations.
- `app/services/` - domain and provider services.
- `app/repositories/` - DB access per domain.
- `app/routes/` - API endpoints.

Module descriptions are navigational only. They do not redefine accepted
authority.
