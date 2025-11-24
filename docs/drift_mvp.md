# Driftinstruktioner (lokal MVP)

1. Kopiera `.env.example` → `.env` och fyll Stripe/Supabase/LiveKit-värden.
2. Starta databasen:
   ```bash
   make db.up
   make db.migrate
   make db.seed
   ```
3. Backend dev-server:
   ```bash
   make backend.dev
   # alternativt docker
   docker compose up backend
   ```
4. Flutter/Next-webb:
   ```bash
   make web.dev    # Next.js
   flutter run -t lib/mvp/mvp_app.dart
   ```
5. Landing-sidan byggs statiskt i `web/landing` och serveras via `docker compose up landing`.
6. QA-script: `python scripts/qa_teacher_smoke.py --base-url http://127.0.0.1:8000 --seminar-id <uuid>`.

> Tips: `docker compose up` startar Postgres, backend och landing i samma kommando (port 8000/4173).
