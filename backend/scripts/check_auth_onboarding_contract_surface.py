from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re
import sys


ROOT = Path(__file__).resolve().parents[2]

SCOPED_FILES = (
    ROOT / "backend/app/main.py",
    ROOT / "backend/app/routes/auth.py",
    ROOT / "backend/app/routes/email_verification.py",
    ROOT / "backend/app/routes/profiles.py",
    ROOT / "backend/app/routes/admin.py",
    ROOT / "backend/app/routes/referrals.py",
    ROOT / "backend/app/repositories/auth.py",
    ROOT / "backend/app/repositories/profiles.py",
    ROOT / "backend/app/repositories/referrals.py",
    ROOT / "backend/app/schemas/__init__.py",
    ROOT / "backend/app/schemas/referrals.py",
    ROOT / "backend/app/services/email_verification.py",
    ROOT / "backend/app/services/referral_service.py",
    ROOT / "backend/app/permissions.py",
    ROOT / "backend/test_email_verification.py",
    ROOT / "backend/tests/test_admin_permissions.py",
    ROOT / "backend/tests/test_auth_email_flows.py",
    ROOT / "backend/tests/test_auth_subject_authority_gate.py",
    ROOT / "backend/tests/test_onboarding_state.py",
    ROOT / "backend/tests/test_referral_memberships.py",
    ROOT / "backend/scripts/provision_test_users.py",
    ROOT / "backend/scripts/qa_quiz_submit_smoke.py",
    ROOT / "backend/scripts/qa_session_smoke.py",
    ROOT / "backend/scripts/seed_local_course_editor_substrate.py",
    ROOT / "frontend/lib/api/api_paths.dart",
    ROOT / "frontend/lib/api/auth_repository.dart",
    ROOT / "frontend/lib/core/auth/auth_claims.dart",
    ROOT / "frontend/lib/core/auth/auth_controller.dart",
    ROOT / "frontend/lib/core/routing/app_router.dart",
    ROOT / "frontend/lib/core/routing/route_session.dart",
    ROOT / "frontend/lib/data/models/profile.dart",
    ROOT / "frontend/lib/domain/models/user_access.dart",
    ROOT / "frontend/lib/features/studio/data/studio_repository.dart",
    ROOT / "frontend/lib/mvp/api_client.dart",
    ROOT / "frontend/test/integration/login_studio_purchase_test.dart",
    ROOT / "frontend/test/routing/app_router_test.dart",
    ROOT / "frontend/test/unit/auth_controller_test.dart",
    ROOT / "frontend/test/unit/profile_test.dart",
    ROOT / "frontend/test/widgets/login_page_test.dart",
)
SCOPED_DIRS = (
    ROOT / "frontend/lib/features/auth/presentation",
)
ALLOWED_SUFFIXES = {".dart", ".py", ".sh"}
IGNORED_PARTS = {"__pycache__", ".dart_tool", "build", ".git", "archive", "actual_truth", "docs"}


@dataclass(frozen=True)
class Rule:
    name: str
    pattern: re.Pattern[str]
    paths: tuple[Path, ...] | None = None


CURRENT_PROFILE_CONSUMER_FILES = (
    ROOT / "backend/app/routes/profiles.py",
    ROOT / "backend/app/schemas/__init__.py",
    ROOT / "frontend/lib/api/auth_repository.dart",
    ROOT / "frontend/lib/mvp/api_client.dart",
    ROOT / "frontend/lib/data/models/profile.dart",
    ROOT / "frontend/test/integration/login_studio_purchase_test.dart",
    ROOT / "frontend/test/unit/profile_test.dart",
    ROOT / "backend/tests/test_onboarding_state.py",
)

AUTH_REGISTER_COUPLING_FILES = (
    ROOT / "backend/app/routes/auth.py",
    ROOT / "backend/app/repositories/auth.py",
    ROOT / "backend/app/schemas/__init__.py",
    ROOT / "frontend/lib/api/auth_repository.dart",
    ROOT / "backend/test_email_verification.py",
)


RULES = (
    Rule(name="/auth/me", pattern=re.compile(r"/auth/me")),
    Rule(
        name="/auth/request-password-reset",
        pattern=re.compile(r"/auth/request-password-reset"),
    ),
    Rule(
        name="/admin/teachers/{user_id}/approve|reject",
        pattern=re.compile(
            r"/admin/teachers/(?:\{[^}]+\}|[^\"'\s]+)/(?:(?:approve)|(?:reject))"
        ),
    ),
    Rule(
        name="api_auth/api_profiles import",
        pattern=re.compile(
            r"(from app\.routes import api_auth\b|from app\.routes import api_profiles\b|app\.routes\.api_auth\b|app\.routes\.api_profiles\b)"
        ),
    ),
    Rule(name="registered_unverified", pattern=re.compile(r"registered_unverified")),
    Rule(name="verified_unpaid", pattern=re.compile(r"verified_unpaid")),
    Rule(
        name="access_active_profile_incomplete",
        pattern=re.compile(r"access_active_profile_incomplete"),
    ),
    Rule(
        name="access_active_profile_complete",
        pattern=re.compile(r"access_active_profile_complete"),
    ),
    Rule(name="welcomed", pattern=re.compile(r"welcomed")),
    Rule(
        name="membership_active current-profile leak",
        pattern=re.compile(r"membership_active"),
        paths=CURRENT_PROFILE_CONSUMER_FILES,
    ),
    Rule(
        name="is_teacher current-profile leak",
        pattern=re.compile(r"is_teacher"),
        paths=CURRENT_PROFILE_CONSUMER_FILES,
    ),
    Rule(
        name="referral_code auth/register coupling",
        pattern=re.compile(r"referral_code"),
        paths=AUTH_REGISTER_COUPLING_FILES,
    ),
)


def _iter_files() -> list[Path]:
    files: set[Path] = {path for path in SCOPED_FILES if path.exists()}
    for directory in SCOPED_DIRS:
        if not directory.exists():
            continue
        for path in directory.rglob("*"):
            if not path.is_file():
                continue
            if any(part in IGNORED_PARTS for part in path.parts):
                continue
            if path.suffix not in ALLOWED_SUFFIXES:
                continue
            files.add(path)
    return sorted(files)


def _line_number(content: str, offset: int) -> int:
    return content.count("\n", 0, offset) + 1


def main() -> int:
    failures: list[str] = []
    for path in _iter_files():
        if path == Path(__file__).resolve():
            continue
        try:
            content = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            content = path.read_text(encoding="utf-8", errors="ignore")
        for rule in RULES:
            if rule.paths is not None and path not in rule.paths:
                continue
            for match in rule.pattern.finditer(content):
                rel_path = path.relative_to(ROOT).as_posix()
                failures.append(
                    f"{rel_path}:{_line_number(content, match.start())}: forbidden {rule.name}"
                )
    if failures:
        print("Auth + Onboarding contract surface check failed:")
        for failure in failures:
            print(f" - {failure}")
        return 1
    print("Auth + Onboarding contract surface check passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
