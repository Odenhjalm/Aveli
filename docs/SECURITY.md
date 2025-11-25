# Security & Secret Hygiene

## Current status
- All committed secrets were removed from the repo. The leaked values in `.env`/`.env.test` included Supabase DB credentials, Supabase anon/service keys, Stripe test keys, LiveKit keys, JWT/media secrets. Rotate them immediately.

## Rotation checklist
1. **Supabase**
   - Rotate anon and service role keys in the Supabase dashboard.
   - Generate a new database password and update `SUPABASE_DB_URL`/`DATABASE_URL`.
   - Regenerate the JWT secret (`SUPABASE_JWT_SECRET`) and update the auth config.
2. **Stripe**
   - Create new secret + publishable keys; rotate webhook signing secrets (`STRIPE_WEBHOOK_SECRET`, `STRIPE_BILLING_WEBHOOK_SECRET`).
   - Replace all price/product IDs if they were tied to compromised test data.
3. **LiveKit**
   - Regenerate API key/secret and webhook secret.
4. **Backend auth**
   - Issue new `JWT_SECRET` and `MEDIA_SIGNING_SECRET`.
5. **Clients**
   - Refresh any cached configuration in CI, Fly.io, and local `.env` files with the rotated values.

## Handling secrets
- Only use the provided templates: `.env.example`, `.env.example.backend`, `.env.example.flutter`, `.env.docker.example`.
- Keep real secrets in untracked files (`.env`, `.env.backend`, `frontend/.env`) or secret managers (Fly.io secrets, GitHub Actions secrets).
- `.gitignore` blocks `.env*`, `/local`, `/secrets`, keys, certs, sqlite files, and editor noise.

## Git history rewrite
- Use `git filter-repo` to strip leaked files from history (see `docs/DEPLOYMENT.md` for commands).
- Force-push after rewriting history and notify collaborators to rebase/clone.

## Access control & observability
- Restrict Supabase IP allowlists for service role/db URLs.
- Enforce least-privilege for GitHub secrets; remove unused ones.
- Monitor `/healthz` + `/readyz` and Stripe/LiveKit webhooks for unexpected failures after rotations.
