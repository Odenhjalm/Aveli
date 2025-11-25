# Deployment Playbook

## Local (Docker)
```bash
cp .env.docker.example .env.docker  # fill secrets
docker compose --env-file .env.docker up --build
# Backend: http://localhost:8080, Landing: http://localhost:3000
```

## Fly.io (backend)
1. Install `flyctl` and log in.
2. Set secrets (rotate from the leaked set listed in `docs/SECURITY.md`):
   ```bash
   flyctl secrets set \
     SUPABASE_URL=... SUPABASE_ANON_KEY=... SUPABASE_SERVICE_ROLE_KEY=... \
     SUPABASE_DB_URL=... SUPABASE_JWT_SECRET=... \
     STRIPE_SECRET_KEY=... STRIPE_PUBLISHABLE_KEY=... \
     STRIPE_WEBHOOK_SECRET=... STRIPE_BILLING_WEBHOOK_SECRET=... \
     STRIPE_PRICE_MONTHLY=... STRIPE_PRICE_YEARLY=... \
     LIVEKIT_API_KEY=... LIVEKIT_API_SECRET=... LIVEKIT_WS_URL=... LIVEKIT_API_URL=... \
     JWT_SECRET=... MEDIA_SIGNING_SECRET=... MEDIA_SIGNING_TTL_SECONDS=600 \
     FRONTEND_BASE_URL=https://your-frontend.app \
     CHECKOUT_SUCCESS_URL=https://your-frontend.app/checkout/success \
     CHECKOUT_CANCEL_URL=https://your-frontend.app/checkout/cancel
   ```
3. Deploy:
   ```bash
   flyctl deploy --config fly.toml
   ```
   - Uses `backend/Dockerfile`, internal port `8080`.
   - Health checks: `/healthz`, `/readyz`.

## Landing (Next.js)
- Location: `frontend/landing`
- Local: `npm install && npm run dev`
- Production: build static/export or host on Vercel/Netlify with env:
  - `NEXT_PUBLIC_SUPABASE_URL`
  - `NEXT_PUBLIC_SUPABASE_ANON_KEY`
  - `NEXT_PUBLIC_API_BASE_URL` (backend HTTPS URL)

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
