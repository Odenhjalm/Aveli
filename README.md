# Aveli Monorepo

Aveli contains the Flutter client, FastAPI backend, Supabase baseline artifacts,
and Next.js landing page. This README is operator orientation only. It is
subordinate to the accepted authority files under `actual_truth/`, especially
`actual_truth/contracts/baseline_v2_authority_freeze_contract.md` and
`actual_truth/contracts/production_deployment_contract.md`.

Authority summary:

- Baseline V2 is a clean conceptual rebaseline with full cutover as the
  implementation target.
- Canonical local baseline evidence is `backend/supabase/baseline_v2_slots/`
  and `backend/supabase/baseline_v2_slots.lock.json`.
- Superseded baseline slot chains are archived legacy evidence only.
- Legacy migrations, historical launch reports, stale docs, local notes, and
  README text do not override accepted contracts.
- LiveKit surfaces may exist in the repository, but LiveKit runtime is
  paused/inert unless later accepted authority explicitly activates it.
- Stripe checkout/session/subscription values are provider correlation only.
  Aveli commerce authority remains in `orders`, `payments`, and `memberships`.
- User-facing product text must be Swedish.
- Generated operator prompts must be copy-paste-ready English.

## Repository Layout

```text
.
|-- actual_truth/       # Canonical authority docs and contracts
|-- backend/            # FastAPI app, baseline replay scripts, Dockerfile
|-- frontend/           # Flutter app and Next.js landing site
|   `-- landing/        # Marketing/landing site
|-- supabase/           # Legacy/root migration history and tooling input
|-- .env.example*       # Safe templates for backend and Flutter
|-- docker-compose.yml  # Optional local compose path
`-- fly.toml            # Fly.io backend deployment config
```

## Prerequisites

- Python 3.11+
- Flutter 3.24+ for `frontend/`
- Node 18+ for `frontend/landing`
- `psql` client
- Docker, optional for compose
- Supabase and Stripe credentials for the runtime surfaces under test
- LiveKit credentials only when an accepted authority explicitly activates or
  verifies that surface; current Baseline V2 authority treats LiveKit as
  paused/inert

## Authority References

- Baseline V2 freeze:
  `actual_truth/contracts/baseline_v2_authority_freeze_contract.md`
- Production deployment:
  `actual_truth/contracts/production_deployment_contract.md`
- System decisions:
  `actual_truth/Aveli_System_Decisions.md`
- Structured manifest:
  `actual_truth/aveli_system_manifest.json`
- Baseline manifest:
  `actual_truth/AVELI_DATABASE_BASELINE_MANIFEST.md`
- System laws:
  `actual_truth/contracts/SYSTEM_LAWS.md`

This README may explain how to orient locally. It does not define launch,
schema, media, commerce, LiveKit, onboarding, or production authority.

## Environment

- Copy `.env.example` to `.env` and `.env.example.backend` to `.env.backend`
  when those templates are needed for local development.
- Flutter local runs may use `frontend/.env.local` or explicit
  `--dart-define` flags.
- Web runs may use `frontend/.env.web` for local development only.
- Production web deploys must use Netlify environment variables plus
  `netlify.toml`, not a checked-in `.env` file.
- Do not commit real keys. Environment files with secrets must remain ignored.
- Backend listens on port `8080` by default.

## Backend Startup

The only valid backend startup entrypoint is `backend.bootstrap.run_server`.

```bash
# Windows
.\.venv\Scripts\python.exe -m backend.bootstrap.run_server

# Linux/macOS
./.venv/bin/python -m backend.bootstrap.run_server
```

- Health: `/healthz`.
- Readiness: `/readyz`.
- Do not use shell activation, `poetry run`, bare `python`, or direct `uvicorn`
  as backend startup authority.

## Baseline And Local DB Authority

- Authoritative local DB source:
  `backend/supabase/baseline_v2_slots/`.
- Canonical baseline lock:
  `backend/supabase/baseline_v2_slots.lock.json`.
- Canonical native local target:
  `postgresql://postgres:postgres@127.0.0.1:5432/aveli_local`.
- Ensure the native local database exists with
  `backend/scripts/ensure_db.sh`.
- Materialize the accepted local baseline on native local Postgres with
  `backend/scripts/replay_v2.sh`.
- Root `supabase/migrations/`, archived migrations, cloned cloud DB state, and
  historical reports are reference or tooling inputs only. They do not override
  baseline slots, the lockfile, or accepted contracts.
- Production database and deployment authority lives in
  `actual_truth/contracts/production_deployment_contract.md`.

## Backend Tests And Lint

```bash
make backend.test
make backend.lint
make qa.teacher
```

`make qa.teacher` expects a running backend on port `8080` and the required
local secrets for the surface being tested.

## Flutter App

```bash
cd frontend
flutter pub get
flutter test
flutter run --dart-define-from-file=.env.local
```

Android emulator runs use `http://10.0.2.2:8080` through the environment
resolver. For web builds, use a web-specific defines file:

```bash
flutter run -d chrome --dart-define-from-file=.env.web
```

Ensure local define files include `API_BASE_URL` and the relevant OAuth redirect
values for the target runtime.

## Landing Site

```bash
cd frontend/landing
npm install
npm run dev
```

Default local URL: `http://localhost:3000`.

## Docker

```bash
docker compose --env-file .env.docker up --build
```

- Backend: `http://localhost:8080`.
- Landing: `http://localhost:3000`.
- Docker is optional and reference-only for the local DB path.
- The canonical baseline replay target remains the native Postgres instance on
  `127.0.0.1:5432/aveli_local`.

## Deployment

Production deployment authority lives in
`actual_truth/contracts/production_deployment_contract.md`.

README deployment notes are not launch authority. Before production deployment
planning is valid, operators must satisfy the accepted contracts for:

- exact production Supabase project targeting;
- baseline scope through `0038`, unless later accepted V2 slot authority
  replaces that chain;
- separate Fly `app` and `worker` process groups;
- `/healthz` and `/readyz`;
- onboarding and membership app-entry authority;
- profile/community media as canonical Baseline V2 scope;
- `home_player_course_links` as source truth with backend read composition;
- `runtime_media` as read-only projection where in scope;
- LiveKit paused/inert status;
- provider checkout/session/subscription values as correlation only;
- Swedish user-facing product text;
- copy-paste-ready English generated operator prompts.

Do not use README text, missing docs, stale docs, legacy migration paths, or
local operator notes as production deployment authority.

## Tooling

- Scripts live in `backend/scripts`.
- Root `scripts/` may exist for compatibility.
- MCP Supabase helper: `backend/scripts/mcp_supabase.py`.
- `.vscode/mcp.json` and `backend/supabase/.temp/*` are repo-local targeting
  evidence only. They are not production database authority.

## Task Branch Guardrail

Install once per clone:

```bash
make guardrails.install
```

Start every new task on a fresh branch:

```bash
make task.branch TASK="short task name"
```

The repo hooks block commit and push on protected branches such as `main`,
`master`, `develop`, `dev`, `production`, and `release`.
