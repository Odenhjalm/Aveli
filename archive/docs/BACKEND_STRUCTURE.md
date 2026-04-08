# Backend Structure (FastAPI)

```
backend/
├── app/                  # FastAPI application
│   ├── config.py         # Pydantic settings (Supabase, Stripe, LiveKit, media)
│   ├── db.py             # Database pool + connection helpers
│   ├── main.py           # App factory, routers, CORS, health endpoints
│   ├── routes/           # API routers (auth, courses, payments, webhooks, sfu)
│   ├── services/         # Stripe, LiveKit, storage, checkout, subscriptions
│   ├── repositories/     # DB access helpers
│   ├── schemas/          # Pydantic models
│   └── utils/            # Logging, HTTP helpers
├── assets/               # Static assets served via /assets
├── media/                # Runtime uploads (gitignored)
├── scripts/              # QA + ops helpers (also via root symlink scripts/)
├── tests/                # pytest suite (unit + integration)
├── Dockerfile            # Production image (PORT 8080)
├── pyproject.toml        # Poetry dependencies
└── README.md             # Backend-specific notes
```

## Runtime
- Default port: `8080`
- Health: `/healthz`, Ready: `/readyz`, Metrics: `/metrics` (Prometheus if installed)
- CORS defaults to localhost dev; override with `CORS_ALLOW_ORIGINS`/`CORS_ALLOW_ORIGIN_REGEX`.

## Integrations
- **Supabase**: `supabase_url`, `supabase_service_role_key`, `supabase_db_url`. Storage presign handled in `app/services/storage_service.py`.
- **Stripe**: Secret + webhook secrets (`STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_BILLING_WEBHOOK_SECRET`), price IDs for subscriptions and services (`STRIPE_PRICE_*` envs). Connect client ID/return URLs optional.
- **LiveKit**: `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`, `LIVEKIT_WS_URL`, `LIVEKIT_API_URL`, optional webhook secret.
- **Auth/media**: `JWT_SECRET`, `MEDIA_SIGNING_SECRET`, `MEDIA_SIGNING_TTL_SECONDS`, `LESSON_MEDIA_MAX_BYTES`.

## Scripts (selected)
- `apply_supabase_migrations.sh` – apply SQL migrations under `supabase/migrations`.
- `qa_teacher_smoke.py` – smoke test login/order/Stripe paths against a running backend.
- `mcp_supabase.py` – call Supabase MCP endpoint defined in `.vscode/mcp.json`.
- `presign_upload.py` – presign Supabase Storage uploads using backend settings.
- Course import helpers: `import_course.py`, `bulk_import.py`, `validate_courses.sh`.

## Tests
- `pytest` suite under `backend/tests` (Stripe/LiveKit mocked).
- Use `make backend.test` for the common path; CI mirrors the same flow (`.github/workflows/flutter.yml`).
