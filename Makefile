.PHONY: dev dev-reset backend.setup backend.dev backend.test backend.lint supabase.migrate qa.teacher docker.up docker.down flutter.get flutter.test guardrails.install task.branch

dev:
	./scripts/dev.sh

dev-reset:
	./scripts/dev_bootstrap.sh

backend.setup:
	cd backend && poetry env use 3.11 && poetry install --sync

backend.dev:
	./scripts/dev.sh

backend.test:
	cd backend && ./.venv/bin/python -m pytest --maxfail=1 --disable-warnings

backend.lint:
	cd backend && ./.venv/bin/python -m ruff check app tests

supabase.migrate:
	SUPABASE_DB_URL=$${SUPABASE_DB_URL:?set SUPABASE_DB_URL} backend/scripts/apply_supabase_migrations.sh

qa.teacher:
	cd backend && set -a && . ./.env && set +a && ./.venv/bin/python scripts/qa_teacher_smoke.py --base-url "$${QA_BASE_URL:-http://127.0.0.1:8080}"

docker.up:
	DOCKER_BUILDKIT=1 docker compose --env-file .env.docker up --build

docker.down:
	docker compose --env-file .env.docker down --remove-orphans

flutter.get:
	cd frontend && flutter pub get

flutter.test:
	cd frontend && flutter test

guardrails.install:
	./codex/scripts/install-task-guardrails.sh

task.branch:
	@test -n "$(TASK)" || (echo "Set TASK, example: make task.branch TASK='lesson reorder'" && exit 1)
	./codex/scripts/start-task-branch.sh "$(TASK)"
