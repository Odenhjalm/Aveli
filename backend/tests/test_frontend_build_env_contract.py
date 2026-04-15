from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BUILD_PROD = ROOT / "frontend" / "scripts" / "build_prod.sh"
NETLIFY_BUILD = ROOT / "frontend" / "scripts" / "netlify_build_web.sh"


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_build_prod_requires_and_emits_subscriptions_enabled_define() -> None:
    source = _read(BUILD_PROD)

    assert ': "${SUBSCRIPTIONS_ENABLED:?Missing SUBSCRIPTIONS_ENABLED}"' in source
    assert '--dart-define=SUBSCRIPTIONS_ENABLED="$SUBSCRIPTIONS_ENABLED"' in source
    assert 'if [[ -n "${SUBSCRIPTIONS_ENABLED:-}" ]]' not in source


def test_netlify_build_uses_single_subscriptions_enabled_env_name() -> None:
    source = _read(NETLIFY_BUILD)

    assert ': "${SUBSCRIPTIONS_ENABLED:?Missing SUBSCRIPTIONS_ENABLED}"' in source
    assert "FLUTTER_SUBSCRIPTIONS_ENABLED" not in source
