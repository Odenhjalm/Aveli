# Deployment Playbook

## Local (Docker)
```bash
cp .env.docker.example .env.docker  # fill secrets
docker compose --env-file .env.docker up --build
# Backend: http://localhost:8080, Landing: http://localhost:3000
```

## Canonical Production Release

Production release is intentionally manual. The deterministic path is:

1. Pick one exact commit on `main`.
2. Verify the database target explicitly.
3. Apply migrations from root `supabase/migrations` only.
4. Deploy backend from the same commit.
5. Trigger the frontend production deploy for the same commit via Netlify source build.
6. Run post-deploy health and runtime-media smoke checks.

### 1. Preflight (exact SHA, clean tree, green checks)

Run release steps from the exact commit you intend to ship:

```bash
git fetch origin main
git checkout <release-sha>
test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
test -z "$(git status --porcelain)"
```

Required GitHub checks for the release SHA must be green before continuing:

- `Backend CI`
- `Validate App Stack`
- `Web CI`
- `Deploy Guard (Flutter Web)`

### 2. Verify the production DB target explicitly

Point the verification scripts at the exact env file or exported env vars you plan to use for release. Do not rely on workstation-specific defaults for production:

```bash
BACKEND_ENV_FILE=/path/to/backend-release.env \
python3 backend/scripts/supabase_verify_env.py

MASTER_ENV_FILE=/path/to/backend-release.env \
VERIFY_WRITE_REPORT=0 \
APP_ENV=production \
backend/scripts/db_verify_remote_readonly.sh
```

Production migration source is root `supabase/migrations` only.

- Do not use `backend/supabase/migrations` for production.
- Do not use `cd backend && supabase db push` for production.
- Do not apply ad hoc SQL directly as a normal release path.

### 3. Apply production migrations from the release commit

Export `SUPABASE_DB_URL` and `SUPABASE_DB_PASSWORD` from the verified release env, then apply the canonical migration set:

```bash
APP_ENV=production \
REQUIRE_CLEAN_WORKTREE=1 \
SUPABASE_PROJECT_REF=<expected-project-ref> \
SUPABASE_DB_URL=postgresql://... \
SUPABASE_DB_PASSWORD=... \
backend/scripts/apply_supabase_migrations.sh
```

### 4. Deploy backend from the same commit

Deploy Fly only after the migration step succeeds:

```bash
flyctl deploy --config fly.toml
```

Notes:

- `fly.toml` uses `backend/Dockerfile` and listens on port `8080`.
- Fly currently automates `/healthz`; treat `/readyz` as a required post-deploy smoke check.
- The worker process is part of the backend release surface. Confirm both app and worker are healthy after deploy.

### 5. Deploy frontend from the same commit

Canonical production web release is a Netlify source build from the linked repo at the same commit SHA.

- Use `netlify.toml` plus Netlify UI/env vars as the production config source.
- Trigger or promote the Netlify production deploy for the same SHA after backend deploy completes.
- Do not use `frontend/.env.web` as production config.
- Do not use `netlify deploy --dir=build/web --prod` as the production path.
- Do not ship a locally built `frontend/build/web` artifact to production.

### 6. Post-deploy verification

At minimum, verify:

```bash
curl -fsS https://aveli.fly.dev/healthz
curl -fsS https://aveli.fly.dev/readyz
```

Then run one authenticated runtime-media smoke against the live backend using a known-good production `runtime_media_id` from an existing smoke account or previously verified content:

```bash
curl -fsS https://aveli.fly.dev/api/media/playback \
  -H "Authorization: Bearer <token>" \
  -H "Content-Type: application/json" \
  -d '{"runtime_media_id":"<known-good-runtime-media-id>"}'
```

Expected result:

- HTTP `200`
- response contains an absolute `playback_url`
- worker logs stay healthy during and after the request

## Fly.io (backend)
1. Install `flyctl` and log in.
2. Set secrets (rotate from the leaked set listed in `docs/SECURITY.md`):
   ```bash
   flyctl secrets set \
     SUPABASE_URL=... SUPABASE_PUBLISHABLE_API_KEY=... SUPABASE_SECRET_API_KEY=... \
     SUPABASE_DB_URL=... \
     STRIPE_SECRET_KEY=... STRIPE_PUBLISHABLE_KEY=... \
     STRIPE_WEBHOOK_SECRET=... STRIPE_BILLING_WEBHOOK_SECRET=... \
     STRIPE_PRICE_MONTHLY=... STRIPE_PRICE_YEARLY=... \
     LIVEKIT_API_KEY=... LIVEKIT_API_SECRET=... LIVEKIT_WS_URL=... LIVEKIT_API_URL=... \
     JWT_SECRET=... MEDIA_SIGNING_SECRET=... MEDIA_SIGNING_TTL_SECONDS=600 \
     FRONTEND_BASE_URL=https://your-frontend.app \
     STRIPE_RETURN_URL=https://app.aveli.app/checkout/return?session_id={CHECKOUT_SESSION_ID} \
     CHECKOUT_SUCCESS_URL=${STRIPE_RETURN_URL} \
     CHECKOUT_CANCEL_URL=https://app.aveli.app/checkout/cancel
   ```
3. Deploy:
   ```bash
   flyctl deploy --config fly.toml
   ```
   - Uses `backend/Dockerfile`, internal port `8080`.
   - Automated Fly health check: `/healthz`.
   - Required manual post-deploy smoke: `/readyz` plus one authenticated runtime-media path.

## Troubleshooting: schema_migrations drift
Break-glass only. This is not part of the canonical production release path.

If remote DB verify reports missing/extra migrations after you have already applied SQL:
```bash
CONFIRM_SCHEMA_MIGRATIONS_FIX=1 \
SUPABASE_DB_URL=postgresql://... \
backend/scripts/fix_schema_migrations.sh
```
This updates `supabase_migrations.schema_migrations` only (no schema changes).

## Landing (Next.js)
- Location: `frontend/landing`
- Local: `npm install && npm run dev`
- Production: build static/export or host on Vercel/Netlify with env:
  - `NEXT_PUBLIC_SUPABASE_URL`
  - `NEXT_PUBLIC_SUPABASE_ANON_KEY` (use the Supabase publishable key)
  - `NEXT_PUBLIC_API_BASE_URL` (backend HTTPS URL)

## Netlify (Flutter Web app)
- Source: Flutter app in `frontend/`
- Netlify config: `netlify.toml` runs `frontend/scripts/netlify_build_web.sh`
- Required Netlify env vars (set in Netlify UI; **no `.env` files for web**):
  - `FLUTTER_API_BASE_URL` → `--dart-define=API_BASE_URL=...`
  - `FLUTTER_SUPABASE_URL` → `--dart-define=SUPABASE_URL=...`
  - `FLUTTER_SUPABASE_PUBLIC_API_KEY` → `--dart-define=SUPABASE_PUBLIC_API_KEY=...`
  - `FLUTTER_STRIPE_PUBLISHABLE_KEY` → `--dart-define=STRIPE_PUBLISHABLE_KEY=...`
  - `FLUTTER_OAUTH_REDIRECT_WEB` → `--dart-define=OAUTH_REDIRECT_WEB=...`
- Build safety: the Netlify build **fails fast** if any required env var is missing (prevents the red config banner in production).
- Reminder: `--dart-define` values are compiled into the frontend bundle (public). Never pass backend secrets.
- Production deploys must be Netlify source builds from the linked repo on `main`.
- Local `flutter build web` output and `netlify deploy --dir=build/web --prod` are legacy/manual artifact paths and are not canonical production release steps.

## Git history cleanup
Rewrite to purge leaked secrets and binary artifacts:
```bash
pip install git-filter-repo  # if not installed
git filter-repo \
  --path .env --path .env.test --path supabase_linux_amd64.tar.gz \
  --path docs/archive/backups --invert-paths
git remote prune origin
git push origin --force --tags
```
Have collaborators reclone or `git fetch --all` + `git reset --hard origin/main` after the rewrite.
