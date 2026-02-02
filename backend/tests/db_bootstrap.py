from __future__ import annotations

import atexit
import os
import subprocess
import time
import uuid
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class TestDatabase:
    container_name: str
    host: str
    port: int
    db_name: str
    user: str
    password: str
    image: str

    @property
    def url(self) -> str:
        return f"postgresql://{self.user}:{self.password}@{self.host}:{self.port}/{self.db_name}"


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _migrations_dir() -> Path:
    return _repo_root() / "supabase" / "migrations"


def _read_supabase_postgres_tag() -> str | None:
    version_path = _repo_root() / "supabase" / "supabase" / ".temp" / "postgres-version"
    try:
        raw = version_path.read_text(encoding="utf-8").strip()
    except OSError:
        return None
    return raw or None


def _default_image() -> str:
    tag = _read_supabase_postgres_tag()
    if tag:
        return f"supabase/postgres:{tag}"
    # Fallback: keep in sync with CI if possible.
    return "supabase/postgres:17.6.1.054"


def _run(cmd: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        check=check,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )


def _wait_for_postgres(container_name: str, *, timeout_seconds: float = 60.0) -> None:
    deadline = time.monotonic() + timeout_seconds
    readiness_sql = (
        "select "
        "(to_regclass('auth.users') is not null) "
        "and (to_regprocedure('auth.uid()') is not null) "
        "and (to_regprocedure('auth.role()') is not null) "
        "and (to_regclass('storage.buckets') is not null);"
    )

    # Supabase Postgres performs extra init steps, including a restart. Prefer
    # waiting for the container healthcheck when available to avoid racing the
    # init shutdown/startup cycle.
    while time.monotonic() < deadline:
        proc = subprocess.run(
            [
                "docker",
                "inspect",
                "--format",
                "{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}",
                container_name,
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        status = proc.stdout.strip() if proc.returncode == 0 else ""
        if status in {"healthy", "none"}:
            break
        time.sleep(0.25)

    while time.monotonic() < deadline:
        proc = subprocess.run(
            [
                "docker",
                "exec",
                "-i",
                container_name,
                "psql",
                "-U",
                "postgres",
                "-d",
                "postgres",
                "-tAc",
                readiness_sql,
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        if proc.returncode == 0 and proc.stdout.strip() == "t":
            return
        time.sleep(0.25)
    raise RuntimeError(
        "Timed out waiting for Supabase Postgres to become ready inside the test container."
    )


def _container_host_port(container_name: str) -> int:
    proc = _run(["docker", "port", container_name, "5432/tcp"])
    # Example output: "127.0.0.1:32768\n"
    text = proc.stdout.strip().splitlines()[0].strip()
    port_str = text.rsplit(":", 1)[-1]
    return int(port_str)


def _apply_migrations(container_name: str) -> None:
    migrations_dir = _migrations_dir()
    if not migrations_dir.exists():
        raise RuntimeError(f"Missing migrations directory: {migrations_dir}")

    migrations = sorted(migrations_dir.glob("*.sql"))
    if not migrations:
        raise RuntimeError(f"No migrations found in: {migrations_dir}")

    for path in migrations:
        proc = subprocess.run(
            [
                "docker",
                "exec",
                "-i",
                container_name,
                "psql",
                "-U",
                "postgres",
                "-d",
                "postgres",
                "-v",
                "ON_ERROR_STOP=1",
                "-f",
                f"/migrations/{path.name}",
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        if proc.returncode != 0:
            raise RuntimeError(
                f"Failed applying migration {path.name}.\n{proc.stdout}"
            )


def stop_test_db(db: TestDatabase) -> None:
    subprocess.run(
        ["docker", "stop", db.container_name],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )


def start_test_db() -> TestDatabase:
    if os.environ.get("AVELI_ALLOW_REMOTE_DB_IN_TESTS") == "1":
        raise RuntimeError(
            "AVELI_ALLOW_REMOTE_DB_IN_TESTS=1 is not supported. "
            "Tests must never connect to Supabase or other remote databases."
        )

    migrations_dir = _migrations_dir()
    container_name = f"aveli-test-db-{uuid.uuid4().hex[:12]}"
    image = os.environ.get("AVELI_TEST_POSTGRES_IMAGE") or _default_image()
    password = os.environ.get("AVELI_TEST_POSTGRES_PASSWORD") or "postgres"

    cmd = [
        "docker",
        "run",
        "-d",
        "--rm",
        "--name",
        container_name,
        "-e",
        f"POSTGRES_PASSWORD={password}",
        "-e",
        "POSTGRES_DB=postgres",
        "-p",
        "127.0.0.1::5432",
        "-v",
        f"{migrations_dir}:/migrations:ro",
        image,
    ]

    try:
        _run(cmd)
    except FileNotFoundError as exc:
        raise RuntimeError(
            "Docker is required to run backend tests safely (local ephemeral Postgres). "
            "Install Docker and ensure the 'docker' CLI is on PATH."
        ) from exc
    except subprocess.CalledProcessError as exc:
        raise RuntimeError(
            f"Failed to start test Postgres container using image '{image}'.\n{exc.stdout}"
        ) from exc

    db = TestDatabase(
        container_name=container_name,
        host="127.0.0.1",
        port=_container_host_port(container_name),
        db_name="postgres",
        user="postgres",
        password=password,
        image=image,
    )

    atexit.register(stop_test_db, db)

    _wait_for_postgres(container_name)
    _apply_migrations(container_name)

    return db
