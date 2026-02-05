#!/usr/bin/env bash
set -euo pipefail

CMD="${1:-}"

IMAGE="${LOCAL_DB_IMAGE:-supabase/postgres:15.1.0.117}"
CONTAINER="${LOCAL_DB_CONTAINER:-aveli-postgres}"
VOLUME_DEFAULT="aveli_postgres_data"
VOLUME="${LOCAL_DB_VOLUME:-$VOLUME_DEFAULT}"
PORT="${LOCAL_DB_PORT:-54322}"
USER="${LOCAL_DB_USER:-postgres}"
PASSWORD="${LOCAL_DB_PASSWORD:-postgres}"
DB="${LOCAL_DB_NAME:-aveli_local}"

LOCAL_DATABASE_URL="postgresql://${USER}:${PASSWORD}@127.0.0.1:${PORT}/${DB}"

usage() {
  cat <<TXT
Usage: $(basename "$0") <command>

Commands:
  up       Start local Postgres container (creates if missing)
  down     Stop/remove container (keeps volume)
  reset    Stop/remove container + delete volume (DANGER: wipes data)
  url      Print LOCAL_DATABASE_URL
  psql     Open psql to local DB
TXT
}

require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: docker is required." >&2
    exit 1
  fi
}

wait_ready() {
  local wait_seconds="${LOCAL_DB_WAIT_SECONDS:-60}"
  if command -v pg_isready >/dev/null 2>&1; then
    for _ in $(seq 1 "$wait_seconds"); do
      if pg_isready -h 127.0.0.1 -p "$PORT" -U "$USER" -d "$DB" >/dev/null 2>&1; then
        return 0
      fi
      sleep 1
    done
    echo "ERROR: local Postgres did not become ready within ${wait_seconds}s (port ${PORT})." >&2
    exit 1
  fi
}

container_exists() {
  docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"
}

container_running() {
  docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"
}

container_host_port() {
  docker inspect "$CONTAINER" --format '{{(index (index .HostConfig.PortBindings "5432/tcp") 0).HostPort}}' 2>/dev/null || true
}

container_data_volume() {
  docker inspect "$CONTAINER" --format '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql/data"}}{{.Name}}{{end}}{{end}}' 2>/dev/null || true
}

case "$CMD" in
  up)
    require_docker
    if container_exists; then
      if [[ -z "${LOCAL_DB_VOLUME:-}" ]]; then
        detected_volume="$(container_data_volume)"
        if [[ -n "$detected_volume" ]]; then
          VOLUME="$detected_volume"
        fi
      fi
      existing_port="$(container_host_port)"
      if [[ -n "$existing_port" && "$existing_port" != "$PORT" ]]; then
        echo "WARN: Existing ${CONTAINER} publishes port ${existing_port}; recreating on ${PORT} (volume preserved: ${VOLUME})." >&2
        docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
      fi
      if ! container_running; then
        if container_exists; then
          docker start "$CONTAINER" >/dev/null
        fi
      fi
    fi
    if ! container_exists; then
      docker run -d \
        --name "$CONTAINER" \
        -e POSTGRES_PASSWORD="$PASSWORD" \
        -e POSTGRES_USER="$USER" \
        -e POSTGRES_DB="$DB" \
        -p "${PORT}:5432" \
        -v "${VOLUME}:/var/lib/postgresql/data" \
        "$IMAGE" >/dev/null
    fi
    wait_ready
    echo "LOCAL_DATABASE_URL=${LOCAL_DATABASE_URL}"
    ;;
  down)
    require_docker
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    ;;
  reset)
    require_docker
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
    docker volume rm "$VOLUME" >/dev/null 2>&1 || true
    ;;
  url)
    echo "$LOCAL_DATABASE_URL"
    ;;
  psql)
    if ! command -v psql >/dev/null 2>&1; then
      echo "ERROR: psql is required." >&2
      exit 1
    fi
    PGPASSWORD="$PASSWORD" psql "$LOCAL_DATABASE_URL"
    ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    echo "ERROR: unknown command: $CMD" >&2
    usage >&2
    exit 2
    ;;
esac
