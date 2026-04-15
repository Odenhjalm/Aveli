from __future__ import annotations

from pathlib import Path

from fastapi.routing import APIRoute

from app.main import app


RouteKey = tuple[str, str]

APP_ENTRY_ENFORCEMENT_DEPENDENCY = "require_app_entry"
AUTH_ONLY_DEPENDENCIES = {"get_current_user", "get_optional_user"}
ROLE_DEPENDENCIES = {"require_teacher", "require_admin"}


NON_APP_ENTRY_ROUTE_CLASSIFICATIONS: dict[RouteKey, str] = {
    ("POST", "/auth/register"): "auth_pre_entry",
    ("POST", "/auth/login"): "auth_pre_entry",
    ("POST", "/auth/forgot-password"): "auth_pre_entry",
    ("POST", "/auth/reset-password"): "auth_pre_entry",
    ("POST", "/auth/refresh"): "auth_pre_entry",
    ("POST", "/auth/onboarding/complete"): "onboarding_completion_pre_entry",
    ("GET", "/entry-state"): "entry_state_pre_entry",
    ("POST", "/auth/send-verification"): "email_verification_pre_entry",
    ("GET", "/auth/verify-email"): "email_verification_pre_entry",
    ("GET", "/profiles/me"): "profile_projection_pre_entry",
    ("PATCH", "/profiles/me"): "profile_projection_pre_entry",
    ("POST", "/referrals/redeem"): "referral_redeem_pre_entry",
    ("GET", "/courses"): "public_discovery",
    ("GET", "/courses/"): "public_discovery",
    ("GET", "/courses/{slug}/pricing"): "public_discovery",
    ("GET", "/courses/by-slug/{slug}"): "public_discovery_optional_identity",
    ("GET", "/courses/{course_id}/public"): "public_discovery",
    ("GET", "/courses/{course_id}"): "public_discovery_optional_identity",
    ("GET", "/api/courses/{slug}/pricing"): "public_discovery",
    ("POST", "/api/billing/create-subscription"): "payment_pre_entry",
    ("POST", "/api/billing/cancel-subscription-intent"): "payment_pre_entry",
    ("POST", "/api/checkout/create"): "payment_pre_entry",
    ("POST", "/api/stripe/webhook"): "webhook",
    ("GET", "/api/course-bundles/{bundle_id}"): "public_discovery",
    (
        "POST",
        "/api/course-bundles/{bundle_id}/checkout-session",
    ): "payment_pre_entry",
    ("GET", "/mcp/logs"): "diagnostic_mcp",
    ("POST", "/mcp/logs"): "diagnostic_mcp",
    ("GET", "/mcp/media-control-plane"): "diagnostic_mcp",
    ("POST", "/mcp/media-control-plane"): "diagnostic_mcp",
    ("GET", "/mcp/domain-observability"): "diagnostic_mcp",
    ("POST", "/mcp/domain-observability"): "diagnostic_mcp",
    ("GET", "/mcp/verification"): "diagnostic_mcp",
    ("POST", "/mcp/verification"): "diagnostic_mcp",
    ("GET", "/healthz"): "diagnostic",
    ("GET", "/readyz"): "diagnostic",
    ("GET", "/metrics"): "diagnostic",
}


def _mounted_routes() -> list[tuple[RouteKey, APIRoute]]:
    routes: list[tuple[RouteKey, APIRoute]] = []
    for route in app.routes:
        if not isinstance(route, APIRoute):
            continue
        for method in sorted((route.methods or set()) - {"HEAD", "OPTIONS"}):
            routes.append(((method, route.path), route))
    return routes


def _dependency_names(route: APIRoute) -> set[str]:
    names: set[str] = set()

    def walk(dependant) -> None:
        call = dependant.call
        name = getattr(call, "__name__", None)
        if name:
            names.add(name)
        for child in dependant.dependencies:
            walk(child)

    walk(route.dependant)
    return names


def _direct_dependency_names(route: APIRoute) -> set[str]:
    return {
        name
        for dependency in route.dependant.dependencies
        if (name := getattr(dependency.call, "__name__", None))
    }


def _describe_route(key: RouteKey, route: APIRoute, reason: str) -> str:
    method, path = key
    return (
        f"{method} {path}: {reason}; "
        f"direct={sorted(_direct_dependency_names(route))}; "
        f"all={sorted(_dependency_names(route))}"
    )


def test_non_app_entry_routes_are_explicitly_classified() -> None:
    unclassified = [
        _describe_route(key, route, "missing non-app-entry classification")
        for key, route in _mounted_routes()
        if APP_ENTRY_ENFORCEMENT_DEPENDENCY not in _dependency_names(route)
        and key not in NON_APP_ENTRY_ROUTE_CLASSIFICATIONS
    ]

    assert unclassified == []


def test_every_app_entry_route_uses_entry_state_enforcement() -> None:
    violations = [
        _describe_route(key, route, "app-entry route missing entry-state enforcement")
        for key, route in _mounted_routes()
        if key not in NON_APP_ENTRY_ROUTE_CLASSIFICATIONS
        and APP_ENTRY_ENFORCEMENT_DEPENDENCY not in _dependency_names(route)
    ]

    assert violations == []


def test_app_entry_enforcement_reuses_entry_state_computation() -> None:
    source = Path("backend/app/auth.py").read_text(encoding="utf-8")

    assert "build_entry_state" in source
    assert "memberships_repo" not in source
    assert "is_membership_row_active" not in source


def test_auth_only_dependencies_are_confined_to_explicit_pre_entry_routes() -> None:
    violations: list[str] = []
    for key, route in _mounted_routes():
        direct_auth_only = _direct_dependency_names(route) & AUTH_ONLY_DEPENDENCIES
        if not direct_auth_only:
            continue
        if key in NON_APP_ENTRY_ROUTE_CLASSIFICATIONS:
            continue
        violations.append(
            _describe_route(
                key,
                route,
                f"direct auth-only dependency {sorted(direct_auth_only)}",
            )
        )

    assert violations == []


def test_role_dependencies_compose_with_entry_state_enforcement() -> None:
    violations: list[str] = []
    for key, route in _mounted_routes():
        role_dependencies = _dependency_names(route) & ROLE_DEPENDENCIES
        if not role_dependencies:
            continue
        if APP_ENTRY_ENFORCEMENT_DEPENDENCY in _dependency_names(route):
            continue
        violations.append(
            _describe_route(
                key,
                route,
                f"role dependency without entry-state enforcement {sorted(role_dependencies)}",
            )
        )

    assert violations == []
