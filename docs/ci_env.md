# CI Environment & Secrets

GitHub Actions now writes `backend/.env` during every backend workflow run so the test
suite no longer depends on a committed `.env`. Populate the following secrets in your
repository settings (Settings → Secrets and variables → Actions → Repository secrets):

| Secret | Used for | Notes |
| --- | --- | --- |
| `CI_DATABASE_URL` | `DATABASE_URL` | Point at the Postgres instance you run tests against. |
| `CI_SUPABASE_URL` | `SUPABASE_URL` | Supabase project URL (only needed for presign/uploads). |
| `CI_SUPABASE_ANON_KEY` | `SUPABASE_ANON_KEY` | Optional if tests never hit anon endpoints. |
| `CI_SUPABASE_SERVICE_ROLE_KEY` | `SUPABASE_SERVICE_ROLE_KEY` | Required for signed URLs and storage presigns. |
| `CI_SUPABASE_DB_URL` | `SUPABASE_DB_URL` | Optional alias if different from `DATABASE_URL`. |
| `CI_MEDIA_SIGNING_SECRET` | `MEDIA_SIGNING_SECRET` | Enables `/media/stream/*` smoke tests. |
| `CI_STRIPE_SECRET_KEY` | `STRIPE_SECRET_KEY` | Needed for checkout/service tests using Stripe mocks. |
| `CI_STRIPE_WEBHOOK_SECRET` | `STRIPE_WEBHOOK_SECRET` | Used by webhook signature verification tests. |
| `CI_FRONTEND_URL` | `FRONTEND_URL` | Base URL for generated links (defaults to `http://localhost:3000`). |

All secrets are optional; the workflow falls back to safe defaults if a secret is not
configured. The defaults mirror `.env.ci.backend` and target a local development stack.

To reproduce CI locally, copy `.env.ci.backend` into `backend/.env` and override the
values you need:

```bash
cp .env.ci.backend backend/.env
sed -i 's|postgresql://postgres:postgres@localhost:5432/aveli|postgresql://oden:pass@localhost:5432/aveli|' backend/.env
```

Never commit real secrets to the repository—only provide them via `.env` on your machine
or through GitHub Secrets in CI.
