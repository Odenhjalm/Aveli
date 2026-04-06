import os
from pathlib import Path


def parse_env_file(path: Path) -> dict:
    env = {}
    if not path.exists():
        return env

    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue

        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        env[key] = value

    return env


def load_env():
    if os.getenv("AVELI_ENV_LOADED") == "1":
        return

    root = Path(__file__).resolve().parents[2]

    env_local = root / "backend" / ".env.local"
    env_default = root / "backend" / ".env"

    env_file = env_local if env_local.exists() else env_default

    if not env_file.exists():
        raise RuntimeError(f"Missing env file: {env_file}")

    env_vars = parse_env_file(env_file)

    # Load into process env ONLY if not already set
    for key, value in env_vars.items():
        if key not in os.environ:
            os.environ[key] = value

    # 🔒 HARD GUARDRAILS
    required = {
        "APP_ENV": "local",
        "MCP_MODE": "local",
        "DATABASE_URL": "postgresql://postgres:postgres@127.0.0.1:5432/aveli_local",
    }

    for key, expected in required.items():
        actual = os.getenv(key)
        if actual is None:
            raise RuntimeError(f"{key} is missing in environment")
        if key != "DATABASE_URL" and actual.lower() != expected:
            raise RuntimeError(f"{key} must be '{expected}', got '{actual}'")

    print(f"[AVELI ENV] Loaded from: {env_file}")
    print(f"[AVELI ENV] APP_ENV={os.getenv('APP_ENV')}")
    print(f"[AVELI ENV] MCP_MODE={os.getenv('MCP_MODE')}")

    os.environ["AVELI_ENV_LOADED"] = "1"