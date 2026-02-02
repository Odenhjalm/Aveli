import pytest

from app.testing.db_safety import assert_safe_test_db_url


def test_allows_localhost_database_url():
    assert_safe_test_db_url(
        "postgresql://postgres:postgres@localhost:5432/postgres", source="DATABASE_URL"
    )


def test_blocks_supabase_database_hosts():
    with pytest.raises(RuntimeError, match="Supabase"):
        assert_safe_test_db_url(
            "postgresql://postgres:postgres@db.example.supabase.co:5432/postgres",
            source="DATABASE_URL",
        )


def test_blocks_non_local_hosts():
    with pytest.raises(RuntimeError, match="local database"):
        assert_safe_test_db_url(
            "postgresql://postgres:postgres@10.10.10.10:5432/postgres",
            source="DATABASE_URL",
        )


def test_allows_unix_socket_dsn():
    assert_safe_test_db_url(
        "host=/run/postgresql dbname=postgres user=postgres",
        source="psycopg.connect",
    )

