.PHONY: backend.setup backend.dev backend.test backend.lint supabase.migrate qa.teacher docker.up docker.down

backend.setup:
	cd backend && poetry env use 3.11 && poetry install --sync

backend.dev:
	cd backend && poetry run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

backend.test:
	cd backend && poetry run pytest --maxfail=1 --disable-warnings

backend.lint:
	cd backend && poetry run ruff check app tests

supabase.migrate:
	SUPABASE_DB_URL=$${SUPABASE_DB_URL:?set SUPABASE_DB_URL} scripts/apply_supabase_migrations.sh

qa.teacher:
	python3 scripts/qa_teacher_smoke.py --base-url "$${QA_BASE_URL:-http://127.0.0.1:8000}"

docker.up:
	DOCKER_BUILDKIT=1 docker compose --env-file .env.docker up --build

docker.down:
	docker compose --env-file .env.docker down --remove-orphans
