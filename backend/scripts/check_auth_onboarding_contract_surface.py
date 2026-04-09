from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
import os
from pathlib import Path
import re
import sys
from urllib.parse import urlparse
from uuid import uuid4

from httpx import ASGITransport, AsyncClient


ROOT = Path(__file__).resolve().parents[2]
BACKEND_ROOT = ROOT / "backend"

if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))


def _configure_local_env() -> None:
    local_database_url = os.environ.get(
        "AVELI_TEST_DATABASE_URL",
        "postgresql://postgres:postgres@127.0.0.1:5432/aveli_local",
    )
    parsed = urlparse(local_database_url)
    for forbidden_key in (
        "SUPABASE_DB_URL",
        "SUPABASE_URL",
        "SUPABASE_SECRET_API_KEY",
        "SUPABASE_SERVICE_ROLE_KEY",
        "SUPABASE_PUBLISHABLE_API_KEY",
        "SUPABASE_PUBLIC_API_KEY",
        "SUPABASE_ANON_KEY",
        "SUPABASE_PROJECT_REF",
        "SUPABASE_JWKS_URL",
        "SUPABASE_JWT_ISSUER",
        "SUPABASE_JWT_SECRET",
        "SUPABASE_JWT_SECRET_LEGACY",
        "MCP_PRODUCTION_DATABASE_URL",
        "MCP_PRODUCTION_SUPABASE_DB_URL",
    ):
        os.environ.pop(forbidden_key, None)

    os.environ["APP_ENV"] = "local"
    os.environ["MCP_MODE"] = "local"
    os.environ["DATABASE_HOST"] = parsed.hostname or "127.0.0.1"
    os.environ["DATABASE_PORT"] = str(parsed.port or 5432)
    os.environ["DATABASE_NAME"] = (parsed.path or "/aveli_local").lstrip("/") or "aveli_local"
    os.environ["DATABASE_USER"] = parsed.username or "postgres"
    os.environ["DATABASE_PASSWORD"] = parsed.password or "postgres"
    os.environ["DATABASE_URL"] = local_database_url
    os.environ.setdefault("SENTRY_DSN", "")


_configure_local_env()

from app import db as app_db  # noqa: E402
from app.auth_onboarding_failures import is_auth_onboarding_surface  # noqa: E402
from app.config import settings  # noqa: E402
from app.main import app  # noqa: E402


CANONICAL_AUTH_ROUTE_SET = {
    ("POST", "/auth/register"),
    ("POST", "/auth/login"),
    ("POST", "/auth/forgot-password"),
    ("POST", "/auth/reset-password"),
    ("POST", "/auth/refresh"),
    ("POST", "/auth/send-verification"),
    ("GET", "/auth/verify-email"),
    ("GET", "/auth/validate-invite"),
    ("POST", "/auth/onboarding/complete"),
    ("GET", "/profiles/me"),
    ("PATCH", "/profiles/me"),
    ("POST", "/admin/users/{user_id}/grant-teacher-role"),
    ("POST", "/admin/users/{user_id}/revoke-teacher-role"),
}

REQUIRED_CANONICAL_ROUTES = {
    ("POST", "/auth/register"),
    ("POST", "/auth/login"),
    ("POST", "/auth/refresh"),
    ("POST", "/auth/onboarding/complete"),
    ("POST", "/admin/users/{user_id}/grant-teacher-role"),
    ("POST", "/admin/users/{user_id}/revoke-teacher-role"),
    ("GET", "/profiles/me"),
    ("PATCH", "/profiles/me"),
}

FORBIDDEN_ROUTES = {
    ("POST", "/auth/change-password"),
    ("POST", "/auth/request-password-reset"),
    ("POST", "/profiles/me/avatar"),
    ("POST", "/api/upload/profile"),
    ("POST", "/upload/profile"),
    ("GET", "/profiles/{user_id}/certificates"),
    ("POST", "/teacher-request"),
    ("GET", "/teacher-request"),
}

REQUIRED_TABLES = (
    ("auth", "users"),
    ("app", "auth_subjects"),
    ("app", "profiles"),
    ("app", "refresh_tokens"),
    ("app", "auth_events"),
    ("app", "admin_bootstrap_state"),
)

FORBIDDEN_TABLES = (
    ("app", "certificates"),
    ("app", "teacher_approvals"),
    ("app", "teacher_requests"),
)

REQUIRED_FUNCTIONS = (("app", "bootstrap_first_admin"),)

AUTH_SCOPE_BACKEND_FILES = (
    ROOT / "backend/app/auth.py",
    ROOT / "backend/app/main.py",
    ROOT / "backend/app/repositories/auth.py",
    ROOT / "backend/app/repositories/auth_subjects.py",
    ROOT / "backend/app/repositories/profiles.py",
    ROOT / "backend/app/routes/admin.py",
    ROOT / "backend/app/routes/auth.py",
    ROOT / "backend/app/routes/email_verification.py",
    ROOT / "backend/app/routes/profiles.py",
    ROOT / "backend/app/schemas/__init__.py",
)

AUTH_SCOPE_FRONTEND_FILES = (
    ROOT / "frontend/lib/api/api_paths.dart",
    ROOT / "frontend/lib/api/auth_repository.dart",
    ROOT / "frontend/lib/core/auth/auth_controller.dart",
    ROOT / "frontend/lib/domain/models/user_access.dart",
    ROOT / "frontend/lib/features/auth/application/user_access_provider.dart",
    ROOT / "frontend/lib/features/community/presentation/profile_page.dart",
)

AUTH_SCOPE_TEST_FILES = (
    ROOT / "backend/tests/test_admin_permissions.py",
    ROOT / "backend/tests/test_auth_change_password.py",
    ROOT / "backend/tests/test_auth_email_flows.py",
    ROOT / "backend/tests/test_auth_subject_authority_gate.py",
    ROOT / "backend/tests/test_onboarding_state.py",
    ROOT / "backend/tests/test_profiles_owner.py",
    ROOT / "backend/tests/utils.py",
    ROOT / "frontend/test/routing/app_router_test.dart",
    ROOT / "frontend/test/unit/auth_controller_test.dart",
    ROOT / "frontend/test/widgets/course_page_access_test.dart",
    ROOT / "frontend/test/widgets/login_page_test.dart",
    ROOT / "frontend/test/widgets/router_bootstrap_test.dart",
)


@dataclass
class ReportSection:
    name: str
    details: list[str] = field(default_factory=list)
    failures: list[str] = field(default_factory=list)

    def ok(self, detail: str) -> None:
        self.details.append(detail)

    def fail(self, detail: str) -> None:
        self.failures.append(detail)


def _read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return path.read_text(encoding="utf-8", errors="ignore")


def _inventory_auth_routes() -> list[tuple[str, str]]:
    inventory: set[tuple[str, str]] = set()
    for route in app.routes:
        methods = getattr(route, "methods", set())
        path = getattr(route, "path", "")
        for method in methods:
            if method in {"HEAD", "OPTIONS"}:
                continue
            if is_auth_onboarding_surface(method, path):
                inventory.add((method, path))
    return sorted(inventory, key=lambda item: (item[1], item[0]))


async def _query_rows(sql: str, params: tuple[object, ...] = ()) -> list[tuple]:
    async with app_db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(sql, params)
            rows = await cur.fetchall()
    return list(rows)


async def _ensure_pool_open() -> None:
    if app_db.pool.closed:
        await app_db.pool.open(wait=True)


def _test_headers(headers: dict[str, str] | None = None) -> dict[str, str]:
    merged = dict(headers or {})
    session_id = app_db.get_test_session_id()
    if session_id:
        merged.setdefault(app_db.TEST_SESSION_HEADER, session_id)
    return merged


def _auth_headers(token: str) -> dict[str, str]:
    return _test_headers({"Authorization": f"Bearer {token}"})


async def _register_user(
    client: AsyncClient,
    *,
    email: str,
    password: str,
    display_name: str,
) -> dict[str, str]:
    response = await client.post(
        "/auth/register",
        json={
            "email": email,
            "password": password,
            "display_name": display_name,
        },
        headers=_test_headers(),
    )
    if response.status_code != 201:
        raise AssertionError(f"register failed: {response.status_code} {response.text}")
    tokens = response.json()
    me_response = await client.get(
        "/profiles/me",
        headers=_auth_headers(tokens["access_token"]),
    )
    if me_response.status_code != 200:
        raise AssertionError(
            f"profiles/me failed after register: {me_response.status_code} {me_response.text}"
        )
    profile = me_response.json()
    return {
        "user_id": str(profile["user_id"]),
        "email": email,
        "password": password,
        "access_token": tokens["access_token"],
        "refresh_token": tokens["refresh_token"],
    }


async def _bootstrap_first_admin(user_id: str) -> None:
    async with app_db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                "SELECT (app.bootstrap_first_admin(%s::uuid)).user_id",
                (user_id,),
            )
            row = await cur.fetchone()
            if row is None:
                raise AssertionError("bootstrap_first_admin returned no row")
            await conn.commit()


async def _ensure_admin_user(
    client: AsyncClient,
    *,
    password: str = "Passw0rd!",
    display_name: str = "Admin",
) -> dict[str, str]:
    candidate = await _register_user(
        client,
        email=f"admin_{uuid4().hex[:8]}@example.com",
        password=password,
        display_name=display_name,
    )

    try:
        await _bootstrap_first_admin(candidate["user_id"])
        return candidate
    except Exception:
        pass

    async with app_db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                SELECT u.email, a.user_id
                  FROM auth.users u
                  JOIN app.auth_subjects a ON a.user_id = u.id
                 WHERE a.is_admin = true
                 ORDER BY u.created_at ASC NULLS LAST, u.id ASC
                """
            )
            admin_rows = await cur.fetchall()

    for email, user_id in admin_rows:
        login_response = await client.post(
            "/auth/login",
            json={"email": str(email), "password": password},
            headers=_test_headers(),
        )
        if login_response.status_code != 200:
            continue
        tokens = login_response.json()
        return {
            "access_token": tokens["access_token"],
            "refresh_token": tokens["refresh_token"],
            "user_id": str(user_id),
            "email": str(email),
            "password": password,
        }

    raise AssertionError("Unable to obtain a canonical admin user for aggregate verification")


async def _fetch_auth_subject(user_id: str) -> dict[str, object]:
    async with app_db.pool.connection() as conn:  # type: ignore[attr-defined]
        async with conn.cursor() as cur:  # type: ignore[attr-defined]
            await cur.execute(
                """
                SELECT onboarding_state, role_v2, role, is_admin
                  FROM app.auth_subjects
                 WHERE user_id = %s
                """,
                (user_id,),
            )
            row = await cur.fetchone()
    if row is None:
        raise AssertionError(f"auth_subject missing for {user_id}")
    return {
        "onboarding_state": row[0],
        "role_v2": row[1],
        "role": row[2],
        "is_admin": row[3],
    }


def _assert_canonical_failure(
    section: ReportSection,
    *,
    label: str,
    response,
    expected_status: int,
    expected_error_code: str,
) -> None:
    if response.status_code != expected_status:
        section.fail(
            f"{label}: expected HTTP {expected_status}, got {response.status_code}: {response.text}"
        )
        return
    payload = response.json()
    expected_keys = {"status", "error_code", "message"}
    allowed_keys = expected_keys | {"field_errors"}
    payload_keys = set(payload)
    if payload.get("status") != "error":
        section.fail(f"{label}: missing canonical status=error payload: {payload}")
        return
    if payload.get("error_code") != expected_error_code:
        section.fail(
            f"{label}: expected error_code={expected_error_code}, got {payload.get('error_code')}"
        )
        return
    if not isinstance(payload.get("message"), str) or not payload["message"].strip():
        section.fail(f"{label}: canonical message missing: {payload}")
        return
    if "detail" in payload or "error" in payload:
        section.fail(f"{label}: forbidden legacy error shape keys present: {payload}")
        return
    if not payload_keys.issubset(allowed_keys):
        section.fail(f"{label}: unexpected failure-envelope keys present: {payload}")
        return
    section.ok(
        f"{label}: HTTP {expected_status} uses canonical failure envelope ({expected_error_code})"
    )


def _scan_forbidden_patterns(
    section: ReportSection,
    *,
    files: tuple[Path, ...],
    rules: tuple[tuple[str, re.Pattern[str]], ...],
) -> None:
    for path in files:
        if not path.exists():
            section.fail(f"missing expected file: {path.relative_to(ROOT).as_posix()}")
            continue
        content = _read_text(path)
        rel_path = path.relative_to(ROOT).as_posix()
        for label, pattern in rules:
            match = pattern.search(content)
            if match:
                line = content.count("\n", 0, match.start()) + 1
                section.fail(f"{rel_path}:{line}: forbidden {label}")


def _scan_required_patterns(
    section: ReportSection,
    *,
    path: Path,
    rules: tuple[tuple[str, re.Pattern[str]], ...],
) -> None:
    content = _read_text(path)
    rel_path = path.relative_to(ROOT).as_posix()
    for label, pattern in rules:
        if not pattern.search(content):
            section.fail(f"{rel_path}: required canonical marker missing for {label}")


async def _route_inventory_section() -> ReportSection:
    section = ReportSection("Route Inventory")
    inventory = _inventory_auth_routes()
    inventory_set = set(inventory)
    for method, path in inventory:
        section.ok(f"{method} {path}")

    missing_required = sorted(REQUIRED_CANONICAL_ROUTES - inventory_set)
    unexpected_routes = sorted(inventory_set - CANONICAL_AUTH_ROUTE_SET)
    present_forbidden = sorted(inventory_set & FORBIDDEN_ROUTES)

    if missing_required:
        for method, path in missing_required:
            section.fail(f"missing canonical route: {method} {path}")
    if unexpected_routes:
        for method, path in unexpected_routes:
            section.fail(f"unexpected auth/onboarding route present: {method} {path}")
    if present_forbidden:
        for method, path in present_forbidden:
            section.fail(f"forbidden legacy route still mounted: {method} {path}")

    return section


async def _baseline_inventory_section() -> ReportSection:
    section = ReportSection("Baseline Inventory")
    required_table_rows = await _query_rows(
        """
        SELECT table_schema, table_name
          FROM information_schema.tables
         WHERE (table_schema, table_name) IN (
            ('auth', 'users'),
            ('app', 'auth_subjects'),
            ('app', 'profiles'),
            ('app', 'refresh_tokens'),
            ('app', 'auth_events'),
            ('app', 'admin_bootstrap_state')
         )
         ORDER BY table_schema, table_name
        """
    )
    existing_required_tables = {(row[0], row[1]) for row in required_table_rows}
    for schema_name, table_name in sorted(existing_required_tables):
        section.ok(f"{schema_name}.{table_name}")

    for required_table in REQUIRED_TABLES:
        if required_table not in existing_required_tables:
            section.fail(f"missing required canonical table: {required_table[0]}.{required_table[1]}")

    forbidden_exact_rows = await _query_rows(
        """
        SELECT table_schema, table_name
          FROM information_schema.tables
         WHERE (table_schema, table_name) IN (
            ('app', 'certificates'),
            ('app', 'teacher_approvals'),
            ('app', 'teacher_requests')
         )
         ORDER BY table_schema, table_name
        """
    )
    forbidden_like_rows = await _query_rows(
        """
        SELECT table_schema, table_name
          FROM information_schema.tables
         WHERE table_schema = 'app'
           AND table_name LIKE 'teacher_request%%'
         ORDER BY table_schema, table_name
        """
    )
    forbidden_tables = {(row[0], row[1]) for row in forbidden_exact_rows + forbidden_like_rows}
    for schema_name, table_name in sorted(forbidden_tables):
        section.fail(f"forbidden legacy table present: {schema_name}.{table_name}")

    function_rows = await _query_rows(
        """
        SELECT routine_schema, routine_name
          FROM information_schema.routines
         WHERE (routine_schema, routine_name) IN (('app', 'bootstrap_first_admin'))
         ORDER BY routine_schema, routine_name
        """
    )
    existing_functions = {(row[0], row[1]) for row in function_rows}
    for schema_name, routine_name in sorted(existing_functions):
        section.ok(f"{schema_name}.{routine_name}(uuid)")
    for required_function in REQUIRED_FUNCTIONS:
        if required_function not in existing_functions:
            section.fail(
                f"missing required canonical function: {required_function[0]}.{required_function[1]}"
            )

    return section


async def _failure_envelope_section() -> ReportSection:
    section = ReportSection("Failure Envelope")
    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport,
        base_url="http://testserver",
        headers=_test_headers(),
    ) as client:
        unauthenticated_profile = await client.get("/profiles/me")
        _assert_canonical_failure(
            section,
            label="GET /profiles/me unauthenticated",
            response=unauthenticated_profile,
            expected_status=401,
            expected_error_code="unauthenticated",
        )

        unauthenticated_admin = await client.post(
            f"/admin/users/{uuid4()}/grant-teacher-role"
        )
        _assert_canonical_failure(
            section,
            label="POST /admin/users/{user_id}/grant-teacher-role unauthenticated",
            response=unauthenticated_admin,
            expected_status=401,
            expected_error_code="unauthenticated",
        )

        referral_register = await client.post(
            "/auth/register",
            json={
                "email": f"referral_{uuid4().hex[:8]}@example.com",
                "password": "Passw0rd!",
                "display_name": "Referral",
                "referral_code": "legacy-referral",
            },
        )
        _assert_canonical_failure(
            section,
            label="POST /auth/register with referral_code",
            response=referral_register,
            expected_status=422,
            expected_error_code="validation_error",
        )

        invalid_login = await client.post(
            "/auth/login",
            json={
                "email": f"missing_{uuid4().hex[:8]}@example.com",
                "password": "wrong-password",
            },
        )
        _assert_canonical_failure(
            section,
            label="POST /auth/login invalid credentials",
            response=invalid_login,
            expected_status=401,
            expected_error_code="invalid_credentials",
        )

    return section


async def _authority_section() -> ReportSection:
    section = ReportSection("Authority Check")
    transport = ASGITransport(app=app)
    async with AsyncClient(
        transport=transport,
        base_url="http://testserver",
        headers=_test_headers(),
    ) as client:
        admin_user = await _ensure_admin_user(client)
        target_user = await _register_user(
            client,
            email=f"target_{uuid4().hex[:8]}@example.com",
            password="Passw0rd!",
            display_name="Target",
        )
        section.ok("canonical admin access is available for grant/revoke verification")

        patch_reject = await client.patch(
            "/profiles/me",
            headers=_auth_headers(target_user["access_token"]),
            json={
                "display_name": "Target",
                "onboarding_state": "completed",
                "role_v2": "teacher",
                "is_admin": True,
            },
        )
        _assert_canonical_failure(
            section,
            label="PATCH /profiles/me authority-field rejection",
            response=patch_reject,
            expected_status=422,
            expected_error_code="validation_error",
        )

        complete_response = await client.post(
            "/auth/onboarding/complete",
            headers=_auth_headers(target_user["access_token"]),
        )
        if complete_response.status_code != 200:
            section.fail(
                f"POST /auth/onboarding/complete failed: {complete_response.status_code} {complete_response.text}"
            )
        else:
            payload = complete_response.json()
            if payload != {
                "status": "completed",
                "onboarding_state": "completed",
                "token_refresh_required": True,
            }:
                section.fail(
                    f"onboarding completion response drifted from canonical contract: {payload}"
                )
            else:
                section.ok(
                    "POST /auth/onboarding/complete is the explicit onboarding mutation boundary"
                )

        subject_after_complete = await _fetch_auth_subject(target_user["user_id"])
        if subject_after_complete["onboarding_state"] != "completed":
            section.fail(
                f"onboarding_state was not completed canonically: {subject_after_complete}"
            )
        else:
            section.ok("app.auth_subjects owns onboarding_state after completion")

        refresh_after_onboarding = await client.post(
            "/auth/refresh",
            json={"refresh_token": target_user["refresh_token"]},
            headers=_test_headers(),
        )
        if refresh_after_onboarding.status_code != 200:
            section.fail(
                "explicit refresh after onboarding failed "
                f"({refresh_after_onboarding.status_code} {refresh_after_onboarding.text})"
            )
        else:
            payload = refresh_after_onboarding.json()
            if set(payload) != {"access_token", "refresh_token", "token_type"}:
                section.fail(f"/auth/refresh returned non-canonical token payload: {payload}")
            else:
                section.ok("token model uses explicit refresh with snapshot tokens")

        non_admin_grant = await client.post(
            f"/admin/users/{admin_user['user_id']}/grant-teacher-role",
            headers=_auth_headers(target_user["access_token"]),
        )
        _assert_canonical_failure(
            section,
            label="non-admin teacher grant rejection",
            response=non_admin_grant,
            expected_status=403,
            expected_error_code="admin_required",
        )

        grant_response = await client.post(
            f"/admin/users/{target_user['user_id']}/grant-teacher-role",
            headers=_auth_headers(admin_user["access_token"]),
        )
        if grant_response.status_code != 204:
            section.fail(
                "admin grant teacher route failed "
                f"({grant_response.status_code} {grant_response.text})"
            )
        else:
            section.ok("teacher authority mutates only through admin grant route")

        granted_subject = await _fetch_auth_subject(target_user["user_id"])
        if granted_subject["role_v2"] != "teacher" or granted_subject["role"] != "teacher":
            section.fail(f"teacher grant did not update canonical auth subject: {granted_subject}")
        else:
            section.ok("app.auth_subjects owns teacher role authority")

        revoked_refresh = await client.post(
            "/auth/refresh",
            json={"refresh_token": target_user["refresh_token"]},
            headers=_test_headers(),
        )
        _assert_canonical_failure(
            section,
            label="refresh after teacher grant revocation boundary",
            response=revoked_refresh,
            expected_status=401,
            expected_error_code="refresh_token_invalid",
        )

        relogin = await client.post(
            "/auth/login",
            json={
                "email": target_user["email"],
                "password": target_user["password"],
            },
            headers=_test_headers(),
        )
        if relogin.status_code != 200:
            section.fail(f"re-login after teacher grant failed: {relogin.status_code} {relogin.text}")
            new_refresh_token = None
        else:
            new_refresh_token = relogin.json()["refresh_token"]

        revoke_response = await client.post(
            f"/admin/users/{target_user['user_id']}/revoke-teacher-role",
            headers=_auth_headers(admin_user["access_token"]),
        )
        if revoke_response.status_code != 204:
            section.fail(
                "admin revoke teacher route failed "
                f"({revoke_response.status_code} {revoke_response.text})"
            )
        else:
            section.ok("teacher authority mutates only through admin revoke route")

        revoked_subject = await _fetch_auth_subject(target_user["user_id"])
        if revoked_subject["role_v2"] != "learner" or revoked_subject["role"] != "learner":
            section.fail(f"teacher revoke did not restore learner authority: {revoked_subject}")
        else:
            section.ok("teacher revocation returns canonical learner authority")

        if new_refresh_token is not None:
            revoked_again = await client.post(
                "/auth/refresh",
                json={"refresh_token": new_refresh_token},
                headers=_test_headers(),
            )
            _assert_canonical_failure(
                section,
                label="refresh after teacher revoke boundary",
                response=revoked_again,
                expected_status=401,
                expected_error_code="refresh_token_invalid",
            )

    backend_content = "\n".join(_read_text(path) for path in AUTH_SCOPE_BACKEND_FILES if path.exists())
    if "referral_code" in backend_content:
        section.fail("referral logic still appears inside auth/onboarding backend surface")
    else:
        section.ok("auth backend rejects referral coupling and does not own referral logic")

    onboarding_mutations = re.findall(
        r"SET\s+onboarding_state\s*=\s*'completed'",
        backend_content,
        flags=re.IGNORECASE,
    )
    if len(onboarding_mutations) != 1:
        section.fail(
            f"expected exactly one canonical onboarding completion mutation, found {len(onboarding_mutations)}"
        )
    else:
        section.ok("onboarding_state mutation exists only at the canonical repository boundary")

    auth_source = _read_text(ROOT / "backend/app/auth.py")
    required_authority_markers = (
        "auth_subject = await get_auth_subject(user_id)",
        "profile = await get_profile(user_id)",
        '"role": normalized_role',
        '"is_admin": is_admin',
    )
    for marker in required_authority_markers:
        if marker not in auth_source:
            section.fail(f"backend authority marker missing in app/auth.py: {marker}")
    if 'payload.get("role")' in auth_source or 'payload.get("is_admin")' in auth_source:
        section.fail("backend current-user authority still derives role/is_admin from token payload")
    else:
        section.ok("backend authority is resolved from canonical auth_subject/profile rows, not JWT claims")

    return section


async def _frontend_section() -> ReportSection:
    section = ReportSection("Frontend Check")
    forbidden_rules = (
        ("direct Supabase client usage", re.compile(r"\bSupabaseClient\b|\bsupabase_flutter\b|\bsupabase\.")),
        (
            "JWT claim authority usage",
            re.compile(r"\bAuthClaims\b|state\.claims|initialState\.claims|claims\s*:|\bapp_metadata\b|\buser_metadata\b"),
        ),
        ("legacy change-password route", re.compile(r"/auth/change-password")),
        ("legacy request-password-reset route", re.compile(r"/auth/request-password-reset")),
        ("legacy avatar upload route", re.compile(r"/profiles/me/avatar|/api/upload/profile|/upload/profile")),
        ("teacher request lifecycle", re.compile(r"teacher-request|teacher_request|teacher approval", re.IGNORECASE)),
    )
    _scan_forbidden_patterns(
        section,
        files=AUTH_SCOPE_FRONTEND_FILES,
        rules=forbidden_rules,
    )
    _scan_required_patterns(
        section,
        path=ROOT / "frontend/lib/api/auth_repository.dart",
        rules=(
            ("canonical onboarding complete call", re.compile(r"ApiPaths\.authOnboardingComplete")),
            ("explicit onboarding refresh boundary", re.compile(r"token_refresh_required")),
            ("explicit auth refresh call", re.compile(r"ApiPaths\.authRefresh")),
        ),
    )
    _scan_required_patterns(
        section,
        path=ROOT / "frontend/lib/domain/models/user_access.dart",
        rules=(
            ("frontend avoids JWT claims for authority", re.compile(r"Frontend must not derive role/admin authority from JWT claims")),
        ),
    )
    if not section.failures:
        section.ok("frontend authority remains backend-owned and refresh-after-onboarding is explicit")
    return section


async def _test_alignment_section() -> ReportSection:
    section = ReportSection("Test Alignment")
    forbidden_rules = (
        ("forbidden direct auth_subject mutation", re.compile(r"UPDATE\s+app\.auth_subjects|INSERT\s+INTO\s+app\.auth_subjects", re.IGNORECASE)),
        ("forbidden teacher approval table", re.compile(r"app\.teacher_approvals|teacher_request", re.IGNORECASE)),
        ("forbidden certificate authority table", re.compile(r"app\.certificates")),
        ("legacy JWT claim field usage", re.compile(r"\bAuthClaims\b|state\.claims|initialState\.claims|claims\s*:")),
    )
    _scan_forbidden_patterns(
        section,
        files=AUTH_SCOPE_TEST_FILES,
        rules=forbidden_rules,
    )
    _scan_required_patterns(
        section,
        path=ROOT / "backend/tests/test_onboarding_state.py",
        rules=(
            ("onboarding completion boundary test", re.compile(r"test_onboarding_complete_requires_explicit_refresh_boundary")),
            ("verify-email does not complete onboarding", re.compile(r"test_verify_email_does_not_complete_onboarding")),
        ),
    )
    _scan_required_patterns(
        section,
        path=ROOT / "backend/tests/test_admin_permissions.py",
        rules=(
            ("admin grant route coverage", re.compile(r"grant-teacher-role")),
            ("admin revoke route coverage", re.compile(r"revoke-teacher-role")),
        ),
    )
    _scan_required_patterns(
        section,
        path=ROOT / "backend/tests/test_profiles_owner.py",
        rules=(
            ("profile projection rejection coverage", re.compile(r"test_profiles_me_patch_rejects_non_projection_authority_fields")),
        ),
    )
    _scan_required_patterns(
        section,
        path=ROOT / "backend/tests/test_auth_change_password.py",
        rules=(
            ("referral rejection coverage", re.compile(r"test_register_rejects_referral_code_with_canonical_failure_envelope")),
            ("forbidden route inventory coverage", re.compile(r"test_removed_legacy_auth_and_profile_routes_are_not_mounted")),
        ),
    )
    if not section.failures:
        section.ok("auth/onboarding tests only assert canonical routes, backend authority, and canonical failures")
    return section


async def _main() -> int:
    settings.enable_test_session_headers = True
    session_id = str(uuid4())
    session_token = app_db.set_test_session_id(session_id)
    sections: list[ReportSection] = []

    try:
        await _ensure_pool_open()
        sections.append(await _route_inventory_section())
        sections.append(await _baseline_inventory_section())
        sections.append(await _failure_envelope_section())
        sections.append(await _authority_section())
        sections.append(await _frontend_section())
        sections.append(await _test_alignment_section())
    finally:
        try:
            async with app_db.pool.connection() as conn:  # type: ignore[attr-defined]
                async with conn.cursor() as cur:  # type: ignore[attr-defined]
                    try:
                        await cur.execute(
                            "SELECT app.cleanup_test_session(%s::uuid)",
                            (session_id,),
                        )
                        await conn.commit()
                    except Exception:
                        await conn.rollback()
        finally:
            app_db.reset_test_session_id(session_token)

    failures = [failure for section in sections for failure in section.failures]

    for section in sections:
        print(f"{section.name}:")
        for detail in section.details:
            print(f" - {detail}")
        if section.failures:
            print(" - FAILURES:")
            for failure in section.failures:
                print(f"   - {failure}")
        print()

    if failures:
        print("AUTH_ONBOARDING_CANONICAL_GATE_FAILED")
        return 1

    print("SYSTEM_CANONICALIZED")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(_main()))
