import sys
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parents[2]
TESTS_DIR = ROOT_DIR / "tests"
for path in (ROOT_DIR, TESTS_DIR):
    if str(path) not in sys.path:
        sys.path.insert(0, str(path))

from tests.conftest import *  # noqa: F401,F403
